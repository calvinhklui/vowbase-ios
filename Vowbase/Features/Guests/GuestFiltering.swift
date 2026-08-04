import Foundation

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
enum GuestPresenceFilter: String, CaseIterable, Sendable {
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
        if mappableOnly, guest.originPrecision != "city" {
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
        guard let label = guest.originLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
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
            guest.originLabel,
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
