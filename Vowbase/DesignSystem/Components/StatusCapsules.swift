import SwiftUI

struct StatusCapsule: View {
    let status: VenueStatus
    var body: some View {
        Text(status.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(VowbaseTheme.rose)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(VowbaseTheme.blush, in: Capsule())
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
