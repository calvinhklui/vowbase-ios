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
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws
    func signOut() async throws
}
