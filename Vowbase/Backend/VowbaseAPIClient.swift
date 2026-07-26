import Foundation

protocol VowbaseAPIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response
}

final class VowbaseAPIClient: VowbaseAPIClientProtocol, Sendable {
    typealias Now = @Sendable () -> Date
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private static let maximumGETAttempts = 3
    private static let maximumRetryDelay: TimeInterval = 2
    private static let authenticationFailureMessage =
        "Authentication is temporarily unavailable."

    private let session: URLSession
    private let configuration: AppConfiguration
    private let authService: any AuthServicing
    private let now: Now
    private let sleeper: Sleeper

    init(
        sessionConfiguration: URLSessionConfiguration,
        configuration: AppConfiguration,
        authService: any AuthServicing,
        now: @escaping Now = { Date() },
        sleeper: @escaping Sleeper = { delay in
            try await Task<Never, Never>.sleep(for: .seconds(delay))
        }
    ) {
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: RedirectRejectingDelegate(),
            delegateQueue: nil
        )
        self.configuration = configuration
        self.authService = authService
        self.now = now
        self.sleeper = sleeper
    }

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        let url = try requestURL(for: request.path)
        let logicalRequestID = UUID().uuidString.lowercased()
        let maximumAttempts = request.method == .get ? Self.maximumGETAttempts : 1
        var attempt = 0
        var transientRetryCount = 0
        var hasRefreshed = false

        while attempt < maximumAttempts {
            attempt += 1
            try Self.checkCancellation()

            let accessToken = try await accessToken()
            try Self.checkCancellation()

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = request.method.rawValue
            urlRequest.httpBody = request.body
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue(logicalRequestID, forHTTPHeaderField: "x-request-id")
            if request.body != nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
                try Self.checkCancellation()
            } catch {
                let normalized = Self.normalizedTransportError(error)
                if request.method == .get,
                   Self.isTransientConnectivityError(error),
                   attempt < maximumAttempts {
                    transientRetryCount += 1
                    try await sleep(Self.backoffDelay(retryNumber: transientRetryCount))
                    continue
                }
                throw normalized
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                do {
                    return try JSONDecoder().decode(Response.self, from: data)
                } catch {
                    throw BackendError.invalidResponse
                }
            }

            if request.method == .get,
               httpResponse.statusCode == 401,
               !hasRefreshed,
               attempt < maximumAttempts {
                hasRefreshed = true
                try await refreshSession()
                continue
            }

            if request.method == .get,
               Self.isTransientStatus(httpResponse.statusCode),
               attempt < maximumAttempts {
                transientRetryCount += 1
                let delay = Self.retryDelay(
                    response: httpResponse,
                    now: now(),
                    retryNumber: transientRetryCount
                )
                try await sleep(delay)
                continue
            }

            throw Self.backendError(from: data, response: httpResponse)
        }

        throw BackendError.invalidResponse
    }

    private func accessToken() async throws -> String {
        do {
            let token = try await authService.currentAccessToken()
            try Self.checkCancellation()
            return token
        } catch {
            throw Self.normalizedAuthError(error)
        }
    }

    private func refreshSession() async throws {
        do {
            try await authService.refreshSession()
            try Self.checkCancellation()
        } catch {
            throw Self.normalizedAuthError(error)
        }
    }

    private func sleep(_ delay: TimeInterval) async throws {
        do {
            try Self.checkCancellation()
            try await sleeper(delay)
            try Self.checkCancellation()
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw BackendError.cancelled
            }
            if let backendError = error as? BackendError {
                throw backendError
            }
            throw BackendError.temporarilyUnavailable(
                message: "Retry scheduling is temporarily unavailable.",
                requestID: nil
            )
        }
    }

    private func requestURL(for path: String) throws -> URL {
        guard Self.hasOnlyValidPercentEscapes(path),
              path.rangeOfCharacter(from: .controlCharacters) == nil,
              path.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !path.contains("\\"),
              !path.isEmpty,
              !path.hasPrefix("/"),
              let requestComponents = URLComponents(string: path),
              requestComponents.scheme == nil,
              requestComponents.host == nil,
              requestComponents.user == nil,
              requestComponents.password == nil,
              requestComponents.fragment == nil,
              !requestComponents.percentEncodedPath.isEmpty,
              Self.isSafeRelativePath(requestComponents.percentEncodedPath),
              Self.isFreeOfEncodedWhitespaceAndControls(
                requestComponents.percentEncodedQuery ?? ""
              ),
              var baseComponents = URLComponents(
                url: configuration.apiBaseURL,
                resolvingAgainstBaseURL: false
              ),
              baseComponents.scheme != nil,
              baseComponents.host != nil,
              baseComponents.user == nil,
              baseComponents.password == nil,
              baseComponents.fragment == nil,
              Self.isSafeBasePath(baseComponents.percentEncodedPath) else {
            throw BackendError.invalidResponse
        }

        let basePath: String
        if baseComponents.percentEncodedPath.isEmpty
            || baseComponents.percentEncodedPath == "/" {
            basePath = ""
        } else {
            basePath = baseComponents.percentEncodedPath.hasSuffix("/")
                ? String(baseComponents.percentEncodedPath.dropLast())
                : baseComponents.percentEncodedPath
        }

        baseComponents.percentEncodedPath =
            basePath + "/" + requestComponents.percentEncodedPath
        baseComponents.queryItems =
            (baseComponents.queryItems ?? []) + (requestComponents.queryItems ?? [])
        baseComponents.fragment = nil

        guard let url = baseComponents.url,
              let finalComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              finalComponents.scheme?.lowercased() == baseComponents.scheme?.lowercased(),
              finalComponents.host?.lowercased() == baseComponents.host?.lowercased(),
              finalComponents.port == baseComponents.port,
              finalComponents.user == nil,
              finalComponents.password == nil else {
            throw BackendError.invalidResponse
        }
        return url
    }

    private static func isSafeRelativePath(_ encodedPath: String) -> Bool {
        var candidate = encodedPath
        for _ in 0..<8 {
            guard let decoded = candidate.removingPercentEncoding else { return false }
            guard isFreeOfWhitespaceAndControls(decoded),
                  !decoded.hasPrefix("/"),
                  !decoded.contains("\\"),
                  !decoded.split(separator: "/", omittingEmptySubsequences: false)
                    .contains(where: { $0 == "." || $0 == ".." }) else {
                return false
            }
            if decoded == candidate { return true }
            candidate = decoded
        }
        return false
    }

    private static func isFreeOfEncodedWhitespaceAndControls(
        _ encodedValue: String
    ) -> Bool {
        var candidate = encodedValue
        for _ in 0..<8 {
            guard isFreeOfWhitespaceAndControls(candidate),
                  let decoded = candidate.removingPercentEncoding else {
                return false
            }
            if decoded == candidate { return true }
            candidate = decoded
        }
        return false
    }

    private static func isFreeOfWhitespaceAndControls(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func isSafeBasePath(_ encodedPath: String) -> Bool {
        let relative = encodedPath.hasPrefix("/")
            ? String(encodedPath.dropFirst())
            : encodedPath
        return relative.isEmpty || isSafeRelativePath(relative)
    }

    private static func hasOnlyValidPercentEscapes(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count,
                      isHexDigit(bytes[index + 1]),
                      isHexDigit(bytes[index + 2]) else {
                    return false
                }
                index += 3
            } else {
                index += 1
            }
        }
        return true
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...70).contains(byte)
            || (97...102).contains(byte)
    }

    private static func backendError(
        from data: Data,
        response: HTTPURLResponse
    ) -> BackendError {
        guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
              !envelope.error.code.isEmpty,
              !envelope.error.message.isEmpty else {
            return .invalidResponse
        }

        let envelopeRequestID = validRequestID(envelope.error.requestID)
        let responseRequestID: String?
        if envelope.error.requestID == nil {
            responseRequestID = validRequestID(
                response.value(forHTTPHeaderField: "x-request-id")
            )
        } else {
            responseRequestID = nil
        }
        let detail = APIErrorEnvelope.Detail(
            code: envelope.error.code,
            message: envelope.error.message,
            requestID: envelopeRequestID ?? responseRequestID
        )
        return BackendError(detail: detail)
    }

    private static func validRequestID(_ value: String?) -> String? {
        guard let value,
              (1...128).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({
                $0.isASCII
                    && !$0.properties.isWhitespace
                    && !CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        return value
    }

    private static func isTransientStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isTransientConnectivityError(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func retryDelay(
        response: HTTPURLResponse,
        now: Date,
        retryNumber: Int
    ) -> TimeInterval {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return backoffDelay(retryNumber: retryNumber)
        }

        if let seconds = Int(rawValue), seconds >= 0 {
            return min(TimeInterval(seconds), maximumRetryDelay)
        }

        if let date = HTTPDateParser.date(from: rawValue) {
            let interval = date.timeIntervalSince(now)
            if interval >= 0 {
                return min(interval, maximumRetryDelay)
            }
        }
        return backoffDelay(retryNumber: retryNumber)
    }

    private static func backoffDelay(retryNumber: Int) -> TimeInterval {
        min(0.25 * pow(2, Double(max(0, retryNumber - 1))), maximumRetryDelay)
    }

    private static func normalizedAuthError(_ error: any Error) -> BackendError {
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        if let backendError = error as? BackendError {
            return backendError
        }
        return .temporarilyUnavailable(
            message: authenticationFailureMessage,
            requestID: nil
        )
    }

    private static func normalizedTransportError(_ error: any Error) -> BackendError {
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .networkUnavailable
        }
        if let backendError = error as? BackendError {
            return backendError
        }
        return .networkUnavailable
    }

    private static func checkCancellation() throws {
        if Task.isCancelled {
            throw BackendError.cancelled
        }
    }
}

final class RedirectRejectingDelegate: NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum HTTPDateParser {
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter.date(from: string)
    }
}
