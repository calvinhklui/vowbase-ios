import SwiftUI

// MARK: - Venues

/// The Venues lens content stays mounted as the console moves through its
/// detents. Its own header is gone; the console's shared, selection-aware
/// header (`ConsoleHeader`) covers it instead.
@MainActor
struct VenuesView: View {
    let store: VowbaseWorkspaceStore
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void
    let onViewOnMap: (MVPVenue) -> Void
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
    @Binding var isNoteEditing: Bool
    /// Owned by `WeddingAppShell`, not this view — the shell needs to know
    /// when this stack has drilled past its root so it can hide the
    /// console's own header and grabber for the pushed detail screen.
    @Binding var path: NavigationPath
    @State private var selectedStatus: VenueStatus?
    @State private var query = ""
    @State private var sort: VenueSortOrder = .lastUpdated

    private var visibleVenues: [MVPVenue] {
        store.filteredVenues(searchText: query, status: selectedStatus, sort: sort)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ConsoleHeader(venues: store.venues)
                        .padding(.bottom, 10)

                    if !store.venues.isEmpty {
                        VenueMetricPills(venues: store.venues, selectedStatus: $selectedStatus)
                    }

                    toolRow
                        .padding(.top, 10)

                    Group {
                        if store.venues.isEmpty {
                            VenuesEmptyState(onAddVenue: onAddVenue, onReturnToMap: onReturnToMap)
                        } else if visibleVenues.isEmpty {
                            noResults
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
                    .padding(.top, 18)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .consoleVerticalScrollHandoff(
                allowsVerticalScrolling: allowsVerticalScrolling,
                onExpand: onRequestExpansion,
                onCollapse: onRequestCollapse
            )
            .scrollDismissesKeyboard(.immediately)
            .vowbaseScrollClearance()
            .navigationBarHidden(true)
            .navigationDestination(for: MVPVenue.self) { venue in
                VenueDetailView(
                    venue: venue,
                    store: store,
                    isNoteEditing: $isNoteEditing,
                    onViewOnMap: { onViewOnMap(venue) },
                    allowsVerticalScrolling: allowsVerticalScrolling,
                    onRequestExpansion: onRequestExpansion,
                    onRequestCollapse: onRequestCollapse
                )
            }
        }
    }

    // MARK: Controls

    private var toolRow: some View {
        HStack(spacing: 4) {
            CompactConsoleSearchField(placeholder: "Search venues", text: $query)

            Menu {
                Picker("Filter by status", selection: $selectedStatus) {
                    Text("All statuses").tag(VenueStatus?.none)
                    ForEach(VenueStatus.compactLifecycleOrder, id: \.self) { status in
                        Text(status.title).tag(Optional(status))
                    }
                }
            } label: {
                CompactConsoleCircleControl(
                    systemImage: "line.3.horizontal.decrease",
                    isActive: selectedStatus != nil
                )
            }
            .accessibilityLabel(selectedStatus.map { "Filter, \($0.title)" } ?? "Filter")

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(VenueSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                CompactConsoleCircleControl(systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                selectedStatus == nil ? "No venues match \u{201c}\(query)\u{201d}" : "No venues match these filters",
                systemImage: selectedStatus == nil ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                description: Text(noResultsDescription)
            )
            Button("Clear filters") {
                query = ""
                selectedStatus = nil
            }
            .font(.system(size: 16, weight: .semibold))
            .tint(VowbaseTheme.rose)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var noResultsDescription: String {
        if selectedStatus != nil {
            return "Try a different lifecycle status or search."
        }
        return "Search covers venue names, status, locations, and contact details."
    }
}

private extension VenueStatus {
    static let compactLifecycleOrder: [VenueStatus] = [
        .suggested, .considering, .contacted, .toured,
        .shortlisted, .negotiating, .booked, .passed
    ]
}

private struct VenueMetricPills: View {
    let venues: [MVPVenue]
    @Binding var selectedStatus: VenueStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VenueStatus.compactLifecycleOrder, id: \.self) { status in
                    let isSelected = selectedStatus == status
                    let count = venues.count(where: { $0.status == status })

                    Button {
                        selectedStatus = isSelected ? nil : status
                    } label: {
                        CompactMetricFilterPill(
                            count: count,
                            title: status.title,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(status.title), \(count) venue\(count == 1 ? "" : "s")")
                    .accessibilityHint(isSelected ? "Double tap to show all venues" : "Double tap to filter the venue list")
                }
            }
        }
        .scrollDisabled(false)
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedStatus)
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
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CompactVenueStatus(status: venue.status)
                    Text(venue.rowSecondaryText)
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
