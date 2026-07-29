import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Profile and invitation repositories")
struct ProfileInvitationRepositoryTests {
    private let userID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789c")!
    private let weddingID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789b")!

    @Test("current profile reads and updates are both scoped to the authenticated user")
    func currentProfileUsesAuthenticatedUserScope() async throws {
        let database = ProfileDatabaseSpy(
            authenticatedUserID: userID,
            selectResponse: profileData,
            updateResponse: profileData
        )
        let repository = SupabaseProfileRepository(database: database)

        let profile = try await repository.currentProfile()
        let updated = try await repository.updateCurrentProfile(
            ProfilePatch(firstName: "Sample")
        )

        #expect(profile == expectedProfile)
        #expect(updated == expectedProfile)
        let expectedScope = [
            ProfileEqualityFilter(column: "id", value: userID.uuidString.lowercased()),
        ]
        #expect(await database.selectRequests == [
            ProfileSelectRequest(
                table: "profiles",
                columns: "id,email,full_name,first_name,last_name,avatar_url",
                equalityFilters: expectedScope,
                singleRow: true
            ),
        ])
        #expect(await database.updateRequests == [
            ProfileUpdateRequest(
                table: "profiles",
                columns: "id,email,full_name,first_name,last_name,avatar_url",
                equalityFilters: expectedScope,
                singleRow: true,
                patch: ProfilePatch(firstName: "Sample")
            ),
        ])
    }

    @Test("invitation preview calls only lookup_invitation with the exact token")
    func previewCallsLookupInvitationWithExactToken() async throws {
        let database = InvitationDatabaseSpy(rpcResponse: invitationPreviewData)
        let repository = SupabaseInvitationRepository(database: database)
        let token = "invite-token-with-case-ABC"

        let preview = try await repository.preview(token: token)

        #expect(preview == expectedPreview)
        #expect(await database.rpcRequests == [
            InvitationRPCRequest(functionName: "lookup_invitation", token: token),
        ])
        #expect(await database.selectRequests.isEmpty)
    }

    @Test("acceptance delegates membership creation to accept_invitation RPC")
    func acceptCallsRPCWithoutMembershipInsert() async throws {
        let database = InvitationDatabaseSpy(
            authenticatedUserID: userID,
            rpcResponse: acceptedWeddingData
        )
        let repository = SupabaseInvitationRepository(database: database)
        let token = "unmodified-invitation-token"

        let acceptedWeddingID = try await repository.accept(token: token)

        #expect(acceptedWeddingID == weddingID)
        #expect(await database.rpcRequests == [
            InvitationRPCRequest(functionName: "accept_invitation", token: token),
        ])
        #expect(await database.selectRequests.isEmpty)
        #expect(await database.insertedTables.isEmpty)
        #expect(await database.authenticatedUserIDCallCount == 1)
    }

    @Test("wedding invitation lists never omit the wedding scope")
    func invitationsUseWeddingIDScope() async throws {
        let database = InvitationDatabaseSpy(
            authenticatedUserID: userID,
            selectResponse: invitationsData
        )
        let repository = SupabaseInvitationRepository(database: database)

        let invitations = try await repository.invitations(weddingID: weddingID)

        #expect(invitations == [expectedInvitation])
        #expect(await database.selectRequests == [
            InvitationSelectRequest(
                table: "wedding_invitations",
                columns: "id,wedding_id,email,role,status,expires_at,invited_by,accepted_at,created_at,token",
                equalityFilters: [
                    .init(column: "wedding_id", value: weddingID.uuidString.lowercased()),
                ],
                orders: [.init(column: "created_at", ascending: false)],
                singleRow: false
            ),
        ])
        #expect(await database.authenticatedUserIDCallCount == 1)
    }

    @Test("invitation preview remains public while signed-out mutations and lists stop before data access")
    func invitationAuthenticationPreflightProtectsMutationsAndListsOnly() async throws {
        let previewDatabase = InvitationDatabaseSpy(rpcResponse: invitationPreviewData)
        let preview = try await SupabaseInvitationRepository(database: previewDatabase)
            .preview(token: "public-preview-token")
        #expect(preview == expectedPreview)
        #expect(await previewDatabase.authenticatedUserIDCallCount == 0)

        let acceptDatabase = InvitationDatabaseSpy(
            authenticatedUserID: userID,
            authenticatedUserIDError: AuthError.sessionMissing
        )
        await #expect(
            throws: BackendError.authenticationRequired(message: nil, requestID: nil)
        ) {
            _ = try await SupabaseInvitationRepository(database: acceptDatabase)
                .accept(token: "must-not-reach-rpc")
        }
        #expect(await acceptDatabase.rpcRequests.isEmpty)
        #expect(await acceptDatabase.authenticatedUserIDCallCount == 1)

        let listDatabase = InvitationDatabaseSpy(
            authenticatedUserID: userID,
            authenticatedUserIDError: AuthError.sessionMissing
        )
        await #expect(
            throws: BackendError.authenticationRequired(message: nil, requestID: nil)
        ) {
            _ = try await SupabaseInvitationRepository(database: listDatabase)
                .invitations(weddingID: weddingID)
        }
        #expect(await listDatabase.selectRequests.isEmpty)
        #expect(await listDatabase.authenticatedUserIDCallCount == 1)
    }

    @Test("production invitation RPC parameters encode only the exact _token argument")
    func invitationRPCParametersEncodeExactUnderscoredToken() throws {
        let token = "Case-sensitive token /?=value"
        let data = try JSONEncoder().encode(InvitationTokenParameters(token: token))
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(object == ["_token": token])
        #expect(object["token"] == nil)
    }

    @Test("profile and invitation adapters normalize auth, PostgREST, and cancellation failures")
    func normalizesRepositoryFailures() async throws {
        let signedOut = SupabaseProfileRepository(
            database: ProfileDatabaseSpy(
                authenticatedUserID: userID,
                authenticatedUserIDError: AuthError.sessionMissing
            )
        )
        await #expect(
            throws: BackendError.authenticationRequired(message: nil, requestID: nil)
        ) {
            _ = try await signedOut.currentProfile()
        }

        let forbidden = SupabaseInvitationRepository(
            database: InvitationDatabaseSpy(
                selectError: PostgrestError(code: "42501", message: "sensitive denial")
            )
        )
        await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil)) {
            _ = try await forbidden.invitations(weddingID: weddingID)
        }

        let cancelled = SupabaseInvitationRepository(
            database: InvitationDatabaseSpy(rpcError: CancellationError())
        )
        await #expect(throws: BackendError.cancelled) {
            _ = try await cancelled.preview(token: "token")
        }
    }

    private var expectedProfile: Profile {
        Profile(
            id: userID,
            email: "sample@example.com",
            fullName: "Sample User",
            firstName: "Sample",
            lastName: "User",
            avatarURL: "https://example.com/avatar.png"
        )
    }

    private var expectedPreview: InvitationPreview {
        InvitationPreview(
            id: UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a")!,
            weddingID: weddingID,
            weddingName: "Example Wedding",
            email: nil,
            role: .partner,
            status: .pending,
            expiresAt: Date(timeIntervalSince1970: 1_846_022_400)
        )
    }

    private var expectedInvitation: WeddingInvitation {
        WeddingInvitation(
            id: UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a")!,
            weddingID: weddingID,
            email: nil,
            role: .partner,
            status: .pending,
            expiresAt: Date(timeIntervalSince1970: 1_846_022_400),
            invitedBy: userID,
            acceptedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600),
            token: "server-token"
        )
    }

    private var profileData: Data {
        Data("""
        {"id":"01908f9d-2265-789a-bcde-f0123456789c","email":"sample@example.com","full_name":"Sample User","first_name":"Sample","last_name":"User","avatar_url":"https://example.com/avatar.png"}
        """.utf8)
    }

    private var invitationPreviewData: Data {
        Data("""
        [{"id":"01908f9d-2265-789a-bcde-f0123456789a","wedding_id":"01908f9d-2265-789a-bcde-f0123456789b","wedding_name":"Example Wedding","email":null,"role":"partner","status":"pending","expires_at":"2028-07-01T00:00:00Z"}]
        """.utf8)
    }

    private var acceptedWeddingData: Data {
        Data("\"01908f9d-2265-789a-bcde-f0123456789b\"".utf8)
    }

    private var invitationsData: Data {
        Data("""
        [{"id":"01908f9d-2265-789a-bcde-f0123456789a","wedding_id":"01908f9d-2265-789a-bcde-f0123456789b","email":null,"role":"partner","status":"pending","expires_at":"2028-07-01T00:00:00Z","invited_by":"01908f9d-2265-789a-bcde-f0123456789c","accepted_at":null,"created_at":"2025-01-01T00:00:00Z","token":"server-token"}]
        """.utf8)
    }
}

private actor ProfileDatabaseSpy: ProfileDatabaseAdapter {
    let authenticatedUserID: UUID
    let authenticatedUserIDError: (any Error)?
    let selectResponse: Data?
    let updateResponse: Data?
    private(set) var selectRequests = [ProfileSelectRequest]()
    private(set) var updateRequests = [ProfileUpdateRequest<ProfilePatch>]()

    init(authenticatedUserID: UUID, authenticatedUserIDError: (any Error)? = nil, selectResponse: Data? = nil, updateResponse: Data? = nil) {
        self.authenticatedUserID = authenticatedUserID
        self.authenticatedUserIDError = authenticatedUserIDError
        self.selectResponse = selectResponse
        self.updateResponse = updateResponse
    }

    func authenticatedUserID() async throws -> UUID {
        if let authenticatedUserIDError { throw authenticatedUserIDError }
        return authenticatedUserID
    }

    func select<Response: Decodable & Sendable>(_ request: ProfileSelectRequest, as: Response.Type) async throws -> Response {
        selectRequests.append(request)
        return try profileInvitationProductionDecoder.decode(
            Response.self,
            from: try #require(selectResponse)
        )
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(_ request: ProfileUpdateRequest<Patch>, as: Response.Type) async throws -> Response {
        guard let request = request as? ProfileUpdateRequest<ProfilePatch> else { throw BackendError.invalidResponse }
        updateRequests.append(request)
        return try profileInvitationProductionDecoder.decode(
            Response.self,
            from: try #require(updateResponse)
        )
    }
}

private actor InvitationDatabaseSpy: InvitationDatabaseAdapter {
    let authenticatedUserID: UUID
    let authenticatedUserIDError: (any Error)?
    let selectResponse: Data?
    let rpcResponse: Data?
    let selectError: (any Error)?
    let rpcError: (any Error)?
    private(set) var selectRequests = [InvitationSelectRequest]()
    private(set) var rpcRequests = [InvitationRPCRequest]()
    private(set) var insertedTables = [String]()
    private(set) var authenticatedUserIDCallCount = 0

    init(
        authenticatedUserID: UUID = UUID(),
        authenticatedUserIDError: (any Error)? = nil,
        selectResponse: Data? = nil,
        rpcResponse: Data? = nil,
        selectError: (any Error)? = nil,
        rpcError: (any Error)? = nil
    ) {
        self.authenticatedUserID = authenticatedUserID
        self.authenticatedUserIDError = authenticatedUserIDError
        self.selectResponse = selectResponse
        self.rpcResponse = rpcResponse
        self.selectError = selectError
        self.rpcError = rpcError
    }

    func authenticatedUserID() async throws -> UUID {
        authenticatedUserIDCallCount += 1
        if let authenticatedUserIDError { throw authenticatedUserIDError }
        return authenticatedUserID
    }

    func select<Response: Decodable & Sendable>(_ request: InvitationSelectRequest, as: Response.Type) async throws -> Response {
        selectRequests.append(request)
        if let selectError { throw selectError }
        return try profileInvitationProductionDecoder.decode(
            Response.self,
            from: try #require(selectResponse)
        )
    }

    func rpc<Response: Decodable & Sendable>(_ request: InvitationRPCRequest, as: Response.Type) async throws -> Response {
        rpcRequests.append(request)
        if let rpcError { throw rpcError }
        return try profileInvitationProductionDecoder.decode(
            Response.self,
            from: try #require(rpcResponse)
        )
    }
}

private let profileInvitationProductionDecoder = PostgrestClient.Configuration.jsonDecoder
