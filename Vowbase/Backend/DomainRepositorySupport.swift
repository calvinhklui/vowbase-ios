import Foundation
import Supabase

/// Shared direct PostgREST plumbing for the product repositories. It deliberately owns no
/// client: every repository receives the app's one SupabaseProvider.
enum DomainRepositorySupport {
    static func authenticated(_ provider: SupabaseProvider) async throws {
        _ = try await provider.client.auth.user()
    }

    static func normalized(_ error: any Error, fallback: String) -> BackendError {
        RepositoryErrorNormalizer.normalized(error, fallbackMessage: fallback)
    }

    static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    static func requirePatch(_ isEmpty: Bool, _ message: String) throws {
        guard !isEmpty else { throw BackendError.validation(message: message, requestID: nil) }
    }
}
