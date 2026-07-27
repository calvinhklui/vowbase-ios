import Foundation
import Testing
@testable import Vowbase

@Suite("Venue photo service")
struct VenuePhotoServiceTests {
    @Test("uses the authorized signing endpoint and exact payload")
    func signsVenuePhoto() async throws {
        let api = VenuePhotoAPIStub(response: Data("{\"url\":\"https://photos.example/signed?sig=opaque\",\"expiresAt\":1784995200}".utf8))
        let service = VenuePhotoService(api: api)
        let venueID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let reference = "abcdefghijklmnopqrstuvwxyz123456"

        let signed = try await service.signedPhoto(
            venueID: venueID,
            photoReference: reference,
            width: 1200
        )

        #expect(signed.expiresAt == 1_784_995_200)
        #expect(signed.url.host == "photos.example")
        let request = try #require(await api.request)
        #expect(request.path == "v1/venue-photos/sign")
        #expect(request.method == "POST")
        let payload = try #require(try requestJSON(request.body) as? [String: Any])
        #expect(payload["venueId"] as? String == venueID.uuidString.uppercased())
        #expect(payload["photoReference"] as? String == reference)
        #expect(payload["width"] as? Int == 1200)
    }

    @Test("authorization failures remain typed backend errors")
    func preservesForbidden() async throws {
        let expected = BackendError.forbidden(message: "Forbidden.", requestID: "photo-request")
        let api = VenuePhotoAPIStub(error: expected)

        await #expect(throws: expected) {
            _ = try await VenuePhotoService(api: api).signedPhoto(
                venueID: UUID(),
                photoReference: "abcdefghijklmnopqrstuvwxyz123456",
                width: 800
            )
        }
        #expect(await api.request != nil)
    }
}

private actor VenuePhotoAPIStub: VowbaseAPIClientProtocol {
    private let response: Data?
    private let error: BackendError?
    private(set) var request: CapturedVenuePhotoRequest?

    init(response: Data? = nil, error: BackendError? = nil) {
        self.response = response
        self.error = error
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        self.request = .init(method: request.method, path: request.path, body: request.body)
        if let error { throw error }
        return try JSONDecoder().decode(Response.self, from: try #require(response))
    }
}

private struct CapturedVenuePhotoRequest: Sendable {
    let method: String
    let path: String
    let body: Data?

    init<Response>(method: APIRequest<Response>.Method, path: String, body: Data?) {
        self.method = method.rawValue
        self.path = path
        self.body = body
    }
}

private func requestJSON(_ body: Data?) throws -> Any {
    try JSONSerialization.jsonObject(with: try #require(body))
}
