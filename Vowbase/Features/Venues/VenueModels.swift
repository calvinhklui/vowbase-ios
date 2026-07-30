import Foundation
enum VenueStatus: String, Codable, Equatable, Sendable { case suggested, considering, contacted, toured, shortlisted, negotiating, booked, passed }
struct Venue: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let name: String
    let status: VenueStatus
    let location: String?
    let locationText: String?
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
    let priceEstimate: Double?
    let priceNotes: String?
    let venueEstimateText: String?
    let allInEstimateText: String?
    let availableDatesText: String?
    let ourNotes: String?
    let summary: String?
    let latitude: Double?
    let longitude: Double?
    let photoURL: String?
    let rawResearch: JSONValue?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case name, status, location, address, city, state, country, website, summary, latitude, longitude
        case locationText = "location_text"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case capacityMin = "capacity_min"
        case capacityMax = "capacity_max"
        case capacityText = "capacity_text"
        case priceEstimate = "price_estimate"
        case priceNotes = "price_notes"
        case venueEstimateText = "venue_est_text"
        case allInEstimateText = "all_in_est_text"
        case availableDatesText = "available_dates_text"
        case ourNotes = "our_notes"
        case photoURL = "photo_url"
        case rawResearch = "raw_research"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
struct VenueDraft:Codable,Equatable,Sendable{let name:String;let status:VenueStatus?;let location:String?;let address:String?;let city:String?;let state:String?;let country:String?;let contactName:String?;let contactEmail:String?;let contactPhone:String?;let website:String?;let capacityMin:Int?;let capacityMax:Int?;let priceEstimate:Double?;let priceNotes:String?;let ourNotes:String?;let latitude:Double?;let longitude:Double?;let photoURL:String?
enum CodingKeys:String,CodingKey{case name;case status;case location;case address;case city;case state;case country;case contactName="contact_name";case contactEmail="contact_email";case contactPhone="contact_phone";case website;case capacityMin="capacity_min";case capacityMax="capacity_max";case priceEstimate="price_estimate";case priceNotes="price_notes";case ourNotes="our_notes";case latitude;case longitude;case photoURL="photo_url"}}
/// A field omitted from `init` (default `.unchanged`) is left untouched server-side;
/// `.null` clears the column. `name` and `status` are never nullable, so they stay
/// plain optionals where `nil` means "don't touch."
struct VenuePatch: Encodable, Equatable, Sendable {
    let name: String?
    let status: VenueStatus?
    let location: NullablePatch<String>
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
    let priceEstimate: NullablePatch<Double>
    let priceNotes: NullablePatch<String>
    let venueEstimateText: NullablePatch<String>
    let allInEstimateText: NullablePatch<String>
    let availableDatesText: NullablePatch<String>
    let ourNotes: NullablePatch<String>
    let latitude: NullablePatch<Double>
    let longitude: NullablePatch<Double>
    let photoURL: NullablePatch<String>
    let rawResearch: JSONValue?

    init(
        name: String? = nil,
        status: VenueStatus? = nil,
        location: NullablePatch<String> = .unchanged,
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
        priceEstimate: NullablePatch<Double> = .unchanged,
        priceNotes: NullablePatch<String> = .unchanged,
        venueEstimateText: NullablePatch<String> = .unchanged,
        allInEstimateText: NullablePatch<String> = .unchanged,
        availableDatesText: NullablePatch<String> = .unchanged,
        ourNotes: NullablePatch<String> = .unchanged,
        latitude: NullablePatch<Double> = .unchanged,
        longitude: NullablePatch<Double> = .unchanged,
        photoURL: NullablePatch<String> = .unchanged,
        rawResearch: JSONValue? = nil
    ) {
        self.name = name
        self.status = status
        self.location = location
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
        self.priceEstimate = priceEstimate
        self.priceNotes = priceNotes
        self.venueEstimateText = venueEstimateText
        self.allInEstimateText = allInEstimateText
        self.availableDatesText = availableDatesText
        self.ourNotes = ourNotes
        self.latitude = latitude
        self.longitude = longitude
        self.photoURL = photoURL
        self.rawResearch = rawResearch
    }

    var isEmpty: Bool {
        name == nil && status == nil
            && location == .unchanged && address == .unchanged && city == .unchanged
            && state == .unchanged && country == .unchanged
            && contactName == .unchanged && contactEmail == .unchanged && contactPhone == .unchanged
            && website == .unchanged
            && capacityMin == .unchanged && capacityMax == .unchanged && capacityText == .unchanged
            && priceEstimate == .unchanged && priceNotes == .unchanged
            && venueEstimateText == .unchanged && allInEstimateText == .unchanged && availableDatesText == .unchanged
            && ourNotes == .unchanged
            && latitude == .unchanged && longitude == .unchanged
            && photoURL == .unchanged
            && rawResearch == nil
    }

    enum CodingKeys: String, CodingKey {
        case name, status, location, address, city, state, country, website, latitude, longitude
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case capacityMin = "capacity_min"
        case capacityMax = "capacity_max"
        case capacityText = "capacity_text"
        case priceEstimate = "price_estimate"
        case priceNotes = "price_notes"
        case venueEstimateText = "venue_est_text"
        case allInEstimateText = "all_in_est_text"
        case availableDatesText = "available_dates_text"
        case ourNotes = "our_notes"
        case photoURL = "photo_url"
        case rawResearch = "raw_research"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(location, forKey: .location)
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
        try container.encode(priceEstimate, forKey: .priceEstimate)
        try container.encode(priceNotes, forKey: .priceNotes)
        try container.encode(venueEstimateText, forKey: .venueEstimateText)
        try container.encode(allInEstimateText, forKey: .allInEstimateText)
        try container.encode(availableDatesText, forKey: .availableDatesText)
        try container.encode(ourNotes, forKey: .ourNotes)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(rawResearch, forKey: .rawResearch)
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
init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);id=try c.decode(UUID.self,forKey:.id);venueID=try c.decode(UUID.self,forKey:c.contains(.venueIDCamel) ? .venueIDCamel : .venueID);weddingID=try c.decode(UUID.self,forKey:c.contains(.weddingIDCamel) ? .weddingIDCamel : .weddingID);url=try c.decode(String.self,forKey:.url);source=try c.decodeIfPresent(String.self,forKey:.source);caption=try c.decodeIfPresent(String.self,forKey:.caption);sortOrder=try c.decodeIfPresent(Int.self,forKey:c.contains(.sortOrderCamel) ? .sortOrderCamel : .sortOrder);createdAt=try c.decode(Date.self,forKey:c.contains(.createdAtCamel) ? .createdAtCamel : .createdAt)}
func encode(to encoder:Encoder)throws{var c=encoder.container(keyedBy:CodingKeys.self);try c.encode(id,forKey:.id);try c.encode(venueID,forKey:.venueID);try c.encode(weddingID,forKey:.weddingID);try c.encode(url,forKey:.url);try c.encodeIfPresent(source,forKey:.source);try c.encodeIfPresent(caption,forKey:.caption);try c.encodeIfPresent(sortOrder,forKey:.sortOrder);try c.encode(createdAt,forKey:.createdAt)}}
struct VenuePhotoDraft:Codable,Equatable,Sendable{let url:String;let source:String?;let caption:String?;let sortOrder:Int?;enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}
struct VenuePhotoPatch:Codable,Equatable,Sendable{let url:String?;let source:String?;let caption:String?;let sortOrder:Int?;var isEmpty:Bool{url==nil&&source==nil&&caption==nil&&sortOrder==nil};enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}


// MARK: - Display helpers moved from ContentView.swift's split (Phase 0)
extension VenueStatus: Hashable {}

extension VenueStatus {
    var title: String {
        switch self {
        case .suggested: "Suggested"
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

enum VenuePriceFormatter {
    static func string(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
