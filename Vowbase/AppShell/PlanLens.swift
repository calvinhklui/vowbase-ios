import SwiftUI

/// The primary destinations in the authenticated wedding workspace.
///
/// `PlanLens` deliberately owns only presentation metadata. Feature-specific
/// state belongs to the feature that renders each lens.
///
/// This replaces `AppTab`. A lens is a point of view onto one shared canvas:
/// selecting one aims the map and fills the console rather than switching to
/// an unrelated screen. Overview remains an internal compatibility route, but
/// it is not exposed in the app rail.
enum PlanLens: String, CaseIterable, Identifiable, Hashable {
    case overview
    case venues
    case guests
    case tasks
    case timeline

    var id: String { rawValue }

    static let visibleRailCases: [PlanLens] = [.timeline, .venues, .guests, .tasks]

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .venues: "Venues"
        case .guests: "Guests"
        case .tasks: "Tasks"
        case .timeline: "Timeline"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .venues: "mappin"
        case .guests: "person.2"
        case .tasks: "checklist"
        case .timeline: "clock.arrow.circlepath"
        }
    }

    /// Whether this lens contributes anything to the map canvas.
    ///
    /// A canvas-optional lens draws no annotations, holds no camera authority,
    /// and does not need a map selection for a peek rail to caption. Its
    /// supported console detents remain a per-lens presentation decision in
    /// `WeddingAppShell`. See spec §2.1.
    var isCanvasOptional: Bool {
        switch self {
        case .tasks, .timeline: true
        case .overview, .venues, .guests: false
        }
    }
}
