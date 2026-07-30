import Observation
import SwiftUI

/// A sheet that can be presented from the authenticated wedding workspace.
///
/// Associated values are raw identifiers so this app-shell layer remains
/// independent of feature model types.
enum SheetDestination: Identifiable, Hashable {
    case addVenue
    case addGuest
    case editVenue(UUID)
    case editGuest(UUID)
    case venueFilters
    case guestFilters
    case shortlist

    var id: String {
        switch self {
        case .addVenue:
            "add-venue"
        case .addGuest:
            "add-guest"
        case let .editVenue(venueID):
            "edit-venue-\(venueID.uuidString)"
        case let .editGuest(guestID):
            "edit-guest-\(guestID.uuidString)"
        case .venueFilters:
            "venue-filters"
        case .guestFilters:
            "guest-filters"
        case .shortlist:
            "shortlist"
        }
    }
}

/// Shared routing and transient presentation state for the authenticated app.
///
/// ## Shell integration
/// Create this model in `WeddingAppShell` with `@State`, then pass it to the
/// lens content. Views that need bindings should declare `@Bindable var
/// navigation: AppNavigationModel` and bind directly to `selectedLens`, a lens
/// path, or `sheetDestination`. `selectVenueOnMap(_:)` is the canonical route
/// from a list/detail to a focused map marker; `clearMapFocus()` acknowledges
/// that request after Overview has applied it.
@MainActor
@Observable
final class AppNavigationModel {
    /// The currently visible lens. Overview — the map — remains the default.
    var selectedLens: PlanLens

    /// Independent navigation stacks preserve each lens's drill-in state.
    var overviewPath = NavigationPath()
    var venuesPath = NavigationPath()
    var guestsPath = NavigationPath()
    var tasksPath = NavigationPath()

    /// The one modal task currently presented by the app shell, if any.
    var sheetDestination: SheetDestination?

    /// A venue Overview should focus the next time it becomes visible.
    ///
    /// This remains set until `clearMapFocus()` is called so the Overview lens
    /// can consume it after it has appeared following a lens change.
    var focusedVenueID: UUID?

    init(selectedLens: PlanLens = .overview) {
        self.selectedLens = selectedLens
    }

    func selectLens(_ lens: PlanLens) {
        selectedLens = lens
        sheetDestination = nil
    }

    func present(_ destination: SheetDestination) {
        sheetDestination = destination
    }

    func dismissSheet() {
        sheetDestination = nil
    }

    /// Routes to Overview and requests that it select and reveal `venueID`.
    func selectVenueOnMap(_ venueID: UUID) {
        selectedLens = .overview
        overviewPath = NavigationPath()
        sheetDestination = nil
        focusedVenueID = venueID
    }

    /// Clears a map focus request after Overview has selected the venue.
    func clearMapFocus() {
        focusedVenueID = nil
    }

    /// Clears presentation-only state while leaving the user's lens and
    /// navigation history intact.
    func clearTransientState() {
        sheetDestination = nil
        focusedVenueID = nil
    }

    /// Returns one lens to its root without disturbing the others.
    func resetNavigation(for lens: PlanLens) {
        switch lens {
        case .overview:
            overviewPath = NavigationPath()
        case .venues:
            venuesPath = NavigationPath()
        case .guests:
            guestsPath = NavigationPath()
        case .tasks:
            tasksPath = NavigationPath()
        }
    }
}
