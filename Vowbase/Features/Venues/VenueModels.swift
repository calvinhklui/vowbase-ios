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
struct VenuePatch:Codable,Equatable,Sendable{let name:String?;let status:VenueStatus?;let location:String?;let address:String?;let city:String?;let state:String?;let country:String?;let contactName:String?;let contactEmail:String?;let contactPhone:String?;let website:String?;let capacityMin:Int?;let capacityMax:Int?;let priceEstimate:Double?;let priceNotes:String?;let ourNotes:String?;let latitude:Double?;let longitude:Double?;let photoURL:String?;let rawResearch:JSONValue?;var isEmpty:Bool{name==nil&&status==nil&&location==nil&&address==nil&&city==nil&&state==nil&&country==nil&&contactName==nil&&contactEmail==nil&&contactPhone==nil&&website==nil&&capacityMin==nil&&capacityMax==nil&&priceEstimate==nil&&priceNotes==nil&&ourNotes==nil&&latitude==nil&&longitude==nil&&photoURL==nil&&rawResearch==nil}
enum CodingKeys:String,CodingKey{case name;case status;case location;case address;case city;case state;case country;case contactName="contact_name";case contactEmail="contact_email";case contactPhone="contact_phone";case website;case capacityMin="capacity_min";case capacityMax="capacity_max";case priceEstimate="price_estimate";case priceNotes="price_notes";case ourNotes="our_notes";case latitude;case longitude;case photoURL="photo_url";case rawResearch="raw_research"}}
struct VenuePhoto:Codable,Equatable,Sendable,Identifiable{
let id:UUID;let venueID:UUID;let weddingID:UUID;let url:String;let source:String?;let caption:String?;let sortOrder:Int?;let createdAt:Date
enum CodingKeys:String,CodingKey{case id;case venueID="venue_id";case venueIDCamel="venueId";case weddingID="wedding_id";case weddingIDCamel="weddingId";case url;case source;case caption;case sortOrder="sort_order";case sortOrderCamel="sortOrder";case createdAt="created_at";case createdAtCamel="createdAt"}
init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);id=try c.decode(UUID.self,forKey:.id);venueID=try c.decode(UUID.self,forKey:c.contains(.venueIDCamel) ? .venueIDCamel : .venueID);weddingID=try c.decode(UUID.self,forKey:c.contains(.weddingIDCamel) ? .weddingIDCamel : .weddingID);url=try c.decode(String.self,forKey:.url);source=try c.decodeIfPresent(String.self,forKey:.source);caption=try c.decodeIfPresent(String.self,forKey:.caption);sortOrder=try c.decodeIfPresent(Int.self,forKey:c.contains(.sortOrderCamel) ? .sortOrderCamel : .sortOrder);createdAt=try c.decode(Date.self,forKey:c.contains(.createdAtCamel) ? .createdAtCamel : .createdAt)}
func encode(to encoder:Encoder)throws{var c=encoder.container(keyedBy:CodingKeys.self);try c.encode(id,forKey:.id);try c.encode(venueID,forKey:.venueID);try c.encode(weddingID,forKey:.weddingID);try c.encode(url,forKey:.url);try c.encodeIfPresent(source,forKey:.source);try c.encodeIfPresent(caption,forKey:.caption);try c.encodeIfPresent(sortOrder,forKey:.sortOrder);try c.encode(createdAt,forKey:.createdAt)}}
struct VenuePhotoDraft:Codable,Equatable,Sendable{let url:String;let source:String?;let caption:String?;let sortOrder:Int?;enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}
struct VenuePhotoPatch:Codable,Equatable,Sendable{let url:String?;let source:String?;let caption:String?;let sortOrder:Int?;var isEmpty:Bool{url==nil&&source==nil&&caption==nil&&sortOrder==nil};enum CodingKeys:String,CodingKey{case url;case source;case caption;case sortOrder="sort_order"}}
