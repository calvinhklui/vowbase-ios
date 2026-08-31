import Foundation

/// The list-level ordering choices for venues. These stay separate from the
/// metric-card status selection, which is a filter rather than a sort.
enum VenueSortOrder: String, CaseIterable, Identifiable, Sendable {
    case lastUpdated
    case nameAscending
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastUpdated: "Last updated"
        case .nameAscending: "Name A–Z"
        case .status: "Status"
        }
    }
}

/// Applies the Venues lens's local search, metric-card status filter, and
/// ordering over already-loaded records. Keeping this pure makes each control
/// immediately responsive and directly testable.
enum VenueQuery {
    static func apply(
        to venues: [Venue],
        searchText: String,
        status: VenueStatus?,
        sort: VenueSortOrder,
        metric: VenueMetric? = nil
    ) -> [Venue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = venues.filter { venue in
            guard status == nil || venue.status == status else { return false }
            guard metric?.condition.matches(venue) ?? true else { return false }
            guard !query.isEmpty else { return true }
            return searchHaystack(for: venue)
                .localizedCaseInsensitiveContains(query)
        }
        return sorted(matched, by: sort)
    }

    static func searchHaystack(for venue: Venue) -> String {
        [
            venue.name,
            venue.status.title,
            venue.status.rawValue,
            venue.address,
            venue.city,
            venue.state,
            venue.country,
            venue.contactName,
            venue.contactEmail,
            venue.contactPhone,
            venue.website,
            venue.summary,
            venue.ourNotes,
            VenueCustomFields.object(in: venue.customFields).values.compactMap { value in
                switch value {
                case let .string(text): text
                case let .number(number): String(number)
                case let .bool(flag): flag ? "Yes" : "No"
                case .array, .object, .null: nil
                }
            }.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    static func sorted(_ venues: [Venue], by sort: VenueSortOrder) -> [Venue] {
        venues.sorted { left, right in
            switch sort {
            case .lastUpdated:
                if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
                return name(left).localizedCaseInsensitiveCompare(name(right)) == .orderedAscending
            case .nameAscending:
                return name(left).localizedCaseInsensitiveCompare(name(right)) == .orderedAscending
            case .status:
                let leftRank = lifecycleRank(left.status)
                let rightRank = lifecycleRank(right.status)
                if leftRank != rightRank { return leftRank < rightRank }
                return name(left).localizedCaseInsensitiveCompare(name(right)) == .orderedAscending
            }
        }
    }

    private static func name(_ venue: Venue) -> String { venue.name }

    private static func lifecycleRank(_ status: VenueStatus) -> Int {
        switch status {
        case .booked: 0
        case .negotiating: 1
        case .shortlisted: 2
        case .toured: 3
        case .contacted: 4
        case .considering: 5
        case .passed: 6
        }
    }
}

// MARK: - Configurable venue metrics

extension VenueStatus {
    static let metricOrder: [VenueStatus] = [
        .considering, .contacted, .toured,
        .shortlisted, .negotiating, .booked, .passed,
    ]
}

enum VenueMetricPresence: String, Codable, Equatable, Sendable {
    case present
    case absent

    func matches(_ value: String?) -> Bool {
        let hasValue = !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return self == .present ? hasValue : !hasValue
    }

    func matches<T>(_ value: T?) -> Bool {
        self == .present ? value != nil : value == nil
    }
}

enum VenueMetricCondition: Codable, Equatable, Sendable {
    case allVenues
    case status(Set<VenueStatus>)
    case location(VenueMetricPresence)
    case capacity(VenueMetricPresence)
    case estimate(VenueMetricPresence)
    case customValue(key: String, value: String)
    case customHasValue(key: String)
    case customCheckbox(key: String, expected: Bool)

    func matches(_ venue: Venue) -> Bool {
        switch self {
        case .allVenues:
            return true
        case let .status(statuses):
            return statuses.contains(venue.status)
        case let .location(presence):
            let hasLocation = [venue.address, venue.city]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains { !$0.isEmpty }
            return (presence == .present) == hasLocation
        case let .capacity(presence):
            return presence.matches(venue.capacityMin ?? venue.capacityMax)
        case let .estimate(presence):
            return presence.matches(venue.canonicalVenueEstimateText)
        case let .customValue(key, value):
            return Self.normalizedValue(Self.comparableValue(
                VenueCustomFields.value(in: venue.customFields, for: key)
            )) == Self.normalizedValue(value)
        case let .customHasValue(key):
            return Self.normalizedValue(Self.comparableValue(
                VenueCustomFields.value(in: venue.customFields, for: key)
            )) != nil
        case let .customCheckbox(key, expected):
            return (VenueCustomFields.value(in: venue.customFields, for: key) == .bool(true)) == expected
        }
    }

    func summary(columns: [VenueCustomColumn]) -> String {
        switch self {
        case .allVenues:
            return "All venues"
        case let .status(statuses):
            let names = VenueStatus.metricOrder.filter(statuses.contains).map(\.title)
            return "Status is " + names.joined(separator: " or ")
        case let .location(presence):
            return presence == .present ? "Has a location" : "Location is missing"
        case let .capacity(presence):
            return presence == .present ? "Has a capacity" : "Capacity is missing"
        case let .estimate(presence):
            return presence == .present ? "Has an estimate" : "Estimate is missing"
        case let .customValue(key, value):
            return "\(Self.columnLabel(for: key, columns: columns)) is \(value)"
        case let .customHasValue(key):
            return "Has \(Self.columnLabel(for: key, columns: columns))"
        case let .customCheckbox(key, expected):
            return "\(Self.columnLabel(for: key, columns: columns)) is \(expected ? "Yes" : "No")"
        }
    }

    private static func columnLabel(for key: String, columns: [VenueCustomColumn]) -> String {
        columns.first(where: { $0.key == key })?.label ?? key
    }

    private static func comparableValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text): return text.isEmpty ? nil : text
        case let .number(number): return VenueCustomFields.displayText(.number(number), kind: .number)
        case let .bool(flag): return flag ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }

    private static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

struct VenueMetric: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var condition: VenueMetricCondition
    var isEnabled: Bool
    let isCustom: Bool

    var cardTitle: String { id == "total-venues" ? "Total" : name }

    func count(in venues: [Venue]) -> Int {
        venues.count(where: condition.matches)
    }
}

struct VenueMetricConfiguration: Codable, Equatable, Sendable {
    static let maximumShownMetrics = 8

    var metrics: [VenueMetric]

    static func `default`(columns: [VenueCustomColumn]) -> VenueMetricConfiguration {
        VenueMetricConfiguration(metrics: systemMetrics(columns: columns))
    }

    var shownMetrics: [VenueMetric] { metrics.filter(\.isEnabled) }
    var availableMetrics: [VenueMetric] { metrics.filter { !$0.isEnabled } }

    func normalized(columns: [VenueCustomColumn]) -> VenueMetricConfiguration {
        let defaults = Self.systemMetrics(columns: columns)
        var normalized = metrics
        for metric in defaults where !normalized.contains(where: { $0.id == metric.id }) {
            normalized.append(metric)
        }
        return VenueMetricConfiguration(metrics: normalized)
    }

    mutating func enable(_ id: String) {
        guard shownMetrics.count < Self.maximumShownMetrics,
              let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        metrics[index].isEnabled = true
    }

    mutating func disable(_ id: String) {
        guard let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        metrics[index].isEnabled = false
    }

    mutating func moveShown(from source: IndexSet, to destination: Int) {
        var shown = shownMetrics
        shown.move(fromOffsets: source, toOffset: destination)
        let shownIDs = Set(shown.map(\.id))
        metrics = shown + metrics.filter { !shownIDs.contains($0.id) }
    }

    mutating func addCustom(name: String, condition: VenueMetricCondition) -> String? {
        guard shownMetrics.count < Self.maximumShownMetrics else { return nil }
        let id = "custom-\(UUID().uuidString.lowercased())"
        metrics.append(VenueMetric(
            id: id,
            name: name,
            condition: condition,
            isEnabled: true,
            isCustom: true
        ))
        return id
    }

    private static func systemMetrics(columns: [VenueCustomColumn]) -> [VenueMetric] {
        var metrics = [
            VenueMetric(id: "total-venues", name: "Total venues", condition: .allVenues, isEnabled: false, isCustom: false),
        ]
        metrics += VenueStatus.metricOrder.map { status in
            VenueMetric(
                id: "status-\(status.rawValue)",
                name: status.title,
                condition: .status([status]),
                isEnabled: true,
                isCustom: false
            )
        }
        metrics += [
            VenueMetric(id: "missing-location", name: "Missing location", condition: .location(.absent), isEnabled: false, isCustom: false),
            VenueMetric(id: "missing-capacity", name: "Missing capacity", condition: .capacity(.absent), isEnabled: false, isCustom: false),
            VenueMetric(id: "missing-estimate", name: "Missing estimate", condition: .estimate(.absent), isEnabled: false, isCustom: false),
        ]
        metrics += columns.map { column in
            VenueMetric(
                id: "field-\(column.key)",
                name: column.label,
                condition: column.kind == .checkbox
                    ? .customCheckbox(key: column.key, expected: true)
                    : .customHasValue(key: column.key),
                isEnabled: false,
                isCustom: false
            )
        }
        return metrics
    }
}

/// Straight-line distance between two known coordinates, calculated locally
/// after the saved wedding location has been resolved once.
enum VenueDistance {
    private static let earthRadiusMiles = 3_958.7613

    static func miles(from origin: Coordinate, to destination: Coordinate) -> Double {
        let latitudeDelta = radians(destination.latitude - origin.latitude)
        let longitudeDelta = radians(destination.longitude - origin.longitude)
        let originLatitude = radians(origin.latitude)
        let destinationLatitude = radians(destination.latitude)
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(originLatitude) * cos(destinationLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadiusMiles * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

enum VenueRowLocationText {
    static func string(
        city: String?,
        state: String?,
        distanceMiles: Double?
    ) -> String {
        let cityStateText = [
            nonblank(city),
            nonblank(state).map(VenueStateAbbreviation.display)
        ]
            .compactMap { $0 }
            .joined(separator: ", ")
        let cityState = cityStateText.isEmpty ? nil : cityStateText
        let location = cityState ?? "Location unavailable"
        // Distances are intentionally paired only with city/state copy. Do not
        // present a distance when normalized geography is absent from the
        // venue record.
        guard cityState != nil, let distanceMiles, distanceMiles.isFinite else { return location }
        let distance = String(
            format: "%.1fmi away",
            locale: Locale(identifier: "en_US_POSIX"),
            distanceMiles
        )
        return "\(location) • \(distance)"
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum VenueStateAbbreviation {
    private static let unitedStates = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
        "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
        "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
        "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
        "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
        "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
        "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
        "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
        "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
        "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT",
        "vermont": "VT", "virginia": "VA", "washington": "WA", "west virginia": "WV",
        "wisconsin": "WI", "wyoming": "WY", "district of columbia": "DC"
    ]

    static func display(_ state: String) -> String {
        if state.count == 2 {
            return state.uppercased()
        }
        return unitedStates[state.lowercased()] ?? state
    }
}
