import Foundation

/// Metadata for a file that has been attached to a venue through the v1 API.
struct VenueDocument: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let venueID: UUID
    let weddingID: UUID
    let fileName: String
    let mimeType: String?
    let sizeBytes: Int64?
    let storagePath: String
    let createdAt: Date
    let updatedAt: Date
}

extension VenueDocument: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case venueID = "venueId"
        case weddingID = "weddingId"
        case fileName
        case mimeType
        case sizeBytes
        case storagePath
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        venueID = try values.decode(UUID.self, forKey: .venueID)
        weddingID = try values.decode(UUID.self, forKey: .weddingID)
        fileName = try values.decode(String.self, forKey: .fileName)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        sizeBytes = try values.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        storagePath = try values.decode(String.self, forKey: .storagePath)
        createdAt = try ISO8601DateDecoding.decode(values.superDecoder(forKey: .createdAt))
        updatedAt = try ISO8601DateDecoding.decode(values.superDecoder(forKey: .updatedAt))
    }
}

/// The one-time capability returned before uploading a venue document's bytes.
struct VenueDocumentUpload: Decodable, Equatable, Sendable {
    let storagePath: String
    let signedURL: URL
    let token: String

    private enum CodingKeys: String, CodingKey {
        case storagePath
        case signedURL = "signedUrl"
        case token
    }
}

/// The short-lived download capability returned for an existing venue document.
struct VenueDocumentDownload: Decodable, Equatable, Sendable {
    let document: VenueDocument
    let url: URL
    let expiresIn: Int
}
