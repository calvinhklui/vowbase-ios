import Foundation
enum VenueStatus: String, Codable, Equatable, Hashable, Sendable { case considering, contacted, toured, shortlisted, negotiating, booked, passed }
enum VenueCustomColumnKind: String, Codable, Equatable, Sendable, CaseIterable {
    case text, number, select, checkbox, rank
}

struct VenueCustomFieldKey: Hashable, Sendable {
    let venueID: UUID
    let key: String
}

enum VenueCustomFieldSaveState: Equatable, Sendable {
    case saving, saved
    case failed(pendingValue: String?)
}

/// The wedding-scoped schema for values in `venues.custom_fields`.
///
/// `key` and `weddingID` are intentionally absent from the patch model: they
/// are immutable database identity, not editable presentation attributes.
struct VenueCustomColumn: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let key: String
    let label: String
    let kind: VenueCustomColumnKind
    let options: JSONValue
    let position: Int
    let hidden: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, key, label, kind, options, position, hidden
        case weddingID = "wedding_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct VenueCustomColumnDraft: Codable, Equatable, Sendable {
    let key: String
    let label: String
    let kind: VenueCustomColumnKind
    let options: JSONValue
    let position: Int?
    let hidden: Bool?

    init(key: String, label: String, kind: VenueCustomColumnKind, options: JSONValue = .array([]), position: Int? = nil, hidden: Bool? = nil) {
        self.key = key; self.label = label; self.kind = kind; self.options = options; self.position = position; self.hidden = hidden
    }
}

struct VenueCustomColumnPatch: Codable, Equatable, Sendable {
    let label: String?
    let kind: VenueCustomColumnKind?
    let options: JSONValue?
    let position: Int?
    let hidden: Bool?

    init(label: String? = nil, kind: VenueCustomColumnKind? = nil, options: JSONValue? = nil, position: Int? = nil, hidden: Bool? = nil) {
        self.label = label; self.kind = kind; self.options = options; self.position = position; self.hidden = hidden
    }
}

/// RFC 7396-style partial values sent to the scoped RPC. `JSONValue.null`
/// removes that key; omitted dictionary keys remain unchanged.
struct VenueCustomFieldsPatch: Codable, Equatable, Sendable {
    let updates: [String: JSONValue]
    init(updates: [String: JSONValue]) { self.updates = updates }
}

enum VenueCustomFields {
    static func object(in value: JSONValue) -> [String: JSONValue] {
        guard case let .object(fields) = value else { return [:] }
        return fields
    }

    static func value(in value: JSONValue, for key: String) -> JSONValue? {
        guard let stored = object(in: value)[key], stored != .null else { return nil }
        return stored
    }

    static func displayText(_ value: JSONValue?, kind: VenueCustomColumnKind) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        case let .number(number):
            return number.rounded() == number && number.magnitude < 1e15 ? String(Int(number)) : String(number)
        case let .bool(flag): return flag ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }

    static func isUnsupported(_ value: JSONValue?, kind: VenueCustomColumnKind) -> Bool {
        guard let value else { return false }
        switch (value, kind) {
        case (.string, .text), (.string, .select), (.number, .number), (.bool, .checkbox): return false
        case (.number, .text), (.string, .number): return false
        case let (.number(score), .rank): return score.rounded() != score || !(1...5).contains(Int(score))
        default: return true
        }
    }

    static func encode(_ text: String, kind: VenueCustomColumnKind) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch kind {
        case .text, .select: return .string(trimmed)
        case .number: return Double(trimmed).map(JSONValue.number)
        case .checkbox: return .bool(true)
        case .rank:
            guard let score = Int(trimmed), (1...5).contains(score) else { return nil }
            return .number(Double(score))
        }
    }

    static func options(in column: VenueCustomColumn) -> [String] {
        guard case let .array(values) = column.options else { return [] }
        return values.compactMap { if case let .string(value) = $0 { value } else { nil } }
    }
}

enum VenueDisplayResolver {
    static func orderedColumns(_ columns: [VenueCustomColumn]) -> [VenueCustomColumn] {
        columns.sorted {
            $0.position == $1.position
                ? $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                : $0.position < $1.position
        }
    }

    static func visibleColumns(_ columns: [VenueCustomColumn]) -> [VenueCustomColumn] {
        orderedColumns(columns).filter { !$0.hidden }
    }
}

struct Venue: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let name: String
    let status: VenueStatus
    let address: String?
    let city: String?
    let state: String?
    let country: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let website: String?
    let capacityMin: Int?
    let capacityMax: Int?
    let capacityText: String?
    let priceNotes: String?
    let venueEstimateText: String?
    let allInEstimateText: String?
    let availableDatesText: String?
    let ourNotes: String?
    let summary: String?
    let latitude: Double?
    let longitude: Double?
    let photoURL: String?
    let customFields: JSONValue
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case name, status, address, city, state, country, website, summary, latitude, longitude
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case capacityMin = "capacity_min"
        case capacityMax = "capacity_max"
        case capacityText = "capacity_text"
        case priceNotes = "price_notes"
        case venueEstimateText = "venue_est_text"
        case allInEstimateText = "all_in_est_text"
        case availableDatesText = "available_dates_text"
        case ourNotes = "our_notes"
        case photoURL = "photo_url"
        case customFields = "custom_fields"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The editable venue estimate shared by the native and web venue surfaces.
    var canonicalVenueEstimateText: String? {
        guard let text = venueEstimateText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    var venueEstimateDisplayText: String {
        canonicalVenueEstimateText ?? "Not added"
    }
}
struct VenueDraft:Codable,Equatable,Sendable{let name:String;let status:VenueStatus?;let address:String?;let city:String?;let state:String?;let country:String?;let contactName:String?;let contactEmail:String?;let contactPhone:String?;let website:String?;let capacityMin:Int?;let capacityMax:Int?;let priceNotes:String?;let ourNotes:String?;let latitude:Double?;let longitude:Double?;let photoURL:String?;let customFields: JSONValue
init(name: String, status: VenueStatus?, address: String?, city: String?, state: String?, country: String?, contactName: String?, contactEmail: String?, contactPhone: String?, website: String?, capacityMin: Int?, capacityMax: Int?, priceNotes: String?, ourNotes: String?, latitude: Double?, longitude: Double?, photoURL: String?, customFields: JSONValue = .object([:])) { self.name=name; self.status=status; self.address=address; self.city=city; self.state=state; self.country=country; self.contactName=contactName; self.contactEmail=contactEmail; self.contactPhone=contactPhone; self.website=website; self.capacityMin=capacityMin; self.capacityMax=capacityMax; self.priceNotes=priceNotes; self.ourNotes=ourNotes; self.latitude=latitude; self.longitude=longitude; self.photoURL=photoURL; self.customFields=customFields }
enum CodingKeys:String,CodingKey{case name;case status;case address;case city;case state;case country;case contactName="contact_name";case contactEmail="contact_email";case contactPhone="contact_phone";case website;case capacityMin="capacity_min";case capacityMax="capacity_max";case priceNotes="price_notes";case ourNotes="our_notes";case latitude;case longitude;case photoURL="photo_url"; case customFields = "custom_fields"}}
/// A field omitted from `init` (default `.unchanged`) is left untouched server-side;
/// `.null` clears the column. `name` and `status` are never nullable, so they stay
/// plain optionals where `nil` means "don't touch."
struct VenuePatch: Encodable, Equatable, Sendable {
    let name: String?
    let status: VenueStatus?
    let address: NullablePatch<String>
    let city: NullablePatch<String>
    let state: NullablePatch<String>
    let country: NullablePatch<String>
    let contactName: NullablePatch<String>
    let contactEmail: NullablePatch<String>
    let contactPhone: NullablePatch<String>
    let website: NullablePatch<String>
    let capacityMin: NullablePatch<Int>
    let capacityMax: NullablePatch<Int>
    let capacityText: NullablePatch<String>
    let priceNotes: NullablePatch<String>
    let venueEstimateText: NullablePatch<String>
    let allInEstimateText: NullablePatch<String>
    let availableDatesText: NullablePatch<String>
    let ourNotes: NullablePatch<String>
    let latitude: NullablePatch<Double>
    let longitude: NullablePatch<Double>
    let photoURL: NullablePatch<String>

    init(
        name: String? = nil,
        status: VenueStatus? = nil,
        address: NullablePatch<String> = .unchanged,
        city: NullablePatch<String> = .unchanged,
        state: NullablePatch<String> = .unchanged,
        country: NullablePatch<String> = .unchanged,
        contactName: NullablePatch<String> = .unchanged,
        contactEmail: NullablePatch<String> = .unchanged,
        contactPhone: NullablePatch<String> = .unchanged,
        website: NullablePatch<String> = .unchanged,
        capacityMin: NullablePatch<Int> = .unchanged,
        capacityMax: NullablePatch<Int> = .unchanged,
        capacityText: NullablePatch<String> = .unchanged,
        priceNotes: NullablePatch<String> = .unchanged,
        venueEstimateText: NullablePatch<String> = .unchanged,
        allInEstimateText: NullablePatch<String> = .unchanged,
        availableDatesText: NullablePatch<String> = .unchanged,
        ourNotes: NullablePatch<String> = .unchanged,
        latitude: NullablePatch<Double> = .unchanged,
        longitude: NullablePatch<Double> = .unchanged,
        photoURL: NullablePatch<String> = .unchanged
    ) {
        self.name = name
        self.status = status
        self.address = address
        self.city = city
        self.state = state
        self.country = country
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.website = website
        self.capacityMin = capacityMin
        self.capacityMax = capacityMax
        self.capacityText = capacityText
        self.priceNotes = priceNotes
        self.venueEstimateText = venueEstimateText
        self.allInEstimateText = allInEstimateText
        self.availableDatesText = availableDatesText
        self.ourNotes = ourNotes
        self.latitude = latitude
        self.longitude = longitude
        self.photoURL = photoURL
    }

    var isEmpty: Bool {
        name == nil && status == nil
            && address == .unchanged && city == .unchanged
            && state == .unchanged && country == .unchanged
            && contactName == .unchanged && contactEmail == .unchanged && contactPhone == .unchanged
            && website == .unchanged
            && capacityMin == .unchanged && capacityMax == .unchanged && capacityText == .unchanged
            && priceNotes == .unchanged
            && venueEstimateText == .unchanged && allInEstimateText == .unchanged && availableDatesText == .unchanged
            && ourNotes == .unchanged
            && latitude == .unchanged && longitude == .unchanged
            && photoURL == .unchanged
    }

    enum CodingKeys: String, CodingKey {
        case name, status, address, city, state, country, website, latitude, longitude
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case capacityMin = "capacity_min"
        case capacityMax = "capacity_max"
        case capacityText = "capacity_text"
        case priceNotes = "price_notes"
        case venueEstimateText = "venue_est_text"
        case allInEstimateText = "all_in_est_text"
        case availableDatesText = "available_dates_text"
        case ourNotes = "our_notes"
        case photoURL = "photo_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(address, forKey: .address)
        try container.encode(city, forKey: .city)
        try container.encode(state, forKey: .state)
        try container.encode(country, forKey: .country)
        try container.encode(contactName, forKey: .contactName)
        try container.encode(contactEmail, forKey: .contactEmail)
        try container.encode(contactPhone, forKey: .contactPhone)
        try container.encode(website, forKey: .website)
        try container.encode(capacityMin, forKey: .capacityMin)
        try container.encode(capacityMax, forKey: .capacityMax)
        try container.encode(capacityText, forKey: .capacityText)
        try container.encode(priceNotes, forKey: .priceNotes)
        try container.encode(venueEstimateText, forKey: .venueEstimateText)
        try container.encode(allInEstimateText, forKey: .allInEstimateText)
        try container.encode(availableDatesText, forKey: .availableDatesText)
        try container.encode(ourNotes, forKey: .ourNotes)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(photoURL, forKey: .photoURL)
    }
}

extension KeyedEncodingContainer where Key == VenuePatch.CodingKeys {
    mutating func encode<T: Encodable & Equatable & Sendable>(_ patch: NullablePatch<T>, forKey key: Key) throws {
        switch patch {
        case .unchanged: break
        case let .value(value): try encode(value, forKey: key)
        case .null: try encodeNil(forKey: key)
        }
    }
}

struct VenuePhoto:Codable,Equatable,Sendable,Hashable,Identifiable{
let id:UUID;let venueID:UUID;let weddingID:UUID;let url:String;let source:String?;let caption:String?;let sortOrder:Int?;let createdAt:Date
enum CodingKeys:String,CodingKey{case id;case venueID="venue_id";case venueIDCamel="venueId";case weddingID="wedding_id";case weddingIDCamel="weddingId";case url;case source;case caption;case sortOrder="sort_order";case sortOrderCamel="sortOrder";case createdAt="created_at";case createdAtCamel="createdAt"}
init(id:UUID,venueID:UUID,weddingID:UUID,url:String,source:String?,caption:String?,sortOrder:Int?,createdAt:Date){self.id=id;self.venueID=venueID;self.weddingID=weddingID;self.url=url;self.source=source;self.caption=caption;self.sortOrder=sortOrder;self.createdAt=createdAt}
init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);id=try c.decode(UUID.self,forKey:.id);venueID=try c.decode(UUID.self,forKey:c.contains(.venueIDCamel) ? .venueIDCamel : .venueID);weddingID=try c.decode(UUID.self,forKey:c.contains(.weddingIDCamel) ? .weddingIDCamel : .weddingID);url=try c.decode(String.self,forKey:.url);source=try c.decodeIfPresent(String.self,forKey:.source);caption=try c.decodeIfPresent(String.self,forKey:.caption);sortOrder=try c.decodeIfPresent(Int.self,forKey:c.contains(.sortOrderCamel) ? .sortOrderCamel : .sortOrder);createdAt=try c.decode(Date.self,forKey:c.contains(.createdAtCamel) ? .createdAtCamel : .createdAt)}
func encode(to encoder:Encoder)throws{var c=encoder.container(keyedBy:CodingKeys.self);try c.encode(id,forKey:.id);try c.encode(venueID,forKey:.venueID);try c.encode(weddingID,forKey:.weddingID);try c.encode(url,forKey:.url);try c.encodeIfPresent(source,forKey:.source);try c.encodeIfPresent(caption,forKey:.caption);try c.encodeIfPresent(sortOrder,forKey:.sortOrder);try c.encode(createdAt,forKey:.createdAt)}}
struct VenuePhotoDraft:Codable,Equatable,Sendable{let url:String;let source:String?;let caption:String?;let sortOrder:Int?;enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}
struct VenuePhotoPatch:Codable,Equatable,Sendable{let url:String?;let source:String?;let caption:String?;let sortOrder:Int?;var isEmpty:Bool{url==nil&&source==nil&&caption==nil&&sortOrder==nil};enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}


// MARK: - Display helpers moved from ContentView.swift's split (Phase 0)
extension VenueStatus {
    var title: String {
        switch self {
        case .considering: "Considering"
        case .contacted: "Contacted"
        case .toured: "Toured"
        case .shortlisted: "Shortlisted"
        case .negotiating: "Negotiating"
        case .booked: "Booked"
        case .passed: "Passed"
        }
    }
}

enum VenueCapacityFormatter {
    static func string(minimum: Int?, maximum: Int?) -> String {
        switch (minimum, maximum) {
        case let (minimum?, maximum?): "\(minimum)–\(maximum)"
        case let (minimum?, nil): "\(minimum)+"
        case let (nil, maximum?): "Up to \(maximum)"
        case (nil, nil): "Not added"
        }
    }
}
