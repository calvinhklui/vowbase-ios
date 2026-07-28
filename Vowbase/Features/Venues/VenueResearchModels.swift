import Foundation

enum VenueResearchSource: Equatable, Sendable {
    case website(URL)
    case file(path: String)
    case text(String)
}

struct VenueResearchStartResult: Codable, Equatable, Sendable {
    let runID: UUID
    let alreadyActive: Bool

    private enum CodingKeys: String, CodingKey {
        case runID = "runId"
        case alreadyActive
    }
}

struct VenueResearchRun: Equatable, Sendable, Identifiable {
    let id: UUID
    let venueID: UUID
    let weddingID: UUID
    let sourceType: String
    let sourceURL: URL?
    let status: String
    let errorCode: String?
    let ocrUsed: Bool
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let suggestions: [VenueResearchSuggestion]
    let facts: [VenueResearchFact]
}

struct VenueResearchSuggestion: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let runID: UUID
    let fieldKey: String
    let currentValue: JSONValue?
    let suggestedValue: JSONValue?
    let confidence: Double?
    let decision: String?
    let conflictReason: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "runId"
        case fieldKey
        case currentValue
        case suggestedValue
        case confidence
        case decision
        case conflictReason
    }
}

struct VenueResearchFact: Equatable, Sendable, Identifiable {
    let id: UUID
    let runID: UUID
    let topic: String
    let content: String
    let decision: String?
    let createdAt: Date
}

struct ApplyResearchResult: Codable, Equatable, Sendable {
    let applied: Int
    let conflicts: Int
}

extension VenueResearchRun: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case venueID = "venueId"
        case weddingID = "weddingId"
        case sourceType
        case sourceURL = "sourceUrl"
        case status
        case errorCode
        case ocrUsed
        case createdAt
        case updatedAt
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        venueID = try values.decode(UUID.self, forKey: .venueID)
        weddingID = try values.decode(UUID.self, forKey: .weddingID)
        sourceType = try values.decode(String.self, forKey: .sourceType)
        sourceURL = try values.decodeIfPresent(URL.self, forKey: .sourceURL)
        status = try values.decode(String.self, forKey: .status)
        errorCode = try values.decodeIfPresent(String.self, forKey: .errorCode)
        ocrUsed = try values.decode(Bool.self, forKey: .ocrUsed)
        createdAt = try ISO8601DateDecoding.decode(values.superDecoder(forKey: .createdAt))
        updatedAt = try ISO8601DateDecoding.decode(values.superDecoder(forKey: .updatedAt))
        completedAt = try values.decodeDateIfPresent(forKey: .completedAt)
        suggestions = []
        facts = []
    }
}

extension VenueResearchFact: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "runId"
        case topic
        case content
        case decision
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        runID = try values.decode(UUID.self, forKey: .runID)
        topic = try values.decode(String.self, forKey: .topic)
        content = try values.decode(String.self, forKey: .content)
        decision = try values.decodeIfPresent(String.self, forKey: .decision)
        createdAt = try ISO8601DateDecoding.decode(values.superDecoder(forKey: .createdAt))
    }
}

private extension KeyedDecodingContainer {
    func decodeDateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        return try ISO8601DateDecoding.decode(superDecoder(forKey: key))
    }
}
