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
