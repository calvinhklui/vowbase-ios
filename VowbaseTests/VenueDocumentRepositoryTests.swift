import Foundation
import Testing
@testable import Vowbase

@Suite("Venue document repository")
struct VenueDocumentRepositoryTests {
    @Test("lists documents through the v1 venue-scoped route")
    func listsDocuments() async throws {
        let venueID = fixtureID(2)
        let api = VenueDocumentAPIStub(responses: [
            documentListResponse(venueID: venueID),
        ])
        let repository = APIVenueDocumentRepository(api: api, transfer: VenueDocumentTransferSpy())

        let documents = try await repository.documents(venueID: venueID)

        #expect(documents.count == 1)
        #expect(documents[0].fileName == "contract.pdf")
        #expect(documents[0].sizeBytes == 4_096)
        let request = try #require((await api.requests).first)
        #expect(request.method == "GET")
        #expect(request.path == "api/v1/venue-documents/?venueId=00000000-0000-4000-8000-000000000002")
        #expect(request.body == nil)
    }

    @Test("uploads with the one-time storage token before registering exact metadata")
    func uploadsAndRegisters() async throws {
        let venueID = fixtureID(2)
        let transfer = VenueDocumentTransferSpy()
        let api = VenueDocumentAPIStub(responses: [
            Data("{\"storagePath\":\"00000000-0000-4000-8000-000000000003/venue/00000000-0000-4000-8000-000000000002/1700000000000-contract.pdf\",\"signedUrl\":\"https://storage.example/object/upload/sign/wedding-attachments/contract.pdf?existing=1\",\"token\":\"upload-token\"}".utf8),
            documentEnvelope(venueID: venueID),
        ])
        let repository = APIVenueDocumentRepository(api: api, transfer: transfer)

        let document = try await repository.upload(
            data: Data("PDF".utf8),
            fileName: "contract.pdf",
            mimeType: "application/pdf",
            venueID: venueID
        )

        #expect(document.fileName == "contract.pdf")
        let upload = try #require(await transfer.uploads.first)
        #expect(upload.data == Data("PDF".utf8))
        #expect(upload.url.host == "storage.example")
        #expect(upload.token == "upload-token")
        #expect(upload.mimeType == "application/pdf")

        let requests = await api.requests
        #expect(requests.map(\.path) == ["api/v1/venue-documents/uploads", "api/v1/venue-documents/"])
        #expect(requests.map(\.method) == ["POST", "POST"])
        let uploadPayload = try #require(try venueDocumentRequestJSON(requests[0].body) as? [String: Any])
        #expect(uploadPayload["venueId"] as? String == venueID.uuidString.uppercased())
        #expect(uploadPayload["fileName"] as? String == "contract.pdf")
        #expect(uploadPayload["contentType"] as? String == "application/pdf")
        #expect(uploadPayload["sizeBytes"] as? Int == 3)
        let registrationPayload = try #require(try venueDocumentRequestJSON(requests[1].body) as? [String: Any])
        #expect(registrationPayload["storagePath"] as? String == "00000000-0000-4000-8000-000000000003/venue/00000000-0000-4000-8000-000000000002/1700000000000-contract.pdf")
        #expect(registrationPayload["mimeType"] as? String == "application/pdf")
        #expect(registrationPayload["sizeBytes"] as? Int == 3)
    }

    @Test("mints a fresh download URL before fetching document bytes")
    func downloadsDocumentBytes() async throws {
        let venueID = fixtureID(2)
        let documentID = fixtureID(1)
        let transfer = VenueDocumentTransferSpy(downloadData: Data("downloaded".utf8))
        let api = VenueDocumentAPIStub(responses: [
            Data("{\"document\":\(documentJSONObject(venueID: venueID, documentID: documentID)),\"url\":\"https://storage.example/object/sign/wedding-attachments/contract.pdf?sig=opaque\",\"expiresIn\":300}".utf8),
        ])
        let repository = APIVenueDocumentRepository(api: api, transfer: transfer)
        let document = try JSONDecoder().decode(VenueDocument.self, from: documentJSON(venueID: venueID, documentID: documentID))

        let data = try await repository.download(document)

        #expect(data == Data("downloaded".utf8))
        #expect((await transfer.downloadURLs).map(\.host) == ["storage.example"])
        let request = try #require((await api.requests).first)
        #expect(request.method == "GET")
        #expect(request.path == "api/v1/venue-documents/00000000-0000-4000-8000-000000000001")
    }

    @Test("renames and deletes through the exact document routes")
    func renamesAndDeletes() async throws {
        let venueID = fixtureID(2)
        let documentID = fixtureID(1)
        let api = VenueDocumentAPIStub(responses: [
            Data("{\"document\":\(documentJSONObject(venueID: venueID, documentID: documentID, fileName: "signed-contract.pdf"))}".utf8),
            Data("{\"deleted\":\(documentJSONObject(venueID: venueID, documentID: documentID, fileName: "signed-contract.pdf"))}".utf8),
        ])
        let repository = APIVenueDocumentRepository(api: api, transfer: VenueDocumentTransferSpy())

        let renamed = try await repository.rename(documentID: documentID, fileName: "signed-contract.pdf")
        let deleted = try await repository.delete(documentID: documentID)

        #expect(renamed.fileName == "signed-contract.pdf")
        #expect(deleted.id == documentID)
        let requests = await api.requests
        #expect(requests.map(\.method) == ["PATCH", "DELETE"])
        #expect(requests.map(\.path) == [
            "api/v1/venue-documents/00000000-0000-4000-8000-000000000001",
            "api/v1/venue-documents/00000000-0000-4000-8000-000000000001",
        ])
        let payload = try #require(try venueDocumentRequestJSON(requests[0].body) as? [String: Any])
        #expect(payload["fileName"] as? String == "signed-contract.pdf")
        #expect(requests[1].body == nil)
    }

    @Test("rejects empty uploads before minting a storage capability")
    func rejectsEmptyUpload() async throws {
        let api = VenueDocumentAPIStub(responses: [])
        let repository = APIVenueDocumentRepository(api: api, transfer: VenueDocumentTransferSpy())

        await #expect(throws: BackendError.validation(
            message: "Document file name, type, and nonzero size are required.",
            requestID: nil
        )) {
            _ = try await repository.upload(
                data: Data(),
                fileName: "contract.pdf",
                mimeType: "application/pdf",
                venueID: fixtureID(2)
            )
        }
        #expect((await api.requests).isEmpty)
    }
}

@Suite("Venue document binary transfer")
struct VenueDocumentBinaryTransferTests {
    @Test("uses the signed upload token without a bearer credential")
    func uploadsWithSignedTokenOnly() async throws {
        let state = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: Data("{\"Key\":\"wedding-attachments/contract.pdf\"}".utf8)),
        ])
        let transfer = URLSessionVenueDocumentBinaryTransfer(
            sessionConfiguration: URLProtocolStub.configuration(for: state)
        )

        try await transfer.upload(
            data: Data("PDF".utf8),
            to: URL(string: "https://storage.example/object/upload/sign/wedding-attachments/contract.pdf?token=old-token&other=value")!,
            token: "new-token",
            mimeType: "application/pdf"
        )

        let request = try #require(state.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.httpBody == Data("PDF".utf8))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/pdf")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "max-age=3600")
        #expect(request.value(forHTTPHeaderField: "x-upsert") == "false")
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "token" })?.value == "new-token")
        #expect(components.queryItems?.first(where: { $0.name == "other" })?.value == "value")
    }

    @Test("downloads signed storage bytes without a bearer credential")
    func downloadsWithoutBearerCredential() async throws {
        let state = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: Data("file contents".utf8)),
        ])
        let transfer = URLSessionVenueDocumentBinaryTransfer(
            sessionConfiguration: URLProtocolStub.configuration(for: state)
        )

        let data = try await transfer.download(
            from: URL(string: "https://storage.example/object/sign/wedding-attachments/contract.pdf?sig=opaque")!
        )

        #expect(data == Data("file contents".utf8))
        let request = try #require(state.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("refuses unsafe storage URLs before starting a network request")
    func refusesInsecureURLs() async throws {
        let state = URLProtocolStub.State(steps: [])
        let transfer = URLSessionVenueDocumentBinaryTransfer(
            sessionConfiguration: URLProtocolStub.configuration(for: state)
        )

        await #expect(throws: BackendError.invalidResponse) {
            _ = try await transfer.download(
                from: URL(string: "http://storage.example/object/sign/contract.pdf")!
            )
        }
        #expect(state.requests.isEmpty)
    }
}

private actor VenueDocumentAPIStub: VowbaseAPIClientProtocol {
    private var responses: [Data]
    private(set) var requests = [CapturedVenueDocumentRequest]()

    init(responses: [Data]) {
        self.responses = responses
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        requests.append(.init(method: request.method, path: request.path, body: request.body))
        guard !responses.isEmpty else { throw BackendError.invalidResponse }
        return try JSONDecoder().decode(Response.self, from: responses.removeFirst())
    }
}

private actor VenueDocumentTransferSpy: VenueDocumentBinaryTransferring {
    struct Upload: Equatable, Sendable {
        let data: Data
        let url: URL
        let token: String
        let mimeType: String
    }

    private(set) var uploads = [Upload]()
    private(set) var downloadURLs = [URL]()
    private let downloadData: Data

    init(downloadData: Data = Data()) {
        self.downloadData = downloadData
    }

    func upload(data: Data, to signedURL: URL, token: String, mimeType: String) async throws {
        uploads.append(.init(data: data, url: signedURL, token: token, mimeType: mimeType))
    }

    func download(from signedURL: URL) async throws -> Data {
        downloadURLs.append(signedURL)
        return downloadData
    }
}

private struct CapturedVenueDocumentRequest: Sendable {
    let method: String
    let path: String
    let body: Data?

    init<Response>(method: APIRequest<Response>.Method, path: String, body: Data?) {
        self.method = method.rawValue
        self.path = path
        self.body = body
    }
}

private func fixtureID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
}

private func documentListResponse(venueID: UUID) -> Data {
    Data("{\"documents\":[\(documentJSONObject(venueID: venueID, documentID: fixtureID(1)))]}".utf8)
}

private func documentEnvelope(venueID: UUID) -> Data {
    Data("{\"document\":\(documentJSONObject(venueID: venueID, documentID: fixtureID(1)))}".utf8)
}

private func documentJSON(venueID: UUID, documentID: UUID) -> Data {
    Data(documentJSONObject(venueID: venueID, documentID: documentID).utf8)
}

private func documentJSONObject(
    venueID: UUID,
    documentID: UUID,
    fileName: String = "contract.pdf"
) -> String {
    """
    {"id":"\(documentID.uuidString.lowercased())","venueId":"\(venueID.uuidString.lowercased())","weddingId":"00000000-0000-4000-8000-000000000003","fileName":"\(fileName)","mimeType":"application/pdf","sizeBytes":4096,"storagePath":"00000000-0000-4000-8000-000000000003/venue/\(venueID.uuidString.lowercased())/contract.pdf","createdAt":"2026-08-24T12:00:00.000Z","updatedAt":"2026-08-24T12:01:00Z"}
    """
}

private func venueDocumentRequestJSON(_ body: Data?) throws -> Any {
    try JSONSerialization.jsonObject(with: try #require(body))
}
