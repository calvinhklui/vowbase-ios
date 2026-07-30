import SwiftUI
import UIKit

// MARK: - Venues

@MainActor
struct VenuesView: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void
    @State private var mode: VenueMode = .shortlist
    @State private var statusFilter: VenueStatusFilter = .all
    @State private var showsFilter = false
    @State private var comparison: [UUID] = []
    @State private var showsComparison = false

    private var visibleVenues: [MVPVenue] {
        store.venues.filter { statusFilter == .all || $0.status == statusFilter.status }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IdentityBar(weddingTitle: store.weddingTitle, onSignOut: onSignOut)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VENUE SEARCH")
                            .eyebrow()
                        Text("Venues")
                            .displayTitle()
                        Text("\(store.venues.count) venues")
                            .font(.system(size: 18))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                    if store.venues.isEmpty {
                        VenuesEmptyState(onAddVenue: onAddVenue, onReturnToMap: onReturnToMap)
                    } else {
                        HStack(spacing: 12) {
                            Picker("Venue mode", selection: $mode) {
                                ForEach(VenueMode.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)

                            Button { showsFilter = true } label: {
                                Label(statusFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(VowbaseTheme.rose)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 42)
                                    .background(VowbaseTheme.background, in: Capsule())
                                    .overlay(Capsule().stroke(VowbaseTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        if mode == .compare && comparison.count >= 2 {
                            Button {
                                showsComparison = true
                            } label: {
                                Label("Compare \(comparison.count) venues", systemImage: "rectangle.split.3x1")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(VowbasePrimaryButtonStyle())
                        }

                        if visibleVenues.isEmpty {
                            ContentUnavailableView("No venues match", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try a different status filter."))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                        } else {
                            LazyVStack(spacing: 22) {
                                ForEach(visibleVenues) { venue in
                                    if mode == .compare {
                                        Button {
                                            toggleComparison(venue.id)
                                        } label: {
                                            VenueCard(venue: venue, selectedForComparison: comparison.contains(venue.id))
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(value: venue) {
                                            VenueCard(venue: venue, selectedForComparison: false)
                                        }
                                        .buttonStyle(.plain)
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
                VenueDetailView(venue: venue, store: store)
            }
            .sheet(isPresented: $showsFilter) {
                VenueFilterSheet(selection: $statusFilter)
                    .presentationDetents([.height(380)])
            }
            .sheet(isPresented: $showsComparison) {
                VenueComparisonSheet(
                    venues: store.venues.filter { comparison.contains($0.id) }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func toggleComparison(_ id: UUID) {
        if comparison.contains(id) {
            comparison.removeAll { $0 == id }
        } else if comparison.count < 3 {
            comparison.append(id)
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

private struct VenueComparisonSheet: View {
    let venues: [MVPVenue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("At a glance") {
                    ForEach(venues) { venue in
                        VStack(alignment: .leading, spacing: VowbaseSpace.small) {
                            Text(venue.name)
                                .font(VowbaseType.cardTitle)
                                .foregroundStyle(VowbaseTheme.ink)
                            StatusCapsule(status: venue.status)
                            LabeledContent("Capacity", value: venue.capacity)
                            LabeledContent("Estimate", value: venue.estimate)
                            LabeledContent("Guest travel", value: venue.travel)
                        }
                        .padding(.vertical, VowbaseSpace.small)
                    }
                }
            }
            .navigationTitle("Compare venues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(VowbaseTheme.rose)
                }
            }
        }
    }
}

private enum VenueMode: String, CaseIterable, Identifiable {
    case shortlist, compare
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum VenueStatusFilter: String, CaseIterable, Identifiable {
    case all, considering, contacted, toured, shortlisted, negotiating, booked, passed
    var id: String { rawValue }
    var title: String { self == .all ? "All statuses" : rawValue.capitalized }
    var status: VenueStatus? { VenueStatus(rawValue: rawValue) }
}

private struct VenueCard: View {
    let venue: MVPVenue
    let selectedForComparison: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VowbaseVenueImage(url: venue.photoURL)
                    .frame(height: 205)
                if selectedForComparison {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, VowbaseTheme.rose)
                        .padding(14)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(venue.name)
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                StatusCapsule(status: venue.status)
                HStack {
                    Label(venue.location, systemImage: "mappin.and.ellipse")
                    Spacer()
                    Label("Map location", systemImage: "map")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VowbaseTheme.mutedInk)
                Divider()
                HStack(spacing: 0) {
                    VenueFact(icon: "person.2", value: venue.capacity, caption: "guests")
                    VenueFact(icon: "dollarsign.circle", value: venue.estimate, caption: "venue est.")
                    VenueFact(icon: "airplane", value: venue.travel, caption: "guest travel")
                }
            }
            .padding(18)
        }
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selectedForComparison ? VowbaseTheme.rose : VowbaseTheme.border, lineWidth: selectedForComparison ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }
}

private struct VenueFact: View {
    let icon: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(value, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(VowbaseTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Add a name, location, capacity, price, and your impressions after each visit — everything you need to build a shortlist worth comparing.")
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
