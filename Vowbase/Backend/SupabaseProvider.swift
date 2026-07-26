import Foundation
import Supabase

final class SupabaseProvider: Sendable {
    let client: SupabaseClient

    init(
        configuration: AppConfiguration,
        makeClient: @Sendable (URL, String) -> SupabaseClient = {
            SupabaseClient(supabaseURL: $0, supabaseKey: $1)
        }
    ) {
        client = makeClient(
            configuration.supabaseURL,
            configuration.supabasePublishableKey
        )
    }
}
