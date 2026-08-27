import CoreLocation
import Foundation
import Observation

struct SaveFailure: Identifiable {
    let id = UUID()
    let message: String
    let retry: @MainActor () -> Void
    let discard: @MainActor () -> Void
}

/// The context bar's countdown line — spec §5.
///
/// `> 365 days` and past dates both render as the absolute date: a day count
/// that large isn't motivating, and a negative one isn't meaningful.
enum WeddingCountdownFormatter {
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let shortDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func date(from weddingDateString: String) -> Date? {
        dateOnlyFormatter.date(from: weddingDateString)
    }

    static func string(from date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    /// `nil` means no date is set — the caller shows "Add your date" instead.
    static func countdownText(for weddingDateString: String?) -> String? {
        guard let weddingDateString, let date = date(from: weddingDateString) else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWedding = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfWedding).day ?? 0
        if days > 0 && days <= 365 {
            return "\(days) days"
        }
        return displayFormatter.string(from: date)
    }

    /// Raw day count, unlike `countdownText` which switches to an absolute
    /// date past a year out — the Needs You "RSVPs outstanding" rule (spec
    /// §11.3) needs the number itself to compare against its 120-day window.
    static func daysUntilWedding(_ weddingDateString: String?) -> Int? {
        guard let weddingDateString, let date = date(from: weddingDateString) else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWedding = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfWedding).day
    }

    /// The Countdown module's secondary line — always relative, never the
    /// absolute date the module already shows on its primary line. Past a
    /// year out, `countdownText` falls back to that same absolute date
    /// (right for the context bar's single either/or line, wrong here where
    /// it just repeats what's already on screen).
    static func countdownPhrase(for weddingDateString: String?) -> String? {
        guard let weddingDateString, let date = date(from: weddingDateString) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        guard let days = daysUntilWedding(weddingDateString) else { return nil }
        return days >= 0 ? "In \(days) days" : "\(-days) days ago"
    }

    static func dateRangeText(start: String?, end: String?) -> String? {
        let startDate = start.flatMap(date(from:))
        let endDate = end.flatMap(date(from:))
        switch (startDate, endDate) {
        case let (startDate?, endDate?):
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return displayFormatter.string(from: startDate)
            }
            if Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate) {
                return "\(shortDisplayFormatter.string(from: startDate)) – \(displayFormatter.string(from: endDate))"
            }
            return "\(displayFormatter.string(from: startDate)) – \(displayFormatter.string(from: endDate))"
        case let (startDate?, nil):
            return displayFormatter.string(from: startDate)
        case let (nil, endDate?):
            return displayFormatter.string(from: endDate)
        case (nil, nil):
            return nil
        }
    }
}

struct VenuePhotoDisplay: Identifiable, Hashable {
    let photo: VenuePhoto
    let url: URL?
    var id: UUID { photo.id }
}

struct MVPVenue: Identifiable, Hashable {
    let id: UUID
    let name: String
    let status: VenueStatus
    let location: String
    let city: String?
    let state: String?
    /// Straight-line distance from the saved wedding location. `nil` means
    /// either side has no usable coordinate, not that the venue is far.
    let distanceMiles: Double?
    /// The most specific stored address available for handing this venue to Maps.
    /// Keep this separate from `location`, whose shorter display copy is useful in UI.
    let mapSearchQuery: String
    /// The stored/synthesized street address without a provider rewrite. This is
    /// the value Maps and document-sharing surfaces should preserve verbatim.
    let fullAddress: String?
    let capacityMin: Int?
    let capacityMax: Int?
    let capacityTextOverride: String?
    let estimate: String
    /// The raw `venue_est_text` value, independent of `estimate`'s `priceEstimate` display
    /// fallback — inline editing reads/writes this, never the derived display string.
    let venueEstimateTextRaw: String?
    /// `nil` when this venue's guest travel hasn't been computed — a real
    /// absence, so each surface can decide whether to omit the stat or show a
    /// placeholder, rather than every one of them rendering the same sentence
    /// and truncating it.
    let travel: String?
    let allInEstimate: String
    let availableDates: String
    let summary: String?
    let website: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let latitude: Double?
    let longitude: Double?
    let coverPhotoURL: URL?
    let coverPhotoCacheKey: String
    let photos: [VenuePhotoDisplay]
    /// Venue-scoped metadata returned by the dedicated v1 document API.
    let documents: [VenueDocument]
    let ourNotes: String?

    var capacity: String {
        capacityTextOverride?.nilIfBlank ?? VenueCapacityFormatter.string(minimum: capacityMin, maximum: capacityMax)
    }

    var photoURLs: [URL] {
        var seen = Set<URL>()
        var result = [URL]()
        for url in ([coverPhotoURL] + photos.map(\.url)).compactMap({ $0 }) where seen.insert(url).inserted {
            result.append(url)
        }
        return result
    }

    var photoURL: URL? { photoURLs.first }

    var rowSecondaryText: String {
        VenueRowLocationText.string(
            city: city,
            state: state,
            distanceMiles: distanceMiles
        )
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

struct GuestCluster: Identifiable {
    let id: String
    let city: String
    let count: Int
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct MVPGuest: Identifiable, Hashable {
    let id: UUID
    let firstName: String
    let lastName: String
    /// Row subtitle resolved from this wedding's own column definitions.
    /// Nil when no suitable column exists or the guest has no value for it.
    let subtitle: String?
    let location: String?
    let email: String?
    let phone: String?
    let rsvp: RSVPStatus
    let isMappable: Bool
    /// Flattened custom values so search reaches custom fields too.
    let customSearchText: String

    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var initials: String {
        [firstName.first, lastName.first]
            .compactMap { $0 }
            .map { String($0).uppercased() }
            .joined()
    }
    var searchText: String {
        [name, subtitle, location, email, phone, customSearchText]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

@MainActor
@Observable
final class VowbaseWorkspaceStore {
    private let repositories: RepositoryContainer?
    private var venueRecords = [Venue]()
    private var venueGalleries = [UUID: [VenuePhoto]]()
    private var venueDocuments = [UUID: [VenueDocument]]()
    private var loadingVenueDocumentIDs = Set<UUID>()
    private var venueDocumentErrors = [UUID: String]()
    private var venuePhotoErrors = [UUID: String]()
    private var signedCoverPhotoURLs = [UUID: URL]()
    private var signedGalleryPhotoURLs = [UUID: URL]()
    /// Coordinates recovered for legacy or free-form venue addresses. These are
    /// deliberately session-only: the recovery must never replace a user's
    /// entered address with a provider label, and the Venue repository has no
    /// established background-write pattern for this best-effort repair.
    private var recoveredVenueCoordinates = [UUID: VenueCoordinateRecovery]()
    /// A failed forward-geocode is still a result for this app session. Keep the
    /// attempted query so repeated loads cannot turn one unresolved venue into
    /// an unbounded stream of identical requests. A changed address naturally
    /// produces a new query and may be tried once.
    private var venueCoordinateRecoveryAttempts = [UUID: String]()
    /// A session-only coordinate recovered from the couple's saved wedding
    /// location through Vowbase's authenticated geocode proxy.
    private var venueDistanceOrigin: VenueDistanceOrigin?
    private var venueDistanceOriginAttemptedQuery: String?
    private var guestRecords = [Guest]()
    private var customColumnRecords = [GuestCustomColumn]()

    /// Serializes each guest's custom-field writes. `GuestPatch.customFields`
    /// replaces the whole JSON object, so two concurrent row commits would
    /// clobber one another without this chain.
    private var customFieldWrites = [UUID: Task<Void, Never>]()

    var selectedVenueID: UUID?
    var isGlobalMenuOpen = false
    var wedding: WeddingSummary?
    var activeMembership: WeddingMembership?
    var isLoading = false
    var errorMessage: String?
    var saveFailure: SaveFailure?

    /// The console header's impact readout for `selectedVenueID` — spec §8.
    /// Reactively recomputed by `refreshTravelImpact()`, called from a
    /// `.task(id: selectedVenueID)` in the view layer so a selection change
    /// cancels any in-flight request for the venue you've since moved away
    /// from rather than racing it.
    var travelImpact: TravelImpactState = .idle

    var canManageTasks: Bool {
        guard let role = activeMembership?.role else { return false }
        return role == .owner || role == .partner || role == .planner
    }

    /// Set when column definitions fail to load. Custom-field rows are hidden
    /// rather than shown broken, and the guest list stays usable.
    var customFieldsUnavailable = false

    /// Per-row save state for inline editing, keyed by guest and field.
    private(set) var fieldSaveStates = [GuestFieldKey: GuestFieldSaveState]()

    init(repositories: RepositoryContainer? = nil) {
        self.repositories = repositories
    }

#if DEBUG
    init(testingWorkspace: Bool) {
        precondition(testingWorkspace)
        repositories = nil

        let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        wedding = WeddingSummary(
            id: weddingID,
            name: "Example Wedding",
            coupleNames: "Example Couple",
            weddingDate: "2027-09-18",
            dateFlexibility: "specific",
            dateRangeStart: nil,
            dateRangeEnd: nil,
            location: "Example City"
        )
        activeMembership = WeddingMembership(
            id: UUID(uuidString: "C1175B62-0CD8-43EC-9AC4-A3C2F65A2598")!,
            weddingId: weddingID,
            userId: UUID(uuidString: "3B4C76E4-E7A5-48A3-B351-439E9488273B")!,
            role: .owner,
            status: "active",
            wedding: wedding!
        )
        venueRecords = [
            Venue(
                id: UUID(uuidString: "4B836FCF-0575-41F8-960C-3C69E70F1D84")!,
                weddingID: weddingID,
                name: "Riverside Pavilion",
                status: .toured,
                location: "Example District, Example City",
                locationText: "Example District, Example City",
                address: "100 Example Avenue, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 150,
                capacityMax: 350,
                capacityText: "150–350",
                priceEstimate: 53_700,
                priceNotes: nil,
                venueEstimateText: "$53.7k",
                allInEstimateText: "$90k–$125k",
                availableDatesText: "Weekends in September",
                ourNotes: nil,
                summary: "An airy riverside venue for a joyful, relaxed celebration.",
                latitude: 39.5,
                longitude: -98.35,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            Venue(
                id: UUID(uuidString: "75AC0474-624B-4106-8A1C-5D13B117A34F")!,
                weddingID: weddingID,
                name: "Harbor Gallery",
                status: .toured,
                location: "Harbor District, Example City",
                locationText: "Harbor District, Example City",
                address: "200 Example Street, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 120,
                capacityMax: 300,
                capacityText: "120–300",
                priceEstimate: 48_000,
                priceNotes: nil,
                venueEstimateText: "$48k",
                allInEstimateText: nil,
                availableDatesText: "October weekends",
                ourNotes: nil,
                summary: nil,
                latitude: 39.6,
                longitude: -98.25,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            Venue(
                id: UUID(uuidString: "2A2B8F0C-A065-499B-BC92-847152B6E0D6")!,
                weddingID: weddingID,
                name: "Meadow House",
                status: .considering,
                location: "Lakeside, Example City",
                locationText: "Lakeside, Example City",
                address: "300 Example Road, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 100,
                capacityMax: 220,
                capacityText: "100–220",
                priceEstimate: 39_000,
                priceNotes: nil,
                venueEstimateText: "$39k",
                allInEstimateText: nil,
                availableDatesText: nil,
                ourNotes: nil,
                summary: nil,
                latitude: 39.4,
                longitude: -98.45,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        ]
        guestRecords = [
            Guest(id: UUID(uuidString: "AE67A07D-D565-4A7D-A960-4B6A186C4D6D")!, weddingID: weddingID, firstName: "Avery", lastName: "Rowan", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Cedar Circle")]), rsvpStatus: .accepted, rsvpDate: nil, originLabel: "Lumen Bay", originLatitude: 39.5, originLongitude: -98.35, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "167E1A25-7B99-499B-9A66-872B2A3B784A")!, weddingID: weddingID, firstName: "Mira", lastName: "Vale", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Juniper Guild")]), rsvpStatus: .pending, rsvpDate: nil, originLabel: "Northvale", originLatitude: 39.6, originLongitude: -98.25, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "3F8DB09C-44F3-4888-8D2B-31EB26F5C487")!, weddingID: weddingID, firstName: "Theo", lastName: "Lark", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Cedar Circle")]), rsvpStatus: .pending, rsvpDate: nil, originLabel: "Willow Coast", originLatitude: 39.4, originLongitude: -98.45, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "DE25BD36-69A1-4DC3-A5E0-5E0AF076E34E")!, weddingID: weddingID, firstName: "Nora", lastName: "Wynn", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Juniper Guild")]), rsvpStatus: .notInvited, rsvpDate: nil, originLabel: "Solace Point", originLatitude: 39.45, originLongitude: -98.3, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt)
        ]
        customColumnRecords = [
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C01")!, weddingID: weddingID, key: "group", label: "Group", kind: .select, options: .array([.string("Cedar Circle"), .string("Juniper Guild")]), position: 0, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C02")!, weddingID: weddingID, key: "meal_choice", label: "Meal choice", kind: .select, options: .array([.string("Chicken"), .string("Fish"), .string("Vegetarian")]), position: 1, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C03")!, weddingID: weddingID, key: "plus_one", label: "Plus one", kind: .checkbox, options: .array([]), position: 2, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C04")!, weddingID: weddingID, key: "table", label: "Table", kind: .number, options: .array([]), position: 3, hidden: false, createdAt: createdAt, updatedAt: createdAt)
        ]
        selectedVenueID = venueRecords.first?.id
    }
#endif

    var venues: [MVPVenue] {
        venueDisplays(for: venueRecords)
    }

    /// Search and ordering stay local because every listed venue is already
    /// loaded for the workspace. The metric-card selection is deliberately
    /// passed through as a status filter so it combines with search.
    func filteredVenues(
        searchText: String,
        status: VenueStatus?,
        sort: VenueSortOrder
    ) -> [MVPVenue] {
        let distances = venueDistances
        return VenueQuery
            .apply(
                to: venueRecords,
                searchText: searchText,
                status: status,
                sort: sort,
                distances: distances
            )
            .map { venueDisplay(for: $0, distanceMiles: distances[$0.id]) }
    }

    private func venueDisplays(for venueRecords: [Venue]) -> [MVPVenue] {
        let distances = venueDistances
        return venueRecords.map { venue in
            venueDisplay(for: venue, distanceMiles: distances[venue.id])
        }
    }

    private var venueDistances: [UUID: Double] {
        guard let origin = venueDistanceOrigin?.coordinate else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: venueRecords.compactMap { venue in
                guard let coordinate = coordinate(for: venue) else { return nil }
                return (venue.id, VenueDistance.miles(from: origin, to: coordinate))
            }
        )
    }

    private func venueDisplay(for venue: Venue, distanceMiles: Double? = nil) -> MVPVenue {
        MVPVenue(
            venue,
            gallery: venueGalleries[venue.id] ?? [],
            documents: venueDocuments[venue.id] ?? [],
            galleryPhotoURLs: signedGalleryPhotoURLs,
            coverPhotoURL: signedCoverPhotoURLs[venue.id],
            recoveredCoordinate: recoveredCoordinate(for: venue),
            distanceMiles: distanceMiles,
            travelText: travelText(for: venue.id)
        )
    }

    /// The plain-duration value venue cards and other planning surfaces show
    /// alongside their own "guest travel" caption. Only ever real for the
    /// selected, resolved venue — computing this for every listed venue
    /// would mean one `travelTimes` request per row, which spec §8 never
    /// asks for. `nil` means "not checked yet", which is a different fact
    /// from a request having failed.
    private func travelText(for venueID: UUID) -> String? {
        guard venueID == selectedVenueID, case let .ready(readout) = travelImpact else {
            return nil
        }
        return TravelDurationFormatter.string(fromSeconds: readout.medianDurationSeconds)
    }
    var guests: [MVPGuest] {
        let columns = customColumnRecords
        return guestRecords.map { MVPGuest($0, columns: columns) }
    }
    var weddingTitle: String { wedding?.coupleNames ?? wedding?.name ?? "Your wedding" }
    var isVenueDocumentsLoading: Bool { !loadingVenueDocumentIDs.isEmpty }

    func isLoadingVenueDocuments(for venueID: UUID) -> Bool {
        loadingVenueDocumentIDs.contains(venueID)
    }

    func venueDocumentError(for venueID: UUID) -> String? {
        venueDocumentErrors[venueID]
    }

    func venuePhotoError(for venueID: UUID) -> String? {
        venuePhotoErrors[venueID]
    }

    /// Columns offered for editing and filtering, in their configured order.
    /// Empty while definitions are unavailable so rows never render broken.
    var visibleCustomColumns: [GuestCustomColumn] {
        customFieldsUnavailable ? [] : GuestDisplayResolver.visibleColumns(customColumnRecords)
    }

    /// Every column including hidden ones, for the administration screen.
    var allCustomColumns: [GuestCustomColumn] {
        GuestDisplayResolver.orderedColumns(customColumnRecords)
    }

    func guestRecord(id: UUID) -> Guest? {
        guestRecords.first { $0.id == id }
    }

    func plusGuests(for guestID: UUID) -> [Guest] {
        guestRecords.filter { $0.plusOfGuestID == guestID }
    }

    func plusHost(for guest: Guest) -> Guest? {
        guest.plusOfGuestID.flatMap(guestRecord(id:))
    }

    /// Raw records, for the counts the filter sheet shows before applying.
    var allGuestRecords: [Guest] { guestRecords }

    func filteredGuests(
        searchText: String,
        filters: GuestFilterSet,
        sort: GuestSortOrder,
        metric: GuestMetric? = nil
    ) -> [MVPGuest] {
        let columns = customColumnRecords
        return GuestQuery
            .apply(to: guestRecords, columns: columns, searchText: searchText, filters: filters, sort: sort)
            .filter { metric?.condition.matches($0) ?? true }
            .map { MVPGuest($0, columns: columns) }
    }

    func saveState(_ key: GuestFieldKey) -> GuestFieldSaveState? {
        fieldSaveStates[key]
    }

    /// Map guest locations only when the server marks them as city-precision.
    /// This keeps individual household addresses out of the planning map.
    var clusters: [GuestCluster] {
        let locatedGuests = guestRecords.compactMap { guest -> (String, Double, Double)? in
            guard guest.originPrecision == "city",
                  let city = GuestLocationLabel.display(for: guest),
                  let latitude = guest.originLatitude,
                  let longitude = guest.originLongitude else {
                return nil
            }
            return (city, latitude, longitude)
        }
        return Dictionary(grouping: locatedGuests, by: { $0.0.lowercased() })
            .compactMap { key, entries in
                guard let first = entries.first else { return nil }
                let count = Double(entries.count)
                return GuestCluster(
                    id: key,
                    city: first.0,
                    count: entries.count,
                    latitude: entries.reduce(0) { $0 + $1.1 } / count,
                    longitude: entries.reduce(0) { $0 + $1.2 } / count
                )
            }
            .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    @discardableResult
    func load(presentsFailure: Bool = true) async -> Bool {
        guard let repositories else { return wedding != nil }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let membership = try await repositories.workspace.memberships().first else {
                venueRecords = []
                guestRecords = []
                customColumnRecords = []
                wedding = nil
                activeMembership = nil
                errorMessage = "This account is not a member of a wedding workspace yet."
                if presentsFailure { presentLoadFailure() }
                return false
            }

            wedding = membership.wedding
            activeMembership = membership
            async let venues = repositories.venues.venues(weddingID: membership.weddingId)
            async let guests = repositories.guests.guests(weddingID: membership.weddingId)
            // Column definitions degrade on their own: losing them should hide
            // custom fields, never take the guest list down with them.
            async let columns = try? repositories.guests.customColumns(weddingID: membership.weddingId)
            venueRecords = try await venues
            guestRecords = try await guests
            if let loadedColumns = await columns {
                customColumnRecords = GuestDisplayResolver.orderedColumns(loadedColumns)
                customFieldsUnavailable = false
            } else {
                customColumnRecords = []
                customFieldsUnavailable = true
            }
            let currentVenueIDs = Set(venueRecords.map(\.id))
            venueGalleries = venueGalleries.filter { currentVenueIDs.contains($0.key) }
            venueDocuments = venueDocuments.filter { currentVenueIDs.contains($0.key) }
            loadingVenueDocumentIDs.formIntersection(currentVenueIDs)
            venueDocumentErrors = venueDocumentErrors.filter { currentVenueIDs.contains($0.key) }
            venuePhotoErrors = venuePhotoErrors.filter { currentVenueIDs.contains($0.key) }
            signedCoverPhotoURLs = signedCoverPhotoURLs.filter { currentVenueIDs.contains($0.key) }
            recoveredVenueCoordinates = recoveredVenueCoordinates.filter { currentVenueIDs.contains($0.key) }
            venueCoordinateRecoveryAttempts = venueCoordinateRecoveryAttempts.filter { currentVenueIDs.contains($0.key) }
            let currentPhotoIDs = Set(venueGalleries.values.flatMap { $0.map(\.id) })
            signedGalleryPhotoURLs = signedGalleryPhotoURLs.filter { currentPhotoIDs.contains($0.key) }
            resolveVenuePhotoURLs(for: venueRecords, repositories: repositories)
            resolveVenueDocuments(for: venueRecords, repositories: repositories)
            recoverVenueCoordinates(for: venueRecords, repositories: repositories)
            recoverVenueDistanceOrigin(for: membership.wedding, repositories: repositories)
            if !venueRecords.contains(where: { $0.id == selectedVenueID }) {
                selectedVenueID = venueRecords.first?.id
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = userMessage(for: error)
            if presentsFailure { presentLoadFailure() }
            return false
        }
    }

    func presentSaveFailure(
        retry: @escaping @MainActor () -> Void,
        discard: @escaping @MainActor () -> Void = {}
    ) {
        let message = errorMessage ?? "Something went wrong while saving your changes."
        errorMessage = nil
        saveFailure = SaveFailure(message: message, retry: retry, discard: discard)
    }

    func updateWeddingDate(_ date: Date) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let updated = try await repositories.workspace.updateWedding(
                id: weddingID,
                patch: WeddingPatch(
                    weddingDate: .value(WeddingCountdownFormatter.string(from: date)),
                    dateFlexibility: "specific",
                    dateRangeStart: .null,
                    dateRangeEnd: .null
                )
            )
            wedding = updated
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func updateWeddingDateRange(start: Date, end: Date) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let updated = try await repositories.workspace.updateWedding(
                id: weddingID,
                patch: WeddingPatch(
                    weddingDate: .null,
                    dateFlexibility: "range",
                    dateRangeStart: .value(WeddingCountdownFormatter.string(from: start)),
                    dateRangeEnd: .value(WeddingCountdownFormatter.string(from: end))
                )
            )
            wedding = updated
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func clearWeddingDates() async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let updated = try await repositories.workspace.updateWedding(
                id: weddingID,
                patch: WeddingPatch(
                    weddingDate: .null,
                    dateFlexibility: "undecided",
                    dateRangeStart: .null,
                    dateRangeEnd: .null
                )
            )
            wedding = updated
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    /// Recomputes `travelImpact` for `selectedVenueID` against the current
    /// guest clusters. Safe to call repeatedly — it always reflects current
    /// selection, so both the reactive `.task(id: selectedVenueID)` and a
    /// manual "Retry" tap can call the same method.
    func refreshTravelImpact() async {
        guard let repositories else {
            travelImpact = .idle
            return
        }
        guard let venueID = selectedVenueID, let venue = venueRecords.first(where: { $0.id == venueID }) else {
            travelImpact = .idle
            return
        }
        guard let coordinate = coordinate(for: venue) else {
            travelImpact = .unavailable(.venueMissingCoordinate)
            return
        }
        let currentClusters = clusters
        guard !currentClusters.isEmpty else {
            travelImpact = .unavailable(.noMappableGuests)
            return
        }

        travelImpact = .loading
        do {
            let destinations = currentClusters.map {
                TravelDestination(id: $0.id, latitude: $0.latitude, longitude: $0.longitude)
            }
            let results = try await repositories.maps.travelTimes(
                weddingID: venue.weddingID,
                origin: coordinate,
                destinations: destinations
            )
            guard !Task.isCancelled, venueID == selectedVenueID else { return }
            travelImpact = .ready(
                TravelImpactCalculator.readout(
                    clusters: currentClusters,
                    totalGuestCount: guestRecords.count,
                    travelTimes: results
                )
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, venueID == selectedVenueID else { return }
            travelImpact = .unavailable(.requestFailed)
        }
    }

    func createVenue(
        name: String,
        location: String,
        selection: AppleMapsAddressSelection? = nil,
        status: VenueStatus
    ) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            // An Apple Maps selection is a more specific, durable lookup value
            // than whatever free-form text happened to be in the field when the
            // user tapped it. Use it for both geocoding and persistence.
            let locationQuery = selection?.address ?? location
            let resolvedLocation = await resolvedLocation(for: locationQuery, repositories: repositories)
            let savedAddress = selection?.address ?? resolvedLocation.displayName
            let venue = try await repositories.venues.createVenue(
                VenueDraft(
                    name: name.trimmed,
                    status: status,
                    address: savedAddress,
                    city: selection?.city ?? resolvedLocation.city,
                    state: selection?.state ?? resolvedLocation.region,
                    country: selection?.country ?? resolvedLocation.country,
                    contactName: nil,
                    contactEmail: nil,
                    contactPhone: nil,
                    website: nil,
                    capacityMin: nil,
                    capacityMax: nil,
                    priceEstimate: nil,
                    priceNotes: nil,
                    ourNotes: nil,
                    latitude: selection?.latitude ?? resolvedLocation.latitude,
                    longitude: selection?.longitude ?? resolvedLocation.longitude,
                    photoURL: nil
                ),
                weddingID: weddingID
            )
            venueRecords.insert(venue, at: 0)
            if venue.latitude == nil || venue.longitude == nil,
               let recoveryQuery = VenueCoordinateRecovery.query(for: venue) {
                // `resolvedLocation` already gave this exact stored query one
                // chance. Do not immediately repeat it in the recovery task.
                venueCoordinateRecoveryAttempts[venue.id] = recoveryQuery
            }
            selectedVenueID = venue.id
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteVenue(_ venue: MVPVenue) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.venues.deleteVenue(id: venue.id)
            venueRecords.removeAll { $0.id == venue.id }
            let orphanedPhotoIDs = Set((venueGalleries[venue.id] ?? []).map(\.id))
            venueGalleries[venue.id] = nil
            venueDocuments[venue.id] = nil
            loadingVenueDocumentIDs.remove(venue.id)
            venueDocumentErrors[venue.id] = nil
            venuePhotoErrors[venue.id] = nil
            signedCoverPhotoURLs[venue.id] = nil
            signedGalleryPhotoURLs = signedGalleryPhotoURLs.filter { !orphanedPhotoIDs.contains($0.key) }
            if selectedVenueID == venue.id {
                selectedVenueID = venueRecords.first?.id
            }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    /// Applies a single-field patch and returns the updated venue, or `nil` on failure.
    /// Deliberately does not touch `errorMessage`/`saveFailure` — inline field edits show
    /// their own per-row failure state (spec §4.3), never a global alert or banner.
    @discardableResult
    func patchVenue(id: UUID, _ patch: VenuePatch) async -> Venue? {
        guard let repositories else { return nil }
        do {
            let updated = try await repositories.venues.updateVenue(id: id, patch: patch)
            replace(updated, in: &venueRecords)
            if patch.address != .unchanged
                || patch.latitude != .unchanged || patch.longitude != .unchanged {
                // A typed location intentionally clears its server coordinate.
                // Discard an old, address-specific fallback before resolving the
                // newly stored text once.
                recoveredVenueCoordinates[id] = nil
                venueCoordinateRecoveryAttempts[id] = nil
                recoverVenueCoordinates(for: [updated], repositories: repositories)
            }
            return updated
        } catch {
            return nil
        }
    }

    func uploadVenueDocument(
        data: Data,
        fileName: String,
        mimeType: String,
        venueID: UUID
    ) async -> Bool {
        guard let repositories,
              venueRecords.contains(where: { $0.id == venueID }) else {
            return unavailable()
        }
        venueDocumentErrors[venueID] = nil
        do {
            let document = try await repositories.venueDocuments.upload(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                venueID: venueID
            )
            var documents = venueDocuments[venueID] ?? []
            documents.removeAll { $0.id == document.id }
            documents.append(document)
            venueDocuments[venueID] = documents.sorted { $0.createdAt < $1.createdAt }
            return true
        } catch {
            venueDocumentErrors[venueID] = userMessage(for: error)
            return false
        }
    }

    /// Retrieves one venue document only after confirming that it belongs to
    /// a venue still loaded in this workspace. The view owns Quick Look.
    func downloadVenueDocument(_ document: VenueDocument) async throws -> Data {
        guard let repositories,
              venueRecords.contains(where: {
                  $0.id == document.venueID && $0.weddingID == document.weddingID
              }) else {
            throw BackendError.validation(
                message: "This document is not available in the current venue workspace.",
                requestID: nil
            )
        }
        return try await repositories.venueDocuments.download(document)
    }

    func deleteVenueDocument(_ document: VenueDocument) async -> Bool {
        guard let repositories,
              venueRecords.contains(where: {
                  $0.id == document.venueID && $0.weddingID == document.weddingID
              }) else {
            return unavailable()
        }
        venueDocumentErrors[document.venueID] = nil
        do {
            _ = try await repositories.venueDocuments.delete(documentID: document.id)
            venueDocuments[document.venueID]?.removeAll { $0.id == document.id }
            return true
        } catch {
            venueDocumentErrors[document.venueID] = userMessage(for: error)
            return false
        }
    }

    func uploadVenuePhoto(data: Data, venueID: UUID) async -> Bool {
        guard let repositories,
              let venue = venueRecords.first(where: { $0.id == venueID }) else {
            return unavailable()
        }
        venuePhotoErrors[venueID] = nil
        do {
            let nextSortOrder = (venueGalleries[venueID] ?? [])
                .compactMap(\.sortOrder)
                .max()
                .map { $0 + 1 } ?? 0
            let photo = try await repositories.venuePhotoMutations.upload(
                data: data,
                mimeType: "image/jpeg",
                venueID: venueID,
                weddingID: venue.weddingID,
                sortOrder: nextSortOrder
            )
            var gallery = venueGalleries[venueID] ?? []
            gallery.removeAll { $0.id == photo.id }
            gallery.append(photo)
            venueGalleries[venueID] = gallery.sorted {
                ($0.sortOrder ?? .max, $0.createdAt) < ($1.sortOrder ?? .max, $1.createdAt)
            }
            let resolver = VenuePhotoURLResolver(photoService: repositories.venuePhotos)
            if let url = await resolver.resolve(venueID: venueID, photoURL: photo.url) {
                signedGalleryPhotoURLs[photo.id] = url
            }
            return true
        } catch {
            venuePhotoErrors[venueID] = userMessage(for: error)
            return false
        }
    }

    func deleteVenuePhoto(_ photo: VenuePhoto) async -> Bool {
        guard let repositories,
              venueRecords.contains(where: {
                  $0.id == photo.venueID && $0.weddingID == photo.weddingID
              }) else {
            return unavailable()
        }
        venuePhotoErrors[photo.venueID] = nil
        do {
            try await repositories.venuePhotoMutations.delete(photo)
            venueGalleries[photo.venueID]?.removeAll { $0.id == photo.id }
            signedGalleryPhotoURLs[photo.id] = nil
            return true
        } catch {
            venuePhotoErrors[photo.venueID] = userMessage(for: error)
            return false
        }
    }

    func deleteVenueCoverPhoto(venueID: UUID) async -> Bool {
        guard let repositories,
              let venue = venueRecords.first(where: { $0.id == venueID }) else {
            return unavailable()
        }
        venuePhotoErrors[venueID] = nil
        do {
            let updated = try await repositories.venuePhotoMutations.deleteCoverPhoto(for: venue)
            replace(updated, in: &venueRecords)
            signedCoverPhotoURLs[venueID] = nil
            return true
        } catch {
            venuePhotoErrors[venueID] = userMessage(for: error)
            return false
        }
    }

    /// Address suggestions for the location autocomplete row. Empty input and lookup
    /// failures both resolve to an empty list rather than throwing.
    func geocodeSuggestions(for query: String) async -> [GeocodeResult] {
        guard let repositories else { return [] }
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return [] }
        return (try? await repositories.maps.geocode(query: trimmed)) ?? []
    }

    /// Creates a guest from every field the Add sheet can capture.
    ///
    /// Returns the created record so the caller can navigate to it. Geocoding
    /// runs first but never blocks the save: an unresolvable address is still
    /// stored, just without a map origin.
    func createGuest(
        firstName: String,
        lastName: String,
        location: String,
        selection: AppleMapsAddressSelection? = nil,
        rsvp: RSVPStatus,
        email: String = "",
        phone: String = "",
        plusGuests: [GuestPlusDraft] = [],
        customFields: [String: JSONValue] = [:]
    ) async -> Guest? {
        guard let repositories, let weddingID = wedding?.id else {
            _ = unavailable()
            return nil
        }
        do {
            let locationQuery = selection?.address ?? location
            // This first lookup is only for the address and its administrative
            // fields. Never use its (potentially street-precise) coordinate for
            // a guest map origin.
            let addressLocation = await resolvedLocation(for: locationQuery, repositories: repositories)
            let savedAddress = selection?.address ?? addressLocation.displayName
            let city = selection?.city ?? addressLocation.city
            let state = selection?.state ?? addressLocation.region
            let country = selection?.country ?? addressLocation.country
            let origin = await coarseGuestOrigin(
                city: city, state: state, country: country, repositories: repositories
            )
            let guest = try await repositories.guests.createGuest(
                GuestDraft(
                    firstName: firstName.trimmed,
                    lastName: lastName.nilIfBlank,
                    email: email.nilIfBlank,
                    phone: phone.nilIfBlank,
                    plusLimit: plusGuests.count,
                    address: savedAddress,
                    city: city,
                    state: state,
                    country: country,
                    customFields: .object(customFields),
                    rsvpStatus: rsvp,
                    // Guest origins intentionally use the city lookup rather
                    // than the selected street coordinate.
                    originLabel: nil,
                    originLatitude: origin?.latitude,
                    originLongitude: origin?.longitude,
                    originPrecision: origin == nil ? nil : "city",
                    geocodeStatus: GuestOriginPrivacy.geocodeStatus(address: savedAddress, origin: origin)
                ),
                weddingID: weddingID
            )
            guestRecords.insert(guest, at: 0)
            for plus in plusGuests where !plus.firstName.trimmed.isEmpty {
                let plusGuest = try await repositories.guests.createGuest(
                    GuestDraft(
                        firstName: plus.firstName.trimmed,
                        lastName: plus.lastName.nilIfBlank,
                        plusOfGuestID: guest.id,
                        rsvpStatus: .notInvited
                    ),
                    weddingID: weddingID
                )
                guestRecords.insert(plusGuest, at: 0)
            }
            errorMessage = nil
            return guest
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    // MARK: - Inline guest editing

    /// Commits one plain-text field.
    ///
    /// Returns false without touching the network when the value is unchanged
    /// or fails validation, so an unmodified row costs nothing.
    @discardableResult
    func commitField(
        _ field: GuestEditableField,
        for guestID: UUID,
        value: String
    ) async -> Bool {
        guard let record = guestRecord(id: guestID) else { return false }
        let key = GuestFieldKey(guestID: guestID, field: field)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != (field.currentValue(in: record) ?? "") else {
            fieldSaveStates[key] = nil
            return false
        }
        guard let patch = field.patch(newValue: trimmed) else {
            // Required and empty. The row restores itself and says why.
            fieldSaveStates[key] = nil
            return false
        }
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
    }

    /// Commits the address, then re-derives the coarse map origin from it.
    ///
    /// Geocoding runs after the write lands and never blocks or reverts it: an
    /// address that cannot be resolved is still the user's address.
    @discardableResult
    func commitAddress(for guestID: UUID, value: String) async -> Bool {
        guard let repositories, let record = guestRecord(id: guestID) else { return false }
        let key = GuestFieldKey(guestID: guestID, field: "address")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (record.address ?? "") else {
            fieldSaveStates[key] = nil
            return false
        }

        guard !trimmed.isEmpty else {
            // Clearing the address clears everything derived from it.
            let patch = GuestPatch(
                address: .null,
                city: .null,
                state: .null,
                country: .null,
                originLabel: .null,
                originLatitude: .null,
                originLongitude: .null,
                originPrecision: .null,
                geocodeStatus: .value("missing")
            )
            return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
        }

        // Show progress across the geocode too, not just the write that follows.
        fieldSaveStates[key] = .saving
        // Resolve the complete address for structured fields, then resolve the
        // disambiguated city query for the only coordinate we retain.
        let resolved = await resolvedLocation(for: trimmed, repositories: repositories)
        let origin = await coarseGuestOrigin(
            city: resolved.city, state: resolved.region, country: resolved.country, repositories: repositories
        )
        let patch = GuestPatch(
            address: .value(trimmed),
            city: resolved.city.map(NullablePatch.value) ?? .null,
            state: resolved.region.map(NullablePatch.value) ?? .null,
            country: resolved.country.map(NullablePatch.value) ?? .null,
            originLabel: .null,
            originLatitude: origin.map { .value($0.latitude) } ?? .null,
            originLongitude: origin.map { .value($0.longitude) } ?? .null,
            originPrecision: origin == nil ? .null : .value("city"),
            geocodeStatus: .value(GuestOriginPrivacy.geocodeStatus(address: trimmed, origin: origin))
        )
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
    }

    /// Saves an Apple Maps choice as one patch. The exact street coordinate is
    /// deliberately never persisted for a guest; the map uses the selected
    /// result's city through the existing coarse-location resolver instead.
    @discardableResult
    func commitAddress(for guestID: UUID, selection: AppleMapsAddressSelection) async -> Bool {
        guard let repositories, let record = guestRecord(id: guestID) else { return false }
        let key = GuestFieldKey(guestID: guestID, field: "address")
        guard selection.address != record.address
            || selection.city != record.city
            || selection.state != record.state
            || selection.country != record.country else {
            fieldSaveStates[key] = nil
            return false
        }

        fieldSaveStates[key] = .saving
        let origin = await coarseGuestOrigin(
            city: selection.city, state: selection.state, country: selection.country, repositories: repositories
        )
        let patch = GuestPatch(
            address: .value(selection.address),
            city: selection.city.map(NullablePatch.value) ?? .null,
            state: selection.state.map(NullablePatch.value) ?? .null,
            country: selection.country.map(NullablePatch.value) ?? .null,
            originLabel: .null,
            originLatitude: origin.map { .value($0.latitude) } ?? .null,
            originLongitude: origin.map { .value($0.longitude) } ?? .null,
            originPrecision: origin == nil ? .null : .value("city"),
            geocodeStatus: .value(GuestOriginPrivacy.geocodeStatus(address: selection.address, origin: origin))
        )
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: selection.address)
    }

    @discardableResult
    func commitRSVP(_ status: RSVPStatus, for guestID: UUID) async -> Bool {
        guard let record = guestRecord(id: guestID), record.rsvpStatus != status else { return false }
        let key = GuestFieldKey(guestID: guestID, field: "rsvpStatus")
        return await applyPatch(
            GuestPatch(rsvpStatus: .value(status)),
            guestID: guestID,
            key: key,
            pendingValue: nil
        )
    }

    /// Queues a custom-field write behind this guest's other custom-field
    /// writes. The merge base is read when the write runs, not when the row was
    /// focused, so edits to different keys cannot erase each other.
    func commitCustomField(_ column: GuestCustomColumn, for guestID: UUID, value: JSONValue?) {
        let previous = customFieldWrites[guestID]
        customFieldWrites[guestID] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.writeCustomField(column, guestID: guestID, value: value)
        }
    }

    private func writeCustomField(
        _ column: GuestCustomColumn,
        guestID: UUID,
        value: JSONValue?
    ) async {
        guard let repositories, let record = guestRecord(id: guestID) else { return }
        let key = GuestFieldKey.customField(guestID: guestID, key: column.key)
        fieldSaveStates[key] = .saving

        let merged = GuestCustomFields.merging(record.customFields, key: column.key, value: value)
        do {
            let updated = try await repositories.guests.updateGuest(
                id: guestID,
                patch: GuestPatch(customFields: merged)
            )
            replace(updated, in: &guestRecords)
            markSaved(key)
        } catch is CancellationError {
            fieldSaveStates[key] = nil
        } catch {
            let pending = GuestCustomFields.displayText(value, kind: column.kind)
            fieldSaveStates[key] = .failed(pendingValue: pending)
        }
    }

    /// Sends a single-field patch and reconciles the row's save state.
    ///
    /// A failure keeps `pendingValue` on the row so the user's input survives;
    /// nothing is reverted and nothing is discarded.
    private func applyPatch(
        _ patch: GuestPatch,
        guestID: UUID,
        key: GuestFieldKey,
        pendingValue: String?
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        guard !patch.isEmpty else { return false }
        fieldSaveStates[key] = .saving
        do {
            let updated = try await repositories.guests.updateGuest(id: guestID, patch: patch)
            replace(updated, in: &guestRecords)
            markSaved(key)
            return true
        } catch is CancellationError {
            fieldSaveStates[key] = nil
            return false
        } catch {
            fieldSaveStates[key] = .failed(pendingValue: pendingValue)
            return false
        }
    }

    /// Shows the confirmation tick briefly, then clears it.
    private func markSaved(_ key: GuestFieldKey) {
        fieldSaveStates[key] = .saved
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.fieldSaveStates[key] == .saved else { return }
            self.fieldSaveStates[key] = nil
        }
    }

    func clearSaveState(_ key: GuestFieldKey) {
        fieldSaveStates[key] = nil
    }

    func deleteGuest(_ guest: MVPGuest) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.guests.deleteGuest(id: guest.id)
            guestRecords.removeAll { $0.id == guest.id }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    // MARK: - Custom column administration

    /// How many guests hold a value for a column. Every destructive action
    /// quotes this so the blast radius is stated before it happens.
    func usageCount(for column: GuestCustomColumn) -> Int {
        guestRecords.filter { guest in
            GuestCustomFields.value(in: guest.customFields, for: column.key) != nil
        }.count
    }

    func usageCount(for column: GuestCustomColumn, option: String) -> Int {
        guestRecords.filter { guest in
            let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
            return GuestCustomFields.displayText(stored, kind: column.kind) == option
        }.count
    }

    /// Slugifies a label into a key, suffixing on collision.
    ///
    /// Keys are shared with the web workspace and immutable once created, so
    /// this runs only at creation time.
    func proposedKey(for label: String) -> String {
        let slug = label
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }
            .joined()
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        let base = slug.isEmpty ? "field" : slug
        let existing = Set(customColumnRecords.map(\.key))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base)_\(index)") { index += 1 }
        return "\(base)_\(index)"
    }

    @discardableResult
    func createCustomColumn(
        label: String,
        kind: GuestCustomColumnKind,
        options: [String]
    ) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        let trimmed = label.trimmed
        guard !trimmed.isEmpty else { return false }
        do {
            let column = try await repositories.guests.createCustomColumn(
                GuestCustomColumnDraft(
                    key: proposedKey(for: trimmed),
                    label: trimmed,
                    kind: kind,
                    options: .array(options.map(JSONValue.string)),
                    position: (customColumnRecords.map(\.position).max() ?? -1) + 1,
                    hidden: false
                ),
                weddingID: weddingID
            )
            customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords + [column])
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    @discardableResult
    func updateCustomColumn(
        _ column: GuestCustomColumn,
        label: String? = nil,
        kind: GuestCustomColumnKind? = nil,
        options: [String]? = nil,
        hidden: Bool? = nil
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            let updated = try await repositories.guests.updateCustomColumn(
                id: column.id,
                patch: GuestCustomColumnPatch(
                    label: label?.trimmed.nilIfBlank,
                    kind: kind,
                    options: options.map { .array($0.map(JSONValue.string)) },
                    hidden: hidden
                )
            )
            replace(updated, in: &customColumnRecords)
            customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    /// Persists a new ordering. Position drives guest detail, Add guest, and
    /// the filter sheet, so this is the single place order is decided.
    func reorderCustomColumns(from source: IndexSet, to destination: Int) async {
        guard let repositories else { _ = unavailable(); return }
        var ordered = GuestDisplayResolver.orderedColumns(customColumnRecords)
        ordered.move(fromOffsets: source, toOffset: destination)
        customColumnRecords = ordered

        for (index, column) in ordered.enumerated() where column.position != index {
            do {
                let updated = try await repositories.guests.updateCustomColumn(
                    id: column.id,
                    patch: GuestCustomColumnPatch(position: index)
                )
                replace(updated, in: &customColumnRecords)
            } catch {
                errorMessage = userMessage(for: error)
                // Re-read the server's truth rather than leave a half-applied order.
                await load()
                return
            }
        }
        customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords)
    }

    /// Renames one option of a select column.
    ///
    /// `rewritingGuests` decides what happens to guests already holding the old
    /// label: rewrite them, or leave them pointing at a label the column no
    /// longer offers (where the detail row shows it as no longer an option).
    @discardableResult
    func renameOption(
        _ column: GuestCustomColumn,
        from oldValue: String,
        to newValue: String,
        rewritingGuests: Bool
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        let trimmed = newValue.trimmed
        guard !trimmed.isEmpty, trimmed != oldValue else { return false }

        var options = GuestCustomFields.options(in: column)
        guard let index = options.firstIndex(of: oldValue) else { return false }
        options[index] = trimmed

        guard await updateCustomColumn(column, options: options) else { return false }
        guard rewritingGuests else { return true }

        for guest in guestRecords {
            let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
            guard GuestCustomFields.displayText(stored, kind: column.kind) == oldValue else { continue }
            do {
                let merged = GuestCustomFields.merging(
                    guest.customFields,
                    key: column.key,
                    value: .string(trimmed)
                )
                let updated = try await repositories.guests.updateGuest(
                    id: guest.id,
                    patch: GuestPatch(customFields: merged)
                )
                replace(updated, in: &guestRecords)
            } catch {
                errorMessage = userMessage(for: error)
                return false
            }
        }
        return true
    }

    @discardableResult
    func deleteCustomColumn(_ column: GuestCustomColumn) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.guests.deleteCustomColumn(id: column.id)
            customColumnRecords.removeAll { $0.id == column.id }
            // The values live on the guests, so refresh them to match.
            await load()
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    private func unavailable() -> Bool {
        errorMessage = "Your wedding workspace is not ready yet. Please try again."
        return false
    }

    private func presentLoadFailure() {
        presentSaveFailure(retry: { [weak self] in
            Task { await self?.load() }
        })
    }

    private func resolveVenuePhotoURLs(
        for venues: [Venue],
        repositories: RepositoryContainer
    ) {
        let resolver = VenuePhotoURLResolver(photoService: repositories.venuePhotos)
        Task { [weak self] in
            for venue in venues {
                guard !Task.isCancelled else { return }
                let gallery = (try? await repositories.venues.venuePhotos(venueID: venue.id)) ?? []
                guard !Task.isCancelled else { return }
                self?.venueGalleries[venue.id] = gallery

                if let coverURL = await resolver.resolve(venueID: venue.id, photoURL: venue.photoURL) {
                    guard !Task.isCancelled else { return }
                    self?.signedCoverPhotoURLs[venue.id] = coverURL
                }

                for photo in gallery {
                    guard !Task.isCancelled else { return }
                    if let url = await resolver.resolve(venueID: venue.id, photoURL: photo.url) {
                        guard !Task.isCancelled else { return }
                        self?.signedGalleryPhotoURLs[photo.id] = url
                    }
                }
            }
        }
    }

    /// Document metadata is loaded separately so a slow file listing never
    /// delays the workspace's core venue and guest records.
    private func resolveVenueDocuments(
        for venues: [Venue],
        repositories: RepositoryContainer
    ) {
        let venuesToResolve = venues.filter { loadingVenueDocumentIDs.insert($0.id).inserted }
        guard !venuesToResolve.isEmpty else { return }
        Task { [weak self] in
            defer {
                if Task.isCancelled {
                    for venue in venuesToResolve {
                        self?.loadingVenueDocumentIDs.remove(venue.id)
                    }
                }
            }
            for venue in venuesToResolve {
                guard !Task.isCancelled else { return }
                do {
                    let documents = try await repositories.venueDocuments.documents(venueID: venue.id)
                    guard !Task.isCancelled,
                          self?.venueRecords.contains(where: {
                              $0.id == venue.id && $0.weddingID == venue.weddingID
                          }) == true else {
                        continue
                    }
                    self?.venueDocuments[venue.id] = documents
                    self?.venueDocumentErrors[venue.id] = nil
                    self?.loadingVenueDocumentIDs.remove(venue.id)
                } catch is CancellationError {
                    self?.loadingVenueDocumentIDs.remove(venue.id)
                } catch {
                    self?.venueDocumentErrors[venue.id] = self?.userMessage(for: error)
                    self?.loadingVenueDocumentIDs.remove(venue.id)
                }
            }
        }
    }

    /// Returns persisted coordinates when available, otherwise an address-bound
    /// in-memory recovery. The address match makes a delayed old lookup harmless
    /// if the venue's location changes while it is in flight.
    private func recoveredCoordinate(for venue: Venue) -> Coordinate? {
        guard venue.latitude == nil || venue.longitude == nil,
              let recovery = recoveredVenueCoordinates[venue.id],
              let query = VenueCoordinateRecovery.query(for: venue),
              recovery.query == query else {
            return nil
        }
        return recovery.coordinate
    }

    private func coordinate(for venue: Venue) -> Coordinate? {
        if let latitude = venue.latitude,
           let longitude = venue.longitude,
           VenueCoordinateRecovery.isUsable(latitude: latitude, longitude: longitude) {
            return .init(latitude: latitude, longitude: longitude)
        }
        return recoveredCoordinate(for: venue)
    }

    /// Repairs only the current app session for venues that already have useful
    /// location text but lack one or both stored coordinate values. This remains
    /// asynchronous so a workspace load is never blocked on an external map
    /// lookup, and is serial to be kind to the geocoding endpoint.
    private func recoverVenueCoordinates(
        for venues: [Venue],
        repositories: RepositoryContainer
    ) {
        Task { [weak self] in
            for venue in venues {
                guard !Task.isCancelled,
                      let query = VenueCoordinateRecovery.query(for: venue) else {
                    continue
                }
                guard let self,
                      self.venueCoordinateRecoveryAttempts[venue.id] != query else {
                    continue
                }

                // Record the attempt before awaiting so a pull-to-refresh or a
                // concurrent location save cannot start a duplicate lookup.
                self.venueCoordinateRecoveryAttempts[venue.id] = query
                guard let result = try? await repositories.maps.geocode(query: query).first,
                      VenueCoordinateRecovery.isUsable(latitude: result.latitude, longitude: result.longitude),
                      !Task.isCancelled,
                      let currentVenue = self.venueRecords.first(where: { $0.id == venue.id }),
                      VenueCoordinateRecovery.query(for: currentVenue) == query,
                      currentVenue.latitude == nil || currentVenue.longitude == nil else {
                    continue
                }
                self.recoveredVenueCoordinates[venue.id] = .init(
                    query: query,
                    coordinate: .init(latitude: result.latitude, longitude: result.longitude)
                )
            }
        }
    }

    /// Resolves the workspace's saved city/region once per value, using the
    /// existing first-party geocode proxy. A lookup failure simply leaves
    /// venue distances absent.
    private func recoverVenueDistanceOrigin(
        for wedding: WeddingSummary,
        repositories: RepositoryContainer
    ) {
        guard let query = VenueDistanceOrigin.query(for: wedding) else {
            venueDistanceOrigin = nil
            venueDistanceOriginAttemptedQuery = nil
            return
        }
        guard venueDistanceOrigin?.query != query,
              venueDistanceOriginAttemptedQuery != query else {
            return
        }

        venueDistanceOrigin = nil
        venueDistanceOriginAttemptedQuery = query
        Task { [weak self] in
            guard let result = try? await repositories.maps.geocode(query: query).first,
                  VenueCoordinateRecovery.isUsable(
                    latitude: result.latitude,
                    longitude: result.longitude
                  ),
                  !Task.isCancelled,
                  let self,
                  VenueDistanceOrigin.query(for: self.wedding) == query else {
                return
            }
            self.venueDistanceOrigin = .init(
                query: query,
                coordinate: .init(latitude: result.latitude, longitude: result.longitude)
            )
        }
    }

    private func resolvedLocation(
        for input: String,
        repositories: RepositoryContainer
    ) async -> ResolvedLocation {
        let query = input.trimmed
        guard !query.isEmpty else { return .empty }
        guard let result = try? await repositories.maps.geocode(query: query).first else {
            return .init(displayName: query, city: nil, region: nil, country: nil, latitude: nil, longitude: nil)
        }
        return .init(
            displayName: result.displayName,
            city: result.city,
            region: result.region,
            country: result.country,
            latitude: result.latitude,
            longitude: result.longitude
        )
    }

    /// The guest map is intentionally city-scale. We first obtain city/state/
    /// country from the address result, then issue a second, disambiguated
    /// lookup for that administrative place and quantize it to the API's
    /// 0.1-degree privacy grid.
    private func coarseGuestOrigin(
        city: String?,
        state: String?,
        country: String?,
        repositories: RepositoryContainer
    ) async -> GuestOriginCoordinate? {
        guard let query = GuestOriginPrivacy.cityQuery(city: city, state: state, country: country) else {
            return nil
        }
        let location = await resolvedLocation(for: query, repositories: repositories)
        return GuestOriginPrivacy.coordinate(city: city, location: location)
    }

    private func replace<T: Identifiable>(_ value: T, in records: inout [T]) where T.ID: Equatable {
        guard let index = records.firstIndex(where: { $0.id == value.id }) else { return }
        records[index] = value
    }

    private func userMessage(for error: Error) -> String {
        if let message = (error as? BackendError)?.message?.nilIfBlank {
            return message
        }

        switch error as? BackendError {
        case .networkUnavailable:
            return "Vowbase couldn’t reach the server. Check your connection and try again."
        case .authenticationRequired:
            return "Your session has ended. Please sign in again."
        default:
            return "The server couldn’t complete that change. Please try again."
        }
    }
}

struct ResolvedLocation {
    let displayName: String?
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?

    static let empty = ResolvedLocation(
        displayName: nil, city: nil, region: nil, country: nil, latitude: nil, longitude: nil
    )
}

struct GuestOriginCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Pure privacy policy so every create/edit path uses the same city-only,
/// disambiguated and quantized guest-origin contract.
enum GuestOriginPrivacy {
    static func cityQuery(city: String?, state: String?, country: String?) -> String? {
        let parts = [city, state, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    static func coordinate(city: String?, location: ResolvedLocation) -> GuestOriginCoordinate? {
        guard city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let latitude = location.latitude,
              let longitude = location.longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        return .init(latitude: rounded(latitude), longitude: rounded(longitude))
    }

    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func geocodeStatus(address: String?, origin: GuestOriginCoordinate?) -> String {
        guard address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "missing"
        }
        return origin == nil ? "failed" : "resolved"
    }
}

/// A best-effort map coordinate associated with the exact text that produced
/// it. It intentionally lives only in `VowbaseWorkspaceStore`: a geocoder's
/// result is useful for this map session, but should not silently mutate the
/// address a couple chose to keep on their venue record.
struct VenueCoordinateRecovery: Equatable {
    let query: String
    let coordinate: Coordinate

    init(query: String, coordinate: Coordinate) {
        self.query = query
        self.coordinate = coordinate
    }

    static func fullAddress(for venue: Venue) -> String? {
        let primary = venue.address?.nilIfBlank
            ?? venue.locationText?.nilIfBlank
            ?? venue.location?.nilIfBlank
        let regionalParts = [venue.city, venue.state, venue.country]
            .compactMap { $0?.nilIfBlank }

        guard var result = primary else {
            return regionalParts.joined(separator: ", ").nilIfBlank
        }
        for part in regionalParts where result.range(of: part, options: .caseInsensitive) == nil {
            result += ", \(part)"
        }
        return result
    }

    static func query(for venue: Venue) -> String? {
        fullAddress(for: venue).flatMap { isMeaningfulLocationText($0) ? $0 : nil }
    }

    static func isUsable(latitude: Double, longitude: Double) -> Bool {
        CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude))
    }

    private static func isMeaningfulLocationText(_ text: String) -> Bool {
        guard text.localizedCaseInsensitiveCompare("Location not added") != .orderedSame else {
            return false
        }
        return text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 3
    }
}

/// Coarse venue-list distance starts from the location the couple saved for the
/// wedding. The resolved coordinate lasts only for this app session.
private struct VenueDistanceOrigin: Equatable {
    let query: String
    let coordinate: Coordinate

    static func query(for wedding: WeddingSummary?) -> String? {
        wedding?.location?.nilIfBlank.flatMap {
            $0.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 3
                ? $0
                : nil
        }
    }
}

private extension MVPVenue {
    init(
        _ venue: Venue,
        gallery: [VenuePhoto] = [],
        documents: [VenueDocument] = [],
        galleryPhotoURLs: [UUID: URL] = [:],
        coverPhotoURL: URL? = nil,
        recoveredCoordinate: Coordinate? = nil,
        distanceMiles: Double? = nil,
        travelText: String? = nil
    ) {
        id = venue.id
        name = venue.name
        status = venue.status
        location = venue.address?.nilIfBlank ?? venue.locationText?.nilIfBlank ?? venue.location ?? venue.city ?? "Location not added"
        fullAddress = VenueCoordinateRecovery.fullAddress(for: venue)
        mapSearchQuery = fullAddress ?? location
        city = venue.city?.nilIfBlank
        state = venue.state?.nilIfBlank
        self.distanceMiles = distanceMiles
        capacityMin = venue.capacityMin
        capacityMax = venue.capacityMax
        capacityTextOverride = venue.capacityText?.nilIfBlank
        estimate = venue.venueEstimateText?.nilIfBlank ?? venue.priceEstimate.map(VenuePriceFormatter.string) ?? "Not added"
        venueEstimateTextRaw = venue.venueEstimateText?.nilIfBlank
        travel = travelText
        allInEstimate = venue.allInEstimateText?.nilIfBlank ?? "Not added"
        availableDates = venue.availableDatesText?.nilIfBlank ?? "Not added"
        summary = venue.summary?.nilIfBlank
        website = venue.website?.nilIfBlank
        contactName = venue.contactName?.nilIfBlank
        contactEmail = venue.contactEmail?.nilIfBlank
        contactPhone = venue.contactPhone?.nilIfBlank
        latitude = recoveredCoordinate?.latitude ?? venue.latitude
        longitude = recoveredCoordinate?.longitude ?? venue.longitude
        // The store resolves the cover URL asynchronously; falling back to a direct parse
        // here avoids a blank-image flash on the first render for plain https URLs, which
        // is exactly what the async resolver would settle on anyway.
        self.coverPhotoURL = coverPhotoURL ?? VenuePhotoURLResolver.directPhotoURL(from: venue.photoURL)
        coverPhotoCacheKey = "venue-cover-\(venue.id)|\(venue.photoURL ?? "none")"
        photos = gallery.map { VenuePhotoDisplay(photo: $0, url: galleryPhotoURLs[$0.id]) }
        self.documents = documents
        ourNotes = venue.ourNotes?.nilIfBlank
    }
}

private extension MVPGuest {
    init(_ guest: Guest, columns: [GuestCustomColumn]) {
        id = guest.id
        firstName = guest.firstName
        lastName = guest.lastName ?? ""
        subtitle = GuestDisplayResolver.subtitle(for: guest, columns: columns)
        location = GuestLocationLabel.display(for: guest) ?? guest.address
        email = guest.email
        phone = guest.phone
        rsvp = guest.rsvpStatus ?? .notInvited
        isMappable = guest.originPrecision == "city"
            && guest.originLatitude != nil
            && guest.originLongitude != nil
        customSearchText = GuestCustomFields.object(in: guest.customFields)
            .values
            .compactMap { value in
                switch value {
                case let .string(text): text
                case let .number(number): String(number)
                default: nil
                }
            }
            .joined(separator: " ")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}
