import Foundation

protocol ProfileRepository: Sendable {
    func currentProfile() async throws -> Profile
    func updateCurrentProfile(_ patch: ProfilePatch) async throws -> Profile
}

struct ProfileEqualityFilter: Equatable, Sendable {
    let column: String
    let value: String
}

struct ProfileSelectRequest: Equatable, Sendable {
    let table: String
    let columns: String
    let equalityFilters: [ProfileEqualityFilter]
    let singleRow: Bool
}

struct ProfileUpdateRequest<Patch: Encodable & Sendable>: Sendable {
    let table: String
    let columns: String
    let equalityFilters: [ProfileEqualityFilter]
    let singleRow: Bool
    let patch: Patch
}

extension ProfileUpdateRequest: Equatable where Patch: Equatable {}

protocol ProfileDatabaseAdapter: Sendable {
    func authenticatedUserID() async throws -> UUID

    func select<Response: Decodable & Sendable>(
        _ request: ProfileSelectRequest,
        as: Response.Type
    ) async throws -> Response

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: ProfileUpdateRequest<Patch>,
        as: Response.Type
    ) async throws -> Response
}
