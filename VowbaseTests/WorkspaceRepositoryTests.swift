import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Workspace repository")
struct WorkspaceRepositoryTests {
    private let userID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789c")!
    private let weddingID = UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789b")!

    @Test("memberships scope the nested wedding query to the authenticated active user")
    func membershipsUsesAuthenticatedActiveScope() async throws {
        let adapter = WorkspaceDatabaseSpy(
            authenticatedUserID: userID,
            selectResponse: membershipData
        )
        let repository = SupabaseWorkspaceRepository(
            database: adapter,
            api: SessionAPIClientSpy()
        )

        let memberships = try await repository.memberships()

        #expect(memberships == [expectedMembership])
        let membership = try #require(memberships.first)
        #expect(membership.id == UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a"))
        #expect(membership.weddingId == weddingID)
        #expect(membership.userId == userID)
        #expect(membership.role == .partner)
        #expect(membership.status == "active")
        #expect(membership.wedding.id == weddingID)
        #expect(membership.wedding.name == "Example Wedding")
        #expect(membership.wedding.coupleNames == "Example Couple")
        #expect(membership.wedding.weddingDate == "2027-06-12")
        #expect(membership.wedding.dateFlexibility == "specific")
        #expect(membership.wedding.dateRangeStart == nil)
        #expect(membership.wedding.dateRangeEnd == nil)
        #expect(membership.wedding.location == "Brooklyn, NY")
        #expect(await adapter.selectRequests == [
            WorkspaceSelectRequest(
                table: "wedding_memberships",
                columns: "id,wedding_id,user_id,role,status,wedding:weddings(id,name,couple_names,wedding_date,date_flexibility,date_range_start,date_range_end,location)",
                equalityFilters: [
                    .init(column: "user_id", value: userID.uuidString.lowercased()),
                    .init(column: "status", value: "active"),
                ],
                singleRow: false
            ),
        ])
    }

    @Test("wedding reads require one row and its exact id filter")
    func weddingUsesSingleRowIDScope() async throws {
        let adapter = WorkspaceDatabaseSpy(
            authenticatedUserID: userID,
            selectResponse: weddingData
        )
        let repository = SupabaseWorkspaceRepository(
            database: adapter,
            api: SessionAPIClientSpy()
        )

        let wedding = try await repository.wedding(id: weddingID)

        #expect(wedding == expectedWedding)
        #expect(await adapter.selectRequests == [
            WorkspaceSelectRequest(
                table: "weddings",
                columns: "id,name,couple_names,wedding_date,date_flexibility,date_range_start,date_range_end,location",
                equalityFilters: [
                    .init(column: "id", value: weddingID.uuidString.lowercased()),
                ],
                singleRow: true
            ),
        ])
    }

    @Test("updates return one scoped wedding row")
    func updateUsesSingleRowIDScope() async throws {
        let adapter = WorkspaceDatabaseSpy(
            authenticatedUserID: userID,
            updateResponse: weddingData
        )
        let repository = SupabaseWorkspaceRepository(
            database: adapter,
            api: SessionAPIClientSpy()
        )
        let patch = WeddingPatch(name: "Example Wedding")

        let wedding = try await repository.updateWedding(id: weddingID, patch: patch)

        #expect(wedding == expectedWedding)
        #expect(await adapter.updateRequests == [
            .init(
                table: "weddings",
                columns: "id,name,couple_names,wedding_date,date_flexibility,date_range_start,date_range_end,location",
                equalityFilters: [
                    .init(column: "id", value: weddingID.uuidString.lowercased()),
                ],
                singleRow: true,
                patch: patch
            ),
        ])
    }

    @Test("wedding timing patches set one mode and clear the other")
    func weddingTimingPatchEncoding() throws {
        let encoder = JSONEncoder()

        let specific = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(WeddingPatch(
                weddingDate: .value("2027-06-12"),
                dateFlexibility: "specific",
                dateRangeStart: .null,
                dateRangeEnd: .null
            ))) as? [String: Any]
        )
        #expect(specific["wedding_date"] as? String == "2027-06-12")
        #expect(specific["date_flexibility"] as? String == "specific")
        #expect(specific["date_range_start"] is NSNull)
        #expect(specific["date_range_end"] is NSNull)

        let range = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(WeddingPatch(
                weddingDate: .null,
                dateFlexibility: "range",
                dateRangeStart: .value("2027-06-01"),
                dateRangeEnd: .value("2027-08-31")
            ))) as? [String: Any]
        )
        #expect(range["wedding_date"] is NSNull)
        #expect(range["date_flexibility"] as? String == "range")
        #expect(range["date_range_start"] as? String == "2027-06-01")
        #expect(range["date_range_end"] as? String == "2027-08-31")
    }

    @Test("session summary uses only the authenticated API endpoint fixture")
    func sessionSummaryUsesAPIOnly() async throws {
        let session = try fixture(named: "session-summary")
        let api = SessionAPIClientSpy(response: session)
        let adapter = WorkspaceDatabaseSpy(authenticatedUserID: userID)
        let repository = SupabaseWorkspaceRepository(database: adapter, api: api)

        let summary = try await repository.sessionSummary()

        #expect(summary == SessionSummary(
            user: .init(id: userID, email: "sample@example.com"),
            weddingIDs: [weddingID]
        ))
        #expect(api.methods == ["GET"])
        #expect(api.paths == ["v1/session"])
        #expect(await adapter.selectRequests.isEmpty)
        #expect(await adapter.updateRequests.isEmpty)
    }

    @Test("role matrix reflects successful owner and partner patch responses")
    func allowedRolesCanUpdate() async throws {
        for role in [WeddingRole.owner, .partner] {
            let adapter = WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                updateResponse: weddingData
            )
            let repository = SupabaseWorkspaceRepository(
                database: adapter,
                api: SessionAPIClientSpy()
            )

            let patch = WeddingPatch(name: "Allowed \(role.rawValue)")
            let result = try await repository.updateWedding(id: weddingID, patch: patch)

            #expect(result.name == patch.name)
            #expect(result.coupleNames == expectedWedding.coupleNames)
            #expect(await adapter.updateRequests == [
                .init(
                    table: "weddings",
                    columns: "id,name,couple_names,wedding_date,date_flexibility,date_range_start,date_range_end,location",
                    equalityFilters: [
                        .init(column: "id", value: weddingID.uuidString.lowercased()),
                    ],
                    singleRow: true,
                    patch: patch
                ),
            ])
        }
    }

    @Test("role matrix maps denied planner parent and viewer outcomes")
    func deniedRolesCannotUpdate() async throws {
        for role in [WeddingRole.planner, .parent, .viewer] {
            let adapter = WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                updateError: PostgrestError(code: "42501", message: "permission denied")
            )
            let repository = SupabaseWorkspaceRepository(
                database: adapter,
                api: SessionAPIClientSpy()
            )

            let patch = WeddingPatch(name: "Denied \(role.rawValue)")
            await #expect(
                throws: BackendError.forbidden(message: "Forbidden.", requestID: nil),
                "\(role.rawValue) denied adapter outcome"
            ) {
                _ = try await repository.updateWedding(id: weddingID, patch: patch)
            }
            #expect(await adapter.updateRequests.last?.patch == patch)
        }
    }

    @Test("signed-out authenticated-user lookup maps to authentication required")
    func mapsSignedOutUserLookup() async throws {
        let repository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                authenticatedUserIDError: AuthError.sessionMissing
            ),
            api: SessionAPIClientSpy()
        )

        await #expect(
            throws: BackendError.authenticationRequired(message: nil, requestID: nil)
        ) {
            _ = try await repository.memberships()
        }
    }

    @Test("auth session errors preserve the authentication-required classification")
    func mapsAuthenticationRequiredAuthErrors() async throws {
        let errors: [AuthError] = [
            .sessionMissing,
            authAPIError(code: .sessionExpired),
            authAPIError(code: .refreshTokenNotFound),
            authAPIError(code: .refreshTokenAlreadyUsed),
            authAPIError(code: .noAuthorization),
            authAPIError(code: .invalidJWT),
            authAPIError(code: .invalidCredentials),
        ]

        for error in errors {
            await #expect(
                throws: BackendError.authenticationRequired(message: nil, requestID: nil)
            ) {
                _ = try await SupabaseWorkspaceRepository(
                    database: WorkspaceDatabaseSpy(
                        authenticatedUserID: userID,
                        authenticatedUserIDError: error
                    ),
                    api: SessionAPIClientSpy()
                ).memberships()
            }
        }
    }

    @Test("auth rate-limit and unexpected errors use safe repository errors")
    func mapsRateLimitedAndUnexpectedAuthErrors() async throws {
        let rateLimitedRepository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                authenticatedUserIDError: authAPIError(code: .overRequestRateLimit)
            ),
            api: SessionAPIClientSpy()
        )
        await #expect(
            throws: BackendError.rateLimited(
                message: "Authentication rate limit reached.",
                requestID: nil
            )
        ) {
            _ = try await rateLimitedRepository.memberships()
        }

        let unavailableRepository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                authenticatedUserIDError: AuthError.weakPassword(
                    message: "sensitive server response",
                    reasons: []
                )
            ),
            api: SessionAPIClientSpy()
        )
        await #expect(
            throws: BackendError.temporarilyUnavailable(
                message: "Authentication is temporarily unavailable.",
                requestID: nil
            )
        ) {
            _ = try await unavailableRepository.memberships()
        }
    }

    @Test("session summary preserves the configured api base path")
    func sessionSummaryComposesConfiguredAPIBasePath() async throws {
        let transport = URLProtocolStub.State(steps: [
            .response(statusCode: 200, body: try fixture(named: "session-summary")),
        ])
        let configuration = try AppConfiguration(
            values: [
                "CONFIGURATION": "Debug",
                "SUPABASE_URL": "https://project.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "publishable-test-key",
                "VOWBASE_API_URL": "https://api.example.com/api",
            ],
            transportPolicy: .debug
        )
        let api = VowbaseAPIClient(
            sessionConfiguration: URLProtocolStub.configuration(for: transport),
            configuration: configuration,
            authService: WorkspaceURLAuthStub()
        )
        let repository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(authenticatedUserID: userID),
            api: api
        )

        let summary = try await repository.sessionSummary()

        #expect(summary.user.id == userID)
        #expect(transport.requests.map(\.url?.path) == ["/api/v1/session"])
    }

    @Test("PostgREST no-row denials and cancellation normalize safely")
    func normalizesDirectDataFailures() async throws {
        let noRowRepository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                selectError: PostgrestError(code: "PGRST116", message: "No rows")
            ),
            api: SessionAPIClientSpy()
        )
        await #expect(throws: BackendError.forbidden(message: "Forbidden.", requestID: nil)) {
            _ = try await noRowRepository.wedding(id: weddingID)
        }

        let cancelledRepository = SupabaseWorkspaceRepository(
            database: WorkspaceDatabaseSpy(
                authenticatedUserID: userID,
                selectError: CancellationError()
            ),
            api: SessionAPIClientSpy()
        )
        await #expect(throws: BackendError.cancelled) {
            _ = try await cancelledRepository.wedding(id: weddingID)
        }
    }

    private var expectedWedding: WeddingSummary {
        WeddingSummary(
            id: weddingID,
            name: "Example Wedding",
            coupleNames: "Example Couple",
            weddingDate: "2027-06-12",
            dateFlexibility: "specific",
            dateRangeStart: nil,
            dateRangeEnd: nil,
            location: "Brooklyn, NY"
        )
    }

    private var expectedMembership: WeddingMembership {
        WeddingMembership(
            id: UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a")!,
            weddingId: weddingID,
            userId: userID,
            role: .partner,
            status: "active",
            wedding: expectedWedding
        )
    }

    private var membershipData: Data {
        Data("""
        [{
          "id": "01908f9d-2265-789a-bcde-f0123456789a",
          "wedding_id": "01908f9d-2265-789a-bcde-f0123456789b",
          "user_id": "01908f9d-2265-789a-bcde-f0123456789c",
          "role": "partner",
          "status": "active",
          "wedding": {
            "id": "01908f9d-2265-789a-bcde-f0123456789b",
            "name": "Example Wedding",
            "couple_names": "Example Couple",
            "wedding_date": "2027-06-12",
            "date_flexibility": "specific",
            "date_range_start": null,
            "date_range_end": null,
            "location": "Brooklyn, NY"
          }
        }]
        """.utf8)
    }

    private var weddingData: Data {
        Data("""
        {
          "id": "01908f9d-2265-789a-bcde-f0123456789b",
          "name": "Example Wedding",
          "couple_names": "Example Couple",
          "wedding_date": "2027-06-12",
          "date_flexibility": "specific",
          "date_range_start": null,
          "date_range_end": null,
          "location": "Brooklyn, NY"
        }
        """.utf8)
    }
}

private actor WorkspaceDatabaseSpy: WorkspaceDatabaseAdapter {
    let authenticatedUserID: UUID
    let authenticatedUserIDError: (any Error)?
    let selectResponse: Data?
    let updateResponse: Data?
    let selectError: (any Error)?
    let updateError: (any Error)?
    private(set) var selectRequests = [WorkspaceSelectRequest]()
    private(set) var updateRequests = [WorkspaceUpdateRequest<WeddingPatch>]()

    init(
        authenticatedUserID: UUID,
        authenticatedUserIDError: (any Error)? = nil,
        selectResponse: Data? = nil,
        updateResponse: Data? = nil,
        selectError: (any Error)? = nil,
        updateError: (any Error)? = nil
    ) {
        self.authenticatedUserID = authenticatedUserID
        self.authenticatedUserIDError = authenticatedUserIDError
        self.selectResponse = selectResponse
        self.updateResponse = updateResponse
        self.selectError = selectError
        self.updateError = updateError
    }

    func authenticatedUserID() async throws -> UUID {
        if let authenticatedUserIDError { throw authenticatedUserIDError }
        return authenticatedUserID
    }

    func select<Response: Decodable & Sendable>(
        _ request: WorkspaceSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        selectRequests.append(request)
        if let selectError { throw selectError }
        return try productionDecoder.decode(
            Response.self,
            from: try #require(selectResponse)
        )
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: WorkspaceUpdateRequest<Patch>,
        as: Response.Type
    ) async throws -> Response {
        guard let request = request as? WorkspaceUpdateRequest<WeddingPatch> else {
            throw BackendError.invalidResponse
        }
        updateRequests.append(request)
        if let updateError { throw updateError }
        if Response.self == WeddingSummary.self {
            let patch = request.patch
            let current = try productionDecoder.decode(
                WeddingSummary.self,
                from: try #require(updateResponse)
            )
            return WeddingSummary(
                id: current.id,
                name: patch.name ?? current.name,
                coupleNames: patch.coupleNames ?? current.coupleNames,
                weddingDate: patch.weddingDate.applying(to: current.weddingDate),
                dateFlexibility: patch.dateFlexibility ?? current.dateFlexibility,
                dateRangeStart: patch.dateRangeStart.applying(to: current.dateRangeStart),
                dateRangeEnd: patch.dateRangeEnd.applying(to: current.dateRangeEnd),
                location: patch.location ?? current.location
            ) as! Response
        }
        return try productionDecoder.decode(Response.self, from: try #require(updateResponse))
    }
}

private extension NullablePatch {
    func applying(to current: Value?) -> Value? {
        switch self {
        case .unchanged: current
        case let .value(value): value
        case .null: nil
        }
    }
}

private final class SessionAPIClientSpy: VowbaseAPIClientProtocol, @unchecked Sendable {
    private let response: Data?
    private(set) var methods = [String]()
    private(set) var paths = [String]()

    init(response: Data? = nil) {
        self.response = response
    }

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        methods.append(request.method.rawValue)
        paths.append(request.path)
        return try JSONDecoder().decode(
            Response.self,
            from: try #require(response)
        )
    }
}

private func fixture(named name: String) throws -> Data {
    let bundle = Bundle(for: WorkspaceRepositoryTestsBundleToken.self)
    let url = try #require(
        bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
}

private final class WorkspaceRepositoryTestsBundleToken {}

private let productionDecoder = PostgrestClient.Configuration.jsonDecoder

private func authAPIError(code: ErrorCode) -> AuthError {
    .api(
        message: "sensitive server response",
        errorCode: code,
        underlyingData: Data(),
        underlyingResponse: HTTPURLResponse(
            url: URL(string: "https://auth.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!
    )
}

private final class WorkspaceURLAuthStub: AuthServicing, Sendable {
    var states: AsyncStream<AuthenticationState> { AsyncStream { $0.finish() } }

    func currentAccessToken() async throws -> String { "access-token" }
    func refreshSession() async throws {}
    func handle(url: URL) async throws {}
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}
    func signOut() async throws {}
}
