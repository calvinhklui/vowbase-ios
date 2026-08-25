import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("App dependencies")
struct AppDependenciesTests {
    @Test("live composition shares its Supabase provider and auth service")
    func liveCompositionSharesDependencies() throws {
        let configuration = try AppConfiguration(values: [
            "SUPABASE_URL": "https://supabase.example.invalid",
            "SUPABASE_PUBLISHABLE_KEY": "publishable-key",
            "VOWBASE_API_URL": "https://api.vowbase.example/v1",
            "CONFIGURATION": "Release",
        ])
        let provider = SupabaseProvider(configuration: configuration)
        let auth = AppDependenciesAuthSpy()
        let api = AppDependenciesAPIClientSpy()

        let dependencies = AppDependencies.live(
            configuration: configuration,
            makeSupabase: { _ in provider },
            makeAuth: { receivedProvider in
                #expect(receivedProvider === provider)
                return auth
            },
            makeAPI: { receivedConfiguration, receivedAuth in
                #expect(receivedConfiguration.apiBaseURL == configuration.apiBaseURL)
                #expect((receivedAuth as? AppDependenciesAuthSpy) === auth)
                return api
            }
        )

        #expect(dependencies.supabase === provider)
        #expect((dependencies.auth as? AppDependenciesAuthSpy) === auth)
        #expect((dependencies.api as? AppDependenciesAPIClientSpy) === api)
        #expect(dependencies.repositories.workspace is SupabaseWorkspaceRepository)
        #expect(dependencies.repositories.attachments is SupabaseAttachmentRepository)
        #expect(dependencies.repositories.venueDocuments is APIVenueDocumentRepository)
        #expect(dependencies.repositories.venuePhotoMutations is VenuePhotoMutationService)
    }

    @Test("auth callback handler accepts only the exact callback route")
    func authCallbackHandlerAcceptsExactRoute() async throws {
        let auth = AuthCallbackSpy()
        let handler = AuthCallbackHandler(auth: auth)
        let callback = try #require(
            URL(string: "vowbase://auth/callback?code=safe&state=expected")
        )

        let outcome = await handler.enqueue(callback)

        #expect(outcome == .handled)
        #expect(await handler.latestOutcome == .handled)
        #expect(auth.handledURLs == [callback])
    }

    @Test(
        "auth callback handler rejects non-callback custom URLs",
        arguments: [
            "https://auth/callback?code=safe",
            "vowbase://account/callback?code=safe",
            "vowbase://auth/callback/?code=safe",
            "vowbase://auth/%63allback?code=safe",
            "vowbase://user@auth/callback?code=safe",
            "vowbase://user:password@auth/callback?code=safe",
            "vowbase://auth:443/callback?code=safe",
            "vowbase://auth/callback?code=safe#fragment",
        ]
    )
    func authCallbackHandlerRejectsInvalidRoutes(value: String) async throws {
        let auth = AuthCallbackSpy()
        let handler = AuthCallbackHandler(auth: auth)
        let url = try #require(URL(string: value))

        let outcome = await handler.enqueue(url)

        #expect(outcome == .rejected)
        #expect(await handler.latestOutcome == .rejected)
        #expect(auth.handledURLs.isEmpty)
    }

    @Test("auth callback handler exposes normalized failures")
    func authCallbackHandlerExposesNormalizedFailures() async throws {
        let auth = AuthCallbackSpy(
            handleError: AuthCallbackSensitiveError(
                detail: "authorization-code raw-provider-payload"
            )
        )
        let handler = AuthCallbackHandler(auth: auth)
        let callback = try #require(URL(string: "vowbase://auth/callback?code=safe"))
        let expected = AuthCallbackHandler.Outcome.failed(
            .temporarilyUnavailable(
                message: "Authentication callback failed.",
                requestID: nil
            )
        )

        let outcome = await handler.enqueue(callback)

        #expect(outcome == expected)
        #expect(await handler.latestOutcome == expected)
        #expect(auth.handledURLs == [callback])
    }

    @Test("auth callback handler preserves order without overlapping auth calls")
    func authCallbackHandlerSerializesAuthCalls() async throws {
        let auth = BlockingAuthCallbackSpy()
        let handler = AuthCallbackHandler(auth: auth)
        let firstURL = try #require(URL(string: "vowbase://auth/callback?code=first"))
        let secondURL = try #require(URL(string: "vowbase://auth/callback?code=second"))

        let first = Task { await handler.enqueue(firstURL) }
        await auth.waitUntilFirstCallStarts()
        let second = Task { await handler.enqueue(secondURL) }
        while await handler.enqueuedCallbackCount < 2 {
            await Task.yield()
        }

        auth.releaseFirstCall()
        let outcomes = await [first.value, second.value]

        #expect(outcomes == [.handled, .handled])
        #expect(auth.handledURLs == [firstURL, secondURL])
        #expect(auth.maximumConcurrentCallCount == 1)
        #expect(await handler.latestOutcome == .handled)
    }
}

private final class AppDependenciesAuthSpy: AuthServicing, Sendable {
    var states: AsyncStream<AuthenticationState> {
        AsyncStream { $0.finish() }
    }

    func currentAccessToken() async throws -> String { "access-token" }
    func refreshSession() async throws {}
    func handle(url: URL) async throws {}

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}

    func signOut() async throws {}
}

private final class AppDependenciesAPIClientSpy: VowbaseAPIClientProtocol, Sendable {
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        throw BackendError.invalidResponse
    }
}

private struct AuthCallbackSensitiveError: Error, Sendable {
    let detail: String
}

private final class AuthCallbackSpy: AuthServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let handleError: (any Error)?
    private var handledURLStorage = [URL]()

    var handledURLs: [URL] { lock.withLock { handledURLStorage } }
    var states: AsyncStream<AuthenticationState> { AsyncStream { $0.finish() } }

    init(handleError: (any Error)? = nil) {
        self.handleError = handleError
    }

    func currentAccessToken() async throws -> String { "access-token" }
    func refreshSession() async throws {}

    func handle(url: URL) async throws {
        lock.withLock { handledURLStorage.append(url) }
        if let handleError { throw handleError }
    }

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}

    func signOut() async throws {}
}

private final class BlockingAuthCallbackSpy: AuthServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let firstCallStarted: AsyncStream<Void>
    private let firstCallStartedContinuation: AsyncStream<Void>.Continuation
    private var firstCallRelease: CheckedContinuation<Void, Never>?
    private var handledURLStorage = [URL]()
    private var activeCallCount = 0
    private var maximumConcurrentCallCountStorage = 0

    var handledURLs: [URL] { lock.withLock { handledURLStorage } }
    var maximumConcurrentCallCount: Int {
        lock.withLock { maximumConcurrentCallCountStorage }
    }
    var states: AsyncStream<AuthenticationState> { AsyncStream { $0.finish() } }

    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        firstCallStarted = pair.stream
        firstCallStartedContinuation = pair.continuation
    }

    func waitUntilFirstCallStarts() async {
        for await _ in firstCallStarted { return }
    }

    func releaseFirstCall() {
        let continuation = lock.withLock {
            let continuation = firstCallRelease
            firstCallRelease = nil
            return continuation
        }
        continuation?.resume()
    }

    func currentAccessToken() async throws -> String { "access-token" }
    func refreshSession() async throws {}

    func handle(url: URL) async throws {
        let isFirstCall = lock.withLock {
            handledURLStorage.append(url)
            activeCallCount += 1
            maximumConcurrentCallCountStorage = max(
                maximumConcurrentCallCountStorage,
                activeCallCount
            )
            return handledURLStorage.count == 1
        }

        if isFirstCall {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    firstCallRelease = continuation
                    firstCallStartedContinuation.yield(())
                }
            }
        }

        lock.withLock { activeCallCount -= 1 }
    }

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}

    func signOut() async throws {}
}
