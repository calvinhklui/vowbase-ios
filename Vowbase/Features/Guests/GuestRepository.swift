import Foundation

protocol GuestRepository: Sendable {
    func guests(weddingID: UUID) async throws -> [Guest]
    func createGuest(_ draft: GuestDraft, weddingID: UUID) async throws -> Guest
    func updateGuest(id: UUID, patch: GuestPatch) async throws -> Guest
    func deleteGuest(id: UUID) async throws
    func customColumns(weddingID: UUID) async throws -> [GuestCustomColumn]
    func createCustomColumn(_ draft: GuestCustomColumnDraft, weddingID: UUID) async throws -> GuestCustomColumn
    func updateCustomColumn(id: UUID, patch: GuestCustomColumnPatch) async throws -> GuestCustomColumn
    func deleteCustomColumn(id: UUID) async throws
    func rsvps(weddingID: UUID) async throws -> [RSVP]
    func upsertRSVP(_ draft: RSVPDraft) async throws -> RSVP
}

struct GuestEqualityFilter: Equatable, Sendable {
    let column: String
    let value: String
}

struct GuestOrder: Equatable, Sendable {
    let column: String
    let ascending: Bool
}

struct GuestSelectRequest: Equatable, Sendable {
    let table: String
    let columns: String
    let equalityFilters: [GuestEqualityFilter]
    let orders: [GuestOrder]
    let singleRow: Bool
}

struct GuestInsertRequest<Draft: Encodable & Sendable>: Sendable {
    let table: String
    let columns: String
    let draft: Draft
    let singleRow: Bool
}

extension GuestInsertRequest: Equatable where Draft: Equatable {}

struct GuestUpdateRequest<Patch: Encodable & Sendable>: Sendable {
    let table: String
    let columns: String
    let equalityFilters: [GuestEqualityFilter]
    let patch: Patch
    let singleRow: Bool
}

extension GuestUpdateRequest: Equatable where Patch: Equatable {}

struct GuestDeleteRequest: Equatable, Sendable {
    let table: String
    let columns: String
    let equalityFilters: [GuestEqualityFilter]
    let singleRow: Bool
}

struct GuestUpsertRequest<Draft: Encodable & Sendable>: Sendable {
    let table: String
    let columns: String
    let draft: Draft
    let onConflict: String
    let singleRow: Bool
}

extension GuestUpsertRequest: Equatable where Draft: Equatable {}

protocol GuestDatabaseAdapter: Sendable {
    func authenticatedUserID() async throws -> UUID

    func select<Response: Decodable & Sendable>(
        _ request: GuestSelectRequest,
        as: Response.Type
    ) async throws -> Response

    func insert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(
        _ request: GuestInsertRequest<Draft>,
        as: Response.Type
    ) async throws -> Response

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: GuestUpdateRequest<Patch>,
        as: Response.Type
    ) async throws -> Response

    func delete<Response: Decodable & Sendable>(
        _ request: GuestDeleteRequest,
        as: Response.Type
    ) async throws -> Response

    func upsert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(
        _ request: GuestUpsertRequest<Draft>,
        as: Response.Type
    ) async throws -> Response
}
