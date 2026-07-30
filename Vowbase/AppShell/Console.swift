import SwiftUI

// MARK: - Console detents

/// The console's three stops, wrapping `PresentationDetent` so the shell can
/// also reason about the resolved point height for camera insets and FAB
/// placement — `PresentationDetent` itself is an opaque value type and can't
/// be pattern-matched back apart. See spec §7.1.
///
/// SwiftUI has no API for a sheet's live drag position, only its settled
/// detent. Camera insets and the FAB therefore snap to whichever detent the
/// console has come to rest at, rather than tracking the drag continuously.
enum ConsoleDetent: CaseIterable {
    case peek
    case half
    case full

    var presentationDetent: PresentationDetent {
        switch self {
        case .peek: .height(256)
        case .half: .fraction(0.5)
        case .full: .fraction(0.94)
        }
    }

    /// The console's resolved height in points, given the screen height it's
    /// measured against — `.half`/`.full` are screen fractions.
    func pointHeight(in screenHeight: CGFloat) -> CGFloat {
        switch self {
        case .peek: 256
        case .half: screenHeight * 0.5
        case .full: screenHeight * 0.94
        }
    }
}

// MARK: - Selection-aware header

/// The console's header, two lines, 16 pt insets. Shows the lens's state at a
/// glance with nothing selected, or the selected object and its consequence
/// otherwise. See spec §7.2.
///
/// The impact readout (§8) isn't wired yet — Phase 4 — so a selected venue's
/// second line shows its location rather than a fabricated travel figure.
struct ConsoleHeader: View {
    let title: String
    let trailing: String?
    let subline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            if let subline {
                Text(subline)
                    .font(.system(size: 14))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .lineLimit(1)
            }
        }
    }
}

extension ConsoleHeader {
    /// No venue selected: the lens's own state at a glance.
    init(venues: [MVPVenue]) {
        title = "Venues"
        trailing = "\(venues.count) venue\(venues.count == 1 ? "" : "s")"
        let counts = Dictionary(grouping: venues, by: \.status).mapValues(\.count)
        let ordered: [VenueStatus] = [.toured, .negotiating, .shortlisted, .considering, .contacted, .booked, .suggested, .passed]
        let parts = ordered.compactMap { status -> String? in
            guard let count = counts[status], count > 0 else { return nil }
            return "\(count) \(status.title.lowercased())"
        }
        subline = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A venue selected: the object, then its secondary line. The impact
    /// readout replaces `subline` once Phase 4 wires `travelTimes`.
    init(selectedVenue venue: MVPVenue) {
        title = venue.name
        trailing = venue.status.title
        subline = venue.location
    }

    /// No selection: the Guests lens's own state at a glance.
    init(guests: [Guest]) {
        title = "Guests"
        trailing = "\(guests.count) guest\(guests.count == 1 ? "" : "s")"
        let counts = Dictionary(grouping: guests, by: { $0.rsvpStatus ?? .notInvited }).mapValues(\.count)
        let ordered: [RSVPStatus] = [.accepted, .pending, .declined, .notInvited]
        let parts = ordered.compactMap { status -> String? in
            guard let count = counts[status], count > 0 else { return nil }
            return "\(count) \(status.title.lowercased())"
        }
        subline = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Tasks has no map selection to reflect — always its own state at a glance.
    init(openTaskCount: Int, dueSoonCount: Int) {
        title = "Tasks"
        trailing = "\(openTaskCount) open"
        subline = dueSoonCount > 0 ? "\(dueSoonCount) due this week" : nil
    }
}

// MARK: - Venue rail (peek)

/// The peek-detent card rail, shared by the Overview lens and the Venues
/// lens's own peek state — both show the same shortlist. Redesigned per
/// spec §7.3: two facts instead of four, location dropped because the card
/// is anchored to a pin already on screen.
struct VenueRailContent: View {
    let store: VowbaseWorkspaceStore

    var body: some View {
        if store.venues.isEmpty {
            Text("Add a venue to start your shortlist.")
                .font(.system(size: 16))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.venues) { venue in
                        Button { store.selectedVenueID = venue.id } label: {
                            VenueRailCard(venue: venue, selected: venue.id == store.selectedVenueID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .contentMargins(.trailing, 18, for: .scrollContent)
        }
    }
}

private struct VenueRailCard: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            VowbaseVenueImage(url: venue.coverPhotoURL)
                .frame(width: 104, height: 132)
            VStack(alignment: .leading, spacing: 8) {
                Text(venue.name)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .lineLimit(2)
                StatusCapsule(status: venue.status)
                Spacer(minLength: 0)
                Label("\(venue.travel) median guest travel", systemImage: "airplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(width: 268, height: 132)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? VowbaseTheme.rose : VowbaseTheme.border, lineWidth: selected ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

// MARK: - Guest rail (peek)

/// The Guests lens's own peek state: avatar, name, RSVP, and the wedding's
/// chosen subtitle column — the same display resolver the Guests list uses.
struct GuestRailContent: View {
    let store: VowbaseWorkspaceStore

    var body: some View {
        let guests = store.guests
        if guests.isEmpty {
            Text("Add a guest to start your list.")
                .font(.system(size: 16))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(guests) { guest in
                        GuestRailCard(guest: guest)
                    }
                }
                .padding(.horizontal, 18)
            }
            .contentMargins(.trailing, 18, for: .scrollContent)
        }
    }
}

private struct GuestRailCard: View {
    let guest: MVPGuest

    var body: some View {
        HStack(spacing: 12) {
            Text(guest.initials)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .frame(width: 46, height: 46)
                .background(VowbaseTheme.blush, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(guest.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)
                if let subtitle = guest.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }
                RSVPStatusCapsule(status: guest.rsvp)
            }
        }
        .padding(14)
        .frame(width: 240, height: 96)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
