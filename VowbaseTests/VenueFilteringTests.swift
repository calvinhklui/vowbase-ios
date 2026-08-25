import Foundation
import Testing
@testable import Vowbase

@Suite("Venue search and sort")
struct VenueFilteringTests {
    private let weddingID = UUID(uuidString: "3D35DBCF-BE26-4DAE-843F-4D1B6B4C57EC")!

    private func venue(
        _ name: String,
        status: VenueStatus = .suggested,
        location: String? = nil,
        address: String? = nil,
        contactName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        updated: TimeInterval = 0,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> Venue {
        Venue(
            id: UUID(),
            weddingID: weddingID,
            name: name,
            status: status,
            location: location,
            locationText: nil,
            address: address,
            city: nil,
            state: nil,
            country: nil,
            contactName: contactName,
            contactEmail: email,
            contactPhone: phone,
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
            latitude: latitude,
            longitude: longitude,
            photoURL: nil,
            rawResearch: nil,
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    private var venues: [Venue] {
        [
            venue("Cedar Hall", status: .shortlisted, location: "Portland", updated: 10),
            venue("Aster Estate", status: .suggested, address: "10 Garden Way", contactName: "Mira Rose", email: "mira@aster.test", updated: 30),
            venue("Birch Barn", status: .contacted, phone: "+1 555 0100", updated: 20),
            venue("Alder House", status: .shortlisted, updated: 40)
        ]
    }

    @Test("Last updated is the default descending order")
    func lastUpdatedSortsDescending() {
        let result = VenueQuery.apply(to: venues, searchText: "", status: nil, sort: .lastUpdated)
        #expect(result.map(\.name) == ["Alder House", "Aster Estate", "Birch Barn", "Cedar Hall"])
    }

    @Test("Name A-Z uses a case-insensitive venue name")
    func nameSortsAscending() {
        let result = VenueQuery.apply(to: venues, searchText: "", status: nil, sort: .nameAscending)
        #expect(result.map(\.name) == ["Alder House", "Aster Estate", "Birch Barn", "Cedar Hall"])
    }

    @Test("Status follows the venue lifecycle and then name")
    func statusSortsByLifecycleThenName() {
        let result = VenueQuery.apply(to: venues, searchText: "", status: nil, sort: .status)
        #expect(result.map(\.name) == ["Aster Estate", "Birch Barn", "Alder House", "Cedar Hall"])
    }

    @Test("Search covers name, status, location, address, and contacts")
    func searchCoversVenueFields() {
        #expect(VenueQuery.apply(to: venues, searchText: "cedar", status: nil, sort: .nameAscending).map(\.name) == ["Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "shortlisted", status: nil, sort: .nameAscending).map(\.name) == ["Alder House", "Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "portland", status: nil, sort: .nameAscending).map(\.name) == ["Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "garden way", status: nil, sort: .nameAscending).map(\.name) == ["Aster Estate"])
        #expect(VenueQuery.apply(to: venues, searchText: "555 0100", status: nil, sort: .nameAscending).map(\.name) == ["Birch Barn"])
    }

    @Test("Metric-card status filtering combines with search")
    func statusAndSearchCombine() {
        let result = VenueQuery.apply(to: venues, searchText: "house", status: .shortlisted, sort: .lastUpdated)
        #expect(result.map(\.name) == ["Alder House"])
    }

    @Test("Nearest-first uses only available local distances and keeps unknown venues last")
    func nearestFirstSortsKnownDistancesBeforeUnknownVenues() {
        let nearby = venue("Nearby", latitude: 40, longitude: -73)
        let farther = venue("Farther", latitude: 41, longitude: -73)
        let unlocated = venue("Unlocated")
        let origin = Coordinate(latitude: 40, longitude: -74)
        let distances = [
            nearby.id: VenueDistance.miles(
                from: origin,
                to: Coordinate(latitude: 40, longitude: -73)
            ),
            farther.id: VenueDistance.miles(
                from: origin,
                to: Coordinate(latitude: 41, longitude: -73)
            ),
        ]

        let result = VenueQuery.apply(
            to: [unlocated, farther, nearby],
            searchText: "",
            status: nil,
            sort: .nearestFirst,
            distances: distances
        )

        #expect(result.map(\.name) == ["Nearby", "Farther", "Unlocated"])
    }

    @Test("Row location text uses coarse city and state with a one-decimal mile distance")
    func rowLocationTextFormatsCoarseDistance() {
        #expect(
            VenueRowLocationText.string(
                city: "Portland",
                state: "or",
                distanceMiles: 12.34
            ) == "Portland, OR • 12.3mi away"
        )
        #expect(
            VenueRowLocationText.string(
                city: "Portland",
                state: "Oregon",
                distanceMiles: nil
            ) == "Portland, OR"
        )
        #expect(
            VenueRowLocationText.string(
                city: nil,
                state: nil,
                distanceMiles: 12.34
            ) == "Location unavailable"
        )
    }
}
