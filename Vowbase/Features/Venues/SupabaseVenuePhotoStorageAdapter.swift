import Foundation
import Supabase

/// The private bucket adapter intentionally only exposes writes. Reads keep
/// using `VenuePhotoService`'s signed-URL path, preserving existing cache and
/// Google Places signing behavior.
final class SupabaseVenuePhotoStorageAdapter: VenuePhotoStorageAdapter, @unchecked Sendable {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func upload(path: String, data: Data, mimeType: String) async throws {
        try await provider.client.storage
            .from("venue-photos")
            .upload(path, data: data, options: FileOptions(contentType: mimeType))
    }

    func remove(path: String) async throws {
        _ = try await provider.client.storage
            .from("venue-photos")
            .remove(paths: [path])
    }
}
