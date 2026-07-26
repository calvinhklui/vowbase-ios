import Foundation

protocol InvitationRepository: Sendable {
    func preview(token: String) async throws -> InvitationPreview
    func accept(token: String) async throws -> UUID
    func invitations(weddingID: UUID) async throws -> [WeddingInvitation]
}

struct InvitationEqualityFilter: Equatable, Sendable {
    let column: String
    let value: String
}

struct InvitationOrder: Equatable, Sendable {
    let column: String
    let ascending: Bool
}

struct InvitationSelectRequest: Equatable, Sendable {
    let table: String
    let columns: String
    let equalityFilters: [InvitationEqualityFilter]
    let orders: [InvitationOrder]
    let singleRow: Bool
}

struct InvitationRPCRequest: Equatable, Sendable {
    let functionName: String
    let token: String
}

protocol InvitationDatabaseAdapter: Sendable {
    func select<Response: Decodable & Sendable>(
        _ request: InvitationSelectRequest,
        as: Response.Type
    ) async throws -> Response

    func rpc<Response: Decodable & Sendable>(
        _ request: InvitationRPCRequest,
        as: Response.Type
    ) async throws -> Response
}
