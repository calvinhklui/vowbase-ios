import Foundation
import Supabase
import Testing
@testable import Vowbase

@Suite("Workspace repository integration")
struct WorkspaceRepositoryIntegrationTests {
    @Test(
        "dedicated non-production workspace roles honor the repository contract",
        .enabled(if: ProcessInfo.processInfo.environment["VOWBASE_INTEGRATION_ENABLED"] == "1")
    )
    func dedicatedNonProductionWorkspace() async throws {
        let configuration = try WorkspaceIntegrationConfiguration.load()

        let owner = try await signedInClient(for: .owner, configuration: configuration)
        try await assertAuthenticatedRole(
            .owner,
            client: owner,
            configuration: configuration
        )

        await #expect(
            throws: BackendError.forbidden(message: "Forbidden.", requestID: nil)
        ) {
            _ = try await owner.repository.wedding(id: configuration.inaccessibleWeddingID)
        }

        for role in [WorkspaceIntegrationRole.owner, .partner] {
            let client = role == .owner
                ? owner
                : try await signedInClient(for: role, configuration: configuration)
            try await assertAuthenticatedRole(
                role,
                client: client,
                configuration: configuration
            )
            let current = try await client.repository.wedding(id: configuration.testWeddingID)
            let patch = WeddingPatch(
                name: current.name,
                coupleNames: current.coupleNames,
                weddingDate: current.weddingDate.map(NullablePatch.value) ?? .null,
                dateFlexibility: current.dateFlexibility,
                dateRangeStart: current.dateRangeStart.map(NullablePatch.value) ?? .null,
                dateRangeEnd: current.dateRangeEnd.map(NullablePatch.value) ?? .null,
                location: current.location
            )

            let updated = try await client.repository.updateWedding(
                id: configuration.testWeddingID,
                patch: patch
            )
            #expect(updated == current)
        }

        for role in [WorkspaceIntegrationRole.planner, .parent, .viewer] {
            let client = try await signedInClient(for: role, configuration: configuration)
            try await assertAuthenticatedRole(
                role,
                client: client,
                configuration: configuration
            )
            let current = try await client.repository.wedding(id: configuration.testWeddingID)
            let patch = WeddingPatch(
                name: current.name,
                coupleNames: current.coupleNames,
                weddingDate: current.weddingDate.map(NullablePatch.value) ?? .null,
                dateFlexibility: current.dateFlexibility,
                dateRangeStart: current.dateRangeStart.map(NullablePatch.value) ?? .null,
                dateRangeEnd: current.dateRangeEnd.map(NullablePatch.value) ?? .null,
                location: current.location
            )

            await #expect(
                throws: BackendError.forbidden(message: "Forbidden.", requestID: nil),
                "\(role.rawValue) must not update the dedicated test wedding"
            ) {
                _ = try await client.repository.updateWedding(
                    id: configuration.testWeddingID,
                    patch: patch
                )
            }
        }
    }

    private func signedInClient(
        for role: WorkspaceIntegrationRole,
        configuration: WorkspaceIntegrationConfiguration
    ) async throws -> WorkspaceIntegrationClient {
        let provider = SupabaseProvider(configuration: configuration.appConfiguration)
        let credentials = configuration.credentials(for: role)
        _ = try await provider.client.auth.setSession(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken
        )

        let authService = AuthService(provider: provider)
        let api = VowbaseAPIClient(
            sessionConfiguration: .ephemeral,
            configuration: configuration.appConfiguration,
            authService: authService
        )
        return WorkspaceIntegrationClient(
            provider: provider,
            repository: SupabaseWorkspaceRepository(provider: provider, api: api)
        )
    }

    private func assertAuthenticatedRole(
        _ expectedRole: WorkspaceIntegrationRole,
        client: WorkspaceIntegrationClient,
        configuration: WorkspaceIntegrationConfiguration
    ) async throws {
        let authenticatedUser = try await client.provider.client.auth.user()
        let session = try await client.repository.sessionSummary()
        #expect(session.user.id == authenticatedUser.id)

        let memberships = try await client.repository.memberships()
        #expect(memberships.allSatisfy { $0.status == "active" })
        #expect(!memberships.contains { $0.weddingId == configuration.inactiveWeddingID })
        guard let membership = memberships.first(
            where: { $0.weddingId == configuration.testWeddingID }
        ) else {
            throw WorkspaceIntegrationAssertionError.missingTestWeddingMembership(
                expectedRole.rawValue
            )
        }
        #expect(membership.userId == authenticatedUser.id)
        #expect(membership.role == expectedRole.weddingRole)
    }
}

private struct WorkspaceIntegrationClient {
    let provider: SupabaseProvider
    let repository: SupabaseWorkspaceRepository
}

private enum WorkspaceIntegrationRole: String, CaseIterable {
    case owner
    case partner
    case planner
    case parent
    case viewer

    var weddingRole: WeddingRole {
        WeddingRole(rawValue: rawValue)!
    }
}

private enum WorkspaceIntegrationAssertionError: Error {
    case missingTestWeddingMembership(String)
}

private struct WorkspaceIntegrationCredentials {
    let accessToken: String
    let refreshToken: String
}

private struct WorkspaceIntegrationConfiguration {
    let appConfiguration: AppConfiguration
    let testWeddingID: UUID
    let inactiveWeddingID: UUID
    let inaccessibleWeddingID: UUID
    private let roleCredentials: [WorkspaceIntegrationRole: WorkspaceIntegrationCredentials]

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> WorkspaceIntegrationConfiguration {
        let enabled = try required("VOWBASE_INTEGRATION_ENABLED", in: environment)
        guard enabled == "1" else {
            throw WorkspaceIntegrationConfigurationError.invalid("VOWBASE_INTEGRATION_ENABLED")
        }

        let nonProductionEnvironment = try required(
            "VOWBASE_INTEGRATION_ENVIRONMENT",
            in: environment
        )
        guard ["test", "staging"].contains(nonProductionEnvironment.lowercased()) else {
            throw WorkspaceIntegrationConfigurationError.invalid(
                "VOWBASE_INTEGRATION_ENVIRONMENT"
            )
        }

        let supabaseURL = try required("VOWBASE_INTEGRATION_SUPABASE_URL", in: environment)
        let apiURL = try required("VOWBASE_INTEGRATION_API_URL", in: environment)
        let productionSupabaseURL = try required(
            "VOWBASE_PRODUCTION_SUPABASE_URL",
            in: environment
        )
        let productionAPIURL = try required("VOWBASE_PRODUCTION_API_URL", in: environment)
        try requireDistinctURL(
            actual: supabaseURL,
            production: productionSupabaseURL,
            actualKey: "VOWBASE_INTEGRATION_SUPABASE_URL",
            productionKey: "VOWBASE_PRODUCTION_SUPABASE_URL"
        )
        try requireDistinctURL(
            actual: apiURL,
            production: productionAPIURL,
            actualKey: "VOWBASE_INTEGRATION_API_URL",
            productionKey: "VOWBASE_PRODUCTION_API_URL"
        )

        let projectRef = try required(
            "VOWBASE_INTEGRATION_SUPABASE_PROJECT_REF",
            in: environment
        )
        let expectedHost = try required(
            "VOWBASE_INTEGRATION_SUPABASE_HOST",
            in: environment
        )
        try validateSupabaseIdentity(
            url: supabaseURL,
            projectRef: projectRef,
            expectedHost: expectedHost
        )

        let testWeddingID = try requiredUUID(
            "VOWBASE_INTEGRATION_TEST_WEDDING_ID",
            in: environment
        )
        let inactiveWeddingID = try requiredUUID(
            "VOWBASE_INTEGRATION_INACTIVE_WEDDING_ID",
            in: environment
        )
        let inaccessibleWeddingID = try requiredUUID(
            "VOWBASE_INTEGRATION_INACCESSIBLE_WEDDING_ID",
            in: environment
        )
        guard Set([testWeddingID, inactiveWeddingID, inaccessibleWeddingID]).count == 3 else {
            throw WorkspaceIntegrationConfigurationError.invalid(
                "VOWBASE_INTEGRATION_*_WEDDING_ID"
            )
        }

        var credentials = [WorkspaceIntegrationRole: WorkspaceIntegrationCredentials]()
        for role in WorkspaceIntegrationRole.allCases {
            let prefix = "VOWBASE_INTEGRATION_\(role.rawValue.uppercased())"
            credentials[role] = WorkspaceIntegrationCredentials(
                accessToken: try required("\(prefix)_ACCESS_TOKEN", in: environment),
                refreshToken: try required("\(prefix)_REFRESH_TOKEN", in: environment)
            )
        }

        let appConfiguration = try AppConfiguration(
            values: [
                "CONFIGURATION": "Debug",
                "SUPABASE_URL": supabaseURL,
                "SUPABASE_PUBLISHABLE_KEY": try required(
                    "VOWBASE_INTEGRATION_SUPABASE_PUBLISHABLE_KEY",
                    in: environment
                ),
                "VOWBASE_API_URL": apiURL,
            ],
            transportPolicy: .debug
        )
        return WorkspaceIntegrationConfiguration(
            appConfiguration: appConfiguration,
            testWeddingID: testWeddingID,
            inactiveWeddingID: inactiveWeddingID,
            inaccessibleWeddingID: inaccessibleWeddingID,
            roleCredentials: credentials
        )
    }

    func credentials(for role: WorkspaceIntegrationRole) -> WorkspaceIntegrationCredentials {
        // `load` fills every role and rejects missing values before tests can run.
        roleCredentials[role]!
    }

    private static func required(
        _ key: String,
        in environment: [String: String]
    ) throws -> String {
        guard let rawValue = environment[key] else {
            throw WorkspaceIntegrationConfigurationError.missing(key)
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw WorkspaceIntegrationConfigurationError.missing(key)
        }
        return value
    }

    private static func requiredUUID(
        _ key: String,
        in environment: [String: String]
    ) throws -> UUID {
        let value = try required(key, in: environment)
        guard let identifier = UUID(uuidString: value) else {
            throw WorkspaceIntegrationConfigurationError.invalid(key)
        }
        return identifier
    }

    private static func requireDistinctURL(
        actual: String,
        production: String,
        actualKey: String,
        productionKey: String
    ) throws {
        guard let actualURL = normalizedURL(actual),
              let productionURL = normalizedURL(production),
              actualURL != productionURL else {
            throw WorkspaceIntegrationConfigurationError.conflict(
                actualKey: actualKey,
                productionKey: productionKey
            )
        }
    }

    private static func normalizedURL(_ value: String) -> String? {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        if components.port == nil {
            components.port = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        }
        components.path = components.path == "/" ? "" : components.path
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func validateSupabaseIdentity(
        url: String,
        projectRef: String,
        expectedHost: String
    ) throws {
        guard let host = URL(string: url)?.host?.lowercased(),
              host == expectedHost.lowercased(),
              host == "\(projectRef.lowercased()).supabase.co" else {
            throw WorkspaceIntegrationConfigurationError.invalid(
                "VOWBASE_INTEGRATION_SUPABASE_PROJECT_REF or VOWBASE_INTEGRATION_SUPABASE_HOST"
            )
        }
    }
}

private enum WorkspaceIntegrationConfigurationError: Error, Equatable {
    case missing(String)
    case invalid(String)
    case conflict(actualKey: String, productionKey: String)
}
