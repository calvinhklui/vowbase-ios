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
        sort: VenueSortOrder
    ) -> [Venue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = venues.filter { venue in
            guard status == nil || venue.status == status else { return false }
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
            venue.location,
            venue.locationText,
            venue.address,
            venue.city,
            venue.state,
            venue.country,
            venue.contactName,
            venue.contactEmail,
            venue.contactPhone,
            venue.website,
            venue.summary,
            venue.ourNotes
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
        case .suggested: 0
        case .considering: 1
        case .contacted: 2
        case .toured: 3
        case .shortlisted: 4
        case .negotiating: 5
        case .booked: 6
        case .passed: 7
        }
    }
}
