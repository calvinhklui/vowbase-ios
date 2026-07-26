import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Authentication service")
struct AuthServiceTests {
    @Test("starts loading and restores signed-in and signed-out sessions")
    func restoresInitialSessions() async throws {
        let signedInAdapter = FakeAuthAdapter()
        let signedInService = AuthService(adapter: signedInAdapter)
        let signedInStream = signedInService.states
        let signedInStates = Task {
            try await values(from: signedInStream, count: 2)
        }
        let userID = UUID()
        signedInAdapter.yield(.initialSession(.init(userID: userID, accessToken: "token")))

        #expect(try await signedInStates.value == [.loading, .signedIn(userID: userID)])

        let signedOutAdapter = FakeAuthAdapter()
        let signedOutService = AuthService(adapter: signedOutAdapter)
        let signedOutStream = signedOutService.states
        let signedOutStates = Task {
            try await values(from: signedOutStream, count: 2)
        }
        signedOutAdapter.yield(.initialSession(nil))

        #expect(try await signedOutStates.value == [.loading, .signedOut])
    }

    @Test("broadcasts transitions and replays the current state to every subscriber")
    func broadcastsAndReplaysCurrentState() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let firstUserID = UUID()
        let secondUserID = UUID()
        let firstStream = service.states
        let firstSubscriber = Task { try await values(from: firstStream, count: 2) }
        adapter.yield(.initialSession(.init(userID: firstUserID, accessToken: "token-1")))

        #expect(
            try await firstSubscriber.value
                == [.loading, .signedIn(userID: firstUserID)]
        )

        let replayStream = service.states
        let concurrentStream = service.states
        let replaySubscriber = Task { try await values(from: replayStream, count: 2) }
        let concurrentSubscriber = Task { try await values(from: concurrentStream, count: 2) }
        adapter.yield(.userUpdated(.init(userID: secondUserID, accessToken: "token-2")))

        let expected: [AuthenticationState] = [
            .signedIn(userID: firstUserID),
            .signedIn(userID: secondUserID),
        ]
        #expect(try await replaySubscriber.value == expected)
        #expect(try await concurrentSubscriber.value == expected)
    }

    @Test("maps auth events, missing sessions, and suppresses duplicate states")
    func mapsEventsWithoutDuplicates() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let userID = UUID()
        let stream = service.states
        let states = Task { try await values(from: stream, count: 4) }

        adapter.yield(.initialSession(nil))
        adapter.yield(.signedIn(.init(userID: userID, accessToken: "token")))
        adapter.yield(.tokenRefreshed(.init(userID: userID, accessToken: "new-token")))
        adapter.yield(.userUpdated(nil))

        #expect(
            try await states.value
                == [.loading, .signedOut, .signedIn(userID: userID), .signedOut]
        )
    }

    @Test(
        "preserves session-bearing recovery and MFA events",
        arguments: [AuthChangeEvent.passwordRecovery, .mfaChallengeVerified]
    )
    func preservesSessionBearingEvents(event: AuthChangeEvent) {
        let session = AuthSessionSnapshot(userID: UUID(), accessToken: "token")

        #expect(
            SupabaseAuthEventMapper.event(event, session: session)
                == .signedIn(session)
        )
        #expect(
            SupabaseAuthEventMapper.event(event, session: nil)
                == .unexpected
        )
    }

    @Test(
        "deduplicates recovery and MFA after the matching sign-in",
        arguments: [AuthChangeEvent.passwordRecovery, .mfaChallengeVerified]
    )
    func deduplicatesSessionBearingEvents(event: AuthChangeEvent) async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let session = AuthSessionSnapshot(userID: UUID(), accessToken: "token")
        let stream = service.states
        let states = Task { try await values(from: stream, count: 4) }

        adapter.yield(.initialSession(nil))
        adapter.yield(.signedIn(session))
        adapter.yield(SupabaseAuthEventMapper.event(event, session: session))
        adapter.yield(.signedOut)

        #expect(
            try await states.value
                == [
                    .loading,
                    .signedOut,
                    .signedIn(userID: session.userID),
                    .signedOut,
                ]
        )
    }

    @Test("emits a stable sanitized failure for event-stream failures")
    func sanitizesEventFailure() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let stream = service.states
        let states = Task { try await values(from: stream, count: 2) }

        adapter.finish(throwing: SensitiveTestError("secret-token provider=apple"))

        #expect(
            try await states.value
                == [.loading, .failed("Authentication state unavailable.")]
        )
    }

    @Test("emits a stable failure when a transition arrives before restoration")
    func sanitizesUnexpectedRestorationEvent() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let stream = service.states
        let states = Task { try await values(from: stream, count: 2) }

        adapter.yield(.signedIn(.init(userID: UUID(), accessToken: "secret-token")))

        #expect(
            try await states.value
                == [.loading, .failed("Authentication state unavailable.")]
        )
    }

    @Test("returns a current nonempty access token")
    func returnsCurrentAccessToken() async throws {
        let adapter = FakeAuthAdapter()
        adapter.currentSessionResult = .success(
            .init(userID: UUID(), accessToken: "access-token")
        )
        let service = AuthService(adapter: adapter)

        #expect(try await service.currentAccessToken() == "access-token")
        #expect(adapter.currentSessionCallCount == 1)
    }

    @Test(
        "maps missing and blank tokens to authentication required",
        arguments: [nil, "", "   \n\t"]
    )
    func rejectsMissingAndBlankTokens(token: String?) async {
        let adapter = FakeAuthAdapter()
        adapter.currentSessionResult = .success(
            token.map { .init(userID: UUID(), accessToken: $0) }
        )
        let service = AuthService(adapter: adapter)

        await #expect(
            throws: BackendError.authenticationRequired(message: nil, requestID: nil)
        ) {
            try await service.currentAccessToken()
        }
    }

    @Test("maps cancellation, connectivity, and sensitive auth failures safely")
    func mapsAccessTokenErrorsSafely() async {
        let cases: [(any Error, BackendError)] = [
            (CancellationError(), .cancelled),
            (URLError(.notConnectedToInternet), .networkUnavailable),
            (
                SensitiveTestError("raw-token raw-nonce provider=google"),
                .temporarilyUnavailable(
                    message: "Authentication is temporarily unavailable.",
                    requestID: nil
                )
            ),
        ]

        for (error, expected) in cases {
            let adapter = FakeAuthAdapter()
            adapter.currentSessionResult = .failure(error)
            let service = AuthService(adapter: adapter)

            await #expect(throws: expected) {
                try await service.currentAccessToken()
            }
        }
    }

    @Test("delegates refresh, URL, OIDC, and sign-out exactly once")
    func delegatesAuthOperationsExactlyOnce() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let url = try #require(URL(string: "vowbase://auth/callback?code=safe"))

        try await service.refreshSession()
        try await service.handle(url: url)
        try await service.signInWithIDToken(
            provider: .apple,
            token: "id-token",
            nonce: "nonce"
        )
        try await service.signOut()

        #expect(adapter.refreshCallCount == 1)
        #expect(adapter.handledURLs == [url])
        #expect(
            adapter.idTokenCalls
                == [.init(provider: .apple, token: "id-token", nonce: "nonce")]
        )
        #expect(adapter.signOutCallCount == 1)
    }

    @Test("sign-out changes state only when the auth event arrives")
    func signOutWaitsForEventAndDoesNotDuplicate() async throws {
        let adapter = FakeAuthAdapter()
        let service = AuthService(adapter: adapter)
        let userID = UUID()
        let initialStream = service.states
        let initialStates = Task { try await values(from: initialStream, count: 2) }
        adapter.yield(.initialSession(.init(userID: userID, accessToken: "token")))
        _ = try await initialStates.value

        try await service.signOut()
        #expect(try await values(from: service.states, count: 1) == [.signedIn(userID: userID)])

        let transitionStream = service.states
        let signedOutStates = Task { try await values(from: transitionStream, count: 2) }
        adapter.yield(.signedOut)
        adapter.yield(.signedOut)
        #expect(
            try await signedOutStates.value
                == [.signedIn(userID: userID), .signedOut]
        )
        #expect(try await values(from: service.states, count: 1) == [.signedOut])
        #expect(adapter.signOutCallCount == 1)
    }

    @Test("cancels auth observation and finishes subscribers on deinit")
    func cancelsObservationOnDeinit() async throws {
        let adapter = FakeAuthAdapter()
        let weakService: WeakAuthServiceReference

        do {
            let service = AuthService(adapter: adapter)
            weakService = WeakAuthServiceReference(service)
            _ = service.states
        }

        try await eventually {
            weakService.isNil && adapter.wasEventStreamTerminated
        }
    }

    @Test("provider constructs and retains exactly one client from app configuration")
    func providerConstructsOneSharedClient() throws {
        let configuration = try AppConfiguration(values: [
            "SUPABASE_URL": "https://supabase.example.invalid",
            "SUPABASE_PUBLISHABLE_KEY": "publishable-test-key",
            "VOWBASE_API_URL": "https://api.example.invalid",
            "CONFIGURATION": "Release",
        ])
        let capture = ClientFactoryCapture()

        let provider = SupabaseProvider(configuration: configuration) { url, key in
            capture.record(url: url, key: key)
            return SupabaseClient(supabaseURL: url, supabaseKey: key)
        }

        #expect(capture.callCount == 1)
        #expect(capture.url == configuration.supabaseURL)
        #expect(capture.key == configuration.supabasePublishableKey)
        #expect(provider.client === provider.client)
    }
}

private struct TimeoutError: Error {}

private func values<Element: Sendable>(
    from stream: AsyncStream<Element>,
    count: Int
) async throws -> [Element] {
    try await withThrowingTaskGroup(of: [Element].self) { group in
        group.addTask {
            var result = [Element]()
            for await value in stream {
                result.append(value)
                if result.count == count { return result }
            }
            throw TimeoutError()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw TimeoutError()
        }

        let result = try await group.next() ?? []
        group.cancelAll()
        return result
    }
}

private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else { throw TimeoutError() }
        await Task.yield()
    }
}

private struct SensitiveTestError: Error, Sendable {
    let detail: String

    init(_ detail: String) {
        self.detail = detail
    }
}

private final class WeakAuthServiceReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var service: AuthService?

    var isNil: Bool { lock.withLock { service == nil } }

    init(_ service: AuthService) {
        self.service = service
    }
}

private final class ClientFactoryCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (callCount: Int, url: URL?, key: String?) = (0, nil, nil)

    var callCount: Int { lock.withLock { storage.callCount } }
    var url: URL? { lock.withLock { storage.url } }
    var key: String? { lock.withLock { storage.key } }

    func record(url: URL, key: String) {
        lock.withLock {
            storage.callCount += 1
            storage.url = url
            storage.key = key
        }
    }
}

private final class FakeAuthAdapter: AuthAdapting, @unchecked Sendable {
    struct IDTokenCall: Equatable, Sendable {
        let provider: OpenIDConnectCredentials.Provider
        let token: String
        let nonce: String?
    }

    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<AuthAdapterEvent, any Error>.Continuation
    let events: AsyncThrowingStream<AuthAdapterEvent, any Error>
    private var storage = Storage()

    var currentSessionResult: Result<AuthSessionSnapshot?, any Error> {
        get { lock.withLock { storage.currentSessionResult } }
        set { lock.withLock { storage.currentSessionResult = newValue } }
    }
    var currentSessionCallCount: Int { lock.withLock { storage.currentSessionCallCount } }
    var refreshCallCount: Int { lock.withLock { storage.refreshCallCount } }
    var handledURLs: [URL] { lock.withLock { storage.handledURLs } }
    var idTokenCalls: [IDTokenCall] { lock.withLock { storage.idTokenCalls } }
    var signOutCallCount: Int { lock.withLock { storage.signOutCallCount } }
    var wasEventStreamTerminated: Bool { lock.withLock { storage.wasEventStreamTerminated } }

    init() {
        let pair = AsyncThrowingStream<AuthAdapterEvent, any Error>.makeStream()
        events = pair.stream
        continuation = pair.continuation
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.storage.wasEventStreamTerminated = true }
        }
    }

    func yield(_ event: AuthAdapterEvent) {
        continuation.yield(event)
    }

    func finish(throwing error: (any Error)? = nil) {
        continuation.finish(throwing: error)
    }

    func currentSession() async throws -> AuthSessionSnapshot? {
        let result = lock.withLock { () -> Result<AuthSessionSnapshot?, any Error> in
            storage.currentSessionCallCount += 1
            return storage.currentSessionResult
        }
        return try result.get()
    }

    func refreshSession() async throws {
        lock.withLock { storage.refreshCallCount += 1 }
    }

    func handle(url: URL) async throws {
        lock.withLock { storage.handledURLs.append(url) }
    }

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {
        lock.withLock {
            storage.idTokenCalls.append(.init(provider: provider, token: token, nonce: nonce))
        }
    }

    func signOut() async throws {
        lock.withLock { storage.signOutCallCount += 1 }
    }

    private struct Storage {
        var currentSessionResult: Result<AuthSessionSnapshot?, any Error> = .success(nil)
        var currentSessionCallCount = 0
        var refreshCallCount = 0
        var handledURLs = [URL]()
        var idTokenCalls = [IDTokenCall]()
        var signOutCallCount = 0
        var wasEventStreamTerminated = false
    }
}
