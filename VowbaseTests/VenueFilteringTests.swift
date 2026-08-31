import Foundation
import Testing
@testable import Vowbase

@Suite("Venue search and sort")
struct VenueFilteringTests {
    private let weddingID = UUID(uuidString: "3D35DBCF-BE26-4DAE-843F-4D1B6B4C57EC")!

    private func venue(
        _ name: String,
        status: VenueStatus = .considering,
        address: String? = nil,
        city: String? = nil,
        contactName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        capacityMin: Int? = nil,
        capacityMax: Int? = nil,
        venueEstimateText: String? = nil,
        customFields: JSONValue = .object([:]),
        updated: TimeInterval = 0,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> Venue {
        Venue(
            id: UUID(),
            weddingID: weddingID,
            name: name,
            status: status,
            address: address,
            city: city,
            state: nil,
            country: nil,
            contactName: contactName,
            contactEmail: email,
            contactPhone: phone,
            website: nil,
            capacityMin: capacityMin,
            capacityMax: capacityMax,
            capacityText: nil,
            priceNotes: nil,
            venueEstimateText: venueEstimateText,
            allInEstimateText: nil,
            availableDatesText: nil,
            ourNotes: nil,
            summary: nil,
            latitude: latitude,
            longitude: longitude,
            photoURL: nil,
            customFields: customFields,
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    private var venues: [Venue] {
        [
            venue("Cedar Hall", status: .shortlisted, address: "Portland", updated: 10),
            venue("Aster Estate", status: .considering, address: "10 Garden Way", contactName: "Mira Rose", email: "mira@aster.test", updated: 30),
            venue("Birch Barn", status: .contacted, phone: "+1 555 0100", updated: 20),
            venue("Alder House", status: .shortlisted, updated: 40)
        ]
    }

    @Test("Venue estimate display uses canonical text only")
    func venueEstimateDisplayUsesCanonicalTextOnly() {
        let absent = venue("No estimate")
        let canonical = venue(
            "Canonical estimate",
            venueEstimateText: "  $175k–$190k  "
        )

        #expect(absent.canonicalVenueEstimateText == nil)
        #expect(absent.venueEstimateDisplayText == "Not added")
        #expect(canonical.canonicalVenueEstimateText == "$175k–$190k")
        #expect(canonical.venueEstimateDisplayText == "$175k–$190k")
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

    @Test("Status follows decision priority and then name")
    func statusSortsByDecisionPriorityThenName() {
        let result = VenueQuery.apply(
            to: [
                venue("Considering", status: .considering),
                venue("Passed", status: .passed),
                venue("Zulu Shortlist", status: .shortlisted),
                venue("Contacted", status: .contacted),
                venue("Booked", status: .booked),
                venue("Toured", status: .toured),
                venue("Negotiating", status: .negotiating),
                venue("Alpha Shortlist", status: .shortlisted),
            ],
            searchText: "",
            status: nil,
            sort: .status
        )

        #expect(result.map(\.name) == [
            "Booked",
            "Negotiating",
            "Alpha Shortlist",
            "Zulu Shortlist",
            "Toured",
            "Contacted",
            "Considering",
            "Passed",
        ])
    }

    @Test("Venue sort choices omit nearest-first")
    func sortChoicesOmitNearestFirst() {
        #expect(VenueSortOrder.allCases == [.lastUpdated, .nameAscending, .status])
    }

    @Test("Search covers name, status, location, address, and contacts")
    func searchCoversVenueFields() {
        #expect(VenueQuery.apply(to: venues, searchText: "cedar", status: nil, sort: .nameAscending).map(\.name) == ["Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "shortlisted", status: nil, sort: .nameAscending).map(\.name) == ["Alder House", "Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "portland", status: nil, sort: .nameAscending).map(\.name) == ["Cedar Hall"])
        #expect(VenueQuery.apply(to: venues, searchText: "garden way", status: nil, sort: .nameAscending).map(\.name) == ["Aster Estate"])
        #expect(VenueQuery.apply(to: venues, searchText: "555 0100", status: nil, sort: .nameAscending).map(\.name) == ["Birch Barn"])
    }

    @Test("Search includes stored venue custom-field values")
    func searchIncludesVenueCustomFields() {
        let result = VenueQuery.apply(
            to: [venue("Garden Estate", customFields: .object(["style": .string("Art deco")]))],
            searchText: "deco",
            status: nil,
            sort: .nameAscending
        )
        #expect(result.map(\.name) == ["Garden Estate"])
    }

    @Test("Rank accepts only whole scores from one through five")
    func rankEncodingAndDisplay() {
        #expect(VenueCustomFields.encode("1", kind: .rank) == .number(1))
        #expect(VenueCustomFields.encode("5", kind: .rank) == .number(5))
        #expect(VenueCustomFields.encode("0", kind: .rank) == nil)
        #expect(VenueCustomFields.encode("6", kind: .rank) == nil)
        #expect(VenueCustomFields.encode("2.5", kind: .rank) == nil)
        #expect(!VenueCustomFields.isUnsupported(.number(3), kind: .rank))
        #expect(VenueCustomFields.isUnsupported(.number(3.5), kind: .rank))
    }

    @Test("Metric-card status filtering combines with search")
    func statusAndSearchCombine() {
        let result = VenueQuery.apply(to: venues, searchText: "house", status: .shortlisted, sort: .lastUpdated)
        #expect(result.map(\.name) == ["Alder House"])
    }

    @Test("Configurable metrics match venue fields and combine with status filtering")
    func configurableMetricsMatchAndCombine() {
        let reception = VenueCustomColumn(
            id: UUID(),
            weddingID: weddingID,
            key: "reception",
            label: "Reception",
            kind: .rank,
            options: .array([]),
            position: 0,
            hidden: false,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        let records = [
            venue(
                "Complete",
                status: .shortlisted,
                city: "Portland",
                capacityMin: 120,
                venueEstimateText: "$20k",
                customFields: .object(["reception": .number(5)])
            ),
            venue("Missing", status: .shortlisted),
            venue("Other status", status: .considering, city: "Salem"),
        ]

        #expect(VenueMetricCondition.location(.present).matches(records[0]))
        #expect(VenueMetricCondition.location(.absent).matches(records[1]))
        #expect(VenueMetricCondition.capacity(.present).matches(records[0]))
        #expect(VenueMetricCondition.estimate(.present).matches(records[0]))
        #expect(VenueMetricCondition.customValue(key: reception.key, value: "5").matches(records[0]))

        let missingLocation = VenueMetric(
            id: "missing-location",
            name: "Missing location",
            condition: .location(.absent),
            isEnabled: true,
            isCustom: false
        )
        let result = VenueQuery.apply(
            to: records,
            searchText: "",
            status: .shortlisted,
            sort: .nameAscending,
            metric: missingLocation
        )
        #expect(result.map(\.name) == ["Missing"])
    }

    @Test("Venue metric configuration preserves lifecycle defaults and supports local customization")
    func venueMetricConfiguration() throws {
        let column = VenueCustomColumn(
            id: UUID(),
            weddingID: weddingID,
            key: "parking",
            label: "Parking",
            kind: .checkbox,
            options: .array([]),
            position: 0,
            hidden: false,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        var configuration = VenueMetricConfiguration.default(columns: [column])

        #expect(configuration.shownMetrics.map(\.id) == [
            "venue-total", "venue-considering", "venue-contacted", "venue-toured", "venue-shortlisted", "venue-booked"
        ])
        #expect(configuration.availableMetrics.contains(where: { $0.id == "field-parking" }))

        configuration.disable("venue-booked")
        let addedID = configuration.addCustom(
            name: "Top reception",
            condition: .customValue(key: "reception", value: "5")
        )
        let customID = try #require(addedID)
        #expect(configuration.shownMetrics.contains(where: { $0.id == customID }))
        #expect(configuration.shownMetrics.count == VenueMetricConfiguration.maximumShownMetrics)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(VenueMetricConfiguration.self, from: data)
        #expect(decoded == configuration)
    }

    @Test("Venue distance coordinates reject malformed persisted values")
    func venueDistanceCoordinatesRequireValidLatitudeAndLongitude() {
        #expect(VenueCoordinateRecovery.isUsable(latitude: 45.5, longitude: -122.6))
        #expect(!VenueCoordinateRecovery.isUsable(latitude: 100, longitude: -122.6))
        #expect(!VenueCoordinateRecovery.isUsable(latitude: 45.5, longitude: -200))
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
