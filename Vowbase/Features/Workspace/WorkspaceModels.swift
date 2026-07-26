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
    let location: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case coupleNames = "couple_names"
        case weddingDate = "wedding_date"
        case location
    }
}

struct WeddingMembership: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let userID: UUID
    let role: WeddingRole
    let status: String
    let wedding: WeddingSummary

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case userID = "user_id"
        case role
        case status
        case wedding
    }
}

struct WeddingPatch: Codable, Equatable, Sendable {
    let name: String?
    let coupleNames: String?
    let weddingDate: String?
    let location: String?

    init(
        name: String? = nil,
        coupleNames: String? = nil,
        weddingDate: String? = nil,
        location: String? = nil
    ) {
        self.name = name
        self.coupleNames = coupleNames
        self.weddingDate = weddingDate
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case coupleNames = "couple_names"
        case weddingDate = "wedding_date"
        case location
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
