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
    let photos: [VenuePhotoDisplay]
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
    private var signedCoverPhotoURLs = [UUID: URL]()
    private var signedGalleryPhotoURLs = [UUID: URL]()
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
        venueRecords.map { venue in
            MVPVenue(
                venue,
                gallery: venueGalleries[venue.id] ?? [],
                galleryPhotoURLs: signedGalleryPhotoURLs,
                coverPhotoURL: signedCoverPhotoURLs[venue.id],
                travelText: travelText(for: venue.id)
            )
        }
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
        sort: GuestSortOrder
    ) -> [MVPGuest] {
        let columns = customColumnRecords
        return GuestQuery
            .apply(to: guestRecords, columns: columns, searchText: searchText, filters: filters, sort: sort)
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
                  let city = guest.originLabel,
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

    func load() async {
        guard let repositories else { return }
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
                presentLoadFailure()
                return
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
            signedCoverPhotoURLs = signedCoverPhotoURLs.filter { currentVenueIDs.contains($0.key) }
            let currentPhotoIDs = Set(venueGalleries.values.flatMap { $0.map(\.id) })
            signedGalleryPhotoURLs = signedGalleryPhotoURLs.filter { currentPhotoIDs.contains($0.key) }
            resolveVenuePhotoURLs(for: venueRecords, repositories: repositories)
            if !venueRecords.contains(where: { $0.id == selectedVenueID }) {
                selectedVenueID = venueRecords.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
            presentLoadFailure()
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
        guard let latitude = venue.latitude, let longitude = venue.longitude else {
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
                origin: Coordinate(latitude: latitude, longitude: longitude),
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

    func createVenue(name: String, location: String, status: VenueStatus) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let location = await resolvedLocation(for: location, repositories: repositories)
            let venue = try await repositories.venues.createVenue(
                VenueDraft(
                    name: name.trimmed,
                    status: status,
                    location: location.displayName,
                    address: location.displayName,
                    city: location.city,
                    state: location.region,
                    country: location.country,
                    contactName: nil,
                    contactEmail: nil,
                    contactPhone: nil,
                    website: nil,
                    capacityMin: nil,
                    capacityMax: nil,
                    priceEstimate: nil,
                    priceNotes: nil,
                    ourNotes: nil,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    photoURL: nil
                ),
                weddingID: weddingID
            )
            venueRecords.insert(venue, at: 0)
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
            return updated
        } catch {
            return nil
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
            let resolved = await resolvedLocation(for: location, repositories: repositories)
            let guest = try await repositories.guests.createGuest(
                GuestDraft(
                    firstName: firstName.trimmed,
                    lastName: lastName.nilIfBlank,
                    email: email.nilIfBlank,
                    phone: phone.nilIfBlank,
                    plusLimit: plusGuests.count,
                    address: resolved.displayName,
                    customFields: .object(customFields),
                    rsvpStatus: rsvp,
                    originLabel: resolved.city ?? resolved.displayName,
                    originLatitude: resolved.latitude,
                    originLongitude: resolved.longitude,
                    originPrecision: resolved.city == nil ? nil : "city",
                    geocodeStatus: resolved.latitude == nil ? nil : "resolved"
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
                originLabel: .null,
                originLatitude: .null,
                originLongitude: .null,
                originPrecision: .null,
                geocodeStatus: .null
            )
            return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
        }

        // Show progress across the geocode too, not just the write that follows.
        fieldSaveStates[key] = .saving
        let resolved = await resolvedLocation(for: trimmed, repositories: repositories)
        let patch = GuestPatch(
            address: .value(trimmed),
            originLabel: (resolved.city ?? resolved.displayName).map(NullablePatch.value) ?? .null,
            originLatitude: resolved.latitude.map(NullablePatch.value) ?? .null,
            originLongitude: resolved.longitude.map(NullablePatch.value) ?? .null,
            originPrecision: resolved.city == nil ? .null : .value("city"),
            geocodeStatus: resolved.latitude == nil ? .null : .value("resolved")
        )
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
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

private struct ResolvedLocation {
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

private extension MVPVenue {
    init(
        _ venue: Venue,
        gallery: [VenuePhoto] = [],
        galleryPhotoURLs: [UUID: URL] = [:],
        coverPhotoURL: URL? = nil,
        travelText: String? = nil
    ) {
        id = venue.id
        name = venue.name
        status = venue.status
        location = venue.locationText?.nilIfBlank ?? venue.location ?? venue.city ?? venue.address ?? "Location not added"
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
        latitude = venue.latitude
        longitude = venue.longitude
        // The store resolves the cover URL asynchronously; falling back to a direct parse
        // here avoids a blank-image flash on the first render for plain https URLs, which
        // is exactly what the async resolver would settle on anyway.
        self.coverPhotoURL = coverPhotoURL ?? VenuePhotoURLResolver.directPhotoURL(from: venue.photoURL)
        photos = gallery.map { VenuePhotoDisplay(photo: $0, url: galleryPhotoURLs[$0.id]) }
        ourNotes = venue.ourNotes?.nilIfBlank
    }
}

private extension MVPGuest {
    init(_ guest: Guest, columns: [GuestCustomColumn]) {
        id = guest.id
        firstName = guest.firstName
        lastName = guest.lastName ?? ""
        subtitle = GuestDisplayResolver.subtitle(for: guest, columns: columns)
        location = guest.originLabel ?? guest.address
        email = guest.email
        phone = guest.phone
        rsvp = guest.rsvpStatus ?? .notInvited
        isMappable = guest.originPrecision == "city"
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
