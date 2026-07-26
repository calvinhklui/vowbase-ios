import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Guest, custom-column, and RSVP repositories")
struct GuestRepositoryTests {
    private let userID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789c")!
    private let weddingID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789b")!
    private let guestID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789d")!
    private let eventID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789e")!
    private let columnID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789f")!

    @Test("final schema models preserve nullable contact fields, JSON custom fields, and enum values")
    func decodesFinalSchemaShapes() throws {
        let guest = try GuestTestDecoding.decoder.decode(Guest.self, from: guestData)
        let column = try GuestTestDecoding.decoder.decode(GuestCustomColumn.self, from: columnData)
        let rsvp = try GuestTestDecoding.decoder.decode(RSVP.self, from: rsvpData)

        #expect(guest.lastName == nil)
        #expect(guest.email == nil)
        #expect(guest.customFields == .object(["party_size": .number(2), "needs_car": .bool(true)]))
        #expect(guest.rsvpStatus == .notInvited)
        #expect(column.kind == .select)
        #expect(column.options == .array([.string("Family"), .string("Friends")]))
        #expect(rsvp.status == .pending)
        #expect(rsvp.mealChoice == nil)
    }

    @Test("every list operation authenticates and scopes itself to the supplied wedding")
    func listsUseWeddingScope() async throws {
        let database = GuestDatabaseSpy(
            authenticatedUserID: userID,
            guestData: guestData,
            columnData: columnData,
            rsvpData: rsvpData
        )
        let repository = SupabaseGuestRepository(database: database)

        _ = try await repository.guests(weddingID: weddingID)
        _ = try await repository.customColumns(weddingID: weddingID)
        _ = try await repository.rsvps(weddingID: weddingID)

        let scope = [GuestEqualityFilter(column: "wedding_id", value: weddingID.uuidString.lowercased())]
        #expect(await database.selectRequests == [
            .init(table: "guests", columns: GuestColumns.guests, equalityFilters: scope, orders: [
                .init(column: "last_name", ascending: true), .init(column: "first_name", ascending: true),
            ], singleRow: false),
            .init(table: "guest_custom_columns", columns: GuestColumns.customColumns, equalityFilters: scope, orders: [
                .init(column: "position", ascending: true),
            ], singleRow: false),
            .init(table: "rsvps", columns: GuestColumns.rsvps, equalityFilters: scope, orders: [
                .init(column: "event_id", ascending: true), .init(column: "guest_id", ascending: true),
            ], singleRow: false),
        ])
        #expect(await database.authenticatedUserIDCallCount == 3)
    }

    @Test("all writes request returned rows and destructive operations remain identifier-scoped")
    func writesSelectReturnedRowsAndStayScoped() async throws {
        let database = GuestDatabaseSpy(
            authenticatedUserID: userID,
            guestData: guestData,
            columnData: columnData,
            rsvpData: rsvpData,
            deletionData: Data("{\"id\":\"\(guestID.uuidString)\"}".utf8)
        )
        let repository = SupabaseGuestRepository(database: database)
        let guestDraft = GuestDraft(firstName: "Avery", customFields: .object(["party_size": .number(2)]))
        let columnDraft = GuestCustomColumnDraft(key: "relationship", label: "Relationship", kind: .text)
        let rsvpDraft = RSVPDraft(weddingID: weddingID, guestID: guestID, eventID: eventID, status: .accepted)

        _ = try await repository.createGuest(guestDraft, weddingID: weddingID)
        _ = try await repository.updateGuest(id: guestID, patch: GuestPatch(email: "avery@example.com"))
        try await repository.deleteGuest(id: guestID)
        _ = try await repository.createCustomColumn(columnDraft, weddingID: weddingID)
        _ = try await repository.updateCustomColumn(id: columnID, patch: .init(hidden: true))
        try await repository.deleteCustomColumn(id: columnID)
        _ = try await repository.upsertRSVP(rsvpDraft)

        #expect(await database.insertRecords.map(\.table) == ["guests", "guest_custom_columns"])
        #expect(await database.insertRecords.map(\.columns) == [GuestColumns.guests, GuestColumns.customColumns])
        #expect(await database.updateRecords.map(\.table) == ["guests", "guest_custom_columns"])
        #expect(await database.updateRecords.allSatisfy { $0.columns != "" && $0.singleRow })
        #expect(await database.deleteRequests == [
            .init(table: "guests", columns: "id", equalityFilters: [.init(column: "id", value: guestID.uuidString.lowercased())], singleRow: true),
            .init(table: "guest_custom_columns", columns: "id", equalityFilters: [.init(column: "id", value: columnID.uuidString.lowercased())], singleRow: true),
        ])
        #expect(await database.upsertRecords == [
            .init(table: "rsvps", columns: GuestColumns.rsvps, onConflict: "guest_id,event_id", singleRow: true),
        ])
        #expect(UUID(uuidString: await database.insertPayloads[0]["wedding_id"] as? String ?? "") == weddingID)
        #expect(UUID(uuidString: await database.insertPayloads[1]["wedding_id"] as? String ?? "") == weddingID)
        #expect(UUID(uuidString: await database.upsertPayloads[0]["wedding_id"] as? String ?? "") == weddingID)
    }

    @Test("signed-out calls fail before all table access")
    func authPreflightStopsEachOperation() async throws {
        let database = GuestDatabaseSpy(
            authenticatedUserID: userID,
            authenticatedUserIDError: AuthError.sessionMissing
        )
        let repository = SupabaseGuestRepository(database: database)

        await #expect(throws: BackendError.authenticationRequired(message: nil, requestID: nil)) {
            _ = try await repository.guests(weddingID: weddingID)
        }
        await #expect(throws: BackendError.authenticationRequired(message: nil, requestID: nil)) {
            _ = try await repository.createGuest(.init(firstName: "No session"), weddingID: weddingID)
        }
        #expect(await database.selectRequests.isEmpty)
        #expect(await database.insertRecords.isEmpty)
    }

    @Test("unit role simulation labels adapter denials rather than claiming hosted RLS coverage")
    func simulatedRLSWriteDenialsNormalizeSafely() async throws {
        for role in [WeddingRole.parent, .viewer] {
            let database = GuestDatabaseSpy(
                authenticatedUserID: userID,
                upsertError: PostgrestError(code: "42501", message: "permission denied")
            )
            await #expect(
                throws: BackendError.forbidden(message: "Forbidden.", requestID: nil),
                "simulated \(role.rawValue) RLS denial"
            ) {
                _ = try await SupabaseGuestRepository(database: database).upsertRSVP(
                    .init(weddingID: weddingID, guestID: guestID, eventID: eventID)
                )
            }
        }
    }

    private var guestData: Data {
        Data("""
        {"id":"\(guestID.uuidString)","wedding_id":"\(weddingID.uuidString)","first_name":"Avery","last_name":null,"email":null,"phone":null,"address":null,"custom_fields":{"party_size":2,"needs_car":true},"rsvp_status":"not_invited","rsvp_date":null,"origin_label":null,"origin_latitude":null,"origin_longitude":null,"origin_precision":null,"geocode_status":null,"created_at":"2026-07-25T12:00:00Z"}
        """.utf8)
    }

    private var columnData: Data {
        Data("""
        {"id":"\(columnID.uuidString)","wedding_id":"\(weddingID.uuidString)","key":"group","label":"Group","kind":"select","options":["Family","Friends"],"position":1,"hidden":false,"created_at":"2026-07-25T12:00:00Z","updated_at":"2026-07-25T12:00:00Z"}
        """.utf8)
    }

    private var rsvpData: Data {
        Data("""
        {"id":"01908f9d-2265-789a-bcde-f0123456789a","wedding_id":"\(weddingID.uuidString)","guest_id":"\(guestID.uuidString)","event_id":"\(eventID.uuidString)","status":"pending","meal_choice":null,"notes":null,"updated_at":"2026-07-25T12:00:00Z"}
        """.utf8)
    }
}

private enum GuestColumns {
    static let guests = "id,wedding_id,first_name,last_name,email,phone,address,custom_fields,rsvp_status,rsvp_date,origin_label,origin_latitude,origin_longitude,origin_precision,geocode_status,created_at"
    static let customColumns = "id,wedding_id,key,label,kind,options,position,hidden,created_at,updated_at"
    static let rsvps = "id,wedding_id,guest_id,event_id,status,meal_choice,notes,updated_at"
}

private enum GuestTestDecoding {
    static var decoder: JSONDecoder {
        let decoder = DatabaseDecoding.makeDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}

private struct GuestMutationRecord: Equatable, Sendable {
    let table: String
    let columns: String
    let singleRow: Bool
}

private struct GuestUpsertRecord: Equatable, Sendable {
    let table: String
    let columns: String
    let onConflict: String
    let singleRow: Bool
}

private actor GuestDatabaseSpy: GuestDatabaseAdapter {
    let userID: UUID
    let authenticatedUserIDError: (any Error)?
    let guestData: Data?
    let columnData: Data?
    let rsvpData: Data?
    let deletionData: Data?
    let upsertError: (any Error)?
    private(set) var authenticatedUserIDCallCount = 0
    private(set) var selectRequests = [GuestSelectRequest]()
    private(set) var insertRecords = [GuestMutationRecord]()
    private(set) var updateRecords = [GuestMutationRecord]()
    private(set) var deleteRequests = [GuestDeleteRequest]()
    private(set) var upsertRecords = [GuestUpsertRecord]()
    private(set) var insertPayloads = [[String: Any]]()
    private(set) var upsertPayloads = [[String: Any]]()

    init(
        authenticatedUserID: UUID,
        authenticatedUserIDError: (any Error)? = nil,
        guestData: Data? = nil,
        columnData: Data? = nil,
        rsvpData: Data? = nil,
        deletionData: Data? = nil,
        upsertError: (any Error)? = nil
    ) {
        self.userID = authenticatedUserID
        self.authenticatedUserIDError = authenticatedUserIDError
        self.guestData = guestData
        self.columnData = columnData
        self.rsvpData = rsvpData
        self.deletionData = deletionData
        self.upsertError = upsertError
    }

    func authenticatedUserID() throws -> UUID {
        authenticatedUserIDCallCount += 1
        if let authenticatedUserIDError { throw authenticatedUserIDError }
        return userID
    }

    func select<Response: Decodable & Sendable>(_ request: GuestSelectRequest, as: Response.Type) throws -> Response {
        selectRequests.append(request)
        return try decode(for: Response.self, list: true)
    }

    func insert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(_ request: GuestInsertRequest<Draft>, as: Response.Type) throws -> Response {
        insertRecords.append(.init(table: request.table, columns: request.columns, singleRow: request.singleRow))
        insertPayloads.append(try object(from: request.draft))
        return try decode(for: Response.self, list: false)
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(_ request: GuestUpdateRequest<Patch>, as: Response.Type) throws -> Response {
        updateRecords.append(.init(table: request.table, columns: request.columns, singleRow: request.singleRow))
        return try decode(for: Response.self, list: false)
    }

    func delete<Response: Decodable & Sendable>(_ request: GuestDeleteRequest, as: Response.Type) throws -> Response {
        deleteRequests.append(request)
        guard let deletionData else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing deletion data")) }
        return try GuestTestDecoding.decoder.decode(Response.self, from: deletionData)
    }

    func upsert<Response: Decodable & Sendable, Draft: Encodable & Sendable>(_ request: GuestUpsertRequest<Draft>, as: Response.Type) throws -> Response {
        upsertRecords.append(.init(table: request.table, columns: request.columns, onConflict: request.onConflict, singleRow: request.singleRow))
        upsertPayloads.append(try object(from: request.draft))
        if let upsertError { throw upsertError }
        return try decode(for: Response.self, list: false)
    }

    private func decode<Response: Decodable & Sendable>(for type: Response.Type, list: Bool) throws -> Response {
        let data: Data
        switch Response.self {
        case is Guest.Type, is [Guest].Type: data = try required(guestData)
        case is GuestCustomColumn.Type, is [GuestCustomColumn].Type: data = try required(columnData)
        case is RSVP.Type, is [RSVP].Type: data = try required(rsvpData)
        default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected response type"))
        }
        if list {
            let arrayData = Data("[".utf8) + data + Data("]".utf8)
            return try GuestTestDecoding.decoder.decode(Response.self, from: arrayData)
        }
        return try GuestTestDecoding.decoder.decode(Response.self, from: data)
    }

    private func required(_ data: Data?) throws -> Data {
        guard let data else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing test response")) }
        return data
    }

    private func object(from value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}

@Suite("Guest repository hosted RLS integration", .serialized)
struct GuestRepositoryIntegrationTests {
    @Test("dedicated non-production roles deny parent/viewer writes and allow an exact safe RSVP upsert", .enabled(if: ProcessInfo.processInfo.environment["VOWBASE_GUEST_INTEGRATION_ENABLED"] == "1"))
    func dedicatedNonProductionRoleMatrix() async throws {
        let configuration = try GuestIntegrationConfiguration.load()
        let owner = try await repository(for: .owner, configuration: configuration)
        let existing = try #require(try await owner.rsvps(weddingID: configuration.weddingID).first {
            $0.guestID == configuration.guestID && $0.eventID == configuration.eventID
        })
        let safeDraft = RSVPDraft(weddingID: existing.weddingID, guestID: existing.guestID, eventID: existing.eventID, status: existing.status, mealChoice: existing.mealChoice, notes: existing.notes)
        #expect(try await owner.upsertRSVP(safeDraft) == existing)
        for role in [GuestIntegrationRole.parent, .viewer] {
            let repository = try await repository(for: role, configuration: configuration)
            await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil), "hosted (role.rawValue) denial") {
                _ = try await repository.upsertRSVP(safeDraft)
            }
        }
    }

    private func repository(for role: GuestIntegrationRole, configuration: GuestIntegrationConfiguration) async throws -> SupabaseGuestRepository {
        let provider = SupabaseProvider(configuration: configuration.appConfiguration)
        let credentials = configuration.credentials(for: role)
        _ = try await provider.client.auth.setSession(accessToken: credentials.accessToken, refreshToken: credentials.refreshToken)
        return SupabaseGuestRepository(provider: provider)
    }
}

private enum GuestIntegrationRole: String, CaseIterable { case owner, parent, viewer }
private struct GuestIntegrationCredentials { let accessToken: String; let refreshToken: String }
private struct GuestIntegrationConfiguration {
    let appConfiguration: AppConfiguration
    let weddingID: UUID
    let guestID: UUID
    let eventID: UUID
    private let credentialsByRole: [GuestIntegrationRole: GuestIntegrationCredentials]

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        func required(_ key: String) throws -> String {
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { throw GuestIntegrationConfigurationError.missing(key) }
            return value
        }
        func uuid(_ key: String) throws -> UUID {
            guard let value = UUID(uuidString: try required(key)) else { throw GuestIntegrationConfigurationError.invalid(key) }
            return value
        }
        guard ["test", "staging"].contains(try required("VOWBASE_GUEST_INTEGRATION_ENVIRONMENT").lowercased()) else { throw GuestIntegrationConfigurationError.invalid("VOWBASE_GUEST_INTEGRATION_ENVIRONMENT") }
        let supabaseURL = try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_URL")
        let productionURL = try required("VOWBASE_PRODUCTION_SUPABASE_URL")
        guard supabaseURL.lowercased() != productionURL.lowercased() else { throw GuestIntegrationConfigurationError.productionTarget }
        let roles = try Dictionary(uniqueKeysWithValues: GuestIntegrationRole.allCases.map { role in
            let prefix = "VOWBASE_GUEST_INTEGRATION_\(role.rawValue.uppercased())"
            return (role, GuestIntegrationCredentials(accessToken: try required("\(prefix)_ACCESS_TOKEN"), refreshToken: try required("\(prefix)_REFRESH_TOKEN")))
        })
        return .init(
            appConfiguration: try AppConfiguration(values: ["CONFIGURATION": "Debug", "SUPABASE_URL": supabaseURL, "SUPABASE_PUBLISHABLE_KEY": try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_PUBLISHABLE_KEY"), "VOWBASE_API_URL": try required("VOWBASE_GUEST_INTEGRATION_API_URL")], transportPolicy: .debug),
            weddingID: try uuid("VOWBASE_GUEST_INTEGRATION_WEDDING_ID"),
            guestID: try uuid("VOWBASE_GUEST_INTEGRATION_SAFE_GUEST_ID"),
            eventID: try uuid("VOWBASE_GUEST_INTEGRATION_SAFE_EVENT_ID"),
            credentialsByRole: roles
        )
    }

    func credentials(for role: GuestIntegrationRole) -> GuestIntegrationCredentials { credentialsByRole[role]! }
}
private enum GuestIntegrationConfigurationError: Error { case missing(String), invalid(String), productionTarget }
