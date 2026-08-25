import Foundation

/// Owns the two-phase persistence for a user-selected venue photo.  The
/// metadata repository and object storage deliberately stay separate so this
/// code can be tested without Photos permissions or a live Supabase client.
protocol VenuePhotoMutationServicing: Sendable {
    func upload(
        data: Data,
        mimeType: String,
        venueID: UUID,
        weddingID: UUID,
        sortOrder: Int?
    ) async throws -> VenuePhoto

    /// Removes an uploaded object before its `venue_photos` record. External
    /// and Google Places photos have no owned object, so deleting them only
    /// detaches their metadata record.
    func delete(_ photo: VenuePhoto) async throws

    /// Clears the legacy `venues.photo_url` cover. An app-owned object is
    /// removed first; an HTTPS URL or `gplaces:` value is only detached.
    func deleteCoverPhoto(for venue: Venue) async throws -> Venue
}

protocol VenuePhotoMetadataMutating: Sendable {
    func authenticatedUserID() async throws -> UUID
    func createPhoto(
        _ draft: VenuePhotoDraft,
        venueID: UUID,
        weddingID: UUID
    ) async throws -> VenuePhoto
    func deletePhoto(id: UUID) async throws
    func clearCoverPhoto(venueID: UUID) async throws -> Venue
}

protocol VenuePhotoStorageAdapter: Sendable {
    func upload(path: String, data: Data, mimeType: String) async throws
    func remove(path: String) async throws
}

/// Adds an explicit authenticated preflight to the existing `VenueRepository`
/// gallery CRUD. Keeping metadata writes on that repository preserves its RLS
/// behavior and avoids a second `venue_photos` SQL implementation.
final class SupabaseVenuePhotoMetadataAdapter: VenuePhotoMetadataMutating, @unchecked Sendable {
    private let provider: SupabaseProvider
    private let repository: any VenueRepository

    init(provider: SupabaseProvider, repository: any VenueRepository) {
        self.provider = provider
        self.repository = repository
    }

    func authenticatedUserID() async throws -> UUID {
        try Task.checkCancellation()
        let userID = try await provider.client.auth.user().id
        try Task.checkCancellation()
        return userID
    }

    func createPhoto(
        _ draft: VenuePhotoDraft,
        venueID: UUID,
        weddingID: UUID
    ) async throws -> VenuePhoto {
        try await repository.createVenuePhoto(draft, venueID: venueID, weddingID: weddingID)
    }

    func deletePhoto(id: UUID) async throws {
        try await repository.deleteVenuePhoto(id: id)
    }

    func clearCoverPhoto(venueID: UUID) async throws -> Venue {
        try await repository.updateVenue(id: venueID, patch: VenuePatch(photoURL: .null))
    }
}

final class VenuePhotoMutationService: VenuePhotoMutationServicing, @unchecked Sendable {
    private let metadata: any VenuePhotoMetadataMutating
    private let storage: any VenuePhotoStorageAdapter

    init(
        metadata: any VenuePhotoMetadataMutating,
        storage: any VenuePhotoStorageAdapter
    ) {
        self.metadata = metadata
        self.storage = storage
    }

    func upload(
        data: Data,
        mimeType: String,
        venueID: UUID,
        weddingID: UUID,
        sortOrder: Int?
    ) async throws -> VenuePhoto {
        guard !data.isEmpty else {
            throw BackendError.validation(message: "Photo data is required.", requestID: nil)
        }
        guard Self.isImageMimeType(mimeType) else {
            throw BackendError.validation(message: "Venue photos must be images.", requestID: nil)
        }

        let path = VenuePhotoStoragePath.make(weddingID: weddingID, venueID: venueID)
        let draft = VenuePhotoDraft(
            url: path,
            source: "upload",
            caption: nil,
            sortOrder: sortOrder
        )

        do {
            try Task.checkCancellation()
            _ = try await metadata.authenticatedUserID()
            try await storage.upload(path: path, data: data, mimeType: mimeType)
            do {
                let photo = try await metadata.createPhoto(draft, venueID: venueID, weddingID: weddingID)
                try Task.checkCancellation()
                return photo
            } catch {
                // A metadata failure must never leave an unreachable private
                // object behind. The original metadata error is the useful one.
                try? await storage.remove(path: path)
                throw error
            }
        } catch {
            throw normalized(error)
        }
    }

    func delete(_ photo: VenuePhoto) async throws {
        do {
            try Task.checkCancellation()
            _ = try await metadata.authenticatedUserID()
            if VenuePhotoStoragePath.isOwned(
                photo.url,
                weddingID: photo.weddingID,
                venueID: photo.venueID
            ) {
                // Keep metadata when object deletion fails so the user can
                // retry instead of silently creating an orphaned storage file.
                try await storage.remove(path: photo.url)
            }
            try await metadata.deletePhoto(id: photo.id)
            try Task.checkCancellation()
        } catch {
            throw normalized(error)
        }
    }

    func deleteCoverPhoto(for venue: Venue) async throws -> Venue {
        guard let photoURL = venue.photoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !photoURL.isEmpty else {
            return venue
        }

        do {
            try Task.checkCancellation()
            _ = try await metadata.authenticatedUserID()
            if VenuePhotoStoragePath.isOwned(
                photoURL,
                weddingID: venue.weddingID,
                venueID: venue.id
            ) {
                try await storage.remove(path: photoURL)
            }
            let updated = try await metadata.clearCoverPhoto(venueID: venue.id)
            try Task.checkCancellation()
            return updated
        } catch {
            throw normalized(error)
        }
    }

    private static func isImageMimeType(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("image/")
    }

    private func normalized(_ error: any Error) -> BackendError {
        RepositoryErrorNormalizer.normalized(
            error,
            fallbackMessage: "Venue photo request failed."
        )
    }
}

/// Private `venue-photos` object names are generated from trusted identifiers,
/// never picker-provided names. This makes it safe to determine whether a
/// record owns a storage object before deleting it.
enum VenuePhotoStoragePath {
    static func make(
        weddingID: UUID,
        venueID: UUID,
        objectID: UUID = UUID()
    ) -> String {
        "\(weddingID.uuidString.lowercased())/\(venueID.uuidString.lowercased())/\(objectID.uuidString.lowercased()).jpg"
    }

    static func isOwned(_ path: String, weddingID: UUID, venueID: UUID) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == Substring(weddingID.uuidString.lowercased()),
              components[1] == Substring(venueID.uuidString.lowercased()) else {
            return false
        }

        let fileName = String(components[2])
        guard fileName.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(fileName.dropLast(4))) != nil
    }
}
