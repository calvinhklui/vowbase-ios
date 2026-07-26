import Foundation

struct Profile: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarURL = "avatar_url"
    }
}

/// Mutable profile presentation fields. The profile identifier and email remain auth-owned.
struct ProfilePatch: Codable, Equatable, Sendable {
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let avatarURL: String?

    init(
        fullName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        avatarURL: String? = nil
    ) {
        self.fullName = fullName
        self.firstName = firstName
        self.lastName = lastName
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarURL = "avatar_url"
    }
}
