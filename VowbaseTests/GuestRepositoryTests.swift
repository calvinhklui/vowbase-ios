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
        _ = try await repository.updateGuest(id: guestID, patch: GuestPatch(email: .null))
        try await repository.deleteGuest(id: guestID)
        _ = try await repository.createCustomColumn(columnDraft, weddingID: weddingID)
        _ = try await repository.updateCustomColumn(id: columnID, patch: .init(hidden: true))
        try await repository.deleteCustomColumn(id: columnID)
        _ = try await repository.upsertRSVP(rsvpDraft)

        #expect(await database.insertRecords.map(\.table) == ["guests", "guest_custom_columns"])
        #expect(await database.insertRecords.map(\.columns) == [GuestColumns.guests, GuestColumns.customColumns])
        #expect(await database.updateRecords.map(\.table) == ["guests", "guest_custom_columns"])
        #expect(await database.updateRecords.allSatisfy { $0.columns != "" && $0.singleRow })
        #expect(await database.updatePayloads[0]["email"] is NSNull)
        #expect(await database.deleteRequests == [
            .init(table: "guests", columns: "id", equalityFilters: [.init(column: "id", value: guestID.uuidString.lowercased())], singleRow: true),
            .init(table: "guest_custom_columns", columns: "id", equalityFilters: [.init(column: "id", value: columnID.uuidString.lowercased())], singleRow: true),
        ])
        #expect(await database.rpcRequests.map(\.functionName) == ["upsert_rsvp_if_planner"])
        #expect(UUID(uuidString: await database.insertPayloads[0]["wedding_id"] as? String ?? "") == weddingID)
        #expect(UUID(uuidString: await database.insertPayloads[1]["wedding_id"] as? String ?? "") == weddingID)
        let rpcPayload = try #require(await database.rpcPayloads.first)
        #expect(Set(rpcPayload.keys) == ["p_wedding_id", "p_guest_id", "p_event_id", "p_status", "p_meal_choice", "p_notes"])
        #expect(UUID(uuidString: rpcPayload["p_wedding_id"] as? String ?? "") == weddingID)
        #expect(UUID(uuidString: rpcPayload["p_guest_id"] as? String ?? "") == guestID)
        #expect(UUID(uuidString: rpcPayload["p_event_id"] as? String ?? "") == eventID)
        #expect(rpcPayload["p_status"] as? String == "accepted")
        #expect(rpcPayload["p_meal_choice"] is NSNull)
        #expect(rpcPayload["p_notes"] is NSNull)
    }

    @Test("guest patch distinguishes unchanged, value, and explicit SQL null")
    func guestPatchEncodesTriStateNullableFields() throws {
        let unchanged = try jsonObject(GuestPatch(firstName: "Avery"))
        #expect(unchanged.count == 1)
        #expect(unchanged["first_name"] as? String == "Avery")

        let values = try jsonObject(GuestPatch(
            lastName: .value("Morgan"),
            email: .null,
            phone: .value("+1 555 0100"),
            address: .null,
            rsvpStatus: .value(.accepted),
            originLabel: .null,
            originLatitude: .value(40.7128),
            originLongitude: .null,
            originPrecision: .value("city"),
            geocodeStatus: .null
        ))
        #expect(values["last_name"] as? String == "Morgan")
        #expect(values["email"] is NSNull)
        #expect(values["phone"] as? String == "+1 555 0100")
        #expect(values["address"] is NSNull)
        #expect(values["rsvp_status"] as? String == "accepted")
        #expect(values["origin_label"] is NSNull)
        #expect(values["origin_latitude"] as? Double == 40.7128)
        #expect(values["origin_longitude"] is NSNull)
        #expect(values["origin_precision"] as? String == "city")
        #expect(values["geocode_status"] is NSNull)
        #expect(values["custom_fields"] == nil)
    }

    @Test("custom_fields remains a non-null JSON object for guest creates and updates")
    func rejectsUnsafeCustomFieldShapesBeforeDataAccess() async throws {
        let database = GuestDatabaseSpy(authenticatedUserID: userID)
        let repository = SupabaseGuestRepository(database: database)

        await #expect(throws: BackendError.validation(
            message: "Custom fields must be a JSON object.",
            requestID: nil
        )) {
            _ = try await repository.createGuest(
                .init(firstName: "Invalid", customFields: .null),
                weddingID: weddingID
            )
        }
        await #expect(throws: BackendError.validation(
            message: "Custom fields must be a JSON object.",
            requestID: nil
        )) {
            _ = try await repository.updateGuest(
                id: guestID,
                patch: .init(customFields: .array([]))
            )
        }
        #expect(await database.insertRecords.isEmpty)
        #expect(await database.updateRecords.isEmpty)
    }

    @Test("RSVP RPC parameter encoding preserves every nullable argument as explicit JSON null")
    func rsvpRPCParametersEncodeExactKeysAndNulls() throws {
        let parameters = RSVPUpsertParameters(
            draft: .init(weddingID: weddingID, guestID: guestID, eventID: eventID)
        )
        let object = try jsonObject(parameters)

        #expect(Set(object.keys) == ["p_wedding_id", "p_guest_id", "p_event_id", "p_status", "p_meal_choice", "p_notes"])
        #expect(object["p_status"] is NSNull)
        #expect(object["p_meal_choice"] is NSNull)
        #expect(object["p_notes"] is NSNull)
    }

    @Test("PostgREST constraint failures normalize to conflict or validation without weakening forbidden")
    func normalizesDatabaseConstraintErrors() async throws {
        let cases: [(String, BackendError)] = [
            ("23505", .conflict(message: "Conflict.", requestID: nil)),
            ("23503", .validation(message: "Invalid data.", requestID: nil)),
            ("23514", .validation(message: "Invalid data.", requestID: nil)),
            ("22023", .validation(message: "Invalid data.", requestID: nil)),
            ("22001", .validation(message: "Invalid data.", requestID: nil)),
            ("42501", .forbidden(message: "Forbidden.", requestID: nil)),
        ]
        for (code, expected) in cases {
            let repository = SupabaseGuestRepository(database: GuestDatabaseSpy(
                authenticatedUserID: userID,
                rpcError: PostgrestError(code: code, message: "sensitive database detail")
            ))
            await #expect(throws: expected, "SQLSTATE \(code)") {
                _ = try await repository.upsertRSVP(.init(weddingID: weddingID, guestID: guestID, eventID: eventID))
            }
        }
    }

    @Test("integration configuration rejects canonically equivalent production URLs")
    func integrationConfigurationRejectsEquivalentProductionURLs() throws {
        var supabaseEquivalent = integrationEnvironment
        supabaseEquivalent["VOWBASE_GUEST_INTEGRATION_SUPABASE_URL"] = "https://test-ref.supabase.co/"
        supabaseEquivalent["VOWBASE_PRODUCTION_SUPABASE_URL"] = "https://TEST-REF.SUPABASE.CO:443"
        #expect(throws: GuestIntegrationConfigurationError.conflict(
            actualKey: "VOWBASE_GUEST_INTEGRATION_SUPABASE_URL",
            productionKey: "VOWBASE_PRODUCTION_SUPABASE_URL"
        )) {
            _ = try GuestIntegrationConfiguration.load(environment: supabaseEquivalent)
        }

        var apiEquivalent = integrationEnvironment
        apiEquivalent["VOWBASE_GUEST_INTEGRATION_API_URL"] = "https://api.test.example.com/api/"
        apiEquivalent["VOWBASE_PRODUCTION_API_URL"] = "https://API.TEST.EXAMPLE.COM:443/api"
        #expect(throws: GuestIntegrationConfigurationError.conflict(
            actualKey: "VOWBASE_GUEST_INTEGRATION_API_URL",
            productionKey: "VOWBASE_PRODUCTION_API_URL"
        )) {
            _ = try GuestIntegrationConfiguration.load(environment: apiEquivalent)
        }
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
        await #expect(throws: BackendError.authenticationRequired(message: nil, requestID: nil)) {
            _ = try await repository.upsertRSVP(.init(weddingID: weddingID, guestID: guestID, eventID: eventID))
        }
        #expect(await database.selectRequests.isEmpty)
        #expect(await database.insertRecords.isEmpty)
        #expect(await database.rpcRequests.isEmpty)
    }

    @Test("unit role simulation labels adapter denials rather than claiming hosted RLS coverage")
    func simulatedRLSWriteDenialsNormalizeSafely() async throws {
        for role in [WeddingRole.parent, .viewer] {
            let database = GuestDatabaseSpy(
                authenticatedUserID: userID,
                rpcError: PostgrestError(code: "42501", message: "permission denied")
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

    private var integrationEnvironment: [String: String] {
        var values = [
            "VOWBASE_GUEST_INTEGRATION_ENABLED": "1",
            "VOWBASE_GUEST_INTEGRATION_ENVIRONMENT": "test",
            "VOWBASE_GUEST_INTEGRATION_SUPABASE_URL": "https://test-ref.supabase.co",
            "VOWBASE_PRODUCTION_SUPABASE_URL": "https://production-ref.supabase.co",
            "VOWBASE_GUEST_INTEGRATION_API_URL": "https://api.test.example.com/api",
            "VOWBASE_PRODUCTION_API_URL": "https://api.production.example.com/api",
            "VOWBASE_GUEST_INTEGRATION_SUPABASE_PROJECT_REF": "test-ref",
            "VOWBASE_GUEST_INTEGRATION_SUPABASE_HOST": "test-ref.supabase.co",
            "VOWBASE_GUEST_INTEGRATION_SUPABASE_PUBLISHABLE_KEY": "publishable-test-key",
            "VOWBASE_GUEST_INTEGRATION_WEDDING_ID": weddingID.uuidString,
            "VOWBASE_GUEST_INTEGRATION_SAFE_GUEST_ID": guestID.uuidString,
            "VOWBASE_GUEST_INTEGRATION_SAFE_EVENT_ID": eventID.uuidString,
        ]
        for role in GuestIntegrationRole.allCases {
            let prefix = "VOWBASE_GUEST_INTEGRATION_\(role.rawValue.uppercased())"
            values["\(prefix)_ACCESS_TOKEN"] = "access-\(role.rawValue)"
            values["\(prefix)_REFRESH_TOKEN"] = "refresh-\(role.rawValue)"
        }
        return values
    }

    private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

private actor GuestDatabaseSpy: GuestDatabaseAdapter {
    let userID: UUID
    let authenticatedUserIDError: (any Error)?
    let guestData: Data?
    let columnData: Data?
    let rsvpData: Data?
    let deletionData: Data?
    let rpcError: (any Error)?
    private(set) var authenticatedUserIDCallCount = 0
    private(set) var selectRequests = [GuestSelectRequest]()
    private(set) var insertRecords = [GuestMutationRecord]()
    private(set) var updateRecords = [GuestMutationRecord]()
    private(set) var updatePayloads = [[String: Any]]()
    private(set) var deleteRequests = [GuestDeleteRequest]()
    private(set) var rpcRequests = [GuestRPCRequest<RSVPUpsertParameters>]()
    private(set) var insertPayloads = [[String: Any]]()
    private(set) var rpcPayloads = [[String: Any]]()

    init(
        authenticatedUserID: UUID,
        authenticatedUserIDError: (any Error)? = nil,
        guestData: Data? = nil,
        columnData: Data? = nil,
        rsvpData: Data? = nil,
        deletionData: Data? = nil,
        rpcError: (any Error)? = nil
    ) {
        self.userID = authenticatedUserID
        self.authenticatedUserIDError = authenticatedUserIDError
        self.guestData = guestData
        self.columnData = columnData
        self.rsvpData = rsvpData
        self.deletionData = deletionData
        self.rpcError = rpcError
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
        updatePayloads.append(try object(from: request.patch))
        return try decode(for: Response.self, list: false)
    }

    func delete<Response: Decodable & Sendable>(_ request: GuestDeleteRequest, as: Response.Type) throws -> Response {
        deleteRequests.append(request)
        guard let deletionData else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing deletion data")) }
        return try GuestTestDecoding.decoder.decode(Response.self, from: deletionData)
    }

    func rpc<Response: Decodable & Sendable>(_ request: GuestRPCRequest<RSVPUpsertParameters>, as: Response.Type) throws -> Response {
        rpcRequests.append(request)
        rpcPayloads.append(try object(from: request.parameters))
        if let rpcError { throw rpcError }
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
        let owner = try await client(for: .owner, configuration: configuration)
        try await assertAuthenticatedRole(.owner, client: owner, configuration: configuration)
        let existing = try #require(try await owner.guests.rsvps(weddingID: configuration.weddingID).first {
            $0.guestID == configuration.guestID && $0.eventID == configuration.eventID
        })
        let safeDraft = RSVPDraft(weddingID: existing.weddingID, guestID: existing.guestID, eventID: existing.eventID, status: existing.status, mealChoice: existing.mealChoice, notes: existing.notes)
        let saved = try await owner.guests.upsertRSVP(safeDraft)
        #expect(saved.id == existing.id)
        #expect(saved.weddingID == existing.weddingID)
        #expect(saved.guestID == existing.guestID)
        #expect(saved.eventID == existing.eventID)
        #expect(saved.status == existing.status)
        #expect(saved.mealChoice == existing.mealChoice)
        #expect(saved.notes == existing.notes)
        for role in [GuestIntegrationRole.parent, .viewer] {
            let client = try await client(for: role, configuration: configuration)
            try await assertAuthenticatedRole(role, client: client, configuration: configuration)
            await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil), "hosted \(role.rawValue) denial") {
                _ = try await client.guests.upsertRSVP(safeDraft)
            }
        }
    }

    private func client(for role: GuestIntegrationRole, configuration: GuestIntegrationConfiguration) async throws -> GuestIntegrationClient {
        let provider = SupabaseProvider(configuration: configuration.appConfiguration)
        let credentials = configuration.credentials(for: role)
        _ = try await provider.client.auth.setSession(accessToken: credentials.accessToken, refreshToken: credentials.refreshToken)
        let authService = AuthService(provider: provider)
        let api = VowbaseAPIClient(
            sessionConfiguration: .ephemeral,
            configuration: configuration.appConfiguration,
            authService: authService
        )
        return GuestIntegrationClient(
            provider: provider,
            guests: SupabaseGuestRepository(provider: provider),
            workspace: SupabaseWorkspaceRepository(provider: provider, api: api)
        )
    }

    private func assertAuthenticatedRole(
        _ role: GuestIntegrationRole,
        client: GuestIntegrationClient,
        configuration: GuestIntegrationConfiguration
    ) async throws {
        let authenticatedUser = try await client.provider.client.auth.user()
        let session = try await client.workspace.sessionSummary()
        #expect(session.user.id == authenticatedUser.id)
        let membership = try #require(try await client.workspace.memberships().first {
            $0.weddingId == configuration.weddingID
        })
        #expect(membership.userId == authenticatedUser.id)
        #expect(membership.status == "active")
        #expect(membership.role.rawValue == role.rawValue)
    }
}

private struct GuestIntegrationClient {
    let provider: SupabaseProvider
    let guests: SupabaseGuestRepository
    let workspace: SupabaseWorkspaceRepository
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
        guard try required("VOWBASE_GUEST_INTEGRATION_ENABLED", in: environment) == "1" else {
            throw GuestIntegrationConfigurationError.invalid("VOWBASE_GUEST_INTEGRATION_ENABLED")
        }
        guard ["test", "staging"].contains(try required("VOWBASE_GUEST_INTEGRATION_ENVIRONMENT", in: environment).lowercased()) else {
            throw GuestIntegrationConfigurationError.invalid("VOWBASE_GUEST_INTEGRATION_ENVIRONMENT")
        }
        let supabaseURL = try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_URL", in: environment)
        let apiURL = try required("VOWBASE_GUEST_INTEGRATION_API_URL", in: environment)
        let productionSupabaseURL = try required("VOWBASE_PRODUCTION_SUPABASE_URL", in: environment)
        let productionAPIURL = try required("VOWBASE_PRODUCTION_API_URL", in: environment)
        try requireDistinctURL(actual: supabaseURL, production: productionSupabaseURL, actualKey: "VOWBASE_GUEST_INTEGRATION_SUPABASE_URL", productionKey: "VOWBASE_PRODUCTION_SUPABASE_URL")
        try requireDistinctURL(actual: apiURL, production: productionAPIURL, actualKey: "VOWBASE_GUEST_INTEGRATION_API_URL", productionKey: "VOWBASE_PRODUCTION_API_URL")
        try validateSupabaseIdentity(
            url: supabaseURL,
            projectRef: try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_PROJECT_REF", in: environment),
            expectedHost: try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_HOST", in: environment)
        )
        let roles = try Dictionary(uniqueKeysWithValues: GuestIntegrationRole.allCases.map { role in
            let prefix = "VOWBASE_GUEST_INTEGRATION_\(role.rawValue.uppercased())"
            return (role, GuestIntegrationCredentials(
                accessToken: try required("\(prefix)_ACCESS_TOKEN", in: environment),
                refreshToken: try required("\(prefix)_REFRESH_TOKEN", in: environment)
            ))
        })
        return .init(
            appConfiguration: try AppConfiguration(values: [
                "CONFIGURATION": "Debug",
                "SUPABASE_URL": supabaseURL,
                "SUPABASE_PUBLISHABLE_KEY": try required("VOWBASE_GUEST_INTEGRATION_SUPABASE_PUBLISHABLE_KEY", in: environment),
                "VOWBASE_API_URL": apiURL,
            ], transportPolicy: .debug),
            weddingID: try requiredUUID("VOWBASE_GUEST_INTEGRATION_WEDDING_ID", in: environment),
            guestID: try requiredUUID("VOWBASE_GUEST_INTEGRATION_SAFE_GUEST_ID", in: environment),
            eventID: try requiredUUID("VOWBASE_GUEST_INTEGRATION_SAFE_EVENT_ID", in: environment),
            credentialsByRole: roles
        )
    }

    func credentials(for role: GuestIntegrationRole) -> GuestIntegrationCredentials { credentialsByRole[role]! }

    private static func required(_ key: String, in environment: [String: String]) throws -> String {
        guard let raw = environment[key] else { throw GuestIntegrationConfigurationError.missing(key) }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GuestIntegrationConfigurationError.missing(key) }
        return value
    }

    private static func requiredUUID(_ key: String, in environment: [String: String]) throws -> UUID {
        guard let value = UUID(uuidString: try required(key, in: environment)) else {
            throw GuestIntegrationConfigurationError.invalid(key)
        }
        return value
    }

    private static func requireDistinctURL(actual: String, production: String, actualKey: String, productionKey: String) throws {
        guard let actualURL = normalizedURL(actual),
              let productionURL = normalizedURL(production),
              actualURL != productionURL else {
            throw GuestIntegrationConfigurationError.conflict(actualKey: actualKey, productionKey: productionKey)
        }
    }

    private static func normalizedURL(_ value: String) -> String? {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return nil }
        components.scheme = scheme
        components.host = host
        if components.port == nil {
            components.port = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path = components.path == "/" ? "" : components.path
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func validateSupabaseIdentity(url: String, projectRef: String, expectedHost: String) throws {
        guard let host = URL(string: url)?.host?.lowercased(),
              host == expectedHost.lowercased(),
              host == "\(projectRef.lowercased()).supabase.co" else {
            throw GuestIntegrationConfigurationError.invalid(
                "VOWBASE_GUEST_INTEGRATION_SUPABASE_PROJECT_REF or VOWBASE_GUEST_INTEGRATION_SUPABASE_HOST"
            )
        }
    }
}
private enum GuestIntegrationConfigurationError: Error, Equatable {
    case missing(String)
    case invalid(String)
    case conflict(actualKey: String, productionKey: String)
}
