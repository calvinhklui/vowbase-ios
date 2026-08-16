import Foundation
import Testing
@testable import Vowbase

@Suite("Map workflow repository")
struct MapWorkflowRepositoryTests {
    @Test("Apple Maps selection saves a one-line postal street address")
    func appleMapsStreetAddress() {
        let address = AppleMapsAddressSearch.streetAddress(
            streetNumber: "1",
            streetName: "Apple Park Way",
            locality: "Cupertino",
            administrativeArea: "CA",
            postalCode: "95014",
            country: "United States"
        )

        #expect(address == "1 Apple Park Way, Cupertino, CA 95014, United States")
        #expect(AppleMapsAddressSearch.streetAddress(
            streetNumber: nil,
            streetName: nil,
            locality: "Cupertino",
            administrativeArea: "CA",
            postalCode: "95014",
            country: "United States"
        ) == nil)
    }

    @Test("geocode and travel requests use versioned camelCase contracts")
    func requestContractsAndFixtureDecoding() async throws {
        let api = MapAPIStub(responses: [try fixture("geocode-response"), try fixture("travel-times-response")])
        let repository = APIMapWorkflowRepository(api: api)
        let weddingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let geocodes = try await repository.geocode(query: "New York")
        let times = try await repository.travelTimes(
            weddingID: weddingID,
            origin: .init(latitude: 40.7128, longitude: -74.006),
            destinations: [.init(id: "venue-1", latitude: 40.758, longitude: -73.9855)]
        )

        #expect(geocodes.first?.provider == "nominatim")
        #expect(times.first?.source == .googleRoutes)
        let requests = await api.requests
        #expect(requests.map(\.path) == ["v1/geocode", "v1/travel-times"])
        let geocode = try #require(try requestJSON(requests[0].body) as? [String: Any])
        #expect(geocode["type"] as? String == "forward")
        #expect(geocode["query"] as? String == "New York")
        let travel = try #require(try requestJSON(requests[1].body) as? [String: Any])
        #expect(travel["weddingId"] as? String == weddingID.uuidString.uppercased())
        #expect(travel["origin"] != nil)
        #expect(travel["destinations"] != nil)
        #expect(travel["wedding_id"] == nil)
    }

    @Test("reverse geocoding uses the exact discriminated payload")
    func reversePayload() async throws {
        let api = MapAPIStub(responses: [try fixture("geocode-response")])
        let repository = APIMapWorkflowRepository(api: api)

        _ = try await repository.reverseGeocode(latitude: 40.7, longitude: -74.0)

        let payload = try #require(try requestJSON((await api.requests)[0].body) as? [String: Any])
        #expect(payload["type"] as? String == "reverse")
        #expect(payload["latitude"] as? Double == 40.7)
        #expect(payload["longitude"] as? Double == -74.0)
    }

    @Test("travel destination bounds fail locally without a network request")
    func destinationLimit() async throws {
        let api = MapAPIStub(responses: [])
        let repository = APIMapWorkflowRepository(api: api)
        await #expect(throws: BackendError.validation(message: "Travel times require between 1 and 40 destinations.", requestID: nil)) {
            _ = try await repository.travelTimes(
                weddingID: UUID(),
                origin: .init(latitude: 0, longitude: 0),
                destinations: []
            )
        }
        #expect(await api.requests.isEmpty)
    }

    @Test("shared API errors propagate unchanged")
    func sharedErrors() async throws {
        let api = MapAPIStub(
            responses: [],
            error: .temporarilyUnavailable(message: "Location lookup failed. Try again.", requestID: "req-1")
        )
        await #expect(throws: BackendError.temporarilyUnavailable(message: "Location lookup failed. Try again.", requestID: "req-1")) {
            _ = try await APIMapWorkflowRepository(api: api).geocode(query: "New York")
        }
    }
}

private actor MapAPIStub: VowbaseAPIClientProtocol {
    private var responses: [Data]
    private let error: BackendError?
    private(set) var requests = [CapturedMapRequest]()

    init(responses: [Data], error: BackendError? = nil) {
        self.responses = responses
        self.error = error
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        requests.append(.init(path: request.path, body: request.body))
        if let error { throw error }
        guard !responses.isEmpty else { throw BackendError.invalidResponse }
        return try JSONDecoder().decode(Response.self, from: responses.removeFirst())
    }
}

private struct CapturedMapRequest: Sendable {
    let path: String
    let body: Data?
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle(for: MapFixtureBundle.self).url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
}

private final class MapFixtureBundle {}

private func requestJSON(_ body: Data?) throws -> Any {
    try JSONSerialization.jsonObject(with: try #require(body))
}
