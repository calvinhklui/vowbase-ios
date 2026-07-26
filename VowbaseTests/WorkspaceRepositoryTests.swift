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
        #expect(await adapter.selectRequests == [
            WorkspaceSelectRequest(
                table: "wedding_memberships",
                columns: "id,wedding_id,user_id,role,status,wedding:weddings(id,name,couple_names,wedding_date,location)",
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
                columns: "id,name,couple_names,wedding_date,location",
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
        let patch = WeddingPatch(name: "Alex & Calvin")

        let wedding = try await repository.updateWedding(id: weddingID, patch: patch)

        #expect(wedding == expectedWedding)
        #expect(await adapter.updateRequests == [
            .init(
                table: "weddings",
                columns: "id,name,couple_names,wedding_date,location",
                equalityFilters: [
                    .init(column: "id", value: weddingID.uuidString.lowercased()),
                ],
                singleRow: true,
                patch: patch
            ),
        ])
    }

    @Test("session summary uses only the authenticated API endpoint fixture")
    func sessionSummaryUsesAPIOnly() async throws {
        let session = try fixture(named: "session-summary")
        let api = SessionAPIClientSpy(response: session)
        let adapter = WorkspaceDatabaseSpy(authenticatedUserID: userID)
        let repository = SupabaseWorkspaceRepository(database: adapter, api: api)

        let summary = try await repository.sessionSummary()

        #expect(summary == SessionSummary(
            user: .init(id: userID, email: "calvin@example.com"),
            weddingIDs: [weddingID]
        ))
        #expect(api.methods == ["GET"])
        #expect(api.paths == ["api/v1/session"])
        #expect(await adapter.selectRequests.isEmpty)
        #expect(await adapter.updateRequests.isEmpty)
    }

    @Test("RLS role matrix allows owners and partners to update")
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

            let result = try await repository.updateWedding(
                id: weddingID,
                patch: WeddingPatch(name: "Allowed \(role.rawValue)")
            )

            #expect(result == expectedWedding, "\(role.rawValue) must be permitted by RLS")
        }
    }

    @Test("RLS role matrix denies planner parent and viewer updates")
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

            await #expect(
                throws: BackendError.forbidden(message: "Forbidden.", requestID: nil),
                "\(role.rawValue) must be denied by RLS"
            ) {
                _ = try await repository.updateWedding(
                    id: weddingID,
                    patch: WeddingPatch(name: "Denied \(role.rawValue)")
                )
            }
        }
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
            name: "Alex & Calvin",
            coupleNames: "Alex and Calvin",
            weddingDate: "2027-06-12",
            location: "Brooklyn, NY"
        )
    }

    private var expectedMembership: WeddingMembership {
        WeddingMembership(
            id: UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a")!,
            weddingID: weddingID,
            userID: userID,
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
            "name": "Alex & Calvin",
            "couple_names": "Alex and Calvin",
            "wedding_date": "2027-06-12",
            "location": "Brooklyn, NY"
          }
        }]
        """.utf8)
    }

    private var weddingData: Data {
        Data("""
        {
          "id": "01908f9d-2265-789a-bcde-f0123456789b",
          "name": "Alex & Calvin",
          "couple_names": "Alex and Calvin",
          "wedding_date": "2027-06-12",
          "location": "Brooklyn, NY"
        }
        """.utf8)
    }
}

private actor WorkspaceDatabaseSpy: WorkspaceDatabaseAdapter {
    let authenticatedUserID: UUID
    let selectResponse: Data?
    let updateResponse: Data?
    let selectError: (any Error)?
    let updateError: (any Error)?
    private(set) var selectRequests = [WorkspaceSelectRequest]()
    private(set) var updateRequests = [WorkspaceUpdateRequest<WeddingPatch>]()

    init(
        authenticatedUserID: UUID,
        selectResponse: Data? = nil,
        updateResponse: Data? = nil,
        selectError: (any Error)? = nil,
        updateError: (any Error)? = nil
    ) {
        self.authenticatedUserID = authenticatedUserID
        self.selectResponse = selectResponse
        self.updateResponse = updateResponse
        self.selectError = selectError
        self.updateError = updateError
    }

    func authenticatedUserID() async throws -> UUID { authenticatedUserID }

    func select<Response: Decodable & Sendable>(
        _ request: WorkspaceSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        selectRequests.append(request)
        if let selectError { throw selectError }
        return try DatabaseDecoding.decoder.decode(
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
        return try DatabaseDecoding.decoder.decode(
            Response.self,
            from: try #require(updateResponse)
        )
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
        return try DatabaseDecoding.decoder.decode(
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
