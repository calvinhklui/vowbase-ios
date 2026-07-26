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

struct GuestRPCRequest<Parameters: Encodable & Sendable>: Sendable {
    let functionName: String
    let parameters: Parameters
}

extension GuestRPCRequest: Equatable where Parameters: Equatable {}

struct RSVPUpsertParameters: Encodable, Equatable, Sendable {
    let weddingID: UUID
    let guestID: UUID
    let eventID: UUID
    let status: RSVPStatus?
    let mealChoice: String?
    let notes: String?

    init(draft: RSVPDraft) {
        weddingID = draft.weddingID
        guestID = draft.guestID
        eventID = draft.eventID
        status = draft.status
        mealChoice = draft.mealChoice
        notes = draft.notes
    }

    private enum CodingKeys: String, CodingKey {
        case weddingID = "p_wedding_id"
        case guestID = "p_guest_id"
        case eventID = "p_event_id"
        case status = "p_status"
        case mealChoice = "p_meal_choice"
        case notes = "p_notes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weddingID, forKey: .weddingID)
        try container.encode(guestID, forKey: .guestID)
        try container.encode(eventID, forKey: .eventID)
        if let status { try container.encode(status, forKey: .status) } else { try container.encodeNil(forKey: .status) }
        if let mealChoice { try container.encode(mealChoice, forKey: .mealChoice) } else { try container.encodeNil(forKey: .mealChoice) }
        if let notes { try container.encode(notes, forKey: .notes) } else { try container.encodeNil(forKey: .notes) }
    }
}

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

    func rpc<Response: Decodable & Sendable>(
        _ request: GuestRPCRequest<RSVPUpsertParameters>,
        as: Response.Type
    ) async throws -> Response
}
