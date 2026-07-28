import Foundation
import Supabase

final class SupabaseAttachmentRepository: AttachmentRepository, @unchecked Sendable {
    private static let columns = "id,wedding_id,parent_type,parent_id,storage_path,file_name,mime_type,size_bytes,uploaded_by,created_at,updated_at"
    private let database: any AttachmentDatabaseAdapter
    private let storage: any AttachmentStorageAdapter

    convenience init(provider: SupabaseProvider) {
        self.init(
            database: SupabaseAttachmentDatabaseAdapter(provider: provider),
            storage: SupabaseAttachmentStorageAdapter(provider: provider)
        )
    }

    init(
        database: any AttachmentDatabaseAdapter,
        storage: any AttachmentStorageAdapter
    ) {
        self.database = database
        self.storage = storage
    }

    func attachments(
        weddingID: UUID,
        parent: AttachmentParent,
        parentID: UUID
    ) async throws -> [Attachment] {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let attachments: [Attachment] = try await database.select(
                .init(
                    columns: Self.columns,
                    equalityFilters: [
                        .init(column: "wedding_id", value: weddingID.uuidString.lowercased()),
                        .init(column: "parent_type", value: parent.rawValue),
                        .init(column: "parent_id", value: parentID.uuidString.lowercased()),
                    ]
                ),
                as: [Attachment].self
            )
            try Task.checkCancellation()
            return attachments
        } catch {
            throw normalized(error)
        }
    }

    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        weddingID: UUID,
        parent: AttachmentParent,
        parentID: UUID
    ) async throws -> Attachment {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.validation(
                message: "Attachment file name and MIME type are required.",
                requestID: nil
            )
        }

        let path = AttachmentPath.make(
            weddingID: weddingID,
            parent: parent,
            parentID: parentID,
            fileName: fileName
        )
        let metadata = AttachmentMetadataCreate(
            weddingID: weddingID,
            parent: parent,
            parentID: parentID,
            storagePath: path,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: Int64(data.count)
        )

        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            try await storage.upload(path: path, data: data, mimeType: mimeType)
            do {
                let attachment: Attachment = try await database.insert(
                    .init(columns: Self.columns, metadata: metadata),
                    as: Attachment.self
                )
                try Task.checkCancellation()
                return attachment
            } catch {
                try? await storage.remove(path: path)
                throw error
            }
        } catch {
            throw normalized(error)
        }
    }

    func download(_ attachment: Attachment) async throws -> Data {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let data = try await storage.download(path: attachment.storagePath)
            try Task.checkCancellation()
            return data
        } catch {
            throw normalized(error)
        }
    }

    func delete(_ attachment: Attachment) async throws {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            try await storage.remove(path: attachment.storagePath)
            let _: AttachmentDeleteReceipt = try await database.delete(
                .init(id: attachment.id),
                as: AttachmentDeleteReceipt.self
            )
            try Task.checkCancellation()
        } catch {
            throw normalized(error)
        }
    }

    private func normalized(_ error: any Error) -> BackendError {
        RepositoryErrorNormalizer.normalized(
            error,
            fallbackMessage: "Attachment request failed."
        )
    }
}

private struct AttachmentDeleteReceipt: Decodable, Sendable {
    let id: UUID
}

private final class SupabaseAttachmentDatabaseAdapter: AttachmentDatabaseAdapter, @unchecked Sendable {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func authenticatedUserID() async throws -> UUID {
        try Task.checkCancellation()
        let id = try await provider.client.auth.user().id
        try Task.checkCancellation()
        return id
    }

    func select<Response: Decodable & Sendable>(
        _ request: AttachmentSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        var query = provider.client.from("attachments").select(request.columns)
        for filter in request.equalityFilters {
            query = query.eq(filter.column, value: filter.value)
        }
        return try await query.order("created_at", ascending: true).execute().value
    }

    func insert<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataInsertRequest,
        as: Response.Type
    ) async throws -> Response {
        try await provider.client
            .from("attachments")
            .insert(request.metadata)
            .select(request.columns)
            .single()
            .execute()
            .value
    }

    func delete<Response: Decodable & Sendable>(
        _ request: AttachmentMetadataDeleteRequest,
        as: Response.Type
    ) async throws -> Response {
        try await provider.client
            .from("attachments")
            .delete()
            .eq("id", value: request.id.uuidString.lowercased())
            .select("id")
            .single()
            .execute()
            .value
    }
}

private final class SupabaseAttachmentStorageAdapter: AttachmentStorageAdapter, @unchecked Sendable {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func upload(path: String, data: Data, mimeType: String) async throws {
        try await provider.client.storage
            .from("wedding-attachments")
            .upload(path, data: data, options: FileOptions(contentType: mimeType))
    }

    func download(path: String) async throws -> Data {
        try await provider.client.storage
            .from("wedding-attachments")
            .download(path: path)
    }

    func remove(path: String) async throws {
        _ = try await provider.client.storage
            .from("wedding-attachments")
            .remove(paths: [path])
    }
}
