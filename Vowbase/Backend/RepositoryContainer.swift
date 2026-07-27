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
    let attachments: any AttachmentRepository
    let maps: any MapWorkflowRepository

    init(supabase: SupabaseProvider, api: any VowbaseAPIClientProtocol) {
        workspace = SupabaseWorkspaceRepository(provider: supabase, api: api)
        profiles = SupabaseProfileRepository(provider: supabase)
        invitations = SupabaseInvitationRepository(provider: supabase)
        guests = SupabaseGuestRepository(provider: supabase)
        schedule = SupabaseScheduleRepository(provider: supabase)
        tasks = SupabaseTaskRepository(provider: supabase)
        vendors = SupabaseVendorRepository(provider: supabase)
        budget = SupabaseBudgetRepository(provider: supabase)
        venues = SupabaseVenueRepository(provider: supabase)
        inspiration = SupabaseInspirationRepository(provider: supabase)
        attachments = SupabaseAttachmentRepository(provider: supabase)
        maps = APIMapWorkflowRepository(api: api)
    }
}
