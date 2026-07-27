import Foundation

protocol AttachmentRepository: Sendable {
    func attachments(
        weddingID: UUID,
        parent: AttachmentParent,
        parentID: UUID
    ) async throws -> [Attachment]
    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        weddingID: UUID,
        parent: AttachmentParent,
        parentID: UUID
    ) async throws -> Attachment
    func download(_ attachment: Attachment) async throws -> Data
    func delete(_ attachment: Attachment) async throws
}

struct AttachmentEqualityFilter: Equatable, Sendable {
    let column: String
    let value: String
}

struct AttachmentSelectRequest: Equatable, Sendable {
    let columns: String
    let equalityFilters: [AttachmentEqualityFilter]
}

struct AttachmentMetadataInsertRequest: Equatable, Sendable {
    let columns: String
    let metadata: AttachmentMetadataCreate
}

struct AttachmentMetadataDeleteRequest: Equatable, Sendable {
    let id: UUID
}

struct AttachmentMetadataCreate: Codable, Equatable, Sendable {
    let weddingID: UUID
    let parent: AttachmentParent
    let parentID: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let sizeBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id"
        case parent = "parent_type"
        case parentID = "parent_id"
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
    }
}

protocol AttachmentDatabaseAdapter: Sendable {
    func authenticatedUserID() async throws -> UUID

    func select<Response: Decodable & Sendable>(
        _ request: AttachmentSelectRequest,
        as: Response.Type
    ) async throws -> Response

    func insert<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataInsertRequest,
        as: Response.Type
    ) async throws -> Response

    func delete<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataDeleteRequest,
        as: Response.Type
    ) async throws -> Response
}

protocol AttachmentStorageAdapter: Sendable {
    func upload(path: String, data: Data, mimeType: String) async throws
    func download(path: String) async throws -> Data
    func remove(path: String) async throws
}
