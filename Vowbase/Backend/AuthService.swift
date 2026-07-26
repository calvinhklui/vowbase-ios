import Foundation
import Supabase

struct AuthSessionSnapshot: Equatable, Sendable {
    let userID: UUID
    let accessToken: String
}

enum AuthAdapterEvent: Equatable, Sendable {
    case initialSession(AuthSessionSnapshot?)
    case signedIn(AuthSessionSnapshot?)
    case signedOut
    case tokenRefreshed(AuthSessionSnapshot?)
    case userUpdated(AuthSessionSnapshot?)
    case unexpected
}

protocol AuthAdapting: Sendable {
    var events: AsyncThrowingStream<AuthAdapterEvent, any Error> { get }

    func currentSession() async throws -> AuthSessionSnapshot?
    func refreshSession() async throws
    func handle(url: URL) async throws
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws
    func signOut() async throws
}

final class AuthService: AuthServicing {
    private static let stateFailureMessage = "Authentication state unavailable."
    private static let operationFailureMessage = "Authentication is temporarily unavailable."

    private let adapter: any AuthAdapting
    private let stateHub: AuthenticationStateHub
    private let observationTask: Task<Void, Never>

    var states: AsyncStream<AuthenticationState> {
        stateHub.stream()
    }

    convenience init(provider: SupabaseProvider) {
        self.init(adapter: SupabaseAuthAdapter(client: provider.client))
    }

    init(adapter: any AuthAdapting) {
        let stateHub = AuthenticationStateHub(initialState: .loading)
        self.adapter = adapter
        self.stateHub = stateHub
        observationTask = Task { [adapter, stateHub] in
            await Self.observe(adapter: adapter, stateHub: stateHub)
        }
    }

    deinit {
        stateHub.finish()
        observationTask.cancel()
    }

    func currentAccessToken() async throws -> String {
        do {
            guard let token = try await adapter.currentSession()?.accessToken,
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackendError.authenticationRequired(message: nil, requestID: nil)
            }
            return token
        } catch {
            throw Self.normalized(error)
        }
    }

    func refreshSession() async throws {
        do {
            try await adapter.refreshSession()
        } catch {
            throw Self.normalized(error)
        }
    }

    func handle(url: URL) async throws {
        do {
            try await adapter.handle(url: url)
        } catch {
            throw Self.normalized(error)
        }
    }

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {
        do {
            try await adapter.signInWithIDToken(
                provider: provider,
                token: token,
                nonce: nonce
            )
        } catch {
            throw Self.normalized(error)
        }
    }

    func signOut() async throws {
        do {
            try await adapter.signOut()
        } catch {
            throw Self.normalized(error)
        }
    }

    private static func observe(
        adapter: any AuthAdapting,
        stateHub: AuthenticationStateHub
    ) async {
        var hasAppliedAuthoritativeEvent = false

        do {
            for try await event in adapter.events {
                guard !Task.isCancelled else { return }

                switch event {
                case .initialSession(let session):
                    guard !hasAppliedAuthoritativeEvent else { continue }
                    stateHub.send(state(for: session))

                case .signedIn(let session),
                     .tokenRefreshed(let session),
                     .userUpdated(let session):
                    hasAppliedAuthoritativeEvent = true
                    stateHub.send(state(for: session))

                case .signedOut:
                    hasAppliedAuthoritativeEvent = true
                    stateHub.send(.signedOut)

                case .unexpected:
                    stateHub.send(.failed(stateFailureMessage))
                }
            }

            guard !Task.isCancelled else { return }
            stateHub.send(.failed(stateFailureMessage))
        } catch {
            guard !Task.isCancelled else { return }
            stateHub.send(.failed(stateFailureMessage))
        }
    }

    private static func state(for session: AuthSessionSnapshot?) -> AuthenticationState {
        guard let session else { return .signedOut }
        return .signedIn(userID: session.userID)
    }

    private static func normalized(_ error: any Error) -> BackendError {
        if let backendError = error as? BackendError {
            return backendError
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .networkUnavailable
        }
        if let authError = error as? AuthError {
            if authError.errorCode == .sessionNotFound
                || authError.errorCode == .sessionExpired
                || authError.errorCode == .refreshTokenNotFound
                || authError.errorCode == .refreshTokenAlreadyUsed
                || authError.errorCode == .noAuthorization
                || authError.errorCode == .invalidJWT
                || authError.errorCode == .invalidCredentials {
                return .authenticationRequired(message: nil, requestID: nil)
            }
            if authError.errorCode == .overRequestRateLimit {
                return .rateLimited(
                    message: "Authentication rate limit reached.",
                    requestID: nil
                )
            }
        }
        return .temporarilyUnavailable(message: operationFailureMessage, requestID: nil)
    }
}

private final class AuthenticationStateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: AuthenticationState
    private var continuations = [UUID: AsyncStream<AuthenticationState>.Continuation]()
    private var isFinished = false

    init(initialState: AuthenticationState) {
        currentState = initialState
    }

    func stream() -> AsyncStream<AuthenticationState> {
        let id = UUID()
        let pair = AsyncStream<AuthenticationState>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        pair.continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id: id)
        }

        var shouldFinish = false
        lock.withLock {
            guard !isFinished else {
                shouldFinish = true
                return
            }
            continuations[id] = pair.continuation
            pair.continuation.yield(currentState)
        }
        if shouldFinish {
            pair.continuation.finish()
        }
        return pair.stream
    }

    func send(_ state: AuthenticationState) {
        let activeContinuations = lock.withLock {
            guard !isFinished, currentState != state else {
                return [AsyncStream<AuthenticationState>.Continuation]()
            }
            currentState = state
            return Array(continuations.values)
        }
        for continuation in activeContinuations {
            continuation.yield(state)
        }
    }

    func finish() {
        let activeContinuations = lock.withLock {
            guard !isFinished else {
                return [AsyncStream<AuthenticationState>.Continuation]()
            }
            isFinished = true
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: id)
        }
    }
}

private final class SupabaseAuthAdapter: AuthAdapting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var events: AsyncThrowingStream<AuthAdapterEvent, any Error> {
        let source = client.auth.authStateChanges
        let pair = AsyncThrowingStream<AuthAdapterEvent, any Error>.makeStream()
        let task = Task {
            for await (event, session) in source {
                guard !Task.isCancelled else { break }
                pair.continuation.yield(
                    SupabaseAuthEventMapper.event(
                        event,
                        session: session.map(Self.snapshot)
                    )
                )
            }
            pair.continuation.finish()
        }
        pair.continuation.onTermination = { _ in task.cancel() }
        return pair.stream
    }

    func currentSession() async throws -> AuthSessionSnapshot? {
        do {
            return Self.snapshot(try await client.auth.session)
        } catch AuthError.sessionMissing {
            return nil
        }
    }

    func refreshSession() async throws {
        _ = try await client.auth.refreshSession()
    }

    func handle(url: URL) async throws {
        _ = try await client.auth.session(from: url)
    }

    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: provider,
                idToken: token,
                nonce: nonce
            )
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private static func snapshot(_ session: Session) -> AuthSessionSnapshot {
        AuthSessionSnapshot(
            userID: session.user.id,
            accessToken: session.accessToken
        )
    }
}

enum SupabaseAuthEventMapper {
    static func event(
        _ event: AuthChangeEvent,
        session: AuthSessionSnapshot?
    ) -> AuthAdapterEvent {
        switch event {
        case .initialSession:
            return .initialSession(session)
        case .signedIn:
            return .signedIn(session)
        case .signedOut, .userDeleted:
            return .signedOut
        case .tokenRefreshed:
            return .tokenRefreshed(session)
        case .userUpdated:
            return .userUpdated(session)
        case .passwordRecovery, .mfaChallengeVerified:
            guard let session else { return .unexpected }
            return .signedIn(session)
        @unknown default:
            return .unexpected
        }
    }
}
