import Foundation

protocol WorkspaceRepository: Sendable {
    func memberships() async throws -> [WeddingMembership]
    func wedding(id: UUID) async throws -> WeddingSummary
    func updateWedding(id: UUID, patch: WeddingPatch) async throws -> WeddingSummary
    func sessionSummary() async throws -> SessionSummary
}

struct WorkspaceEqualityFilter: Equatable, Sendable {
    let column: String
    let value: String
}

struct WorkspaceSelectRequest: Equatable, Sendable {
    let table: String
    let columns: String
    let equalityFilters: [WorkspaceEqualityFilter]
    let singleRow: Bool
}

struct WorkspaceUpdateRequest<Patch: Encodable & Sendable>: Sendable {
    let table: String
    let columns: String
    let equalityFilters: [WorkspaceEqualityFilter]
    let singleRow: Bool
    let patch: Patch
}

extension WorkspaceUpdateRequest: Equatable where Patch: Equatable {}

protocol WorkspaceDatabaseAdapter: Sendable {
    func authenticatedUserID() async throws -> UUID

    func select<Response: Decodable & Sendable>(
        _ request: WorkspaceSelectRequest,
        as: Response.Type
    ) async throws -> Response

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: WorkspaceUpdateRequest<Patch>,
        as: Response.Type
    ) async throws -> Response
}
