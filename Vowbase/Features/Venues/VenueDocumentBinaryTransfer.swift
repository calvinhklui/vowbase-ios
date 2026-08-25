import Foundation

/// Transfers document bytes through server-minted storage capabilities. This intentionally does
/// not use `VowbaseAPIClient`: a bearer token must only ever go to the Vowbase API origin.
protocol VenueDocumentBinaryTransferring: Sendable {
    func upload(
        data: Data,
        to signedURL: URL,
        token: String,
        mimeType: String
    ) async throws

    func download(from signedURL: URL) async throws -> Data
}

final class URLSessionVenueDocumentBinaryTransfer: VenueDocumentBinaryTransferring, @unchecked Sendable {
    private let session: URLSession

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(
            configuration: sessionConfiguration,
            delegate: SignedTransferRedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }

    func upload(
        data: Data,
        to signedURL: URL,
        token: String,
        mimeType: String
    ) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.invalidResponse
        }

        var request = URLRequest(url: try signedUploadURL(signedURL, token: token))
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("max-age=3600", forHTTPHeaderField: "Cache-Control")
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        _ = try await perform(request, returningData: false)
    }

    func download(from signedURL: URL) async throws -> Data {
        let request = URLRequest(url: try validatedHTTPSURL(signedURL))
        return try await perform(request, returningData: true)
    }

    private func perform(_ request: URLRequest, returningData: Bool) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw BackendError.invalidResponse
            }
            return returningData ? data : Data()
        } catch is CancellationError {
            throw BackendError.cancelled
        } catch let error as BackendError {
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .cannotFindHost
            || error.code == .cannotConnectToHost
            || error.code == .dnsLookupFailed {
            throw BackendError.networkUnavailable
        } catch {
            throw BackendError.temporarilyUnavailable(
                message: "Document transfer is temporarily unavailable.",
                requestID: nil
            )
        }
    }

    private func signedUploadURL(_ url: URL, token: String) throws -> URL {
        let validatedURL = try validatedHTTPSURL(url)
        guard var components = URLComponents(url: validatedURL, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidResponse
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        guard let signedURL = components.url else { throw BackendError.invalidResponse }
        return signedURL
    }

    private func validatedHTTPSURL(_ url: URL) throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            throw BackendError.invalidResponse
        }
        return url
    }
}

private final class SignedTransferRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
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
