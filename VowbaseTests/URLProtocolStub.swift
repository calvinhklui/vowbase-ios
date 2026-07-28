import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Step: @unchecked Sendable {
        case response(statusCode: Int, headers: [String: String] = [:], body: Data)
        case redirect(statusCode: Int, location: URL)
        case error(URLError)
        case nonHTTP(body: Data)
        case pending
    }

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [Step]
        private var recordedRequests: [URLRequest] = []
        private var capturedBodies: [String: Data] = [:]
        private var cancellationCount = 0

        init(steps: [Step]) {
            self.steps = steps
        }

        var requests: [URLRequest] {
            lock.withLock { recordedRequests }
        }

        var bodies: [Data?] {
            lock.withLock { recordedRequests.map(\.httpBody) }
        }

        var cancellations: Int {
            lock.withLock { cancellationCount }
        }

        fileprivate func captureBody(from request: URLRequest) {
            guard let requestID = request.value(forHTTPHeaderField: "x-request-id"),
                  let body = Self.bodyData(from: request) else {
                return
            }
            lock.withLock {
                capturedBodies[requestID] = body
            }
        }

        private static func bodyData(from request: URLRequest) -> Data? {
            if let body = request.httpBody {
                return body
            }
            guard let stream = request.httpBodyStream else {
                return nil
            }

            stream.open()
            defer { stream.close() }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { return nil }
                if count == 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }

        fileprivate func takeStep(for request: URLRequest) -> Step? {
            lock.withLock {
                var recordedRequest = request
                if recordedRequest.httpBody == nil,
                   let requestID = request.value(forHTTPHeaderField: "x-request-id") {
                    recordedRequest.httpBody = capturedBodies.removeValue(forKey: requestID)
                }
                recordedRequests.append(recordedRequest)
                guard !steps.isEmpty else { return nil }
                return steps.removeFirst()
            }
        }

        fileprivate func recordCancellation() {
            lock.withLock {
                cancellationCount += 1
            }
        }
    }

    private final class WeakState: @unchecked Sendable {
        weak var value: State?

        init(_ value: State) {
            self.value = value
        }
    }

    private static let stateHeader = "x-vowbase-urlprotocol-state"
    private static let registryLock = NSLock()
    private static var registry: [String: WeakState] = [:]

    private let deliveryLock = NSLock()
    private var isStopped = false

    static func configuration(for state: State) -> URLSessionConfiguration {
        let identifier = UUID().uuidString.lowercased()
        registryLock.withLock {
            registry = registry.filter { $0.value.value != nil }
            registry[identifier] = WeakState(state)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        configuration.httpAdditionalHeaders = [stateHeader: identifier]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let state = state(for: request) else { return false }
        state.captureBody(from: request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let state = Self.state(for: request),
              let step = state.takeStep(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch step {
        case .response(let statusCode, let headers, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            deliver {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }

        case .redirect(let statusCode, let location):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Location": location.absoluteString]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            deliver {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data())
                client?.urlProtocolDidFinishLoading(self)
            }

        case .error(let error):
            deliver {
                client?.urlProtocol(self, didFailWithError: error)
            }

        case .nonHTTP(let body):
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let response = URLResponse(
                url: url,
                mimeType: "application/json",
                expectedContentLength: body.count,
                textEncodingName: "utf-8"
            )
            deliver {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }

        case .pending:
            break
        }
    }

    override func stopLoading() {
        let shouldRecord = deliveryLock.withLock {
            guard !isStopped else { return false }
            isStopped = true
            return true
        }
        if shouldRecord {
            Self.state(for: request)?.recordCancellation()
        }
    }

    private func deliver(_ work: () -> Void) {
        let shouldDeliver = deliveryLock.withLock { !isStopped }
        if shouldDeliver {
            work()
        }
    }

    private static func state(for request: URLRequest) -> State? {
        guard let identifier = request.value(forHTTPHeaderField: stateHeader) else {
            return nil
        }
        return registryLock.withLock {
            guard let state = registry[identifier]?.value else {
                registry.removeValue(forKey: identifier)
                return nil
            }
            return state
        }
    }
}
