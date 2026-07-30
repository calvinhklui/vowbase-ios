import Foundation
import Testing
@testable import Vowbase

@Suite("Guest filtering, search, and sort")
struct GuestFilteringTests {
    private let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!

    private func guest(
        _ first: String,
        rsvp: RSVPStatus? = .pending,
        email: String? = nil,
        phone: String? = nil,
        origin: String? = nil,
        precision: String? = nil,
        custom: [String: JSONValue] = [:],
        created: TimeInterval = 0
    ) -> Guest {
        Guest(
            id: UUID(),
            weddingID: weddingID,
            firstName: first,
            lastName: nil,
            email: email,
            phone: phone,
            address: origin,
            customFields: .object(custom),
            rsvpStatus: rsvp,
            rsvpDate: nil,
            originLabel: origin,
            originLatitude: nil,
            originLongitude: nil,
            originPrecision: precision,
            geocodeStatus: nil,
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    private func selectColumn(_ key: String, options: [String]) -> GuestCustomColumn {
        GuestCustomColumn(
            id: UUID(), weddingID: weddingID, key: key, label: key.capitalized, kind: .select,
            options: .array(options.map(JSONValue.string)), position: 0, hidden: false,
            createdAt: .distantPast, updatedAt: .distantPast
        )
    }

    private var roster: [Guest] {
        [
            guest("Avery", rsvp: .accepted, email: "a@example.com", origin: "Lumen Bay", precision: "city",
                  custom: ["meal": .string("Vegan"), "plus_one": .bool(true), "table": .number(4)], created: 10),
            guest("Mira", rsvp: .pending, email: "m@example.com", origin: "Northvale", precision: "city",
                  custom: ["meal": .string("Fish")], created: 20),
            guest("Theo", rsvp: .pending, origin: "Willow Coast", precision: "approximate",
                  custom: ["meal": .string("Fish")], created: 30),
            guest("Nora", rsvp: .notInvited, email: "n@example.com", phone: "+1 555 0100", created: 40),
            guest("Cass", rsvp: .declined, custom: ["plus_one": .bool(false)], created: 50)
        ]
    }

    // MARK: - Single dimensions

    @Test("An empty filter set matches everyone")
    func emptySetMatchesAll() {
        let filters = GuestFilterSet()
        #expect(filters.isEmpty)
        #expect(roster.allSatisfy(filters.matches))
    }

    @Test("RSVP selections OR together")
    func rsvpOrsWithinField() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.pending, .accepted]
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Avery", "Mira", "Theo"])
    }

    @Test("A missing RSVP counts as not invited")
    func missingRSVPDefaults() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.notInvited]
        let unset = guest("Ghost", rsvp: nil)
        #expect(filters.matches(unset))
    }

    @Test("Location selections include an explicit no-location bucket")
    func locationBuckets() {
        var filters = GuestFilterSet()
        filters.locations = [.none]
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Cass", "Nora"])

        filters.locations = [.named("Northvale"), .none]
        #expect(roster.filter(filters.matches).count == 3)
    }

    @Test("Mappable-only keeps just city-precision origins")
    func mappableOnly() {
        var filters = GuestFilterSet()
        filters.mappableOnly = true
        // Theo has an approximate origin and must be excluded.
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Avery", "Mira"])
    }

    @Test("Presence filters distinguish any, has, and none")
    func presenceFilters() {
        var filters = GuestFilterSet()
        filters.email = .present
        #expect(roster.filter(filters.matches).count == 3)

        filters.email = .absent
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Cass", "Theo"])

        filters.email = .any
        #expect(roster.filter(filters.matches).count == roster.count)
    }

    @Test("Whitespace-only contact details count as absent")
    func blankContactIsAbsent() {
        #expect(GuestPresenceFilter.absent.matches("   "))
        #expect(!GuestPresenceFilter.present.matches("   "))
    }

    // MARK: - Combination semantics

    @Test("Conditions AND across fields while ORing within one")
    func andAcrossOrWithin() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.pending]
        filters.locations = [.named("Northvale"), .named("Willow Coast")]
        filters.email = .present
        // Both are pending and in-scope by location, but only Mira has email.
        #expect(roster.filter(filters.matches).map(\.firstName) == ["Mira"])
        #expect(filters.conditionCount == 3)
    }

    @Test("Contradictory conditions yield an empty result rather than an error")
    func contradictionYieldsEmpty() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.declined]
        filters.email = .present
        #expect(roster.filter(filters.matches).isEmpty)
    }

    // MARK: - Custom conditions

    @Test("Select conditions match any chosen option")
    func selectConditions() {
        var filters = GuestFilterSet()
        filters.customConditions["meal"] = .anyOf(["Fish"])
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Mira", "Theo"])

        filters.customConditions["meal"] = .anyOf(["Fish", "Vegan"])
        #expect(roster.filter(filters.matches).count == 3)
    }

    @Test("The empty token selects guests with no value for the column")
    func emptyTokenMatchesAbsent() {
        var filters = GuestFilterSet()
        filters.customConditions["meal"] = .anyOf([GuestCustomCondition.emptyToken])
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Cass", "Nora"])
    }

    @Test("An empty option set leaves the column unconstrained")
    func emptyOptionSetIsInactive() {
        var filters = GuestFilterSet()
        filters.customConditions["meal"] = .anyOf([])
        #expect(roster.filter(filters.matches).count == roster.count)
        #expect(filters.conditionCount == 0)
    }

    @Test("Checkbox conditions separate false from absent correctly")
    func checkboxConditions() {
        var filters = GuestFilterSet()
        filters.customConditions["plus_one"] = .checkbox(true)
        #expect(roster.filter(filters.matches).map(\.firstName) == ["Avery"])

        // Unchecked covers both an explicit false and no stored value.
        filters.customConditions["plus_one"] = .checkbox(false)
        #expect(roster.filter(filters.matches).map(\.firstName).sorted() == ["Cass", "Mira", "Nora", "Theo"])
    }

    @Test("Numeric values match their displayed form")
    func numericMatching() {
        var filters = GuestFilterSet()
        filters.customConditions["table"] = .anyOf(["4"])
        #expect(roster.filter(filters.matches).map(\.firstName) == ["Avery"])
    }

    // MARK: - Search

    @Test("Search reaches custom values, not just names")
    func searchCoversCustomFields() {
        let results = GuestQuery.apply(
            to: roster, columns: [selectColumn("meal", options: ["Fish", "Vegan"])],
            searchText: "vegan", filters: GuestFilterSet(), sort: .nameAscending
        )
        #expect(results.map(\.firstName) == ["Avery"])
    }

    @Test("Search reaches coarse origin and email")
    func searchCoversOriginAndEmail() {
        #expect(
            GuestQuery.apply(to: roster, columns: [], searchText: "northvale",
                             filters: GuestFilterSet(), sort: .nameAscending).map(\.firstName) == ["Mira"]
        )
        #expect(
            GuestQuery.apply(to: roster, columns: [], searchText: "n@example",
                             filters: GuestFilterSet(), sort: .nameAscending).map(\.firstName) == ["Nora"]
        )
    }

    @Test("Search is case- and whitespace-insensitive")
    func searchNormalizes() {
        let results = GuestQuery.apply(to: roster, columns: [], searchText: "  AVERY  ",
                                       filters: GuestFilterSet(), sort: .nameAscending)
        #expect(results.map(\.firstName) == ["Avery"])
    }

    @Test("Search composes with filters rather than replacing them")
    func searchComposesWithFilters() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.accepted]
        let results = GuestQuery.apply(to: roster, columns: [], searchText: "fish",
                                       filters: filters, sort: .nameAscending)
        // Fish belongs to pending guests only, so the accepted filter wins.
        #expect(results.isEmpty)
    }

    // MARK: - Sort

    @Test("Sort orders behave as labelled")
    func sortOrders() {
        #expect(GuestQuery.sorted(roster, by: .nameAscending).map(\.firstName)
            == ["Avery", "Cass", "Mira", "Nora", "Theo"])
        #expect(GuestQuery.sorted(roster, by: .nameDescending).map(\.firstName)
            == ["Theo", "Nora", "Mira", "Cass", "Avery"])
        #expect(GuestQuery.sorted(roster, by: .recentlyAdded).map(\.firstName)
            == ["Cass", "Nora", "Theo", "Mira", "Avery"])
    }

    @Test("RSVP sort follows the lifecycle, then name")
    func rsvpSortFollowsLifecycle() {
        #expect(GuestQuery.sorted(roster, by: .rsvpStatus).map(\.firstName)
            == ["Nora", "Mira", "Theo", "Avery", "Cass"])
    }

    // MARK: - Counts driving the sheet

    @Test("Location buckets are distinct, sorted, and end with no-location")
    func locationBucketListing() {
        let buckets = GuestQuery.locationBuckets(in: roster)
        #expect(buckets == [.named("Lumen Bay"), .named("Northvale"), .named("Willow Coast"), .none])
        #expect(GuestQuery.count(roster, in: .none) == 2)
        #expect(GuestQuery.count(roster, in: .named("Northvale")) == 1)
    }

    @Test("Option counts include an empty bucket")
    func optionCounts() {
        let counts = GuestQuery.optionCounts(roster, column: selectColumn("meal", options: ["Fish", "Vegan"]))
        #expect(counts.options["Fish"] == 2)
        #expect(counts.options["Vegan"] == 1)
        #expect(counts.empty == 2)
    }

    @Test("RSVP counts back the chip labels")
    func rsvpCounts() {
        #expect(GuestQuery.count(roster, rsvp: .pending) == 2)
        #expect(GuestQuery.count(roster, rsvp: .declined) == 1)
    }

    /// The count the footer promises has to be the count the list shows, or the
    /// whole "no dead ends" guarantee is a lie.
    @Test("The previewed count equals the applied result count")
    func previewCountMatchesResult() {
        var filters = GuestFilterSet()
        filters.rsvpStatuses = [.pending]
        filters.customConditions["meal"] = .anyOf(["Fish"])

        let previewed = roster.filter(filters.matches).count
        let applied = GuestQuery.apply(to: roster, columns: [], searchText: "",
                                       filters: filters, sort: .nameAscending).count
        #expect(previewed == applied)
        #expect(applied == 2)
    }
}
