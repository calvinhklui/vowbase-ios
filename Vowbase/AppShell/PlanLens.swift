import SwiftUI

/// The primary destinations in the authenticated wedding workspace.
///
/// `PlanLens` deliberately owns only presentation metadata. Feature-specific
/// state belongs to the feature that renders each lens.
///
/// This replaces `AppTab`. Where `AppTab` was a plain tab identifier, a lens
/// is a point of view onto one shared canvas: selecting one aims the map and
/// fills the console, rather than switching to an unrelated screen. Map/Venues/
/// Guests/Tasks becoming Overview/Venues/Guests/Tasks is a rename, not a fourth
/// destination added to three — Overview is what the Map tab already was, seen
/// as "no lens selected" rather than as a destination of its own. See
/// `docs/vowbase-ios-map-command-center-ux-spec.md` §2, §9.
enum PlanLens: String, CaseIterable, Identifiable, Hashable {
    case overview
    case venues
    case guests
    case tasks

    var id: String { rawValue }

    /// Overview remains a routing destination for internal workflows, but is
    /// intentionally not an end-user lens while the venue-first workspace is
    /// active.
    static let visibleRailCases: [PlanLens] = [.venues, .guests, .tasks]

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .venues: "Venues"
        case .guests: "Guests"
        case .tasks: "Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .venues: "mappin"
        case .guests: "person.2"
        case .tasks: "checklist"
        }
    }

    /// Whether this lens contributes anything to the map canvas.
    ///
    /// A canvas-optional lens draws no annotations, holds no camera authority,
    /// and opens its console at `.full` rather than `.peek` — there is no map
    /// selection for a peek rail to caption. Tasks is the first of these;
    /// Budget will be the second. See spec §2.1.
    var isCanvasOptional: Bool {
        switch self {
        case .tasks: true
        case .overview, .venues, .guests: false
        }
    }
}
