import Foundation

final class APIMapWorkflowRepository: MapWorkflowRepository, @unchecked Sendable {
    private let api: any VowbaseAPIClientProtocol

    init(api: any VowbaseAPIClientProtocol) {
        self.api = api
    }

    func geocode(query: String) async throws -> [GeocodeResult] {
        let response: GeocodeResponse = try await send(
            path: "v1/geocode",
            body: GeocodeRequest.forward(query: query)
        )
        return response.results
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodeResult] {
        let response: GeocodeResponse = try await send(
            path: "v1/geocode",
            body: GeocodeRequest.reverse(latitude: latitude, longitude: longitude)
        )
        return response.results
    }

    func travelTimes(
        weddingID: UUID,
        origin: Coordinate,
        destinations: [TravelDestination]
    ) async throws -> [TravelTime] {
        guard (1...40).contains(destinations.count) else {
            throw BackendError.validation(
                message: "Travel times require between 1 and 40 destinations.",
                requestID: nil
            )
        }
        let response: TravelTimesResponse = try await send(
            path: "v1/travel-times",
            body: TravelTimesRequest(
                weddingID: weddingID,
                origin: origin,
                destinations: destinations
            )
        )
        return response.results
    }

    private func send<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw BackendError.invalidResponse
        }
        return try await api.send(APIRequest(method: .post, path: path, body: data))
    }
}

private enum GeocodeRequest: Encodable, Sendable {
    case forward(query: String)
    case reverse(latitude: Double, longitude: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case latitude
        case longitude
    }

    private enum Kind: String, Codable {
        case forward
        case reverse
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .forward(query):
            try container.encode(Kind.forward, forKey: .type)
            try container.encode(query, forKey: .query)
        case let .reverse(latitude, longitude):
            try container.encode(Kind.reverse, forKey: .type)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
        }
    }
}

private struct GeocodeResponse: Codable, Sendable {
    let results: [GeocodeResult]
    let cached: Bool
}

private struct TravelTimesRequest: Codable, Sendable {
    let weddingID: UUID
    let origin: Coordinate
    let destinations: [TravelDestination]

    private enum CodingKeys: String, CodingKey {
        case weddingID = "weddingId"
        case origin
        case destinations
    }
}

private struct TravelTimesResponse: Codable, Sendable {
    let results: [TravelTime]
}
