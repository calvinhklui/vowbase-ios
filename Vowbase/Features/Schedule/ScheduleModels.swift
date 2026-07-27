import Foundation

enum EventType: String, Codable, Equatable, Sendable { case ceremony, reception, rehearsal, brunch, other }
enum EventVisibility: String, Codable, Equatable, Sendable { case allGuests = "all_guests", weddingParty = "wedding_party", privateEvent = "private" }
enum DayOfStatus: String, Codable, Equatable, Sendable { case planned, inProgress = "in_progress", complete, skipped }

struct WeddingEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID; let weddingID: UUID; let name: String; let eventType: EventType?; let date: String?; let startTime: String?; let endTime: String?; let location: String?; let description: String?; let visibility: EventVisibility?; let createdAt: Date
    enum CodingKeys: String, CodingKey { case id; case weddingID = "wedding_id"; case name; case eventType = "event_type"; case date; case startTime = "start_time"; case endTime = "end_time"; case location; case description; case visibility; case createdAt = "created_at" }
}
struct EventDraft: Codable, Equatable, Sendable { let name: String; let eventType: EventType?; let date: String?; let startTime: String?; let endTime: String?; let location: String?; let description: String?; let visibility: EventVisibility?
    init(name: String, eventType: EventType? = nil, date: String? = nil, startTime: String? = nil, endTime: String? = nil, location: String? = nil, description: String? = nil, visibility: EventVisibility? = nil) { self.name = name; self.eventType = eventType; self.date = date; self.startTime = startTime; self.endTime = endTime; self.location = location; self.description = description; self.visibility = visibility }
    enum CodingKeys: String, CodingKey { case name; case eventType = "event_type"; case date; case startTime = "start_time"; case endTime = "end_time"; case location; case description; case visibility }
}
struct EventPatch: Encodable, Equatable, Sendable { let name: String?; let eventType: NullablePatch<EventType>; let date: NullablePatch<String>; let startTime: NullablePatch<String>; let endTime: NullablePatch<String>; let location: NullablePatch<String>; let description: NullablePatch<String>; let visibility: NullablePatch<EventVisibility>
    init(name: String? = nil, eventType: NullablePatch<EventType> = .unchanged, date: NullablePatch<String> = .unchanged, startTime: NullablePatch<String> = .unchanged, endTime: NullablePatch<String> = .unchanged, location: NullablePatch<String> = .unchanged, description: NullablePatch<String> = .unchanged, visibility: NullablePatch<EventVisibility> = .unchanged) { self.name=name; self.eventType=eventType; self.date=date; self.startTime=startTime; self.endTime=endTime; self.location=location; self.description=description; self.visibility=visibility }
    var isEmpty: Bool { name == nil && eventType == .unchanged && date == .unchanged && startTime == .unchanged && endTime == .unchanged && location == .unchanged && description == .unchanged && visibility == .unchanged }
    enum CodingKeys: String, CodingKey { case name; case eventType="event_type"; case date; case startTime="start_time"; case endTime="end_time"; case location; case description; case visibility }
    func encode(to e: Encoder) throws { var c=e.container(keyedBy:CodingKeys.self); try c.encodeIfPresent(name,forKey:.name); try c.encode(eventType,forKey:.eventType); try c.encode(date,forKey:.date); try c.encode(startTime,forKey:.startTime); try c.encode(endTime,forKey:.endTime); try c.encode(location,forKey:.location); try c.encode(description,forKey:.description); try c.encode(visibility,forKey:.visibility) }
}
extension KeyedEncodingContainer where Key == EventPatch.CodingKeys { mutating func encode<T: Encodable & Equatable & Sendable>(_ p: NullablePatch<T>, forKey key: Key) throws { switch p { case .unchanged: break; case .value(let v): try encode(v,forKey:key); case .null: try encodeNil(forKey:key) } } }

struct DayOfItem: Codable, Equatable, Sendable, Identifiable { let id: UUID; let weddingID: UUID; let time: String?; let title: String; let description: String?; let owner: String?; let location: String?; let relatedVendorID: UUID?; let status: DayOfStatus?; let createdAt: Date
    enum CodingKeys: String, CodingKey { case id; case weddingID="wedding_id"; case time; case title; case description; case owner; case location; case relatedVendorID="related_vendor_id"; case status; case createdAt="created_at" } }
struct DayOfItemDraft: Codable, Equatable, Sendable { let time: String?; let title: String; let description: String?; let owner: String?; let location: String?; let relatedVendorID: UUID?; let status: DayOfStatus?
    enum CodingKeys: String, CodingKey { case time; case title; case description; case owner; case location; case relatedVendorID="related_vendor_id"; case status } }
struct DayOfItemPatch: Codable, Equatable, Sendable { let time: String?; let title: String?; let description: String?; let owner: String?; let location: String?; let relatedVendorID: UUID?; let status: DayOfStatus?
    var isEmpty: Bool { time == nil && title == nil && description == nil && owner == nil && location == nil && relatedVendorID == nil && status == nil }
    enum CodingKeys: String, CodingKey { case time; case title; case description; case owner; case location; case relatedVendorID="related_vendor_id"; case status } }
