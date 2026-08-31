import Foundation
import Supabase

protocol MetricConfigurationRepository: Sendable {
    func configuration(
        weddingID: UUID,
        surface: MetricConfigurationSurface
    ) async throws -> SharedMetricConfiguration?
    func update(
        _ configuration: SharedMetricConfiguration,
        tiles: [SharedMetricTile]
    ) async throws -> SharedMetricConfiguration
    func seedIfMissing(
        weddingID: UUID,
        surface: MetricConfigurationSurface,
        tiles: [SharedMetricTile]
    ) async throws -> SharedMetricConfiguration
}

final class SupabaseMetricConfigurationRepository: MetricConfigurationRepository, @unchecked Sendable {
    private let provider: SupabaseProvider
    private let columns = "id,wedding_id,user_id,surface,tiles,schema_version,revision,updated_by,updated_at"

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func configuration(
        weddingID: UUID,
        surface: MetricConfigurationSurface
    ) async throws -> SharedMetricConfiguration? {
        try await run {
            let user = try await self.provider.client.auth.user()
            let rows: [SharedMetricConfiguration] = try await self.provider.client
                .from("metric_configurations")
                .select(self.columns)
                .eq("wedding_id", value: DomainRepositorySupport.uuid(weddingID))
                .eq("user_id", value: DomainRepositorySupport.uuid(user.id))
                .eq("surface", value: surface.rawValue)
                .execute()
                .value
            return rows.first
        }
    }

    func update(
        _ configuration: SharedMetricConfiguration,
        tiles: [SharedMetricTile]
    ) async throws -> SharedMetricConfiguration {
        try await run {
            let user = try await self.provider.client.auth.user()
            let payload = MetricConfigurationUpdate(
                tiles: tiles,
                schemaVersion: 1,
                revision: configuration.revision + 1,
                updatedBy: user.id
            )
            return try await self.provider.client
                .from("metric_configurations")
                .update(payload)
                .eq("id", value: DomainRepositorySupport.uuid(configuration.id))
                .eq("wedding_id", value: DomainRepositorySupport.uuid(configuration.weddingID))
                .eq("user_id", value: DomainRepositorySupport.uuid(configuration.userID))
                .eq("surface", value: configuration.surface.rawValue)
                .eq("revision", value: String(configuration.revision))
                .select(self.columns)
                .single()
                .execute()
                .value
        }
    }

    func seedIfMissing(
        weddingID: UUID,
        surface: MetricConfigurationSurface,
        tiles: [SharedMetricTile]
    ) async throws -> SharedMetricConfiguration {
        try await run {
            let user = try await self.provider.client.auth.user()
            let seed = MetricConfigurationSeed(
                weddingID: weddingID,
                userID: user.id,
                surface: surface,
                tiles: tiles,
                updatedBy: user.id
            )
            do {
                return try await self.provider.client
                    .from("metric_configurations")
                    .insert(seed)
                    .select(self.columns)
                    .single()
                    .execute()
                    .value
            } catch {
                if let existing = try await self.configuration(weddingID: weddingID, surface: surface) {
                    return existing
                }
                throw error
            }
        }
    }

    private func run<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            try await DomainRepositorySupport.authenticated(provider)
            return try await body()
        } catch {
            throw DomainRepositorySupport.normalized(error, fallback: "Metrics request failed.")
        }
    }
}

private struct MetricConfigurationUpdate: Codable, Sendable {
    let tiles: [SharedMetricTile]
    let schemaVersion: Int
    let revision: Int
    let updatedBy: UUID

    enum CodingKeys: String, CodingKey {
        case tiles
        case schemaVersion = "schema_version"
        case revision
        case updatedBy = "updated_by"
    }
}

private struct MetricConfigurationSeed: Codable, Sendable {
    let weddingID: UUID
    let userID: UUID
    let surface: MetricConfigurationSurface
    let tiles: [SharedMetricTile]
    let schemaVersion = 1
    let revision = 1
    let updatedBy: UUID

    enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id"
        case userID = "user_id"
        case surface
        case tiles
        case schemaVersion = "schema_version"
        case revision
        case updatedBy = "updated_by"
    }
}
