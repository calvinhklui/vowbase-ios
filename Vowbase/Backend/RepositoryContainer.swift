import Foundation

/// The single composition root for UI-independent wedding domain data. All repositories share
/// the one authenticated SupabaseProvider created by AppDependencies.
struct RepositoryContainer: Sendable {
    let workspace: any WorkspaceRepository
    let profiles: any ProfileRepository
    let invitations: any InvitationRepository
    let guests: any GuestRepository
    let schedule: any ScheduleRepository
    let tasks: any TaskRepository
    let vendors: any VendorRepository
    let budget: any BudgetRepository
    let venues: any VenueRepository
    let inspiration: any InspirationRepository
    let timeline: any TimelineRepository
    let attachments: any AttachmentRepository
    let maps: any MapWorkflowRepository
    let venuePhotos: any VenuePhotoServicing
    let venuePhotoMutations: any VenuePhotoMutationServicing
    let venueDocuments: any VenueDocumentRepository
    let metrics: any MetricConfigurationRepository

    init(supabase: SupabaseProvider, api: any VowbaseAPIClientProtocol) {
        workspace = SupabaseWorkspaceRepository(provider: supabase, api: api)
        profiles = SupabaseProfileRepository(provider: supabase)
        invitations = SupabaseInvitationRepository(provider: supabase)
        guests = SupabaseGuestRepository(provider: supabase)
        schedule = SupabaseScheduleRepository(provider: supabase)
        tasks = SupabaseTaskRepository(provider: supabase)
        vendors = SupabaseVendorRepository(provider: supabase)
        budget = SupabaseBudgetRepository(provider: supabase)
        let venueRepository = SupabaseVenueRepository(provider: supabase)
        venues = venueRepository
        inspiration = SupabaseInspirationRepository(provider: supabase)
        timeline = SupabaseTimelineRepository(provider: supabase)
        attachments = SupabaseAttachmentRepository(provider: supabase)
        maps = APIMapWorkflowRepository(api: api)
        venuePhotos = VenuePhotoService(api: api) { path in
            try await supabase.client.storage
                .from("venue-photos")
                .createSignedURL(path: path, expiresIn: 60 * 60)
        }
        venuePhotoMutations = VenuePhotoMutationService(
            metadata: SupabaseVenuePhotoMetadataAdapter(
                provider: supabase,
                repository: venueRepository
            ),
            storage: SupabaseVenuePhotoStorageAdapter(provider: supabase)
        )
        venueDocuments = APIVenueDocumentRepository(api: api)
        metrics = SupabaseMetricConfigurationRepository(provider: supabase)
    }
}
