import Foundation
import Testing
@testable import Vowbase

@Suite("Inspiration and private attachment contracts")
struct InspirationAttachmentRepositoryTests {
    private let weddingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let parentID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let attachmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test("inspiration records match the current product schema")
    func inspirationRecordDecodes() throws {
        let item = try DatabaseDecoding.decoder.decode(
            InspirationItem.self,
            from: Data("""
            {"id":"00000000-0000-0000-0000-000000000003","wedding_id":"00000000-0000-0000-0000-000000000001","title":"Floral arch","image_url":"https://example.invalid/arch.jpg","category":"florals","status":"shortlisted","position_x":0,"position_y":0,"width":240,"created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-02T00:00:00Z"}
            """.utf8)
        )

        #expect(item.category == .florals)
        #expect(item.status == .shortlisted)
    }

    @Test("attachment paths are owned by the wedding, not a caller path")
    func ownedPaths() {
        let objectID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let path = AttachmentPath.make(
            weddingID: weddingID,
            parent: .venue,
            parentID: parentID,
            fileName: "other-wedding/../../contract.pdf",
            objectID: objectID
        )

        #expect(path == "00000000-0000-0000-0000-000000000001/venue/00000000-0000-0000-0000-000000000002/00000000-0000-0000-0000-000000000004-other-wedding_.._.._contract.pdf")
        #expect(!path.contains("../"))
        #expect(!path.contains("other-wedding/"))
    }

    @Test("attachment lists apply all ownership filters")
    func attachmentListScopesWeddingAndParent() async throws {
        let log = AttachmentOperationLog()
        let database = AttachmentDatabaseSpy(
            attachment: attachment,
            log: log
        )
        let repository = SupabaseAttachmentRepository(
            database: database,
            storage: AttachmentStorageSpy(log: log)
        )

        _ = try await repository.attachments(
            weddingID: weddingID,
            parent: .vendor,
            parentID: parentID
        )

        #expect(await database.selectRequests == [
            .init(
                columns: "id,wedding_id,parent_type,parent_id,storage_path,file_name,mime_type,size_bytes,uploaded_by,created_at,updated_at",
                equalityFilters: [
                    .init(column: "wedding_id", value: weddingID.uuidString.lowercased()),
                    .init(column: "parent_type", value: "vendor"),
                    .init(column: "parent_id", value: parentID.uuidString.lowercased()),
                ]
            ),
        ])
    }

    @Test("metadata failure removes the uploaded private object")
    func uploadCompensatesForMetadataFailure() async throws {
        let log = AttachmentOperationLog()
        let database = AttachmentDatabaseSpy(
            attachment: attachment,
            insertError: .temporarilyUnavailable(message: "metadata unavailable", requestID: nil),
            log: log
        )
        let storage = AttachmentStorageSpy(log: log)
        let repository = SupabaseAttachmentRepository(database: database, storage: storage)

        await #expect(
            throws: BackendError.temporarilyUnavailable(
                message: "metadata unavailable",
                requestID: nil
            )
        ) {
            _ = try await repository.upload(
                data: Data("contract".utf8),
                fileName: "contract.pdf",
                mimeType: "application/pdf",
                weddingID: weddingID,
                parent: .venue,
                parentID: parentID
            )
        }

        let uploadedPath = try #require(await storage.uploadedPaths.first)
        #expect(await storage.removedPaths == [uploadedPath])
        #expect(await log.operations == ["auth", "storage.upload", "metadata.insert", "storage.remove"])
    }

    @Test("deletion leaves metadata intact if private object removal fails")
    func deleteOnlyDeletesMetadataAfterObjectRemoval() async throws {
        let log = AttachmentOperationLog()
        let storage = AttachmentStorageSpy(
            removeError: .forbidden(message: "Forbidden.", requestID: nil),
            log: log
        )
        let database = AttachmentDatabaseSpy(attachment: attachment, log: log)
        let repository = SupabaseAttachmentRepository(database: database, storage: storage)

        await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil)) {
            try await repository.delete(attachment)
        }
        #expect(await database.deleteRequests.isEmpty)

        let successStorage = AttachmentStorageSpy(log: log)
        let successRepository = SupabaseAttachmentRepository(database: database, storage: successStorage)
        try await successRepository.delete(attachment)
        #expect(await database.deleteRequests == [AttachmentMetadataDeleteRequest(id: attachmentID)])
        #expect(await log.operations.suffix(3) == ["auth", "storage.remove", "metadata.delete"])
    }

    @Test("membership denial happens before any storage request")
    func membershipDenialDoesNotTouchStorage() async throws {
        let log = AttachmentOperationLog()
        let database = AttachmentDatabaseSpy(
            attachment: attachment,
            authenticationError: .forbidden(message: "Forbidden.", requestID: nil),
            log: log
        )
        let storage = AttachmentStorageSpy(log: log)
        let repository = SupabaseAttachmentRepository(database: database, storage: storage)

        await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil)) {
            _ = try await repository.upload(
                data: Data("contract".utf8),
                fileName: "contract.pdf",
                mimeType: "application/pdf",
                weddingID: weddingID,
                parent: .venue,
                parentID: parentID
            )
        }
        #expect(await storage.uploadedPaths.isEmpty)
        #expect(await log.operations == ["auth"])
    }

    private var attachment: Vowbase.Attachment {
        Vowbase.Attachment(
            id: attachmentID,
            weddingID: weddingID,
            parent: .venue,
            parentID: parentID,
            storagePath: "00000000-0000-0000-0000-000000000001/venue/00000000-0000-0000-0000-000000000002/contract.pdf",
            fileName: "contract.pdf",
            mimeType: "application/pdf",
            sizeBytes: 8,
            uploadedBy: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private actor AttachmentOperationLog {
    private(set) var operations = [String]()
    func record(_ operation: String) { operations.append(operation) }
}

private actor AttachmentDatabaseSpy: AttachmentDatabaseAdapter {
    private let attachment: Vowbase.Attachment
    private let authenticationError: BackendError?
    private let insertError: BackendError?
    private let log: AttachmentOperationLog
    private(set) var selectRequests = [AttachmentSelectRequest]()
    private(set) var deleteRequests = [AttachmentMetadataDeleteRequest]()

    init(
        attachment: Vowbase.Attachment,
        authenticationError: BackendError? = nil,
        insertError: BackendError? = nil,
        log: AttachmentOperationLog
    ) {
        self.attachment = attachment
        self.authenticationError = authenticationError
        self.insertError = insertError
        self.log = log
    }

    func authenticatedUserID() async throws -> UUID {
        await log.record("auth")
        if let authenticationError { throw authenticationError }
        return UUID()
    }

    func select<Response: Decodable & Sendable>(
        _ request: AttachmentSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        selectRequests.append(request)
        return try decode(Response.self, json: "[\(attachmentJSON)]")
    }

    func insert<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataInsertRequest,
        as: Response.Type
    ) async throws -> Response {
        await log.record("metadata.insert")
        if let insertError { throw insertError }
        return try decode(Response.self, json: attachmentJSON)
    }

    func delete<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataDeleteRequest,
        as: Response.Type
    ) async throws -> Response {
        deleteRequests.append(request)
        await log.record("metadata.delete")
        return try decode(Response.self, json: "{\"id\":\"\(attachment.id.uuidString)\"}")
    }

    private var attachmentJSON: String {
        "{\"id\":\"\(attachment.id.uuidString)\",\"wedding_id\":\"\(attachment.weddingID.uuidString)\",\"parent_type\":\"\(attachment.parent.rawValue)\",\"parent_id\":\"\(attachment.parentID.uuidString)\",\"storage_path\":\"\(attachment.storagePath)\",\"file_name\":\"\(attachment.fileName)\",\"mime_type\":\"application/pdf\",\"size_bytes\":8,\"uploaded_by\":null,\"created_at\":\"2026-07-01T00:00:00Z\",\"updated_at\":\"2026-07-01T00:00:00Z\"}"
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        json: String
    ) throws -> Response {
        try DatabaseDecoding.decoder.decode(Response.self, from: Data(json.utf8))
    }
}

private actor AttachmentStorageSpy: AttachmentStorageAdapter {
    private let removeError: BackendError?
    private let log: AttachmentOperationLog
    private(set) var uploadedPaths = [String]()
    private(set) var removedPaths = [String]()

    init(removeError: BackendError? = nil, log: AttachmentOperationLog) {
        self.removeError = removeError
        self.log = log
    }

    func upload(path: String, data: Data, mimeType: String) async throws {
        uploadedPaths.append(path)
        await log.record("storage.upload")
    }

    func download(path: String) async throws -> Data {
        Data()
    }

    func remove(path: String) async throws {
        removedPaths.append(path)
        await log.record("storage.remove")
        if let removeError { throw removeError }
    }
}
