import Foundation
protocol VenueRepository: Sendable {
    func venues(weddingID: UUID) async throws -> [Venue]
    func createVenue(_ draft: VenueDraft, weddingID: UUID) async throws -> Venue
    func updateVenue(id: UUID, weddingID: UUID, patch: VenuePatch) async throws -> Venue
    func deleteVenue(id: UUID) async throws
    func customColumns(weddingID: UUID) async throws -> [VenueCustomColumn]
    func createCustomColumn(_ draft: VenueCustomColumnDraft, weddingID: UUID) async throws -> VenueCustomColumn
    func updateCustomColumn(id: UUID, weddingID: UUID, patch: VenueCustomColumnPatch) async throws -> VenueCustomColumn
    func deleteCustomColumn(id: UUID, weddingID: UUID) async throws
    /// Applies only the supplied keys. JSON null clears a key rather than
    /// replacing the entire `custom_fields` object.
    func patchCustomFields(venueID: UUID, weddingID: UUID, updates: [String: JSONValue]) async throws -> Venue
    func venuePhotos(venueID:UUID)async throws->[VenuePhoto];func createVenuePhoto(_ draft:VenuePhotoDraft,venueID:UUID,weddingID:UUID)async throws->VenuePhoto;func updateVenuePhoto(id:UUID,patch:VenuePhotoPatch)async throws->VenuePhoto;func deleteVenuePhoto(id:UUID)async throws
}
