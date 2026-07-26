import Foundation
import Supabase

final class SupabaseProfileRepository: ProfileRepository, @unchecked Sendable {
    private static let profileColumns = "id,email,full_name,first_name,last_name,avatar_url"

    private let database: any ProfileDatabaseAdapter

    convenience init(provider: SupabaseProvider) {
        self.init(database: SupabaseProfileDatabaseAdapter(provider: provider))
    }

    init(database: any ProfileDatabaseAdapter) {
        self.database = database
    }

    func currentProfile() async throws -> Profile {
        do {
            try Task.checkCancellation()
            let userID = try await database.authenticatedUserID()
            let profile: Profile = try await database.select(
                Self.profileRequest(userID: userID),
                as: Profile.self
            )
            try Task.checkCancellation()
            return profile
        } catch {
            throw Self.normalized(error)
        }
    }

    func updateCurrentProfile(_ patch: ProfilePatch) async throws -> Profile {
        do {
            try Task.checkCancellation()
            let userID = try await database.authenticatedUserID()
            let request = ProfileUpdateRequest(
                table: "profiles",
                columns: Self.profileColumns,
                equalityFilters: Self.userScope(userID),
                singleRow: true,
                patch: patch
            )
            let profile: Profile = try await database.update(request, as: Profile.self)
            try Task.checkCancellation()
            return profile
        } catch {
            throw Self.normalized(error)
        }
    }

    private static func profileRequest(userID: UUID) -> ProfileSelectRequest {
        ProfileSelectRequest(
            table: "profiles",
            columns: profileColumns,
            equalityFilters: userScope(userID),
            singleRow: true
        )
    }

    private static func userScope(_ userID: UUID) -> [ProfileEqualityFilter] {
        [.init(column: "id", value: userID.uuidString.lowercased())]
    }

    private static func normalized(_ error: any Error) -> BackendError {
        RepositoryErrorNormalizer.normalized(error, fallbackMessage: "Profile request failed.")
    }
}

private final class SupabaseProfileDatabaseAdapter: ProfileDatabaseAdapter, @unchecked Sendable {
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
        _ request: ProfileSelectRequest,
        as: Response.Type
    ) async throws -> Response {
        var query = provider.client.from(request.table).select(request.columns)
        for filter in request.equalityFilters {
            query = query.eq(filter.column, value: filter.value)
        }
        if request.singleRow {
            return try await query.single().execute().value
        }
        return try await query.execute().value
    }

    func update<Response: Decodable & Sendable, Patch: Encodable & Sendable>(
        _ request: ProfileUpdateRequest<Patch>,
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
