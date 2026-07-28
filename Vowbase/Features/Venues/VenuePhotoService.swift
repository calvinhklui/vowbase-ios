import Foundation

protocol VenuePhotoServicing: Sendable {
    func signedPhoto(
        venueID: UUID,
        photoReference: String,
        width: Int
    ) async throws -> SignedVenuePhoto
}

struct SignedVenuePhoto: Codable, Equatable, Sendable {
    let url: URL
    let expiresAt: Int
}

final class VenuePhotoService: VenuePhotoServicing, @unchecked Sendable {
    private let api: any VowbaseAPIClientProtocol

    init(api: any VowbaseAPIClientProtocol) {
        self.api = api
    }

    func signedPhoto(
        venueID: UUID,
        photoReference: String,
        width: Int = 800
    ) async throws -> SignedVenuePhoto {
        let request = VenuePhotoSigningRequest(
            venueID: venueID,
            photoReference: photoReference,
            width: width
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(request)
        } catch {
            throw BackendError.invalidResponse
        }
        return try await api.send(
            APIRequest(method: .post, path: "v1/venue-photos/sign", body: data)
        )
    }
}

private struct VenuePhotoSigningRequest: Encodable {
    let venueID: UUID
    let photoReference: String
    let width: Int

    private enum CodingKeys: String, CodingKey {
        case venueID = "venueId"
        case photoReference
        case width
    }
}
