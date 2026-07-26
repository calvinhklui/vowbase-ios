import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Vowbase API client")
struct VowbaseAPIClientTests {
    struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    @Test("sends authenticated JSON headers and retains one request ID across a retry")
    func sendsHeadersAndStableRequestID() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 500, body: errorBody(code: "internal_failure")),
            .response(statusCode: 200, body: payloadBody("ok")),
        ])
        let auth = APIClientAuthStub(tokens: ["token-one", "token-two"])
        let client = try makeClient(transport: transport, auth: auth)

        let result: Payload = try await client.send(
            APIRequest(method: .get, path: "weddings/current")
        )

        #expect(result == Payload(value: "ok"))
        #expect(auth.tokenCallCount == 2)
        let requests = transport.requests
        #expect(requests.count == 2)
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer token-one", "Bearer token-two",
        ])
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Accept") == "application/json"
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Content-Type") == nil
        })
        let requestIDs = requests.compactMap {
            $0.value(forHTTPHeaderField: "x-request-id")
        }
        #expect(requestIDs.count == 2)
        #expect(requestIDs[0] == requestIDs[1])
        #expect(UUID(uuidString: requestIDs[0]) != nil)
    }

    @Test("preserves the configured base path and merges base and request queries")
    func constructsURLUnderBase() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: payloadBody("ok")),
        ])
        let client = try makeClient(
            transport: transport,
            baseURL: "https://api.example.com/root/v1?tenant=abc",
            auth: APIClientAuthStub()
        )

        let _: Payload = try await client.send(
            APIRequest(method: .get, path: "weddings/current?include=members")
        )

        let url = try #require(transport.requests.first?.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        #expect(components.scheme == "https")
        #expect(components.host == "api.example.com")
        #expect(components.path == "/root/v1/weddings/current")
        #expect(components.queryItems == [
            URLQueryItem(name: "tenant", value: "abc"),
            URLQueryItem(name: "include", value: "members"),
        ])
    }

    @Test(
        "rejects unsafe or malformed request paths before auth or transport",
        arguments: [
            "https://evil.example/steal",
            "//evil.example/steal",
            "//user:password@evil.example/steal",
            "/absolute/path",
            "../escape",
            "safe/%2e%2e/escape",
            "safe/%252e%252e/escape",
            "safe/%20space",
            "safe/%0Anewline",
            "safe?query=%09tab",
            "safe?query=%250Anewline",
            "safe#fragment",
            "safe\\evil",
            "safe/%",
            "",
        ]
    )
    func rejectsUnsafePaths(path: String) async throws {
        let transport = URLProtocolStub.State(steps: [])
        let auth = APIClientAuthStub()
        let client = try makeClient(transport: transport, auth: auth)

        await #expect(throws: BackendError.invalidResponse) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: path)
            )
        }
        #expect(auth.tokenCallCount == 0)
        #expect(transport.requests.isEmpty)
    }

    @Test("decodes every 2xx boundary and rejects malformed success JSON")
    func handlesSuccessBoundaries() async throws {
        for status in [200, 299] {
            let transport = URLProtocolStub.State(steps: [
                .response(statusCode: status, body: payloadBody("\(status)")),
            ])
            let client = try makeClient(transport: transport, auth: APIClientAuthStub())
            let result: Payload = try await client.send(
                APIRequest(method: .get, path: "boundary")
            )
            #expect(result.value == "\(status)")
        }

        for status in [199, 300] {
            let transport = URLProtocolStub.State(steps: [
                .response(
                    statusCode: status,
                    body: errorBody(code: "validation_failed", message: "Safe message")
                ),
            ])
            let client = try makeClient(transport: transport, auth: APIClientAuthStub())
            await #expect(
                throws: BackendError.validation(message: "Safe message", requestID: nil)
            ) {
                let _: Payload = try await client.send(
                    APIRequest(method: .get, path: "boundary")
                )
            }
        }

        let malformed = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: Data("not-json secret".utf8)),
        ])
        let malformedClient = try makeClient(
            transport: malformed,
            auth: APIClientAuthStub()
        )
        await #expect(throws: BackendError.invalidResponse) {
            let _: Payload = try await malformedClient.send(
                APIRequest(method: .get, path: "malformed")
            )
        }
    }

    @Test(
        "rejects redirects without following or replaying requests",
        arguments: [APIRequest<Payload>.Method.get, .post]
    )
    func rejectsRedirects(method: APIRequest<Payload>.Method) async throws {
        let transport = URLProtocolStub.State(steps: [
            .redirect(
                statusCode: method == .get ? 302 : 307,
                location: URL(string: "https://evil.example/steal")!
            ),
            .response(statusCode: 200, body: payloadBody("must-not-follow")),
        ])
        let client = try makeClient(transport: transport, auth: APIClientAuthStub())

        await #expect(throws: BackendError.invalidResponse) {
            let _: Payload = try await client.send(
                APIRequest(
                    method: method,
                    path: "redirect",
                    body: method == .get ? nil : Data("{}".utf8)
                )
            )
        }
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.host == "api.example.com")
    }

    @Test("owned transport delegate rejects redirected requests")
    func redirectDelegateReturnsNil() throws {
        let originalURL = try #require(URL(string: "https://api.example.com/original"))
        let redirectedURL = try #require(URL(string: "https://evil.example/steal"))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: originalURL)
        let response = try #require(
            HTTPURLResponse(
                url: originalURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirectedURL.absoluteString]
            )
        )
        var acceptedRequest: URLRequest?

        RedirectRejectingDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectedURL)
        ) {
            acceptedRequest = $0
        }

        #expect(acceptedRequest == nil)
    }

    @Test("maps envelope codes authoritatively and preserves safe request IDs")
    func mapsErrorEnvelopes() async throws {
        let cases: [(Int, String, BackendError)] = [
            (418, "authentication_required", .authenticationRequired(message: "Safe", requestID: "server-1")),
            (401, "wedding_forbidden", .forbidden(message: "Safe", requestID: "server-1")),
            (500, "validation_failed", .validation(message: "Safe", requestID: "server-1")),
            (400, "conflict", .conflict(message: "Safe", requestID: "server-1")),
            (400, "rate_limited", .rateLimited(message: "Safe", requestID: "server-1")),
            (400, "provider_failed", .temporarilyUnavailable(message: "Safe", requestID: "server-1")),
            (400, "future_code", .unknown(message: "Safe", requestID: "server-1")),
        ]

        for (status, code, expected) in cases {
            let transport = URLProtocolStub.State(steps: [
                .response(
                    statusCode: status,
                    body: errorBody(code: code, message: "Safe", requestID: "server-1")
                ),
            ])
            let client = try makeClient(transport: transport, auth: APIClientAuthStub())
            await #expect(throws: expected) {
                let _: Payload = try await client.send(
                    APIRequest(method: .post, path: "errors", body: Data("{}".utf8))
                )
            }
        }
    }

    @Test("uses a valid response request ID only when the envelope omits one")
    func fallsBackToResponseRequestID() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(
                statusCode: 403,
                headers: ["x-request-id": "header-request-42"],
                body: errorBody(code: "forbidden", message: "No")
            ),
            .response(
                statusCode: 403,
                headers: ["x-request-id": "header-ignored"],
                body: errorBody(code: "forbidden", message: "No", requestID: "envelope-wins")
            ),
        ])
        let client = try makeClient(transport: transport, auth: APIClientAuthStub())

        await #expect(
            throws: BackendError.forbidden(message: "No", requestID: "header-request-42")
        ) {
            let _: Payload = try await client.send(
                APIRequest(method: .post, path: "one", body: Data("{}".utf8))
            )
        }
        await #expect(
            throws: BackendError.forbidden(message: "No", requestID: "envelope-wins")
        ) {
            let _: Payload = try await client.send(
                APIRequest(method: .post, path: "two", body: Data("{}".utf8))
            )
        }
    }

    @Test("sanitizes malformed error envelopes and non-HTTP responses")
    func rejectsMalformedResponses() async throws {
        let steps: [URLProtocolStub.Step] = [
            .response(statusCode: 400, body: Data("secret raw body".utf8)),
            .response(statusCode: 400, body: Data("{\"error\":{\"message\":\"secret\"}}".utf8)),
            .nonHTTP(body: payloadBody("ok")),
        ]

        for step in steps {
            let transport = URLProtocolStub.State(steps: [step])
            let client = try makeClient(transport: transport, auth: APIClientAuthStub())
            await #expect(throws: BackendError.invalidResponse) {
                let _: Payload = try await client.send(
                    APIRequest(method: .post, path: "malformed", body: Data("{}".utf8))
                )
            }
        }
    }

    @Test("GET refreshes once after 401, fetches a new token, and stops at a second 401")
    func refreshesGETOnce() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 401, body: errorBody(code: "authentication_required")),
            .response(statusCode: 401, body: errorBody(code: "authentication_required")),
        ])
        let auth = APIClientAuthStub(tokens: ["expired", "refreshed"])
        let client = try makeClient(transport: transport, auth: auth)

        await #expect(
            throws: BackendError.authenticationRequired(message: "Safe", requestID: nil)
        ) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "private")
            )
        }

        #expect(auth.tokenCallCount == 2)
        #expect(auth.refreshCallCount == 1)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.map {
            $0.value(forHTTPHeaderField: "Authorization")
        } == ["Bearer expired", "Bearer refreshed"])
    }

    @Test("GET has one total three-attempt budget across auth and transient retries")
    func enforcesMixedAttemptBudget() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 500, body: errorBody(code: "internal_failure")),
            .response(statusCode: 401, body: errorBody(code: "authentication_required")),
            .response(statusCode: 503, body: errorBody(code: "temporarily_unavailable")),
            .response(statusCode: 200, body: payloadBody("must-not-send")),
        ])
        let auth = APIClientAuthStub(tokens: ["one", "two", "three"])
        let delays = DelayRecorder()
        let client = try makeClient(transport: transport, auth: auth, delays: delays)

        await #expect(
            throws: BackendError.temporarilyUnavailable(message: "Safe", requestID: nil)
        ) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "mixed")
            )
        }

        #expect(transport.requests.count == 3)
        #expect(auth.tokenCallCount == 3)
        #expect(auth.refreshCallCount == 1)
        #expect(await delays.values == [0.25])
    }

    @Test("GET retries connectivity, 429, and 5xx at most twice with deterministic delays")
    func retriesTransientGETFailures() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let httpDate = HTTPDateFormatter.string(from: now.addingTimeInterval(2))
        let cases: [([URLProtocolStub.Step], [TimeInterval])] = [
            ([
                .error(URLError(.notConnectedToInternet)),
                .error(URLError(.networkConnectionLost)),
                .response(statusCode: 200, body: payloadBody("ok")),
            ], [0.25, 0.5]),
            ([
                .response(statusCode: 429, headers: ["Retry-After": "10"], body: errorBody(code: "rate_limited")),
                .response(statusCode: 429, headers: ["Retry-After": "invalid"], body: errorBody(code: "rate_limited")),
                .response(statusCode: 200, body: payloadBody("ok")),
            ], [2, 0.5]),
            ([
                .response(statusCode: 503, headers: ["Retry-After": httpDate], body: errorBody(code: "temporarily_unavailable")),
                .response(statusCode: 500, headers: ["Retry-After": "Sat, 01 Jan 2000 00:00:00 GMT"], body: errorBody(code: "internal_failure")),
                .response(statusCode: 200, body: payloadBody("ok")),
            ], [2, 0.5]),
        ]

        for (steps, expectedDelays) in cases {
            let transport = URLProtocolStub.State(steps: steps)
            let delays = DelayRecorder()
            let client = try makeClient(
                transport: transport,
                auth: APIClientAuthStub(),
                now: now,
                delays: delays
            )
            let result: Payload = try await client.send(
                APIRequest(method: .get, path: "transient")
            )
            #expect(result.value == "ok")
            #expect(transport.requests.count == 3)
            #expect(await delays.values == expectedDelays)
        }
    }

    @Test("GET stops after three connectivity attempts")
    func stopsAfterMaximumConnectivityAttempts() async throws {
        let transport = URLProtocolStub.State(steps: [
            .error(URLError(.timedOut)),
            .error(URLError(.cannotConnectToHost)),
            .error(URLError(.dnsLookupFailed)),
            .response(statusCode: 200, body: payloadBody("must-not-send")),
        ])
        let delays = DelayRecorder()
        let client = try makeClient(
            transport: transport,
            auth: APIClientAuthStub(),
            delays: delays
        )

        await #expect(throws: BackendError.networkUnavailable) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "offline")
            )
        }
        #expect(transport.requests.count == 3)
        #expect(await delays.values == [0.25, 0.5])
    }

    @Test(
        "POST PATCH and DELETE never retry or refresh",
        arguments: [APIRequest<Payload>.Method.post, .patch, .delete]
    )
    func mutationsNeverRetry(method: APIRequest<Payload>.Method) async throws {
        let cases: [(URLProtocolStub.Step, BackendError)] = [
            (
                .response(statusCode: 401, body: errorBody(code: "authentication_required")),
                .authenticationRequired(message: "Safe", requestID: nil)
            ),
            (.error(URLError(.notConnectedToInternet)), .networkUnavailable),
            (
                .response(statusCode: 503, body: errorBody(code: "temporarily_unavailable")),
                .temporarilyUnavailable(message: "Safe", requestID: nil)
            ),
        ]

        for (firstStep, expected) in cases {
            let transport = URLProtocolStub.State(steps: [
                firstStep,
                .response(statusCode: 200, body: payloadBody("must-not-send")),
            ])
            let auth = APIClientAuthStub()
            let client = try makeClient(transport: transport, auth: auth)
            await #expect(throws: expected) {
                let _: Payload = try await client.send(
                    APIRequest(method: method, path: "mutation", body: Data("{\"a\":1}".utf8))
                )
            }
            #expect(transport.requests.count == 1)
            #expect(auth.tokenCallCount == 1)
            #expect(auth.refreshCallCount == 0)
            #expect(transport.bodies.first! == Data("{\"a\":1}".utf8))
            #expect(
                transport.requests[0].value(forHTTPHeaderField: "Content-Type")
                    == "application/json"
            )
        }
    }

    @Test("does not retry ordinary 4xx, decoding errors, or auth-service errors")
    func avoidsNonTransientRetries() async throws {
        let badRequestTransport = URLProtocolStub.State(steps: [
            .response(statusCode: 400, body: errorBody(code: "validation_failed")),
            .response(statusCode: 200, body: payloadBody("must-not-send")),
        ])
        let badRequestClient = try makeClient(
            transport: badRequestTransport,
            auth: APIClientAuthStub()
        )
        await #expect(throws: BackendError.validation(message: "Safe", requestID: nil)) {
            let _: Payload = try await badRequestClient.send(
                APIRequest(method: .get, path: "bad")
            )
        }
        #expect(badRequestTransport.requests.count == 1)

        let decodingTransport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: Data("{}".utf8)),
            .response(statusCode: 200, body: payloadBody("must-not-send")),
        ])
        let decodingClient = try makeClient(
            transport: decodingTransport,
            auth: APIClientAuthStub()
        )
        await #expect(throws: BackendError.invalidResponse) {
            let _: Payload = try await decodingClient.send(
                APIRequest(method: .get, path: "decode")
            )
        }
        #expect(decodingTransport.requests.count == 1)

        let authError = BackendError.authenticationRequired(message: nil, requestID: nil)
        let auth = APIClientAuthStub(tokenHandler: { _ in throw authError })
        let authTransport = URLProtocolStub.State(steps: [])
        let authClient = try makeClient(transport: authTransport, auth: auth)
        await #expect(throws: authError) {
            let _: Payload = try await authClient.send(
                APIRequest(method: .get, path: "auth")
            )
        }
        #expect(auth.tokenCallCount == 1)
        #expect(authTransport.requests.isEmpty)
    }

    @Test("maps cancellation while fetching a token")
    func cancelsDuringTokenFetch() async throws {
        let auth = APIClientAuthStub(tokenHandler: { _ in throw CancellationError() })
        let transport = URLProtocolStub.State(steps: [])
        let client = try makeClient(transport: transport, auth: auth)

        await #expect(throws: BackendError.cancelled) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "cancel")
            )
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("maps URLSession cancellation and stops the in-flight protocol load")
    func cancelsDuringRequest() async throws {
        let transport = URLProtocolStub.State(steps: [.pending])
        let client = try makeClient(transport: transport, auth: APIClientAuthStub())
        let task = Task {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "pending")
            )
        }

        try await waitUntil { transport.requests.count == 1 }
        task.cancel()
        await #expect(throws: BackendError.cancelled) {
            try await task.value
        }
        try await waitUntil { transport.cancellations == 1 }
        #expect(transport.requests.count == 1)
    }

    @Test("maps cancellation during refresh and does not resend")
    func cancelsDuringRefresh() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 401, body: errorBody(code: "authentication_required")),
        ])
        let auth = APIClientAuthStub(refreshHandler: { throw CancellationError() })
        let client = try makeClient(transport: transport, auth: auth)

        await #expect(throws: BackendError.cancelled) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "refresh")
            )
        }
        #expect(auth.refreshCallCount == 1)
        #expect(transport.requests.count == 1)
    }

    @Test("maps cancellation during retry sleep and does not resend")
    func cancelsDuringSleep() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 500, body: errorBody(code: "internal_failure")),
            .response(statusCode: 200, body: payloadBody("must-not-send")),
        ])
        let client = try makeClient(
            transport: transport,
            auth: APIClientAuthStub(),
            sleeper: { _ in throw CancellationError() }
        )

        await #expect(throws: BackendError.cancelled) {
            let _: Payload = try await client.send(
                APIRequest(method: .get, path: "sleep")
            )
        }
        #expect(transport.requests.count == 1)
    }

    @Test("concurrent sends use isolated request IDs and decode their own responses")
    func concurrentSendsStayIsolated() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: payloadBody("first")),
            .response(statusCode: 200, body: payloadBody("second")),
        ])
        let client = try makeClient(transport: transport, auth: APIClientAuthStub())

        async let first: Payload = client.send(
            APIRequest(method: .get, path: "first")
        )
        async let second: Payload = client.send(
            APIRequest(method: .get, path: "second")
        )
        let values = try await [first, second]

        #expect(Set(values.map(\.value)) == Set(["first", "second"]))
        let requestIDs = transport.requests.compactMap {
            $0.value(forHTTPHeaderField: "x-request-id")
        }
        #expect(requestIDs.count == 2)
        #expect(Set(requestIDs).count == 2)
        #expect(requestIDs.allSatisfy { UUID(uuidString: $0) != nil })
    }

    @Test("separately registered sessions keep concurrent state isolated")
    func separateSessionsStayIsolated() async throws {
        let firstTransport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: payloadBody("first-only")),
        ])
        let secondTransport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: payloadBody("second-only")),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            auth: APIClientAuthStub()
        )
        let secondClient = try makeClient(
            transport: secondTransport,
            auth: APIClientAuthStub()
        )

        async let first: Payload = firstClient.send(
            APIRequest(method: .get, path: "first")
        )
        async let second: Payload = secondClient.send(
            APIRequest(method: .get, path: "second")
        )

        #expect(try await first == Payload(value: "first-only"))
        #expect(try await second == Payload(value: "second-only"))
        #expect(firstTransport.requests.map { $0.url?.path } == ["/v1/first"])
        #expect(secondTransport.requests.map { $0.url?.path } == ["/v1/second"])
    }

    private func makeClient(
        transport: URLProtocolStub.State,
        baseURL: String = "https://api.example.com/v1",
        auth: APIClientAuthStub,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000),
        delays: DelayRecorder = DelayRecorder(),
        sleeper: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) throws -> VowbaseAPIClient {
        let values = [
            "CONFIGURATION": "Debug",
            "SUPABASE_URL": "https://project.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "publishable-test-key",
            "VOWBASE_API_URL": baseURL,
        ]
        let configuration = try AppConfiguration(
            values: values,
            transportPolicy: .debug
        )
        let resolvedSleeper = sleeper ?? { delay in
            await delays.record(delay)
        }
        return VowbaseAPIClient(
            sessionConfiguration: URLProtocolStub.configuration(for: transport),
            configuration: configuration,
            authService: auth,
            now: { now },
            sleeper: resolvedSleeper
        )
    }

    private func payloadBody(_ value: String) -> Data {
        Data("{\"value\":\"\(value)\"}".utf8)
    }

    private func errorBody(
        code: String,
        message: String = "Safe",
        requestID: String? = nil
    ) -> Data {
        let requestIDField = requestID.map { ",\"requestId\":\"\($0)\"" } ?? ""
        return Data(
            "{\"error\":{\"code\":\"\(code)\",\"message\":\"\(message)\"\(requestIDField)}}".utf8
        )
    }
}

private final class APIClientAuthStub: AuthServicing, @unchecked Sendable {
    typealias TokenHandler = @Sendable (Int) async throws -> String
    typealias RefreshHandler = @Sendable () async throws -> Void

    private let lock = NSLock()
    private var tokenCalls = 0
    private var refreshCalls = 0
    private let tokenHandler: TokenHandler
    private let refreshHandler: RefreshHandler

    var states: AsyncStream<AuthenticationState> {
        AsyncStream { $0.finish() }
    }

    var tokenCallCount: Int {
        lock.withLock { tokenCalls }
    }

    var refreshCallCount: Int {
        lock.withLock { refreshCalls }
    }

    init(
        tokens: [String] = ["access-token"],
        tokenHandler: TokenHandler? = nil,
        refreshHandler: @escaping RefreshHandler = {}
    ) {
        self.tokenHandler = tokenHandler ?? { index in
            tokens[min(index - 1, tokens.count - 1)]
        }
        self.refreshHandler = refreshHandler
    }

    func currentAccessToken() async throws -> String {
        let call = lock.withLock {
            tokenCalls += 1
            return tokenCalls
        }
        return try await tokenHandler(call)
    }

    func refreshSession() async throws {
        lock.withLock {
            refreshCalls += 1
        }
        try await refreshHandler()
    }

    func handle(url: URL) async throws {}

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}

    func signOut() async throws {}
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}

private enum HTTPDateFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter.string(from: date)
    }
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            throw URLError(.timedOut)
        }
        await Task.yield()
    }
}
