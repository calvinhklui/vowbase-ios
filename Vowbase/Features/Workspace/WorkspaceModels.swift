import Foundation

enum WeddingRole: String, Codable, Sendable {
    case owner
    case partner
    case planner
    case parent
    case viewer
}

struct WeddingSummary: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let coupleNames: String?
    let weddingDate: String?
    let dateFlexibility: String?
    let dateRangeStart: String?
    let dateRangeEnd: String?
    let location: String?

    init(
        id: UUID,
        name: String,
        coupleNames: String?,
        weddingDate: String?,
        dateFlexibility: String? = nil,
        dateRangeStart: String? = nil,
        dateRangeEnd: String? = nil,
        location: String?
    ) {
        self.id = id
        self.name = name
        self.coupleNames = coupleNames
        self.weddingDate = weddingDate
        self.dateFlexibility = dateFlexibility
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case coupleNames = "couple_names"
        case weddingDate = "wedding_date"
        case dateFlexibility = "date_flexibility"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
        case location
    }
}

struct WeddingMembership: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingId: UUID
    let userId: UUID
    let role: WeddingRole
    let status: String
    let wedding: WeddingSummary

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingId = "wedding_id"
        case userId = "user_id"
        case role
        case status
        case wedding
    }
}

struct WeddingPatch: Encodable, Equatable, Sendable {
    let name: String?
    let coupleNames: String?
    let weddingDate: NullablePatch<String>
    let dateFlexibility: String?
    let dateRangeStart: NullablePatch<String>
    let dateRangeEnd: NullablePatch<String>
    let location: String?

    init(
        name: String? = nil,
        coupleNames: String? = nil,
        weddingDate: NullablePatch<String> = .unchanged,
        dateFlexibility: String? = nil,
        dateRangeStart: NullablePatch<String> = .unchanged,
        dateRangeEnd: NullablePatch<String> = .unchanged,
        location: String? = nil
    ) {
        self.name = name
        self.coupleNames = coupleNames
        self.weddingDate = weddingDate
        self.dateFlexibility = dateFlexibility
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case coupleNames = "couple_names"
        case weddingDate = "wedding_date"
        case dateFlexibility = "date_flexibility"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
        case location
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(coupleNames, forKey: .coupleNames)
        try encode(weddingDate, into: &container, forKey: .weddingDate)
        try container.encodeIfPresent(dateFlexibility, forKey: .dateFlexibility)
        try encode(dateRangeStart, into: &container, forKey: .dateRangeStart)
        try encode(dateRangeEnd, into: &container, forKey: .dateRangeEnd)
        try container.encodeIfPresent(location, forKey: .location)
    }

    private func encode<Value: Encodable & Equatable & Sendable>(
        _ patch: NullablePatch<Value>,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        switch patch {
        case .unchanged: break
        case let .value(value): try container.encode(value, forKey: key)
        case .null: try container.encodeNil(forKey: key)
        }
    }
}

struct SessionSummary: Codable, Equatable, Sendable {
    struct User: Codable, Equatable, Sendable {
        let id: UUID
        let email: String?
    }

    let user: User
    let weddingIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case user
        case weddingIDs = "weddingIds"
    }
}
