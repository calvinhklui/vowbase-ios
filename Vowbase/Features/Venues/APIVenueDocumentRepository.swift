import Foundation

final class APIVenueDocumentRepository: VenueDocumentRepository, @unchecked Sendable {
    private let api: any VowbaseAPIClientProtocol
    private let transfer: any VenueDocumentBinaryTransferring

    init(
        api: any VowbaseAPIClientProtocol,
        transfer: any VenueDocumentBinaryTransferring = URLSessionVenueDocumentBinaryTransfer()
    ) {
        self.api = api
        self.transfer = transfer
    }

    func documents(venueID: UUID) async throws -> [VenueDocument] {
        let response: VenueDocumentsResponse = try await api.send(
            APIRequest(method: .get, path: "api/v1/venue-documents/?venueId=\(pathID(venueID))")
        )
        return response.documents
    }

    func createUpload(
        venueID: UUID,
        fileName: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> VenueDocumentUpload {
        try validate(fileName: fileName, mimeType: mimeType, sizeBytes: sizeBytes)
        return try await api.send(
            APIRequest(
                method: .post,
                path: "api/v1/venue-documents/uploads",
                body: try encode(VenueDocumentUploadRequest(
                    venueID: venueID,
                    fileName: fileName,
                    contentType: mimeType,
                    sizeBytes: sizeBytes
                ))
            )
        )
    }

    func register(
        venueID: UUID,
        storagePath: String,
        fileName: String,
        mimeType: String?,
        sizeBytes: Int64?
    ) async throws -> VenueDocument {
        guard !storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sizeBytes.map({ $0 >= 0 }) ?? true else {
            throw BackendError.validation(
                message: "Document metadata is invalid.",
                requestID: nil
            )
        }

        let response: VenueDocumentResponse = try await api.send(
            APIRequest(
                method: .post,
                path: "api/v1/venue-documents/",
                body: try encode(VenueDocumentRegistrationRequest(
                    venueID: venueID,
                    storagePath: storagePath,
                    fileName: fileName,
                    mimeType: mimeType,
                    sizeBytes: sizeBytes
                ))
            )
        )
        return response.document
    }

    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        venueID: UUID
    ) async throws -> VenueDocument {
        let upload = try await createUpload(
            venueID: venueID,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: Int64(data.count)
        )
        try await transfer.upload(
            data: data,
            to: upload.signedURL,
            token: upload.token,
            mimeType: mimeType
        )
        return try await register(
            venueID: venueID,
            storagePath: upload.storagePath,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: Int64(data.count)
        )
    }

    func signedDownload(documentID: UUID) async throws -> VenueDocumentDownload {
        try await api.send(
            APIRequest(method: .get, path: "api/v1/venue-documents/\(pathID(documentID))")
        )
    }

    func download(_ document: VenueDocument) async throws -> Data {
        let signedDownload = try await signedDownload(documentID: document.id)
        return try await transfer.download(from: signedDownload.url)
    }

    func rename(documentID: UUID, fileName: String) async throws -> VenueDocument {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.validation(message: "A document file name is required.", requestID: nil)
        }
        let response: VenueDocumentResponse = try await api.send(
            APIRequest(
                method: .patch,
                path: "api/v1/venue-documents/\(pathID(documentID))",
                body: try encode(VenueDocumentRenameRequest(fileName: fileName))
            )
        )
        return response.document
    }

    func delete(documentID: UUID) async throws -> VenueDocument {
        let response: VenueDocumentDeletionResponse = try await api.send(
            APIRequest(method: .delete, path: "api/v1/venue-documents/\(pathID(documentID))")
        )
        return response.deleted
    }

    private func validate(fileName: String, mimeType: String, sizeBytes: Int64) throws {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sizeBytes > 0 else {
            throw BackendError.validation(
                message: "Document file name, type, and nonzero size are required.",
                requestID: nil
            )
        }
    }

    private func pathID(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw BackendError.invalidResponse
        }
    }
}

private struct VenueDocumentsResponse: Decodable, Sendable {
    let documents: [VenueDocument]
}

private struct VenueDocumentResponse: Decodable, Sendable {
    let document: VenueDocument
}

private struct VenueDocumentDeletionResponse: Decodable, Sendable {
    let deleted: VenueDocument
}

private struct VenueDocumentUploadRequest: Encodable {
    let venueID: UUID
    let fileName: String
    let contentType: String
    let sizeBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case venueID = "venueId"
        case fileName
        case contentType
        case sizeBytes
    }
}

private struct VenueDocumentRegistrationRequest: Encodable {
    let venueID: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String?
    let sizeBytes: Int64?

    private enum CodingKeys: String, CodingKey {
        case venueID = "venueId"
        case storagePath
        case fileName
        case mimeType
        case sizeBytes
    }
}

private struct VenueDocumentRenameRequest: Encodable {
    let fileName: String
}
