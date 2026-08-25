import Foundation

protocol VenueDocumentRepository: Sendable {
    func documents(venueID: UUID) async throws -> [VenueDocument]

    func createUpload(
        venueID: UUID,
        fileName: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> VenueDocumentUpload

    func register(
        venueID: UUID,
        storagePath: String,
        fileName: String,
        mimeType: String?,
        sizeBytes: Int64?
    ) async throws -> VenueDocument

    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        venueID: UUID
    ) async throws -> VenueDocument

    func signedDownload(documentID: UUID) async throws -> VenueDocumentDownload
    func download(_ document: VenueDocument) async throws -> Data
    func rename(documentID: UUID, fileName: String) async throws -> VenueDocument
    func delete(documentID: UUID) async throws -> VenueDocument
}
