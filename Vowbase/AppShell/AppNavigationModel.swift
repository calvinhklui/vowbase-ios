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
/// tab content. Views that need bindings should declare `@Bindable var
/// navigation: AppNavigationModel` and bind directly to `selectedTab`, a tab
/// path, or `sheetDestination`. `selectVenueOnMap(_:)` is the canonical route
/// from a list/detail to a focused map marker; `clearMapFocus()` acknowledges
/// that request after Map has applied it.
@MainActor
@Observable
final class AppNavigationModel {
    /// The currently visible root tab. The map remains the default workspace.
    var selectedTab: AppTab

    /// Independent navigation stacks preserve each tab's drill-in state.
    var mapPath = NavigationPath()
    var venuesPath = NavigationPath()
    var guestsPath = NavigationPath()

    /// The one modal task currently presented by the app shell, if any.
    var sheetDestination: SheetDestination?

    /// A venue Map should focus the next time it becomes visible.
    ///
    /// This remains set until `clearMapFocus()` is called so a Map view can
    /// consume it after it has appeared following a tab change.
    var focusedVenueID: UUID?

    init(selectedTab: AppTab = .map) {
        self.selectedTab = selectedTab
    }

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
        sheetDestination = nil
    }

    func present(_ destination: SheetDestination) {
        sheetDestination = destination
    }

    func dismissSheet() {
        sheetDestination = nil
    }

    /// Routes to Map and requests that it select and reveal `venueID`.
    func selectVenueOnMap(_ venueID: UUID) {
        selectedTab = .map
        mapPath = NavigationPath()
        sheetDestination = nil
        focusedVenueID = venueID
    }

    /// Clears a Map focus request after the Map has selected the venue.
    func clearMapFocus() {
        focusedVenueID = nil
    }

    /// Clears presentation-only state while leaving the user's tab and
    /// navigation history intact.
    func clearTransientState() {
        sheetDestination = nil
        focusedVenueID = nil
    }

    /// Returns one tab to its root without disturbing the other tabs.
    func resetNavigation(for tab: AppTab) {
        switch tab {
        case .map:
            mapPath = NavigationPath()
        case .venues:
            venuesPath = NavigationPath()
        case .guests:
            guestsPath = NavigationPath()
        }
    }
}
