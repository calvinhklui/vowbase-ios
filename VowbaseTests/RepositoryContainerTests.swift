import Foundation
import Testing
@testable import Vowbase
@Suite("Repository container") struct RepositoryContainerTests {
    @Test("composition accepts the shared provider") func composition() throws {
        let configuration = try AppConfiguration(values:["SUPABASE_URL":"https://supabase.example.invalid","SUPABASE_PUBLISHABLE_KEY":"key","VOWBASE_API_URL":"https://api.example.invalid","CONFIGURATION":"Release"])
        let provider = SupabaseProvider(configuration: configuration)
        let container = RepositoryContainer(supabase: provider, api: ContainerAPI())
        #expect(container.schedule is SupabaseScheduleRepository)
        #expect(container.inspiration is SupabaseInspirationRepository)
        #expect(container.attachments is SupabaseAttachmentRepository)
        #expect(container.maps is APIMapWorkflowRepository)
        #expect(container.venueResearch is APIVenueResearchRepository)
        #expect(container.venuePhotos is VenuePhotoService)
    }
}
private struct ContainerAPI: VowbaseAPIClientProtocol { func send<Response>(_ request: APIRequest<Response>) async throws -> Response where Response : Decodable, Response : Sendable { throw BackendError.invalidResponse } }
