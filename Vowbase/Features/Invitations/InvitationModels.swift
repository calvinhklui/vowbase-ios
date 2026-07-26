import Foundation

enum InvitationRole: String, Codable, Sendable {
    case partner
    case planner
    case parent
    case viewer
}

enum InvitationStatus: String, Codable, Sendable {
    case pending
    case accepted
    case expired
    case revoked
}

struct InvitationPreview: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let weddingName: String
    let email: String?
    let role: InvitationRole
    let status: InvitationStatus
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case weddingName = "wedding_name"
        case email
        case role
        case status
        case expiresAt = "expires_at"
    }
}

struct WeddingInvitation: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let email: String?
    let role: InvitationRole
    let status: InvitationStatus
    let expiresAt: Date
    let invitedBy: UUID?
    let acceptedAt: Date?
    let createdAt: Date
    let token: String

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case email
        case role
        case status
        case expiresAt = "expires_at"
        case invitedBy = "invited_by"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
        case token
    }
}
