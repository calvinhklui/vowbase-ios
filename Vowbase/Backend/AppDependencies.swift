import Foundation

struct AppDependencies: Sendable {
    let supabase: SupabaseProvider
    let auth: any AuthServicing
    let api: any VowbaseAPIClientProtocol
    let repositories: RepositoryContainer

    init(
        supabase: SupabaseProvider,
        auth: any AuthServicing,
        api: any VowbaseAPIClientProtocol
    ) {
        self.supabase = supabase
        self.auth = auth
        self.api = api
        repositories = RepositoryContainer(supabase: supabase, api: api)
    }

    static func live(configuration: AppConfiguration) -> AppDependencies {
        live(
            configuration: configuration,
            makeSupabase: { SupabaseProvider(configuration: $0) },
            makeAuth: { AuthService(provider: $0) },
            makeAPI: { configuration, auth in
                VowbaseAPIClient(
                    sessionConfiguration: .default,
                    configuration: configuration,
                    authService: auth
                )
            }
        )
    }

    static func live(
        configuration: AppConfiguration,
        makeSupabase: @Sendable (AppConfiguration) -> SupabaseProvider,
        makeAuth: @Sendable (SupabaseProvider) -> any AuthServicing,
        makeAPI: @Sendable (
            AppConfiguration,
            any AuthServicing
        ) -> any VowbaseAPIClientProtocol
    ) -> AppDependencies {
        let supabase = makeSupabase(configuration)
        let auth = makeAuth(supabase)
        let api = makeAPI(configuration, auth)
        return AppDependencies(supabase: supabase, auth: auth, api: api)
    }
}
