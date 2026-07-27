import Foundation
import Supabase

final class SupabaseGuestRepository: GuestRepository, @unchecked Sendable {
    private static let guestColumns = "id,wedding_id,first_name,last_name,email,phone,address,custom_fields,rsvp_status,rsvp_date,origin_label,origin_latitude,origin_longitude,origin_precision,geocode_status,created_at"
    private static let customColumnColumns = "id,wedding_id,key,label,kind,options,position,hidden,created_at,updated_at"
    private static let rsvpColumns = "id,wedding_id,guest_id,event_id,status,meal_choice,notes,updated_at"
    private let database: any GuestDatabaseAdapter

    convenience init(provider: SupabaseProvider) {
        self.init(database: SupabaseGuestDatabaseAdapter(provider: provider))
    }

    init(database: any GuestDatabaseAdapter) {
        self.database = database
    }

    func guests(weddingID: UUID) async throws -> [Guest] {
        try await list(
            .init(table: "guests", columns: Self.guestColumns, equalityFilters: [scope(weddingID)], orders: [.init(column: "last_name", ascending: true), .init(column: "first_name", ascending: true)], singleRow: false),
            as: [Guest].self
        )
    }

    func createGuest(_ draft: GuestDraft, weddingID: UUID) async throws -> Guest {
        try validateCustomFields(draft.customFields)
        return try await insert(.init(table: "guests", columns: Self.guestColumns, draft: GuestCreatePayload(weddingID: weddingID, draft: draft), singleRow: true), as: Guest.self)
    }

    func updateGuest(id: UUID, patch: GuestPatch) async throws -> Guest {
        guard !patch.isEmpty else {
            throw BackendError.validation(
                message: "Guest update must include at least one field.",
                requestID: nil
            )
        }
        if let customFields = patch.customFields {
            try validateCustomFields(customFields)
        }
        return try await update(.init(table: "guests", columns: Self.guestColumns, equalityFilters: [scope(id: id)], patch: patch, singleRow: true), as: Guest.self)
    }

    func deleteGuest(id: UUID) async throws {
        try await delete(.init(table: "guests", columns: "id", equalityFilters: [scope(id: id)], singleRow: true))
    }

    func customColumns(weddingID: UUID) async throws -> [GuestCustomColumn] {
        try await list(
            .init(table: "guest_custom_columns", columns: Self.customColumnColumns, equalityFilters: [scope(weddingID)], orders: [.init(column: "position", ascending: true)], singleRow: false),
            as: [GuestCustomColumn].self
        )
    }

    func createCustomColumn(_ draft: GuestCustomColumnDraft, weddingID: UUID) async throws -> GuestCustomColumn {
        try await insert(.init(table: "guest_custom_columns", columns: Self.customColumnColumns, draft: GuestCustomColumnCreatePayload(weddingID: weddingID, draft: draft), singleRow: true), as: GuestCustomColumn.self)
    }

    func updateCustomColumn(id: UUID, patch: GuestCustomColumnPatch) async throws -> GuestCustomColumn {
        try await update(.init(table: "guest_custom_columns", columns: Self.customColumnColumns, equalityFilters: [scope(id: id)], patch: patch, singleRow: true), as: GuestCustomColumn.self)
    }

    func deleteCustomColumn(id: UUID) async throws {
        try await delete(.init(table: "guest_custom_columns", columns: "id", equalityFilters: [scope(id: id)], singleRow: true))
    }

    func rsvps(weddingID: UUID) async throws -> [RSVP] {
        try await list(
            .init(table: "rsvps", columns: Self.rsvpColumns, equalityFilters: [scope(weddingID)], orders: [.init(column: "event_id", ascending: true), .init(column: "guest_id", ascending: true)], singleRow: false),
            as: [RSVP].self
        )
    }

    func upsertRSVP(_ draft: RSVPDraft) async throws -> RSVP {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let rsvp: RSVP = try await database.rpc(
                .init(
                    functionName: "upsert_rsvp_if_planner",
                    parameters: RSVPUpsertParameters(draft: draft)
                ),
                as: RSVP.self
            )
            try Task.checkCancellation()
            return rsvp
        } catch {
            throw normalized(error)
        }
    }

    private func list<Response: Decodable & Sendable>(_ request: GuestSelectRequest, as: Response.Type) async throws -> Response {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let response = try await database.select(request, as: Response.self)
            try Task.checkCancellation()
            return response
        } catch { throw normalized(error) }
    }

    private func insert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(_ request: GuestInsertRequest<Draft>, as: Response.Type) async throws -> Response {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let response = try await database.insert(request, as: Response.self)
            try Task.checkCancellation()
            return response
        } catch { throw normalized(error) }
    }

    private func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(_ request: GuestUpdateRequest<Patch>, as: Response.Type) async throws -> Response {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let response = try await database.update(request, as: Response.self)
            try Task.checkCancellation()
            return response
        } catch { throw normalized(error) }
    }

    private func delete(_ request: GuestDeleteRequest) async throws {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let _: GuestDeletionReceipt = try await database.delete(request, as: GuestDeletionReceipt.self)
            try Task.checkCancellation()
        } catch { throw normalized(error) }
    }

    private func scope(_ weddingID: UUID) -> GuestEqualityFilter {
        .init(column: "wedding_id", value: weddingID.uuidString.lowercased())
    }

    private func scope(id: UUID) -> GuestEqualityFilter {
        .init(column: "id", value: id.uuidString.lowercased())
    }

    private func normalized(_ error: any Error) -> BackendError {
        RepositoryErrorNormalizer.normalized(error, fallbackMessage: "Guest request failed.")
    }

    private func validateCustomFields(_ value: JSONValue) throws {
        guard case .object = value else {
            throw BackendError.validation(
                message: "Custom fields must be a JSON object.",
                requestID: nil
            )
        }
    }
}

struct GuestCreatePayload: Codable, Equatable, Sendable {
    let weddingID: UUID
    let firstName: String
    let lastName: String?
    let email: String?
    let phone: String?
    let address: String?
    let customFields: JSONValue
    let rsvpStatus: RSVPStatus?
    let originLabel: String?
    let originLatitude: Double?
    let originLongitude: Double?
    let originPrecision: String?
    let geocodeStatus: String?

    init(weddingID: UUID, draft: GuestDraft) {
        self.weddingID = weddingID; firstName = draft.firstName; lastName = draft.lastName
        email = draft.email; phone = draft.phone; address = draft.address; customFields = draft.customFields
        rsvpStatus = draft.rsvpStatus; originLabel = draft.originLabel; originLatitude = draft.originLatitude
        originLongitude = draft.originLongitude; originPrecision = draft.originPrecision; geocodeStatus = draft.geocodeStatus
    }

    private enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id", firstName = "first_name", lastName = "last_name", email, phone, address
        case customFields = "custom_fields", rsvpStatus = "rsvp_status", originLabel = "origin_label"
        case originLatitude = "origin_latitude", originLongitude = "origin_longitude", originPrecision = "origin_precision", geocodeStatus = "geocode_status"
    }
}

struct GuestCustomColumnCreatePayload: Codable, Equatable, Sendable {
    let weddingID: UUID
    let key: String
    let label: String
    let kind: GuestCustomColumnKind
    let options: JSONValue
    let position: Int?
    let hidden: Bool?

    init(weddingID: UUID, draft: GuestCustomColumnDraft) {
        self.weddingID = weddingID; key = draft.key; label = draft.label; kind = draft.kind
        options = draft.options; position = draft.position; hidden = draft.hidden
    }

    private enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id", key, label, kind, options, position, hidden
    }
}

private struct GuestDeletionReceipt: Decodable, Sendable { let id: UUID }

private final class SupabaseGuestDatabaseAdapter: GuestDatabaseAdapter, @unchecked Sendable {
    private let provider: SupabaseProvider
    init(provider: SupabaseProvider) { self.provider = provider }

    func authenticatedUserID() async throws -> UUID {
        try Task.checkCancellation()
        let id = try await provider.client.auth.user().id
        try Task.checkCancellation()
        return id
    }

    func select<Response: Decodable & Sendable>(_ request: GuestSelectRequest, as: Response.Type) async throws -> Response {
        var query = provider.client.from(request.table).select(request.columns)
        for filter in request.equalityFilters { query = query.eq(filter.column, value: filter.value) }
        guard let firstOrder = request.orders.first else {
            return request.singleRow ? try await query.single().execute().value : try await query.execute().value
        }
        var ordered = query.order(firstOrder.column, ascending: firstOrder.ascending)
        for order in request.orders.dropFirst() { ordered = ordered.order(order.column, ascending: order.ascending) }
        return request.singleRow ? try await ordered.single().execute().value : try await ordered.execute().value
    }

    func insert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(_ request: GuestInsertRequest<Draft>, as: Response.Type) async throws -> Response {
        let query = try provider.client.from(request.table).insert(request.draft).select(request.columns)
        return request.singleRow ? try await query.single().execute().value : try await query.execute().value
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(_ request: GuestUpdateRequest<Patch>, as: Response.Type) async throws -> Response {
        var query = try provider.client.from(request.table).update(request.patch)
        for filter in request.equalityFilters { query = query.eq(filter.column, value: filter.value) }
        let returning = query.select(request.columns)
        return request.singleRow ? try await returning.single().execute().value : try await returning.execute().value
    }

    func delete<Response: Decodable & Sendable>(_ request: GuestDeleteRequest, as: Response.Type) async throws -> Response {
        var query = provider.client.from(request.table).delete()
        for filter in request.equalityFilters { query = query.eq(filter.column, value: filter.value) }
        let returning = query.select(request.columns)
        return request.singleRow ? try await returning.single().execute().value : try await returning.execute().value
    }

    func rpc<Response: Decodable & Sendable>(_ request: GuestRPCRequest<RSVPUpsertParameters>, as: Response.Type) async throws -> Response {
        try await provider.client
            .rpc(request.functionName, params: request.parameters)
            .execute()
            .value
    }
}
