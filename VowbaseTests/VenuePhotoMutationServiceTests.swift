import Foundation
import Testing
@testable import Vowbase

@Suite("Venue photo mutation service")
struct VenuePhotoMutationServiceTests {
    private let weddingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let venueID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test("generated paths are scoped to one wedding and venue")
    func generatedPathIsOwned() {
        let objectID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let path = VenuePhotoStoragePath.make(
            weddingID: weddingID,
            venueID: venueID,
            objectID: objectID
        )

        #expect(path == "00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000002/00000000-0000-0000-0000-000000000004.jpg")
        #expect(VenuePhotoStoragePath.isOwned(path, weddingID: weddingID, venueID: venueID))
        #expect(!VenuePhotoStoragePath.isOwned(path, weddingID: UUID(), venueID: venueID))
        #expect(!VenuePhotoStoragePath.isOwned("\(weddingID.uuidString.lowercased())}/\(venueID.uuidString.lowercased())}/not-a-uuid.jpg", weddingID: weddingID, venueID: venueID))
        #expect(!VenuePhotoStoragePath.isOwned("https://images.example/venue.jpg", weddingID: weddingID, venueID: venueID))
    }

    @Test("upload stores the private object before registering gallery metadata")
    func uploadStoresThenRegistersMetadata() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)

        _ = try await service.upload(
            data: Data([0xFF, 0xD8]),
            mimeType: "image/jpeg",
            venueID: venueID,
            weddingID: weddingID,
            sortOrder: 4
        )

        let uploadedPath = try #require(await storage.uploadedPaths.first)
        #expect(VenuePhotoStoragePath.isOwned(uploadedPath, weddingID: weddingID, venueID: venueID))
        let draft = try #require(await metadata.createdDrafts.first)
        #expect(draft == VenuePhotoDraft(url: uploadedPath, source: "upload", caption: nil, sortOrder: 4))
        #expect(await metadata.createdVenueIDs == [venueID])
        #expect(await metadata.createdWeddingIDs == [weddingID])
        #expect(await log.operations == ["auth", "storage.upload", "metadata.create"])
    }

    @Test("metadata failure removes the just-uploaded private object")
    func uploadCompensatesForMetadataFailure() async throws {
        let log = VenuePhotoOperationLog()
        let expected = BackendError.temporarilyUnavailable(message: "metadata unavailable", requestID: nil)
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, createError: expected, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)

        await #expect(throws: expected) {
            _ = try await service.upload(
                data: Data([0xFF, 0xD8]),
                mimeType: "image/jpeg",
                venueID: venueID,
                weddingID: weddingID,
                sortOrder: nil
            )
        }

        let uploadedPath = try #require(await storage.uploadedPaths.first)
        #expect(await storage.removedPaths == [uploadedPath])
        #expect(await log.operations == ["auth", "storage.upload", "metadata.create", "storage.remove"])
    }

    @Test("owned gallery deletion removes the object before metadata")
    func deleteOwnedPhotoRemovesStorageThenMetadata() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)
        let ownedPhoto = VenuePhoto(
            id: photoID,
            venueID: venueID,
            weddingID: weddingID,
            url: VenuePhotoStoragePath.make(weddingID: weddingID, venueID: venueID, objectID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
            source: "upload",
            caption: nil,
            sortOrder: 0,
            createdAt: .now
        )

        try await service.delete(ownedPhoto)

        #expect(await storage.removedPaths == [ownedPhoto.url])
        #expect(await metadata.deletedPhotoIDs == [photoID])
        #expect(await log.operations == ["auth", "storage.remove", "metadata.delete"])
    }

    @Test("external and Google Places gallery deletion only detaches metadata")
    func deleteExternalPhotoDoesNotDeleteUpstreamObject() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)
        let externalPhoto = VenuePhoto(
            id: photoID,
            venueID: venueID,
            weddingID: weddingID,
            url: "gplaces:abcdefghijklmnopqrstuvwxyz123456",
            source: "google",
            caption: nil,
            sortOrder: 0,
            createdAt: .now
        )

        try await service.delete(externalPhoto)

        #expect(await storage.removedPaths.isEmpty)
        #expect(await metadata.deletedPhotoIDs == [photoID])
        #expect(await log.operations == ["auth", "metadata.delete"])
    }

    @Test("failed owned object deletion keeps gallery metadata for retry")
    func deleteFailureKeepsMetadata() async throws {
        let log = VenuePhotoOperationLog()
        let expected = BackendError.forbidden(message: "Forbidden.", requestID: nil)
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(removeError: expected, log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)
        let ownedPhoto = VenuePhoto(
            id: photoID,
            venueID: venueID,
            weddingID: weddingID,
            url: VenuePhotoStoragePath.make(weddingID: weddingID, venueID: venueID),
            source: "upload",
            caption: nil,
            sortOrder: 0,
            createdAt: .now
        )

        await #expect(throws: expected) { try await service.delete(ownedPhoto) }
        #expect(await metadata.deletedPhotoIDs.isEmpty)
    }

    @Test("legacy external cover deletion clears the database field without touching upstream")
    func deleteExternalCoverOnlyDetaches() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)

        _ = try await service.deleteCoverPhoto(for: venue(photoURL: "https://images.example/cover.jpg"))

        #expect(await storage.removedPaths.isEmpty)
        #expect(await metadata.clearedCoverVenueIDs == [venueID])
        #expect(await log.operations == ["auth", "cover.clear"])
    }

    @Test("legacy owned cover removes its object before clearing the field")
    func deleteOwnedCoverRemovesStorageThenClears() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)
        let path = VenuePhotoStoragePath.make(weddingID: weddingID, venueID: venueID)

        _ = try await service.deleteCoverPhoto(for: venue(photoURL: path))

        #expect(await storage.removedPaths == [path])
        #expect(await metadata.clearedCoverVenueIDs == [venueID])
        #expect(await log.operations == ["auth", "storage.remove", "cover.clear"])
    }

    @Test("non-image and empty uploads fail before touching storage")
    func rejectsInvalidUploadInput() async throws {
        let log = VenuePhotoOperationLog()
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)

        await #expect(throws: BackendError.validation(message: "Photo data is required.", requestID: nil)) {
            _ = try await service.upload(data: Data(), mimeType: "image/jpeg", venueID: venueID, weddingID: weddingID, sortOrder: nil)
        }
        await #expect(throws: BackendError.validation(message: "Venue photos must be images.", requestID: nil)) {
            _ = try await service.upload(data: Data([1]), mimeType: "application/pdf", venueID: venueID, weddingID: weddingID, sortOrder: nil)
        }
        #expect(await log.operations.isEmpty)
        #expect(await storage.uploadedPaths.isEmpty)
    }

    @Test("authentication failure happens before an upload reaches private storage")
    func authenticationFailureDoesNotTouchStorage() async throws {
        let log = VenuePhotoOperationLog()
        let expected = BackendError.authenticationRequired(message: nil, requestID: nil)
        let metadata = VenuePhotoMetadataSpy(photo: galleryPhoto, authenticationError: expected, log: log)
        let storage = VenuePhotoStorageSpy(log: log)
        let service = VenuePhotoMutationService(metadata: metadata, storage: storage)

        await #expect(throws: expected) {
            _ = try await service.upload(
                data: Data([0xFF, 0xD8]),
                mimeType: "image/jpeg",
                venueID: venueID,
                weddingID: weddingID,
                sortOrder: nil
            )
        }

        #expect(await log.operations == ["auth"])
        #expect(await storage.uploadedPaths.isEmpty)
    }

    private var galleryPhoto: VenuePhoto {
        VenuePhoto(
            id: photoID,
            venueID: venueID,
            weddingID: weddingID,
            url: "https://images.example/venue.jpg",
            source: "research",
            caption: nil,
            sortOrder: 0,
            createdAt: .now
        )
    }

    private func venue(photoURL: String?) -> Venue {
        Venue(
            id: venueID,
            weddingID: weddingID,
            name: "Riverside Pavilion",
            status: .considering,
            address: nil,
            city: nil,
            state: nil,
            country: nil,
            contactName: nil,
            contactEmail: nil,
            contactPhone: nil,
            website: nil,
            capacityMin: nil,
            capacityMax: nil,
            capacityText: nil,
            priceEstimate: nil,
            priceNotes: nil,
            venueEstimateText: nil,
            allInEstimateText: nil,
            availableDatesText: nil,
            ourNotes: nil,
            summary: nil,
            latitude: nil,
            longitude: nil,
            photoURL: photoURL,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

private actor VenuePhotoOperationLog {
    private(set) var operations = [String]()
    func record(_ operation: String) { operations.append(operation) }
}

private actor VenuePhotoMetadataSpy: VenuePhotoMetadataMutating {
    private let photo: VenuePhoto
    private let authenticationError: BackendError?
    private let createError: BackendError?
    private let log: VenuePhotoOperationLog
    private(set) var createdDrafts = [VenuePhotoDraft]()
    private(set) var createdVenueIDs = [UUID]()
    private(set) var createdWeddingIDs = [UUID]()
    private(set) var deletedPhotoIDs = [UUID]()
    private(set) var clearedCoverVenueIDs = [UUID]()

    init(
        photo: VenuePhoto,
        authenticationError: BackendError? = nil,
        createError: BackendError? = nil,
        log: VenuePhotoOperationLog
    ) {
        self.photo = photo
        self.authenticationError = authenticationError
        self.createError = createError
        self.log = log
    }

    func authenticatedUserID() async throws -> UUID {
        await log.record("auth")
        if let authenticationError { throw authenticationError }
        return UUID()
    }

    func createPhoto(_ draft: VenuePhotoDraft, venueID: UUID, weddingID: UUID) async throws -> VenuePhoto {
        createdDrafts.append(draft)
        createdVenueIDs.append(venueID)
        createdWeddingIDs.append(weddingID)
        await log.record("metadata.create")
        if let createError { throw createError }
        return photo
    }

    func deletePhoto(id: UUID) async throws {
        deletedPhotoIDs.append(id)
        await log.record("metadata.delete")
    }

    func clearCoverPhoto(venueID: UUID) async throws -> Venue {
        clearedCoverVenueIDs.append(venueID)
        await log.record("cover.clear")
        return Venue(
            id: venueID,
            weddingID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Riverside Pavilion",
            status: .considering,
            address: nil,
            city: nil,
            state: nil,
            country: nil,
            contactName: nil,
            contactEmail: nil,
            contactPhone: nil,
            website: nil,
            capacityMin: nil,
            capacityMax: nil,
            capacityText: nil,
            priceEstimate: nil,
            priceNotes: nil,
            venueEstimateText: nil,
            allInEstimateText: nil,
            availableDatesText: nil,
            ourNotes: nil,
            summary: nil,
            latitude: nil,
            longitude: nil,
            photoURL: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

private actor VenuePhotoStorageSpy: VenuePhotoStorageAdapter {
    private let removeError: BackendError?
    private let log: VenuePhotoOperationLog
    private(set) var uploadedPaths = [String]()
    private(set) var removedPaths = [String]()

    init(removeError: BackendError? = nil, log: VenuePhotoOperationLog) {
        self.removeError = removeError
        self.log = log
    }

    func upload(path: String, data: Data, mimeType: String) async throws {
        uploadedPaths.append(path)
        await log.record("storage.upload")
    }

    func remove(path: String) async throws {
        removedPaths.append(path)
        await log.record("storage.remove")
        if let removeError { throw removeError }
    }
}
