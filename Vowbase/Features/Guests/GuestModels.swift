import Foundation

enum RSVPStatus: String, Codable, Equatable, Sendable {
    case notInvited = "not_invited"
    case pending
    case maybe
    case accepted
    case declined
}

enum GuestCustomColumnKind: String, Codable, Equatable, Sendable {
    case text
    case number
    case select
    case checkbox
}

struct Guest: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let firstName: String
    let lastName: String?
    let email: String?
    let phone: String?
    let plusLimit: Int
    let plusOfGuestID: UUID?
    let address: String?
    let city: String?
    let state: String?
    let country: String?
    let customFields: JSONValue
    let rsvpStatus: RSVPStatus?
    let rsvpDate: Date?
    let originLatitude: Double?
    let originLongitude: Double?
    let originPrecision: String?
    let geocodeStatus: String?
    let createdAt: Date

    init(
        id: UUID,
        weddingID: UUID,
        firstName: String,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        plusLimit: Int = 0,
        plusOfGuestID: UUID? = nil,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        customFields: JSONValue = .object([:]),
        rsvpStatus: RSVPStatus? = nil,
        rsvpDate: Date? = nil,
        originLatitude: Double? = nil,
        originLongitude: Double? = nil,
        originPrecision: String? = nil,
        geocodeStatus: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.weddingID = weddingID
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.plusLimit = plusLimit
        self.plusOfGuestID = plusOfGuestID
        self.address = address
        self.city = city
        self.state = state
        self.country = country
        self.customFields = customFields
        self.rsvpStatus = rsvpStatus
        self.rsvpDate = rsvpDate
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.originPrecision = originPrecision
        self.geocodeStatus = geocodeStatus
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
        case plusLimit = "plus_limit"
        case plusOfGuestID = "plus_of_guest_id"
        case address
        case city, state, country
        case customFields = "custom_fields"
        case rsvpStatus = "rsvp_status"
        case rsvpDate = "rsvp_date"
        case originLatitude = "origin_latitude"
        case originLongitude = "origin_longitude"
        case originPrecision = "origin_precision"
        case geocodeStatus = "geocode_status"
        case createdAt = "created_at"
    }
}

struct GuestDraft: Codable, Equatable, Sendable {
    let firstName: String
    let lastName: String?
    let email: String?
    let phone: String?
    let plusLimit: Int
    let plusOfGuestID: UUID?
    let address: String?
    let city: String?
    let state: String?
    let country: String?
    let customFields: JSONValue
    let rsvpStatus: RSVPStatus?
    let originLatitude: Double?
    let originLongitude: Double?
    let originPrecision: String?
    let geocodeStatus: String?

    init(
        firstName: String,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        plusLimit: Int = 0,
        plusOfGuestID: UUID? = nil,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        customFields: JSONValue = .object([:]),
        rsvpStatus: RSVPStatus? = nil,
        originLatitude: Double? = nil,
        originLongitude: Double? = nil,
        originPrecision: String? = nil,
        geocodeStatus: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.plusLimit = plusLimit
        self.plusOfGuestID = plusOfGuestID
        self.address = address
        self.city = city
        self.state = state
        self.country = country
        self.customFields = customFields
        self.rsvpStatus = rsvpStatus
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.originPrecision = originPrecision
        self.geocodeStatus = geocodeStatus
    }

    private enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
        case plusLimit = "plus_limit"
        case plusOfGuestID = "plus_of_guest_id"
        case address
        case city, state, country
        case customFields = "custom_fields"
        case rsvpStatus = "rsvp_status"
        case originLatitude = "origin_latitude"
        case originLongitude = "origin_longitude"
        case originPrecision = "origin_precision"
        case geocodeStatus = "geocode_status"
    }
}

struct GuestPlusDraft: Equatable, Sendable {
    let firstName: String
    let lastName: String
}

enum NullablePatch<Value: Encodable & Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case value(Value)
    case null
}

struct GuestPatch: Encodable, Equatable, Sendable {
    let firstName: String?
    let lastName: NullablePatch<String>
    let email: NullablePatch<String>
    let phone: NullablePatch<String>
    let plusLimit: Int?
    let plusOfGuestID: NullablePatch<UUID>
    let address: NullablePatch<String>
    let city: NullablePatch<String>
    let state: NullablePatch<String>
    let country: NullablePatch<String>
    let customFields: JSONValue?
    let rsvpStatus: NullablePatch<RSVPStatus>
    let originLatitude: NullablePatch<Double>
    let originLongitude: NullablePatch<Double>
    let originPrecision: NullablePatch<String>
    let geocodeStatus: NullablePatch<String>

    init(
        firstName: String? = nil,
        lastName: NullablePatch<String> = .unchanged,
        email: NullablePatch<String> = .unchanged,
        phone: NullablePatch<String> = .unchanged,
        plusLimit: Int? = nil,
        plusOfGuestID: NullablePatch<UUID> = .unchanged,
        address: NullablePatch<String> = .unchanged,
        city: NullablePatch<String> = .unchanged,
        state: NullablePatch<String> = .unchanged,
        country: NullablePatch<String> = .unchanged,
        customFields: JSONValue? = nil,
        rsvpStatus: NullablePatch<RSVPStatus> = .unchanged,
        originLatitude: NullablePatch<Double> = .unchanged,
        originLongitude: NullablePatch<Double> = .unchanged,
        originPrecision: NullablePatch<String> = .unchanged,
        geocodeStatus: NullablePatch<String> = .unchanged
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.plusLimit = plusLimit
        self.plusOfGuestID = plusOfGuestID
        self.address = address
        self.city = city
        self.state = state
        self.country = country
        self.customFields = customFields
        self.rsvpStatus = rsvpStatus
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.originPrecision = originPrecision
        self.geocodeStatus = geocodeStatus
    }

    private enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
        case plusLimit = "plus_limit"
        case plusOfGuestID = "plus_of_guest_id"
        case address
        case city, state, country
        case customFields = "custom_fields"
        case rsvpStatus = "rsvp_status"
        case originLatitude = "origin_latitude"
        case originLongitude = "origin_longitude"
        case originPrecision = "origin_precision"
        case geocodeStatus = "geocode_status"
    }

    var isEmpty: Bool {
        firstName == nil
            && lastName == .unchanged
            && email == .unchanged
            && phone == .unchanged
            && plusLimit == nil
            && plusOfGuestID == .unchanged
            && address == .unchanged
            && city == .unchanged && state == .unchanged && country == .unchanged
            && customFields == nil
            && rsvpStatus == .unchanged
            && originLatitude == .unchanged
            && originLongitude == .unchanged
            && originPrecision == .unchanged
            && geocodeStatus == .unchanged
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try encode(lastName, forKey: .lastName, into: &container)
        try encode(email, forKey: .email, into: &container)
        try encode(phone, forKey: .phone, into: &container)
        try container.encodeIfPresent(plusLimit, forKey: .plusLimit)
        try encode(plusOfGuestID, forKey: .plusOfGuestID, into: &container)
        try encode(address, forKey: .address, into: &container)
        try encode(city, forKey: .city, into: &container)
        try encode(state, forKey: .state, into: &container)
        try encode(country, forKey: .country, into: &container)
        try container.encodeIfPresent(customFields, forKey: .customFields)
        try encode(rsvpStatus, forKey: .rsvpStatus, into: &container)
        try encode(originLatitude, forKey: .originLatitude, into: &container)
        try encode(originLongitude, forKey: .originLongitude, into: &container)
        try encode(originPrecision, forKey: .originPrecision, into: &container)
        try encode(geocodeStatus, forKey: .geocodeStatus, into: &container)
    }

    private func encode<Value: Encodable & Equatable & Sendable>(
        _ field: NullablePatch<Value>,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch field {
        case .unchanged:
            break
        case let .value(value):
            try container.encode(value, forKey: key)
        case .null:
            try container.encodeNil(forKey: key)
        }
    }
}

struct GuestCustomColumn: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let key: String
    let label: String
    let kind: GuestCustomColumnKind
    let options: JSONValue
    let position: Int
    let hidden: Bool
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case key
        case label
        case kind
        case options
        case position
        case hidden
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GuestCustomColumnDraft: Codable, Equatable, Sendable {
    let key: String
    let label: String
    let kind: GuestCustomColumnKind
    let options: JSONValue
    let position: Int?
    let hidden: Bool?

    init(
        key: String,
        label: String,
        kind: GuestCustomColumnKind,
        options: JSONValue = .array([]),
        position: Int? = nil,
        hidden: Bool? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.options = options
        self.position = position
        self.hidden = hidden
    }
}

struct GuestCustomColumnPatch: Codable, Equatable, Sendable {
    let key: String?
    let label: String?
    let kind: GuestCustomColumnKind?
    let options: JSONValue?
    let position: Int?
    let hidden: Bool?

    init(
        key: String? = nil,
        label: String? = nil,
        kind: GuestCustomColumnKind? = nil,
        options: JSONValue? = nil,
        position: Int? = nil,
        hidden: Bool? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.options = options
        self.position = position
        self.hidden = hidden
    }
}

struct RSVP: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let guestID: UUID
    let eventID: UUID
    let status: RSVPStatus?
    let mealChoice: String?
    let notes: String?
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case guestID = "guest_id"
        case eventID = "event_id"
        case status
        case mealChoice = "meal_choice"
        case notes
        case updatedAt = "updated_at"
    }
}

struct RSVPDraft: Codable, Equatable, Sendable {
    let weddingID: UUID
    let guestID: UUID
    let eventID: UUID
    let status: RSVPStatus?
    let mealChoice: String?
    let notes: String?

    init(
        weddingID: UUID,
        guestID: UUID,
        eventID: UUID,
        status: RSVPStatus? = nil,
        mealChoice: String? = nil,
        notes: String? = nil
    ) {
        self.weddingID = weddingID
        self.guestID = guestID
        self.eventID = eventID
        self.status = status
        self.mealChoice = mealChoice
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id"
        case guestID = "guest_id"
        case eventID = "event_id"
        case status
        case mealChoice = "meal_choice"
        case notes
    }
}


// MARK: - Display helpers moved from ContentView.swift's split (Phase 0)
extension RSVPStatus: Hashable {}

extension RSVPStatus {
    static var allCases: [RSVPStatus] { [.notInvited, .pending, .maybe, .accepted, .declined] }

    var title: String {
        switch self {
        case .notInvited: "Not invited"
        case .pending: "Pending"
        case .maybe: "Maybe"
        case .accepted: "Accepted"
        case .declined: "Declined"
        }
    }
}
