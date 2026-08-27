import Foundation

/// Structured administrative fields are the guest-safe display source.
enum GuestLocationLabel {
    static func display(for guest: Guest) -> String? {
        let parts = [guest.city, guest.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Where a guest's coarse origin places them in the Location filter.
///
/// Guests with no resolved origin are a real bucket people filter on, not an
/// absence to hide, so they get an explicit case.
enum GuestLocationBucket: Hashable, Sendable {
    case named(String)
    case none

    var title: String {
        switch self {
        case let .named(label): label
        case .none: "No location"
        }
    }
}

/// A three-way condition. `any` means the field is not constrained at all,
/// which is different from constraining it to "absent".
enum GuestPresenceFilter: String, CaseIterable, Codable, Sendable {
    case any
    case present
    case absent

    var title: String {
        switch self {
        case .any: "Any"
        case .present: "Has"
        case .absent: "None"
        }
    }

    func matches(_ value: String?) -> Bool {
        let hasValue = !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        switch self {
        case .any: return true
        case .present: return hasValue
        case .absent: return !hasValue
        }
    }
}

/// A condition on one custom column, shaped by that column's kind.
enum GuestCustomCondition: Equatable, Sendable {
    /// Selected option labels. `nil` inside the set means "empty".
    case anyOf(Set<String>)
    case checkbox(Bool)

    /// Sentinel for "no value stored", so Empty can be selected alongside
    /// real options in the same multi-select.
    static let emptyToken = "\u{0}empty"

    var isActive: Bool {
        switch self {
        case let .anyOf(values): !values.isEmpty
        case .checkbox: true
        }
    }
}

enum GuestSortOrder: String, CaseIterable, Identifiable, Sendable {
    case nameAscending
    case nameDescending
    case recentlyAdded
    case rsvpStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        case .recentlyAdded: "Recently added"
        case .rsvpStatus: "RSVP status"
        }
    }
}

/// Every active filter condition.
///
/// Conditions AND across fields and OR within one field. That covers the
/// questions people actually ask ("pending guests in two cities who have an
/// email") without shipping a boolean expression editor onto a phone.
struct GuestFilterSet: Equatable, Sendable {
    var rsvpStatuses = Set<RSVPStatus>()
    var locations = Set<GuestLocationBucket>()
    var mappableOnly = false
    var email = GuestPresenceFilter.any
    var phone = GuestPresenceFilter.any
    var customConditions = [String: GuestCustomCondition]()

    var isEmpty: Bool { conditionCount == 0 }

    /// Conditions shown as removable tokens, including RSVP now that it has
    /// no dedicated chip row of its own.
    var conditionCount: Int {
        rsvpStatuses.count
            + locations.count
            + (mappableOnly ? 1 : 0)
            + (email == .any ? 0 : 1)
            + (phone == .any ? 0 : 1)
            + customConditions.values.filter(\.isActive).count
    }

    func matches(_ guest: Guest) -> Bool {
        if !rsvpStatuses.isEmpty, !rsvpStatuses.contains(guest.rsvpStatus ?? .notInvited) {
            return false
        }
        if !locations.isEmpty, !locations.contains(Self.bucket(for: guest)) {
            return false
        }
        // Mappable means the address resolved to city precision, which is all
        // the map ever receives.
        if mappableOnly,
           (guest.originPrecision != "city" || guest.originLatitude == nil || guest.originLongitude == nil) {
            return false
        }
        guard email.matches(guest.email), phone.matches(guest.phone) else { return false }

        for (key, condition) in customConditions {
            guard matches(guest, key: key, condition: condition) else { return false }
        }
        return true
    }

    private func matches(_ guest: Guest, key: String, condition: GuestCustomCondition) -> Bool {
        let stored = GuestCustomFields.value(in: guest.customFields, for: key)
        switch condition {
        case let .anyOf(values):
            guard !values.isEmpty else { return true }
            guard let text = Self.comparableText(stored) else {
                return values.contains(GuestCustomCondition.emptyToken)
            }
            return values.contains(text)
        case let .checkbox(expected):
            return (stored == .bool(true)) == expected
        }
    }

    static func bucket(for guest: Guest) -> GuestLocationBucket {
        guard let label = GuestLocationLabel.display(for: guest) else {
            return .none
        }
        return .named(label)
    }

    /// The text a stored value is matched by. Options are authored as strings,
    /// so numbers compare by their display form.
    private static func comparableText(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text): return text.isEmpty ? nil : text
        case let .number(number): return GuestCustomFields.displayText(.number(number), kind: .number)
        case let .bool(flag): return flag ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }
}

/// Applies search, filters, and sort over already-loaded guests.
///
/// Everything is local, which is what makes the sheet's live result count free
/// to compute on every toggle.
enum GuestQuery {
    static func apply(
        to guests: [Guest],
        columns: [GuestCustomColumn],
        searchText: String,
        filters: GuestFilterSet,
        sort: GuestSortOrder
    ) -> [Guest] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = guests.filter { guest in
            guard filters.matches(guest) else { return false }
            guard !query.isEmpty else { return true }
            return searchHaystack(for: guest, columns: columns).contains(query)
        }
        return sorted(matched, by: sort)
    }

    /// Search reaches names, contact details, coarse origin, and every custom
    /// value — the spec's list, not just the name.
    static func searchHaystack(for guest: Guest, columns: [GuestCustomColumn]) -> String {
        var parts = [
            guest.firstName,
            guest.lastName,
            guest.email,
            guest.phone,
            GuestLocationLabel.display(for: guest),
            guest.address
        ].compactMap { $0 }

        for value in GuestCustomFields.object(in: guest.customFields).values {
            switch value {
            case let .string(text): parts.append(text)
            case let .number(number):
                if let text = GuestCustomFields.displayText(.number(number), kind: .number) {
                    parts.append(text)
                }
            default: break
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    static func sorted(_ guests: [Guest], by order: GuestSortOrder) -> [Guest] {
        switch order {
        case .nameAscending:
            return guests.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        case .nameDescending:
            return guests.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedDescending }
        case .recentlyAdded:
            return guests.sorted { $0.createdAt > $1.createdAt }
        case .rsvpStatus:
            // Lifecycle order, then name, so the grouping reads as a funnel.
            return guests.sorted { left, right in
                let leftRank = rank(left.rsvpStatus ?? .notInvited)
                let rightRank = rank(right.rsvpStatus ?? .notInvited)
                return leftRank == rightRank
                    ? name(left).localizedCaseInsensitiveCompare(name(right)) == .orderedAscending
                    : leftRank < rightRank
            }
        }
    }

    /// Distinct coarse origins present in the list, with a trailing
    /// no-location bucket when any guest lacks one.
    static func locationBuckets(in guests: [Guest]) -> [GuestLocationBucket] {
        var named = Set<String>()
        var hasUnlocated = false
        for guest in guests {
            switch GuestFilterSet.bucket(for: guest) {
            case let .named(label): named.insert(label)
            case .none: hasUnlocated = true
            }
        }
        var buckets = named
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(GuestLocationBucket.named)
        if hasUnlocated { buckets.append(.none) }
        return buckets
    }

    static func count(_ guests: [Guest], in bucket: GuestLocationBucket) -> Int {
        guests.filter { GuestFilterSet.bucket(for: $0) == bucket }.count
    }

    static func count(_ guests: [Guest], rsvp: RSVPStatus) -> Int {
        guests.filter { ($0.rsvpStatus ?? .notInvited) == rsvp }.count
    }

    /// How many guests hold each option of a select column, plus the empty
    /// bucket, so the filter sheet can show counts before anything is applied.
    static func optionCounts(
        _ guests: [Guest],
        column: GuestCustomColumn
    ) -> (options: [String: Int], empty: Int) {
        var counts = [String: Int]()
        var empty = 0
        for guest in guests {
            let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
            if let text = GuestCustomFields.displayText(stored, kind: column.kind) {
                counts[text, default: 0] += 1
            } else {
                empty += 1
            }
        }
        return (counts, empty)
    }

    private static func name(_ guest: Guest) -> String {
        [guest.firstName, guest.lastName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func rank(_ status: RSVPStatus) -> Int {
        switch status {
        case .notInvited: 0
        case .pending: 1
        case .maybe: 2
        case .accepted: 3
        case .declined: 4
        }
    }
}

// MARK: - Configurable guest metrics

/// A compact card always has one count condition. Keeping this separate from
/// `GuestFilterSet` means tapping a card can narrow the ledger without
/// rewriting the user's search or the independently managed filter row.
enum GuestMetricCondition: Codable, Equatable, Sendable {
    case allGuests
    case rsvp(Set<RSVPStatus>)
    case address(GuestPresenceFilter)
    case customValue(key: String, value: String)
    case customHasValue(key: String)
    case customCheckbox(key: String, expected: Bool)

    func matches(_ guest: Guest) -> Bool {
        switch self {
        case .allGuests:
            return true
        case let .rsvp(statuses):
            return statuses.contains(guest.rsvpStatus ?? .notInvited)
        case let .address(presence):
            return presence.matches(guest.address)
        case let .customValue(key, value):
            return GuestMetricCondition.normalizedValue(
                GuestMetricCondition.comparableValue(
                    GuestCustomFields.value(in: guest.customFields, for: key)
                )
            ) == GuestMetricCondition.normalizedValue(value)
        case let .customHasValue(key):
            return GuestMetricCondition.normalizedValue(
                GuestMetricCondition.comparableValue(
                    GuestCustomFields.value(in: guest.customFields, for: key)
                )
            ) != nil
        case let .customCheckbox(key, expected):
            return (GuestCustomFields.value(in: guest.customFields, for: key) == .bool(true)) == expected
        }
    }

    func summary(columns: [GuestCustomColumn]) -> String {
        switch self {
        case .allGuests:
            return "All guests"
        case let .rsvp(statuses):
            let names = RSVPStatus.allCases.filter(statuses.contains).map(\.title)
            return "RSVP is " + names.joined(separator: " or ")
        case let .address(presence):
            return presence == .absent ? "Address is missing" : "Has an address"
        case let .customValue(key, value):
            return "\(Self.columnLabel(for: key, columns: columns)) is \(value)"
        case let .customHasValue(key):
            return "Has \(Self.columnLabel(for: key, columns: columns))"
        case let .customCheckbox(key, expected):
            return "\(Self.columnLabel(for: key, columns: columns)) is \(expected ? "Yes" : "No")"
        }
    }

    private static func columnLabel(for key: String, columns: [GuestCustomColumn]) -> String {
        columns.first(where: { $0.key == key })?.label ?? key
    }

    private static func comparableValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text): return text.isEmpty ? nil : text
        case let .number(number): return GuestCustomFields.displayText(.number(number), kind: .number)
        case let .bool(flag): return flag ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }

    /// Text custom fields are authored by people, unlike select values, so
    /// their metric equality follows the existing search normalization.
    private static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

struct GuestMetric: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var condition: GuestMetricCondition
    var isEnabled: Bool
    let isCustom: Bool

    /// The card rail uses a compact label while configuration keeps the more
    /// descriptive metric name used in the approved management surface.
    var cardTitle: String { id == "total-guests" ? "Total" : name }

    func count(in guests: [Guest]) -> Int {
        guests.count(where: condition.matches)
    }
}

/// Device-local MVP configuration. Guest data remains server-backed; this is
/// only each planner's preferred compact dashboard arrangement.
struct GuestMetricConfiguration: Codable, Equatable, Sendable {
    static let maximumShownMetrics = 8

    var metrics: [GuestMetric]

    static func `default`(columns: [GuestCustomColumn]) -> GuestMetricConfiguration {
        GuestMetricConfiguration(metrics: systemMetrics(columns: columns))
    }

    var shownMetrics: [GuestMetric] { metrics.filter(\.isEnabled) }
    var availableMetrics: [GuestMetric] { metrics.filter { !$0.isEnabled } }

    func normalized(columns: [GuestCustomColumn]) -> GuestMetricConfiguration {
        let defaults = Self.systemMetrics(columns: columns)
        var normalized = metrics
        for metric in defaults where !normalized.contains(where: { $0.id == metric.id }) {
            normalized.append(metric)
        }
        return GuestMetricConfiguration(metrics: normalized)
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
        let available = metrics.filter { !shownIDs.contains($0.id) }
        metrics = shown + available
    }

    mutating func addCustom(name: String, condition: GuestMetricCondition) -> String? {
        guard shownMetrics.count < Self.maximumShownMetrics else { return nil }
        let id = "custom-\(UUID().uuidString.lowercased())"
        metrics.append(GuestMetric(id: id, name: name, condition: condition, isEnabled: true, isCustom: true))
        return id
    }

    private static func systemMetrics(columns: [GuestCustomColumn]) -> [GuestMetric] {
        var metrics = [
            GuestMetric(id: "total-guests", name: "Total guests", condition: .allGuests, isEnabled: true, isCustom: false),
            GuestMetric(id: "needs-response", name: "Needs response", condition: .rsvp([.pending, .maybe]), isEnabled: true, isCustom: false),
            GuestMetric(id: "accepted", name: "Accepted", condition: .rsvp([.accepted]), isEnabled: false, isCustom: false),
            GuestMetric(id: "missing-address", name: "Missing address", condition: .address(.absent), isEnabled: false, isCustom: false)
        ]
        metrics += columns.map { column in
            GuestMetric(
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
