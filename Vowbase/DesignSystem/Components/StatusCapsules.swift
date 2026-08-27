import SwiftUI

struct StatusCapsule: View {
    let status: VenueStatus
    var body: some View {
        Text(status.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(status.badgeColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(status.badgeColor.opacity(0.16), in: Capsule())
    }
}

extension VenueStatus {
    var badgeColor: Color {
        switch self {
        case .considering: Color(uiColor: .systemOrange)
        case .contacted: Color(uiColor: .systemBlue)
        case .toured: Color(uiColor: .systemIndigo)
        case .shortlisted: Color(uiColor: .systemTeal)
        case .negotiating: Color(uiColor: .systemBrown)
        case .booked: Color(uiColor: .systemGreen)
        case .passed: Color(uiColor: .secondaryLabel)
        }
    }
}

struct RSVPStatusCapsule: View {
    let status: RSVPStatus
    var body: some View {
        Text(status.title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(status == .notInvited ? VowbaseTheme.mutedInk : VowbaseTheme.rose)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(status == .notInvited ? VowbaseTheme.border.opacity(0.55) : VowbaseTheme.blush, in: Capsule())
    }
}
