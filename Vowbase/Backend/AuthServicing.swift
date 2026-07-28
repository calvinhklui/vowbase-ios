import Foundation
import Supabase

enum AuthenticationState: Equatable, Sendable {
    case loading
    case signedOut
    case signedIn(userID: UUID)
    case failed(String)
}

protocol AuthServicing: Sendable {
    var states: AsyncStream<AuthenticationState> { get }

    func currentAccessToken() async throws -> String
    func refreshSession() async throws
    func handle(url: URL) async throws
    func signInWithGoogle() async throws
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws
    func signOut() async throws
}

extension AuthServicing {
    func signInWithGoogle() async throws {
        throw BackendError.temporarilyUnavailable(
            message: "Google sign-in is temporarily unavailable.",
            requestID: nil
        )
    }
}
