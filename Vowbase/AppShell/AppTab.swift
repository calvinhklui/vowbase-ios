import SwiftUI

/// The primary destinations in the authenticated wedding workspace.
///
/// `AppTab` deliberately owns only presentation metadata. Feature-specific
/// state belongs to the feature that renders each tab.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case map
    case venues
    case guests
    case tasks

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .map: "Map"
        case .venues: "Venues"
        case .guests: "Guests"
        case .tasks: "Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .venues: "mappin"
        case .guests: "person.2"
        case .tasks: "checklist"
        }
    }
}
