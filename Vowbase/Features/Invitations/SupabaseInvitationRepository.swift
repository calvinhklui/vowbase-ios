import Foundation
import Supabase

final class SupabaseInvitationRepository: InvitationRepository, @unchecked Sendable {
    private static let invitationColumns =
        "id,wedding_id,email,role,status,expires_at,invited_by,accepted_at,created_at,token"

    private let database: any InvitationDatabaseAdapter

    convenience init(provider: SupabaseProvider) {
        self.init(database: SupabaseInvitationDatabaseAdapter(provider: provider))
    }

    init(database: any InvitationDatabaseAdapter) {
        self.database = database
    }

    func preview(token: String) async throws -> InvitationPreview {
        do {
            try Task.checkCancellation()
            let previews: [InvitationPreview] = try await database.rpc(
                .init(functionName: "lookup_invitation", token: token),
                as: [InvitationPreview].self
            )
            guard let preview = previews.first else {
                throw PostgrestError(code: "PGRST116", message: "Invitation not found")
            }
            try Task.checkCancellation()
            return preview
        } catch {
            throw Self.normalized(error)
        }
    }

    func accept(token: String) async throws -> UUID {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let weddingID: UUID = try await database.rpc(
                .init(functionName: "accept_invitation", token: token),
                as: UUID.self
            )
            try Task.checkCancellation()
            return weddingID
        } catch {
            throw Self.normalized(error)
        }
    }

    func invitations(weddingID: UUID) async throws -> [WeddingInvitation] {
        do {
            try Task.checkCancellation()
            _ = try await database.authenticatedUserID()
            let request = InvitationSelectRequest(
                table: "wedding_invitations",
                columns: Self.invitationColumns,
                equalityFilters: [
                    .init(column: "wedding_id", value: weddingID.uuidString.lowercased()),
                ],
                orders: [.init(column: "created_at", ascending: false)],
                singleRow: false
            )
            let invitations: [WeddingInvitation] = try await database.select(
                request,
                as: [WeddingInvitation].self
            )
            try Task.checkCancellation()
            return invitations
        } catch {
            throw Self.normalized(error)
        }
    }

    private static func normalized(_ error: any Error) -> BackendError {
        RepositoryErrorNormalizer.normalized(error, fallbackMessage: "Invitation request failed.")
    }
}

struct InvitationTokenParameters: Encodable, Sendable {
    let token: String

    private enum CodingKeys: String, CodingKey {
        case token = "_token"
    }
}

private final class SupabaseInvitationDatabaseAdapter: InvitationDatabaseAdapter, @unchecked Sendable {
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
        _ request: InvitationSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        var query = provider.client.from(request.table).select(request.columns)
        for filter in request.equalityFilters {
            query = query.eq(filter.column, value: filter.value)
        }
        guard let firstOrder = request.orders.first else {
            if request.singleRow {
                return try await query.single().execute().value
            }
            return try await query.execute().value
        }
        var ordered = query.order(firstOrder.column, ascending: firstOrder.ascending)
        for order in request.orders.dropFirst() {
            ordered = ordered.order(order.column, ascending: order.ascending)
        }
        if request.singleRow {
            return try await ordered.single().execute().value
        }
        return try await ordered.execute().value
    }

    func rpc<Response: Decodable & Sendable>(
        _ request: InvitationRPCRequest,
        as: Response.Type
    ) async throws -> Response {
        try await provider.client
            .rpc(request.functionName, params: InvitationTokenParameters(token: request.token))
            .execute()
            .value
    }
}

enum RepositoryErrorNormalizer {
    static func normalized(_ error: any Error, fallbackMessage: String) -> BackendError {
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
                return .rateLimited(message: "Authentication rate limit reached.", requestID: nil)
            }
            return .temporarilyUnavailable(
                message: "Authentication is temporarily unavailable.",
                requestID: nil
            )
        }
        if let transport = error as? URLError {
            return transport.code == .cancelled ? .cancelled : .networkUnavailable
        }
        if let postgrest = error as? PostgrestError,
           postgrest.code == "42501" || postgrest.code == "PGRST116" {
            return .forbidden(message: "Forbidden.", requestID: nil)
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .unknown(message: fallbackMessage, requestID: nil)
    }
}
