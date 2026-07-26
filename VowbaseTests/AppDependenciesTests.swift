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
