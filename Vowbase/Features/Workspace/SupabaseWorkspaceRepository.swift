import Foundation
import Supabase

final class SupabaseWorkspaceRepository: WorkspaceRepository, @unchecked Sendable {
    private static let weddingColumns =
        "id,name,couple_names,wedding_date,date_flexibility,date_range_start,date_range_end,location"
    private static let membershipColumns =
        "id,wedding_id,user_id,role,status,wedding:weddings(\(weddingColumns))"

    private let database: any WorkspaceDatabaseAdapter
    private let api: any VowbaseAPIClientProtocol

    convenience init(provider: SupabaseProvider, api: any VowbaseAPIClientProtocol) {
        self.init(
            database: SupabaseWorkspaceDatabaseAdapter(provider: provider),
            api: api
        )
    }

    init(
        database: any WorkspaceDatabaseAdapter,
        api: any VowbaseAPIClientProtocol
    ) {
        self.database = database
        self.api = api
    }

    func memberships() async throws -> [WeddingMembership] {
        do {
            try Task.checkCancellation()
            let userId = try await database.authenticatedUserID()
            let request = WorkspaceSelectRequest(
                table: "wedding_memberships",
                columns: Self.membershipColumns,
                equalityFilters: [
                    .init(column: "user_id", value: userId.uuidString.lowercased()),
                    .init(column: "status", value: "active"),
                ],
                singleRow: false
            )
            let memberships: [WeddingMembership] = try await database.select(
                request,
                as: [WeddingMembership].self
            )
            try Task.checkCancellation()
            return memberships
        } catch {
            throw Self.normalized(error)
        }
    }

    func wedding(id: UUID) async throws -> WeddingSummary {
        do {
            let request = Self.weddingRequest(id: id)
            let wedding: WeddingSummary = try await database.select(
                request,
                as: WeddingSummary.self
            )
            try Task.checkCancellation()
            return wedding
        } catch {
            throw Self.normalized(error)
        }
    }

    func updateWedding(id: UUID, patch: WeddingPatch) async throws -> WeddingSummary {
        do {
            try Task.checkCancellation()
            let request = WorkspaceUpdateRequest(
                table: "weddings",
                columns: Self.weddingColumns,
                equalityFilters: [
                    .init(column: "id", value: id.uuidString.lowercased()),
                ],
                singleRow: true,
                patch: patch
            )
            let wedding: WeddingSummary = try await database.update(
                request,
                as: WeddingSummary.self
            )
            try Task.checkCancellation()
            return wedding
        } catch {
            throw Self.normalized(error)
        }
    }

    func sessionSummary() async throws -> SessionSummary {
        do {
            try Task.checkCancellation()
            let session: SessionSummary = try await api.send(
                APIRequest(method: .get, path: "v1/session")
            )
            try Task.checkCancellation()
            return session
        } catch {
            throw Self.normalized(error)
        }
    }

    private static func weddingRequest(id: UUID) -> WorkspaceSelectRequest {
        WorkspaceSelectRequest(
            table: "weddings",
            columns: weddingColumns,
            equalityFilters: [
                .init(column: "id", value: id.uuidString.lowercased()),
            ],
            singleRow: true
        )
    }

    private static func normalized(_ error: any Error) -> BackendError {
        if let backendError = error as? BackendError {
            return backendError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        if let authError = error as? AuthError {
            if authError.errorCode == .sessionNotFound
                || authError.errorCode == .sessionExpired
                || authError.errorCode == .refreshTokenNotFound
                || authError.errorCode == .refreshTokenAlreadyUsed
                || authError.errorCode == .noAuthorization
                || authError.errorCode == .invalidJWT
                || authError.errorCode == .invalidCredentials {
                return .authenticationRequired(message: nil, requestID: nil)
            }
            if authError.errorCode == .overRequestRateLimit {
                return .rateLimited(
                    message: "Authentication rate limit reached.",
                    requestID: nil
                )
            }
            return .temporarilyUnavailable(
                message: "Authentication is temporarily unavailable.",
                requestID: nil
            )
        }
        if let transport = error as? URLError {
            if transport.code == .cancelled {
                return .cancelled
            }
            return .networkUnavailable
        }
        if let postgrest = error as? PostgrestError,
           postgrest.code == "42501" || postgrest.code == "PGRST116" {
            return .forbidden(message: "Forbidden.", requestID: nil)
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .unknown(message: "Workspace request failed.", requestID: nil)
    }
}

private final class SupabaseWorkspaceDatabaseAdapter: WorkspaceDatabaseAdapter, @unchecked Sendable {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func authenticatedUserID() async throws -> UUID {
        try Task.checkCancellation()
        let user = try await provider.client.auth.user()
        try Task.checkCancellation()
        return user.id
    }

    func select<Response: Decodable & Sendable>(
        _ request: WorkspaceSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        var query = provider.client
            .from(request.table)
            .select(request.columns)
        for filter in request.equalityFilters {
            query = query.eq(filter.column, value: filter.value)
        }
        if request.singleRow {
            return try await query.single().execute().value
        }
        return try await query.execute().value
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: WorkspaceUpdateRequest<Patch>,
        as: Response.Type
    ) async throws -> Response {
        var query = try provider.client.from(request.table).update(request.patch)
        for filter in request.equalityFilters {
            query = query.eq(filter.column, value: filter.value)
        }
        let returning = query.select(request.columns)
        if request.singleRow {
            return try await returning.single().execute().value
        }
        return try await returning.execute().value
    }
}
