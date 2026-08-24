import SwiftUI

// MARK: - Venues

/// The Venues lens's half/full console content. Reached by dragging the
/// console up from its peek rail (`VenueRailContent`), not by a tab — see
/// `docs/vowbase-ios-map-command-center-ux-spec.md` §7.4. Its own header is
/// gone; the console's shared, selection-aware header (`ConsoleHeader`)
/// covers it now.
@MainActor
struct VenuesView: View {
    let store: VowbaseWorkspaceStore
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void
    let onViewOnMap: (MVPVenue) -> Void
    @Binding var isNoteEditing: Bool
    /// Owned by `WeddingAppShell`, not this view — the shell needs to know
    /// when this stack has drilled past its root so it can hide the
    /// console's own header and grabber for the pushed detail screen.
    @Binding var path: NavigationPath
    @State private var selectedStatus: VenueStatus?

    private var visibleVenues: [MVPVenue] {
        store.venues.filter { selectedStatus == nil || $0.status == selectedStatus }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.venues.isEmpty {
                        VenuesEmptyState(onAddVenue: onAddVenue, onReturnToMap: onReturnToMap)
                    } else {
                        VenueMetricCards(venues: store.venues, selectedStatus: $selectedStatus)

                        if visibleVenues.isEmpty {
                            VStack(spacing: 12) {
                                ContentUnavailableView(
                                    "No venues match this status",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("Try a different lifecycle status.")
                                )
                                Button("Clear filter") {
                                    selectedStatus = nil
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .tint(VowbaseTheme.rose)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(visibleVenues.enumerated()), id: \.element.id) { index, venue in
                                    NavigationLink(value: venue) {
                                        CompactVenueRow(venue: venue)
                                    }
                                    .buttonStyle(.plain)

                                    if index < visibleVenues.count - 1 {
                                        Divider()
                                            .padding(.leading, 86)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .vowbaseScrollClearance()
            .refreshable {
                await store.load()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: MVPVenue.self) { venue in
                VenueDetailView(
                    venue: venue,
                    store: store,
                    isNoteEditing: $isNoteEditing,
                    onViewOnMap: { onViewOnMap(venue) }
                )
            }
        }
    }
}

private extension VenueStatus {
    static let compactLifecycleOrder: [VenueStatus] = [
        .suggested, .considering, .contacted, .toured,
        .shortlisted, .negotiating, .booked, .passed
    ]
}

private struct VenueMetricCards: View {
    let venues: [MVPVenue]
    @Binding var selectedStatus: VenueStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VowbaseSpace.small) {
                ForEach(VenueStatus.compactLifecycleOrder, id: \.self) { status in
                    let isSelected = selectedStatus == status
                    let count = venues.count(where: { $0.status == status })

                    Button {
                        selectedStatus = isSelected ? nil : status
                    } label: {
                        VenueMetricCard(status: status, venueCount: count, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(status.title), \(count) venue\(count == 1 ? "" : "s")")
                    .accessibilityHint(isSelected ? "Double tap to show all venues" : "Double tap to filter the venue list")
                }
            }
            .padding(.vertical, VowbaseSpace.small)
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedStatus)
    }
}

private struct VenueMetricCard: View {
    let status: VenueStatus
    let venueCount: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: VowbaseSpace.xSmall) {
            Text("\(venueCount)")
                .font(.system(.title2, design: .default, weight: .semibold))
                .foregroundStyle(VowbaseTheme.rose)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(status.title)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(VowbaseTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
        .padding(VowbaseSpace.medium)
        .frame(width: 104, height: 88, alignment: .leading)
        .background(
            isSelected ? VowbaseTheme.blush : VowbaseDesign.surface,
            in: RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous)
                .stroke(isSelected ? VowbaseTheme.rose : VowbaseTheme.border.opacity(0.55), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }
}

private struct CompactVenueRow: View {
    let venue: MVPVenue

    var body: some View {
        HStack(spacing: 12) {
            VowbaseVenueImage(url: venue.photoURL, cacheKey: venue.coverPhotoCacheKey)
                .frame(width: 72, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CompactVenueStatus(status: venue.status)
                    Text(venue.location)
                        .font(.system(size: 13))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label(venue.capacity, systemImage: "person.2")
                    Label(venue.estimate, systemImage: "dollarsign.circle")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CompactVenueStatus: View {
    let status: VenueStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(status.badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.badgeColor.opacity(0.16), in: Capsule())
    }
}

private struct VenuesEmptyState: View {
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 34))
                .foregroundStyle(VowbaseTheme.rose)
                .padding(22)
                .background(VowbaseTheme.blush, in: Circle())

            VStack(spacing: 8) {
                Text("Start your venue shortlist.")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .multilineTextAlignment(.center)
                Text("Add a name, location, capacity, price, and your impressions after each visit — everything you need to build a shortlist and choose the right place.")
                    .font(.system(size: 15))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button("Add venue", action: onAddVenue)
                    .buttonStyle(VowbasePrimaryButtonStyle())
                Button("Return to Map", action: onReturnToMap)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.rose)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}
