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
    private let signStoragePhoto: (@Sendable (String) async throws -> URL)?

    init(
        api: any VowbaseAPIClientProtocol,
        signStoragePhoto: (@Sendable (String) async throws -> URL)? = nil
    ) {
        self.api = api
        self.signStoragePhoto = signStoragePhoto
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

struct VenuePhotoURLResolver: Sendable {
    private static let googlePhotoPrefix = "gplaces:"
    private static let photoReferenceRange = 20...600
    private let photoService: any VenuePhotoServicing

    init(photoService: any VenuePhotoServicing) {
        self.photoService = photoService
    }

    func resolve(
        venueID: UUID,
        photoURL: String?,
        width: Int = 1_200
    ) async -> URL? {
        if let directURL = Self.directPhotoURL(from: photoURL) {
            return directURL
        }
        if let reference = Self.googlePhotoReference(in: photoURL) {
            return try? await photoService.signedPhoto(
                venueID: venueID,
                photoReference: reference,
                width: width
            ).url
        }
        guard let photoURL, Self.isStoragePath(photoURL),
              let service = photoService as? VenuePhotoService else {
            return nil
        }
        return try? await service.signedStoragePhoto(path: photoURL)
    }

    static func directPhotoURL(from value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    private static func googlePhotoReference(in value: String?) -> String? {
        guard let value,
              value.hasPrefix(googlePhotoPrefix) else {
            return nil
        }
        let reference = String(value.dropFirst(googlePhotoPrefix.count))
        guard photoReferenceRange.contains(reference.count),
              reference.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
            return nil
        }
        return reference
    }

    private static func isStoragePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("://") else {
            return false
        }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

private extension VenuePhotoService {
    func signedStoragePhoto(path: String) async throws -> URL {
        guard let signStoragePhoto else { throw BackendError.invalidResponse }
        return try await signStoragePhoto(path)
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
