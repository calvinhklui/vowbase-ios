import Foundation

/// The web-authored ordered tile schema. iOS displays only `count` tiles but
/// retains pie and bar tiles verbatim whenever it writes a count-tile edit.
enum MetricConfigurationSurface: String, Codable, Sendable {
    case guests
    case venues
}

enum SharedMetricTileType: String, Codable, Sendable {
    case count
    case pie
    case bar
}

struct SharedMetricTile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let type: SharedMetricTileType
    let label: String
    let field: String
    let value: String?
}

struct SharedMetricConfiguration: Codable, Equatable, Sendable {
    let id: UUID
    let weddingID: UUID
    let userID: UUID
    let surface: MetricConfigurationSurface
    let tiles: [SharedMetricTile]
    let schemaVersion: Int
    let revision: Int
    let updatedBy: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case userID = "user_id"
        case surface
        case tiles
        case schemaVersion = "schema_version"
        case revision
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    static func canonicalDefaults(for surface: MetricConfigurationSurface) -> [SharedMetricTile] {
        switch surface {
        case .guests:
            return [
                .init(id: "guest-total", type: .count, label: "Total", field: "__total", value: nil),
                .init(id: "guest-not-invited", type: .count, label: "Not invited", field: "rsvp_status", value: "not_invited"),
                .init(id: "guest-pending", type: .count, label: "Pending", field: "rsvp_status", value: "pending"),
                .init(id: "guest-maybe", type: .count, label: "Maybe", field: "rsvp_status", value: "maybe"),
                .init(id: "guest-accepted", type: .count, label: "Accepted", field: "rsvp_status", value: "accepted"),
                .init(id: "guest-declined", type: .count, label: "Declined", field: "rsvp_status", value: "declined"),
            ]
        case .venues:
            return [
                .init(id: "venue-total", type: .count, label: "Total", field: "__total", value: nil),
                .init(id: "venue-considering", type: .count, label: "Considering", field: "status", value: "considering"),
                .init(id: "venue-contacted", type: .count, label: "Contacted", field: "status", value: "contacted"),
                .init(id: "venue-toured", type: .count, label: "Toured", field: "status", value: "toured"),
                .init(id: "venue-shortlisted", type: .count, label: "Shortlisted", field: "status", value: "shortlisted"),
                .init(id: "venue-booked", type: .count, label: "Booked", field: "status", value: "booked"),
            ]
        }
    }
}

enum MetricConfigurationProjection {
    static func guestMetrics(
        from tiles: [SharedMetricTile],
        columns: [GuestCustomColumn]
    ) -> [GuestMetric] {
        let customKeys = Set(columns.map(\.key))
        return tiles.compactMap { tile in
            guard tile.type == .count, let condition = guestCondition(for: tile, customKeys: customKeys) else {
                return nil
            }
            return GuestMetric(id: tile.id, name: tile.label, condition: condition, isEnabled: true, isCustom: true)
        }
    }

    static func venueMetrics(
        from tiles: [SharedMetricTile],
        columns: [VenueCustomColumn]
    ) -> [VenueMetric] {
        let customKeys = Set(columns.map(\.key))
        return tiles.compactMap { tile in
            guard tile.type == .count, let condition = venueCondition(for: tile, customKeys: customKeys) else {
                return nil
            }
            return VenueMetric(id: tile.id, name: tile.label, condition: condition, isEnabled: true, isCustom: true)
        }
    }

    static func replacingCountTiles(
        in existing: [SharedMetricTile],
        with replacement: [SharedMetricTile],
        replacingCountTileIDs: Set<String>
    ) -> [SharedMetricTile] {
        var replacementIterator = replacement.makeIterator()
        var merged = [SharedMetricTile]()
        for tile in existing {
            if tile.type == .count, replacingCountTileIDs.contains(tile.id) {
                if let next = replacementIterator.next() { merged.append(next) }
            } else {
                merged.append(tile)
            }
        }
        while let next = replacementIterator.next() { merged.append(next) }
        return merged
    }

    static func tile(from metric: GuestMetric) -> SharedMetricTile? {
        let fieldAndValue: (String, String?)
        switch metric.condition {
        case .allGuests: fieldAndValue = ("__total", nil)
        case let .rsvp(statuses):
            guard statuses.count == 1, let status = statuses.first else { return nil }
            fieldAndValue = ("rsvp_status", status.rawValue)
        case let .address(presence): fieldAndValue = ("address", presence == .present ? "yes" : "no")
        case let .email(presence): fieldAndValue = ("email", presence == .present ? "yes" : "no")
        case let .phone(presence): fieldAndValue = ("phone", presence == .present ? "yes" : "no")
        case let .customValue(key, value): fieldAndValue = ("cf:\(key)", value)
        case .customHasValue: return nil
        case let .customCheckbox(key, expected): fieldAndValue = ("cf:\(key)", expected ? "yes" : "no")
        }
        return .init(id: metric.id, type: .count, label: metric.name, field: fieldAndValue.0, value: fieldAndValue.1)
    }

    static func tile(from metric: VenueMetric) -> SharedMetricTile? {
        let fieldAndValue: (String, String?)
        switch metric.condition {
        case .allVenues: fieldAndValue = ("__total", nil)
        case let .status(statuses):
            guard statuses.count == 1, let status = statuses.first else { return nil }
            fieldAndValue = ("status", status.rawValue)
        case let .location(presence): fieldAndValue = ("has_location", presence == .present ? "yes" : "no")
        case let .capacity(presence): fieldAndValue = ("has_capacity", presence == .present ? "yes" : "no")
        case let .estimate(presence): fieldAndValue = ("has_estimate", presence == .present ? "yes" : "no")
        case let .customValue(key, value): fieldAndValue = ("cf:\(key)", value)
        case .customHasValue: return nil
        case let .customCheckbox(key, expected): fieldAndValue = ("cf:\(key)", expected ? "yes" : "no")
        }
        return .init(id: metric.id, type: .count, label: metric.name, field: fieldAndValue.0, value: fieldAndValue.1)
    }

    private static func guestCondition(
        for tile: SharedMetricTile,
        customKeys: Set<String>
    ) -> GuestMetricCondition? {
        switch tile.field {
        case "__total": return .allGuests
        case "rsvp_status":
            guard let value = tile.value, let status = RSVPStatus(rawValue: value) else { return nil }
            return .rsvp([status])
        case "address": return presenceCondition(tile.value).map(GuestMetricCondition.address)
        case "email": return presenceCondition(tile.value).map(GuestMetricCondition.email)
        case "phone": return presenceCondition(tile.value).map(GuestMetricCondition.phone)
        default:
            guard tile.field.hasPrefix("cf:"), customKeys.contains(String(tile.field.dropFirst(3))), let value = tile.value else { return nil }
            return .customValue(key: String(tile.field.dropFirst(3)), value: value)
        }
    }

    private static func venueCondition(
        for tile: SharedMetricTile,
        customKeys: Set<String>
    ) -> VenueMetricCondition? {
        switch tile.field {
        case "__total": return .allVenues
        case "status":
            guard let value = tile.value, let status = VenueStatus(rawValue: value) else { return nil }
            return .status([status])
        case "has_location": return venuePresenceCondition(tile.value).map(VenueMetricCondition.location)
        case "has_capacity": return venuePresenceCondition(tile.value).map(VenueMetricCondition.capacity)
        case "has_estimate": return venuePresenceCondition(tile.value).map(VenueMetricCondition.estimate)
        default:
            guard tile.field.hasPrefix("cf:"), customKeys.contains(String(tile.field.dropFirst(3))), let value = tile.value else { return nil }
            return .customValue(key: String(tile.field.dropFirst(3)), value: value)
        }
    }

    private static func presenceCondition(_ value: String?) -> GuestPresenceFilter? {
        switch value {
        case "yes": .present
        case "no": .absent
        default: nil
        }
    }

    private static func venuePresenceCondition(_ value: String?) -> VenueMetricPresence? {
        switch value {
        case "yes": .present
        case "no": .absent
        default: nil
        }
    }
}
