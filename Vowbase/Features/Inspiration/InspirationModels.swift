import Foundation
struct InspirationItem:Codable,Equatable,Sendable,Identifiable{let id:UUID;let weddingID:UUID;let title:String?;let imageURL:String;let sourceURL:String?;let notes:String?;let positionX:Double;let positionY:Double;let width:Double;let createdAt:Date;let updatedAt:Date
enum CodingKeys:String,CodingKey{case id;case weddingID="weddingId";case title;case imageURL="imageUrl";case sourceURL="sourceUrl";case notes;case positionX;case positionY;case width;case createdAt;case updatedAt}}
struct InspirationDraft:Codable,Equatable,Sendable{let title:String?;let imageURL:String;let sourceURL:String?;let notes:String?;let positionX:Double?;let positionY:Double?;let width:Double?;enum CodingKeys:String,CodingKey{case title;case imageURL="image_url";case sourceURL="source_url";case notes;case positionX="position_x";case positionY="position_y";case width}}
struct InspirationPatch:Codable,Equatable,Sendable{let title:String?;let imageURL:String?;let sourceURL:String?;let notes:String?;let positionX:Double?;let positionY:Double?;let width:Double?;var isEmpty:Bool{title==nil&&imageURL==nil&&sourceURL==nil&&notes==nil&&positionX==nil&&positionY==nil&&width==nil};enum CodingKeys:String,CodingKey{case title;case imageURL="image_url";case sourceURL="source_url";case notes;case positionX="position_x";case positionY="position_y";case width}}
struct MoodboardRequirement: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let importance: String
    let title: String
    let description: String?
    let position: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        weddingID: UUID,
        importance: String,
        title: String,
        description: String?,
        position: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.weddingID = weddingID
        self.importance = importance
        self.title = title
        self.description = description
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case importance
        case title
        case description
        case position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private enum DecodingKeys: String, CodingKey {
        case id, importance, title, description, position
        case weddingIDSnake = "wedding_id"
        case weddingIDCamel = "weddingId"
        case createdAtSnake = "created_at"
        case createdAtCamel = "createdAt"
        case updatedAtSnake = "updated_at"
        case updatedAtCamel = "updatedAt"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DecodingKeys.self)
        func key(_ snakeCase: DecodingKeys, or camelCase: DecodingKeys) -> DecodingKeys {
            values.contains(snakeCase) ? snakeCase : camelCase
        }
        id = try values.decode(UUID.self, forKey: .id)
        weddingID = try values.decode(UUID.self, forKey: key(.weddingIDSnake, or: .weddingIDCamel))
        importance = try values.decode(String.self, forKey: .importance)
        title = try values.decode(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        position = try values.decode(Int.self, forKey: .position)
        createdAt = try values.decode(Date.self, forKey: key(.createdAtSnake, or: .createdAtCamel))
        updatedAt = try values.decode(Date.self, forKey: key(.updatedAtSnake, or: .updatedAtCamel))
    }
}
struct MoodboardNote:Codable,Equatable,Sendable,Identifiable{let id:UUID;let weddingID:UUID;let title:String;let body:String;let positionX:Double;let positionY:Double;let width:Double;let height:Double;let createdAt:Date;let updatedAt:Date;enum CodingKeys:String,CodingKey{case id;case weddingID="weddingId";case title;case body;case positionX;case positionY;case width;case height;case createdAt;case updatedAt}}
