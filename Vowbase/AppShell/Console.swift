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

    /// Peek has to fit everything the console stacks at rest, or its content
    /// runs underneath the lens rail — which is what made the rail look like
    /// it was covering every lens. The arithmetic, top to bottom:
    ///
    ///     27  grabber (22 pt of clearance + a 5 pt capsule)
    ///     14  stack spacing
    ///     50  header — two lines for a selected venue and its impact row
    ///     14  stack spacing
    ///    104  the tallest rail card
    ///      8  breathing room
    ///     86  lens rail (70 pt tall, 16 pt of padding)
    ///
    /// Anything added to the console's resting stack has to be paid for here.
    static let peekHeight: CGFloat = 303

    var presentationDetent: PresentationDetent {
        switch self {
        case .peek: .height(Self.peekHeight)
        case .half: .fraction(0.5)
        // Deliberately not .large: that system detent reserves a visible
        // gap at the top as an affordance. There's nothing under the
        // console worth keeping visible once you've dragged this far, so
        // .full covers the context bar too rather than peeking it out.
        case .full: .fraction(1.0)
        }
    }

    /// The console's resolved height in points, given the screen height it's
    /// measured against — `.half`/`.full` are screen fractions.
    func pointHeight(in screenHeight: CGFloat) -> CGFloat {
        switch self {
        case .peek: Self.peekHeight
        case .half: screenHeight * 0.5
        case .full: screenHeight
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

    /// No selection: the Guests lens's own state at a glance.
    init(guests: [Guest]) {
        title = "Guests"
        trailing = "\(guests.count) guest\(guests.count == 1 ? "" : "s")"
        let counts = Dictionary(grouping: guests, by: { $0.rsvpStatus ?? .notInvited }).mapValues(\.count)
        let ordered: [RSVPStatus] = [.accepted, .maybe, .pending, .declined, .notInvited]
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

// MARK: - Venue impact header (selected venue)

/// The header for a selected venue: name and status on the first line, the
/// impact readout (spec §8) on the second — replacing `ConsoleHeader`'s
/// plain-string subline, since this row needs its own tap target and a
/// per-state layout, not just a different string.
struct VenueImpactHeader: View {
    let venue: MVPVenue
    let impact: TravelImpactState
    let onTapReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(venue.name)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(venue.status.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            VenueImpactRow(state: impact, onTap: onTapReadout)
        }
    }
}

/// The readout row itself, spec §8 and §8.1. Every non-idle, non-loading
/// state is a tap target: a real number routes to the guests it describes,
/// an unavailable one routes to its own fix.
struct VenueImpactRow: View {
    let state: TravelImpactState
    let onTap: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Calculating guest travel…")
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .font(.system(size: 14))
        case let .unavailable(reason):
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text(reason.message)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if reason == .requestFailed {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VowbaseTheme.rose)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
        case let .ready(readout):
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(VowbaseTheme.rose)
                        .frame(width: 7, height: 7)
                    Text(readout.summaryText)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                    if readout.isEstimated {
                        Text("Est.")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(VowbaseTheme.border.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
        }
    }
}

private extension TravelUnavailableReason {
    var message: String {
        switch self {
        case .venueMissingCoordinate:
            "Add this venue's location to see guest travel"
        case .noMappableGuests:
            "No guest locations yet — add some to see travel"
        case .requestFailed:
            "Guest travel unavailable"
        }
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
                .frame(width: 88, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineLimit(1)
                StatusCapsule(status: venue.status)
                if let travel = venue.travel {
                    Label("\(travel) median guest travel", systemImage: "airplane")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(width: 260, height: 104)
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
            VStack(alignment: .leading, spacing: 4) {
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
            }
        }
        .padding(14)
        // Width is intentionally unset — a fixed width stretched every card
        // to the same size regardless of name length, which centered short
        // content (avatar included) inside the leftover space instead of
        // letting it sit flush against the leading edge.
        .frame(height: 78)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
