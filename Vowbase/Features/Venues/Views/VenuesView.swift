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
    @Binding var isNoteEditing: Bool
    /// Owned by `WeddingAppShell`, not this view — the shell needs to know
    /// when this stack has drilled past its root so it can hide the
    /// console's own header and grabber for the pushed detail screen.
    @Binding var path: NavigationPath
    @State private var statusFilter: VenueStatusFilter = .all
    @State private var showsFilter = false

    private var visibleVenues: [MVPVenue] {
        store.venues.filter { statusFilter == .all || $0.status == statusFilter.status }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.venues.isEmpty {
                        VenuesEmptyState(onAddVenue: onAddVenue, onReturnToMap: onReturnToMap)
                    } else {
                        HStack(spacing: 10) {
                            Text("Shortlist")
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .foregroundStyle(VowbaseTheme.ink)
                            Text("· \(visibleVenues.count)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(VowbaseTheme.rose)

                            Spacer(minLength: 8)

                            Button { showsFilter = true } label: {
                                Label(statusFilter.compactTitle, systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(VowbaseTheme.rose)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 42)
                                    .background(VowbaseTheme.background, in: Capsule())
                                    .overlay(Capsule().stroke(VowbaseTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)

                        if visibleVenues.isEmpty {
                            ContentUnavailableView("No venues match", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try a different status filter."))
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
                VenueDetailView(venue: venue, store: store, isNoteEditing: $isNoteEditing)
            }
            .sheet(isPresented: $showsFilter) {
                VenueFilterSheet(selection: $statusFilter)
                    .presentationDetents([.height(380)])
            }
        }
    }
}

private enum VenueStatusFilter: String, CaseIterable, Identifiable {
    case all, considering, contacted, toured, shortlisted, negotiating, booked, passed
    var id: String { rawValue }
    var title: String { self == .all ? "All statuses" : rawValue.capitalized }
    var compactTitle: String { self == .all ? "Filter" : rawValue.capitalized }
    var status: VenueStatus? { VenueStatus(rawValue: rawValue) }
}

private struct CompactVenueRow: View {
    let venue: MVPVenue

    var body: some View {
        HStack(spacing: 12) {
            VowbaseVenueImage(url: venue.photoURL)
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
            .foregroundStyle(VowbaseTheme.rose)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VowbaseTheme.blush, in: Capsule())
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

private struct VenueFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: VenueStatusFilter

    var body: some View {
        NavigationStack {
            List(VenueStatusFilter.allCases) { item in
                Button {
                    selection = item
                    dismiss()
                } label: {
                    HStack {
                        Text(item.title)
                        Spacer()
                        if item == selection { Image(systemName: "checkmark").foregroundStyle(VowbaseTheme.rose) }
                    }
                }
                .foregroundStyle(VowbaseTheme.ink)
            }
            .navigationTitle("Venue status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
