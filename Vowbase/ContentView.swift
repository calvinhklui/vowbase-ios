import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        VowbaseAuthenticatedContent()
    }
}

struct VowbaseAuthenticatedContent: View {
    @State private var store: VowbaseWorkspaceStore
    let onSignOut: () -> Void

    init(
        repositories: RepositoryContainer? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.onSignOut = onSignOut
        _store = State(initialValue: VowbaseWorkspaceStore(repositories: repositories))
    }

#if DEBUG
    init(
        testingWorkspace: Bool,
        onSignOut: @escaping () -> Void = {}
    ) {
        precondition(testingWorkspace)
        self.onSignOut = onSignOut
        _store = State(initialValue: VowbaseWorkspaceStore(testingWorkspace: true))
    }
#endif

    var body: some View {
        WeddingAppShell(store: store, onSignOut: onSignOut)
            .task { await store.load() }
    }
}

// MARK: - App shell

private enum QuickAddDestination: String, Identifiable {
    case venue
    case guest

    var id: String { rawValue }
}

@MainActor
private struct WeddingAppShell: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
    @State private var navigation: AppNavigationModel
    @State private var quickAdd: QuickAddDestination?
    @State private var isQuickAddPresented = false

    init(
        store: VowbaseWorkspaceStore,
        initialTab: AppTab = .map,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onSignOut = onSignOut
        _navigation = State(initialValue: AppNavigationModel(selectedTab: initialTab))
    }

    var body: some View {
        @Bindable var navigation = navigation

        ZStack {
            VowbaseTheme.background.ignoresSafeArea()

            Group {
                switch navigation.selectedTab {
                case .map:
                    MapWorkspaceView(
                        store: store,
                        onSignOut: onSignOut
                    )
                case .venues:
                    VenuesView(store: store, onSignOut: onSignOut)
                case .guests:
                    GuestsView(store: store, onSignOut: onSignOut)
                }
            }

            if store.isLoading {
                ProgressView("Loading your wedding")
                    .tint(VowbaseTheme.rose)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let errorMessage = store.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await store.load() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.rose)
                }
                .font(.system(size: 16))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(24)
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VowbaseTabBar(selection: $navigation.selectedTab)
        }
        .overlay {
            if isQuickAddPresented {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
                            isQuickAddPresented = false
                        }
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            QuickAddOverlay(
                isPresented: $isQuickAddPresented,
                onAddVenue: { quickAdd = .venue },
                onAddGuest: { quickAdd = .guest }
            )
            .padding(.trailing, VowbaseControlMetric.screenInset)
            .padding(.bottom, VowbaseTabBar.fabBottomClearance)
        }
        .sheet(item: $quickAdd) { destination in
            switch destination {
            case .venue:
                AddVenueSheet(store: store)
                    .presentationDetents([.medium, .large])
            case .guest:
                AddGuestSheet(store: store)
                    .presentationDetents([.medium, .large])
            }
        }
        .animation(.snappy(duration: 0.28), value: navigation.selectedTab)
    }

}

private struct VowbaseTabBar: View {
    static let fabBottomClearance: CGFloat = 90

    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                tabContent
                    .glassEffect(
                        .regular.tint(Color.black.opacity(0.54)),
                        in: Capsule()
                    )
            } else {
                tabContent
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
        }
        .padding(.horizontal, VowbaseControlMetric.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var tabContent: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    VowbaseTabBarItem(tab: tab, isSelected: selection == tab)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: 70)
    }

    private func select(_ tab: AppTab) {
        guard selection != tab else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08)) {
            selection = tab
        }
    }
}

private struct VowbaseTabBarItem: View {
    let tab: AppTab
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolVariant(.fill)

            Text(tab.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background {
            if isSelected {
                Capsule()
                    .fill(.white.opacity(0.16))
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
            }
        }
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct IdentityBar: View {
    let weddingTitle: String
    let onSignOut: () -> Void
    @State private var isAccountMenuPresented = false

    var body: some View {
        HStack(spacing: 14) {
            Button { isAccountMenuPresented = true } label: {
                Text(weddingInitials)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .frame(width: 58, height: 58)
                    .background(VowbaseTheme.blush)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")
            .accessibilityHint("Opens account actions")

            Text(weddingTitle)
                .font(VowbaseType.detailTitle)
                .foregroundStyle(VowbaseTheme.ink)
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityLabel("Current wedding: \(weddingTitle)")

            Spacer(minLength: 0)
        }
        .confirmationDialog(
            "Your Vowbase account",
            isPresented: $isAccountMenuPresented,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with Apple or Google at any time.")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .stroke(VowbaseTheme.border.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    private var weddingInitials: String {
        weddingTitle
            .split { !$0.isLetter }
            .compactMap(\.first)
            .prefix(2)
            .map { String($0).uppercased() }
            .joined(separator: "&")
    }
}

// MARK: - Map

@MainActor
private struct MapWorkspaceView: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
    @State private var showsVenues = true
    @State private var showsGuests = true
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.2, longitude: -74.4),
            span: MKCoordinateSpan(latitudeDelta: 11.5, longitudeDelta: 13.0)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                if showsVenues {
                    ForEach(store.venues) { venue in
                        if let coordinate = venue.coordinate {
                            Annotation(venue.name, coordinate: coordinate, anchor: .bottom) {
                                Button {
                                    store.selectedVenueID = venue.id
                                } label: {
                                    VenueMapAnnotation(
                                        venue: venue,
                                        selected: store.selectedVenueID == venue.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(venue.name), \(venue.status.title)")
                            }
                        }
                    }
                }

                if showsGuests {
                    ForEach(store.clusters) { cluster in
                        Annotation("\(cluster.count) guests in \(cluster.city)", coordinate: cluster.coordinate) {
                            GuestClusterAnnotation(cluster: cluster)
                                .accessibilityLabel("\(cluster.count) guests in \(cluster.city)")
                        }
                    }
                }
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 20) {
                IdentityBar(weddingTitle: store.weddingTitle, onSignOut: onSignOut)
                HStack(spacing: 10) {
                    LayerChip(title: "Venues", icon: "mappin", isOn: $showsVenues, tint: VowbaseTheme.rose)
                    LayerChip(title: "Guests", icon: "person.2", isOn: $showsGuests, tint: VowbaseTheme.guestBlue)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShortlistPanel(store: store)
            .padding(.bottom, 8)
        }
    }
}

private struct LayerChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: isOn ? "checkmark" : "eye.slash")
                    .font(.system(size: 12, weight: .bold))
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isOn ? tint : VowbaseTheme.mutedInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(isOn ? tint.opacity(0.38) : VowbaseTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Visible" : "Hidden")
    }
}

private struct VenueMapAnnotation: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: selected ? 30 : 25))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, VowbaseTheme.rose)
            if selected {
                Text(venue.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(VowbaseTheme.rose.opacity(0.45), lineWidth: 1))
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }
}

private struct GuestClusterAnnotation: View {
    let cluster: GuestCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(VowbaseTheme.guestBlue, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 4))
            .shadow(color: VowbaseTheme.guestBlue.opacity(0.36), radius: 8, y: 3)
    }
}

@MainActor
private struct ShortlistPanel: View {
    let store: VowbaseWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(VowbaseTheme.border)
                .frame(width: 76, height: 7)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack {
                Text("Shortlist")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                Spacer()
                Text("\(store.venues.count) venues")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }

            if let selectedVenue = store.venues.first(where: { $0.id == store.selectedVenueID }) ?? store.venues.first {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.venues) { venue in
                            Button { store.selectedVenueID = venue.id } label: {
                                MapVenueCard(venue: venue, selected: venue.id == selectedVenue.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.trailing, 18, for: .scrollContent)
            } else {
                Text("Add a venue to start your shortlist.")
                    .font(.system(size: 16))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous))
    }
}

private struct MapVenueCard: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            VowbaseVenueImage(url: venue.photoURL)
                .frame(width: 106, height: 148)
            VStack(alignment: .leading, spacing: 10) {
                Text(venue.name)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .lineLimit(2)
                StatusCapsule(status: venue.status)
                Label(venue.location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                Divider()
                Label("\(venue.travel) median guest travel", systemImage: "airplane")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(width: 165, height: 148, alignment: .leading)
        }
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selected ? VowbaseTheme.rose : VowbaseTheme.border, lineWidth: selected ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}

// MARK: - Venues

@MainActor
private struct VenuesView: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
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
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
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

private struct VenueDetailView: View {
    let venue: MVPVenue
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VowbaseVenueImage(url: venue.photoURL)
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if venue.photoURLs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(venue.photoURLs.dropFirst(), id: \.absoluteString) { photoURL in
                                VowbaseVenueImage(url: photoURL)
                                    .frame(width: 108, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                Text(venue.name).displayTitle()
                StatusCapsule(status: venue.status)
                Label(venue.location, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                if let summary = venue.summary?.nilIfBlank {
                    Text(summary)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 18) {
                    VenueFact(icon: "person.2", value: venue.capacity, caption: "guests")
                    VenueFact(icon: "dollarsign.circle", value: venue.estimate, caption: "venue est.")
                    VenueFact(icon: "dollarsign.square", value: venue.allInEstimate, caption: "all-in est.")
                    VenueFact(icon: "calendar", value: venue.availableDates, caption: "available dates")
                }
                .padding()
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if venue.website != nil || venue.contactName != nil || venue.contactEmail != nil || venue.contactPhone != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Venue details")
                            .font(.title2.weight(.semibold))
                        if let website = venue.website { VenueDetailRow(title: "Website", value: website, icon: "link") }
                        if let contact = venue.contactName { VenueDetailRow(title: "Contact", value: contact, icon: "person") }
                        if let email = venue.contactEmail { VenueDetailRow(title: "Email", value: email, icon: "envelope") }
                        if let phone = venue.contactPhone { VenueDetailRow(title: "Phone", value: phone, icon: "phone") }
                    }
                    .padding()
                    .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(VowbaseTheme.border, lineWidth: 1)
                    }
                }
                Text("Notes")
                    .font(.title2.weight(.semibold))
                Text(venue.ourNotes?.nilIfBlank ?? "No notes added yet.")
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(16)
        }
        .navigationTitle("Venue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit venue") { isEditing = true }
                    Button("Delete venue", role: .destructive) { isConfirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditVenueSheet(store: store, venue: venue)
        }
        .alert("Delete \(venue.name)?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                Task {
                    if await store.deleteVenue(venue) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the venue from your wedding workspace.")
        }
    }
}

private struct VenueDetailRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        LabeledContent(title) {
            Label(value, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(VowbaseTheme.mutedInk)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Guests

@MainActor
private struct GuestsView: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
    @State private var query = ""
    @State private var filter: GuestFilter = .all
    @State private var onlyLocated = false
    @State private var showsFilter = false

    private var visibleGuests: [MVPGuest] {
        store.guests.filter { guest in
            let matchingFilter = filter.matches(guest)
            let matchingLocation = !onlyLocated || guest.location != nil
            guard matchingFilter && matchingLocation else { return false }
            guard !query.isEmpty else { return true }
            return guest.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IdentityBar(weddingTitle: store.weddingTitle, onSignOut: onSignOut)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GUEST LIST").eyebrow()
                        Text("Guests").displayTitle()
                        Text("\(store.guests.count) guests")
                            .font(.system(size: 18))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(VowbaseTheme.mutedInk)
                            TextField("Search guests", text: $query)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
                        Button {
                            showsFilter = true
                        } label: {
                            Label("Filters", systemImage: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(onlyLocated ? .white : VowbaseTheme.ink)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .background(onlyLocated ? VowbaseTheme.rose : VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(GuestFilter.allCases) { item in
                                Button { filter = item } label: {
                                    Text(item.title(total: store.guests.count, guests: store.guests))
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(filter == item ? .white : VowbaseTheme.mutedInk)
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: 44)
                                        .background(filter == item ? VowbaseTheme.rose : VowbaseTheme.background, in: Capsule())
                                        .overlay(Capsule().stroke(filter == item ? .clear : VowbaseTheme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(visibleGuests) { guest in
                            NavigationLink(value: guest) {
                                GuestRow(guest: guest)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 72)
                        }
                    }
                    if visibleGuests.isEmpty {
                        ContentUnavailableView("No guests found", systemImage: "person.2.slash", description: Text("Try a different name or RSVP filter."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .refreshable {
                await store.load()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: MVPGuest.self) { guest in
                GuestDetailView(guest: guest, store: store)
            }
            .sheet(isPresented: $showsFilter) {
                GuestFilterSheet(onlyLocated: $onlyLocated)
                    .presentationDetents([.height(280)])
            }
        }
    }
}

private enum GuestFilter: String, CaseIterable, Identifiable {
    case all, pending, notInvited, accepted
    var id: String { rawValue }

    func matches(_ guest: MVPGuest) -> Bool {
        switch self {
        case .all: true
        case .pending: guest.rsvp == .pending
        case .notInvited: guest.rsvp == .notInvited
        case .accepted: guest.rsvp == .accepted
        }
    }

    func title(total: Int, guests: [MVPGuest]) -> String {
        let count = self == .all ? total : guests.filter { matches($0) }.count
        let label: String = switch self {
        case .all: "All"
        case .pending: "Pending"
        case .notInvited: "Not invited"
        case .accepted: "Accepted"
        }
        return "\(label) \(count)"
    }
}

private struct GuestFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var onlyLocated: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Guest information") {
                    Toggle("Only guests with a location", isOn: $onlyLocated)
                        .tint(VowbaseTheme.rose)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .navigationTitle("Filters")
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

private struct GuestRow: View {
    let guest: MVPGuest

    var body: some View {
        HStack(spacing: 14) {
            Text(guest.initials)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .frame(width: 58, height: 58)
                .background(VowbaseTheme.blush, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(guest.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.ink)
                HStack(spacing: 6) {
                    Text(guest.group)
                    Text("•")
                    Text(guest.location ?? "Location not added")
                    if guest.location != nil {
                        Image(systemName: "mappin")
                            .foregroundStyle(VowbaseTheme.guestBlue)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            RSVPStatusCapsule(status: guest.rsvp)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

private struct GuestDetailView: View {
    let guest: MVPGuest
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Text(guest.initials)
                        .font(.system(size: 30, design: .serif))
                        .frame(width: 76, height: 76)
                        .background(VowbaseTheme.blush, in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(guest.name).font(.title2.weight(.semibold))
                        RSVPStatusCapsule(status: guest.rsvp)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Guest details") {
                LabeledContent("Group", value: guest.group)
                LabeledContent("Location", value: guest.location ?? "Not added")
                LabeledContent("Email", value: guest.email ?? "Not added")
            }
        }
        .navigationTitle("Guest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit guest") { isEditing = true }
                    Button("Delete guest", role: .destructive) { isConfirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditGuestSheet(store: store, guest: guest)
        }
        .alert("Delete \(guest.name)?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                Task {
                    if await store.deleteGuest(guest) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the guest from your wedding workspace.")
        }
    }
}

// MARK: - Quick add

private struct AddButton: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen ? "xmark" : "plus")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(VowbaseTheme.rose, in: Circle())
                .shadow(color: VowbaseTheme.rose.opacity(0.34), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Close quick add" : "Quick add")
    }
}

private struct QuickAddMenu: View {
    let addAction: (QuickAddDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { addAction(.venue) } label: {
                Label("Add venue", systemImage: "mappin.and.ellipse")
                    .frame(minWidth: 150, alignment: .leading)
            }
            Button { addAction(.guest) } label: {
                Label("Add guest", systemImage: "person.badge.plus")
                    .frame(minWidth: 150, alignment: .leading)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(VowbaseTheme.ink)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .buttonStyle(.plain)
    }
}

@MainActor
private struct AddVenueSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var location = ""
    @State private var status: VenueStatus = .considering
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("First, the essentials") {
                    TextField("Venue name", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                    TextField("Address or location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    Picker("Status", selection: $status) {
                        ForEach([VenueStatus.considering, .contacted, .toured, .shortlisted], id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save venue") {
                        isSaving = true
                        Task {
                            let didSave = await store.createVenue(
                                name: name,
                                location: location,
                                status: status
                            )
                            isSaving = false
                            guard didSave else { return }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmed.isEmpty || isSaving)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}

@MainActor
private struct AddGuestSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFirstNameFocused: Bool
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    @State private var rsvp: RSVPStatus = .notInvited
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("First, the essentials") {
                    TextField("First name", text: $firstName)
                        .focused($isFirstNameFocused)
                        .textInputAutocapitalization(.words)
                    TextField("Last name (optional)", text: $lastName)
                        .textInputAutocapitalization(.words)
                    Picker("RSVP", selection: $rsvp) {
                        ForEach(RSVPStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    TextField("Address or location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save guest") {
                        isSaving = true
                        Task {
                            let didSave = await store.createGuest(
                                firstName: firstName,
                                lastName: lastName,
                                location: location,
                                rsvp: rsvp
                            )
                            isSaving = false
                            guard didSave else { return }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                    .disabled(firstName.trimmed.isEmpty || isSaving)
                }
            }
            .onAppear { isFirstNameFocused = true }
        }
    }
}

@MainActor
private struct EditVenueSheet: View {
    let store: VowbaseWorkspaceStore
    let venue: MVPVenue
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var location: String
    @State private var status: VenueStatus
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, venue: MVPVenue) {
        self.store = store
        self.venue = venue
        _name = State(initialValue: venue.name)
        _location = State(initialValue: venue.location == "Location not added" ? "" : venue.location)
        _status = State(initialValue: venue.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Venue details") {
                    TextField("Venue name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Address or location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    Picker("Status", selection: $status) {
                        ForEach([
                            VenueStatus.suggested, .considering, .contacted, .toured,
                            .shortlisted, .negotiating, .booked, .passed,
                        ], id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Edit venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let didSave = await store.updateVenue(
                                venue,
                                name: name,
                                location: location,
                                status: status
                            )
                            isSaving = false
                            if didSave { dismiss() }
                        }
                    }
                    .disabled(name.trimmed.isEmpty || isSaving)
                }
            }
        }
    }
}

@MainActor
private struct EditGuestSheet: View {
    let store: VowbaseWorkspaceStore
    let guest: MVPGuest
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var location: String
    @State private var rsvp: RSVPStatus
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, guest: MVPGuest) {
        self.store = store
        self.guest = guest
        _firstName = State(initialValue: guest.firstName)
        _lastName = State(initialValue: guest.lastName)
        _location = State(initialValue: guest.location ?? "")
        _rsvp = State(initialValue: guest.rsvp)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Guest details") {
                    TextField("First name", text: $firstName)
                        .textInputAutocapitalization(.words)
                    TextField("Last name (optional)", text: $lastName)
                        .textInputAutocapitalization(.words)
                    Picker("RSVP", selection: $rsvp) {
                        ForEach(RSVPStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    TextField("Address or location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Edit guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let didSave = await store.updateGuest(
                                guest,
                                firstName: firstName,
                                lastName: lastName,
                                location: location,
                                rsvp: rsvp
                            )
                            isSaving = false
                            if didSave { dismiss() }
                        }
                    }
                    .disabled(firstName.trimmed.isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Reusable views and MVP fixtures

private struct VowbaseVenueImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            venueImagePlaceholder
                        }
                    }
                } else {
                    venueImagePlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var venueImagePlaceholder: some View {
        Image(systemName: "building.2")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(VowbaseTheme.rose.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VowbaseTheme.blush)
    }
}

private struct StatusCapsule: View {
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

private struct RSVPStatusCapsule: View {
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

enum VowbaseTheme {
    static let background = VowbaseDesign.background
    static let groupedBackground = VowbaseDesign.groupedBackground
    static let ink = VowbaseDesign.textPrimary
    static let mutedInk = VowbaseDesign.textSecondary
    static let rose = VowbaseDesign.rose
    static let blush = VowbaseDesign.blush
    static let border = VowbaseDesign.separator
    static let guestBlue = VowbaseDesign.guestBlue
}

private extension Text {
    func displayTitle() -> some View {
        font(VowbaseType.screenDisplay)
            .foregroundStyle(VowbaseTheme.ink)
    }

    func eyebrow() -> some View {
        font(VowbaseType.eyebrow)
            .tracking(1.6)
            .foregroundStyle(VowbaseTheme.rose)
    }
}

extension VenueStatus: Hashable {}

private extension VenueStatus {
    var title: String {
        switch self {
        case .suggested: "Suggested"
        case .considering: "Considering"
        case .contacted: "Contacted"
        case .toured: "Toured"
        case .shortlisted: "Shortlisted"
        case .negotiating: "Negotiating"
        case .booked: "Booked"
        case .passed: "Passed"
        }
    }
}

extension RSVPStatus: Hashable {}

private extension RSVPStatus {
    static var allCases: [RSVPStatus] { [.notInvited, .pending, .accepted, .declined] }

    var title: String {
        switch self {
        case .notInvited: "Not invited"
        case .pending: "Pending"
        case .accepted: "Accepted"
        case .declined: "Declined"
        }
    }
}

private struct MVPVenue: Identifiable, Hashable {
    let id: UUID
    let name: String
    let status: VenueStatus
    let location: String
    let capacity: String
    let estimate: String
    let travel: String
    let allInEstimate: String
    let availableDates: String
    let summary: String?
    let website: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let latitude: Double?
    let longitude: Double?
    let photoURLs: [URL]
    let ourNotes: String?

    var photoURL: URL? { photoURLs.first }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

private struct GuestCluster: Identifiable {
    let id: String
    let city: String
    let count: Int
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private struct MVPGuest: Identifiable, Hashable {
    let id: UUID
    let firstName: String
    let lastName: String
    let group: String
    let location: String?
    let email: String?
    let rsvp: RSVPStatus

    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var initials: String {
        [firstName.first, lastName.first]
            .compactMap { $0 }
            .map { String($0).uppercased() }
            .joined()
    }
    var searchText: String { [name, group, location, email].compactMap { $0 }.joined(separator: " ") }
}

@MainActor
@Observable
private final class VowbaseWorkspaceStore {
    private let repositories: RepositoryContainer?
    private var venueRecords = [Venue]()
    private var signedVenuePhotoURLs = [UUID: [URL]]()
    private var guestRecords = [Guest]()

    var selectedVenueID: UUID?
    var isGlobalMenuOpen = false
    var wedding: WeddingSummary?
    var isLoading = false
    var errorMessage: String?

    init(repositories: RepositoryContainer? = nil) {
        self.repositories = repositories
    }

#if DEBUG
    init(testingWorkspace: Bool) {
        precondition(testingWorkspace)
        repositories = nil

        let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        wedding = WeddingSummary(
            id: weddingID,
            name: "Example Wedding",
            coupleNames: "Example Couple",
            weddingDate: "2027-09-18",
            location: "Example City"
        )
        venueRecords = [
            Venue(
                id: UUID(uuidString: "4B836FCF-0575-41F8-960C-3C69E70F1D84")!,
                weddingID: weddingID,
                name: "Riverside Pavilion",
                status: .toured,
                location: "Example District, Example City",
                locationText: "Example District, Example City",
                address: "100 Example Avenue, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 150,
                capacityMax: 350,
                capacityText: "150–350",
                priceEstimate: 53_700,
                priceNotes: nil,
                venueEstimateText: "$53.7k",
                allInEstimateText: "$90k–$125k",
                availableDatesText: "Weekends in September",
                ourNotes: nil,
                summary: "An airy riverside venue for a joyful, relaxed celebration.",
                latitude: 39.5,
                longitude: -98.35,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            Venue(
                id: UUID(uuidString: "75AC0474-624B-4106-8A1C-5D13B117A34F")!,
                weddingID: weddingID,
                name: "Harbor Gallery",
                status: .toured,
                location: "Harbor District, Example City",
                locationText: "Harbor District, Example City",
                address: "200 Example Street, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 120,
                capacityMax: 300,
                capacityText: "120–300",
                priceEstimate: 48_000,
                priceNotes: nil,
                venueEstimateText: "$48k",
                allInEstimateText: nil,
                availableDatesText: "October weekends",
                ourNotes: nil,
                summary: nil,
                latitude: 39.6,
                longitude: -98.25,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            Venue(
                id: UUID(uuidString: "2A2B8F0C-A065-499B-BC92-847152B6E0D6")!,
                weddingID: weddingID,
                name: "Meadow House",
                status: .considering,
                location: "Lakeside, Example City",
                locationText: "Lakeside, Example City",
                address: "300 Example Road, Example City",
                city: "Example City",
                state: "EX",
                country: "US",
                contactName: nil,
                contactEmail: nil,
                contactPhone: nil,
                website: nil,
                capacityMin: 100,
                capacityMax: 220,
                capacityText: "100–220",
                priceEstimate: 39_000,
                priceNotes: nil,
                venueEstimateText: "$39k",
                allInEstimateText: nil,
                availableDatesText: nil,
                ourNotes: nil,
                summary: nil,
                latitude: 39.4,
                longitude: -98.45,
                photoURL: nil,
                rawResearch: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        ]
        guestRecords = [
            Guest(id: UUID(uuidString: "AE67A07D-D565-4A7D-A960-4B6A186C4D6D")!, weddingID: weddingID, firstName: "Avery", lastName: "Rowan", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Cedar Circle")]), rsvpStatus: .accepted, rsvpDate: nil, originLabel: "Lumen Bay", originLatitude: 39.5, originLongitude: -98.35, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "167E1A25-7B99-499B-9A66-872B2A3B784A")!, weddingID: weddingID, firstName: "Mira", lastName: "Vale", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Juniper Guild")]), rsvpStatus: .pending, rsvpDate: nil, originLabel: "Northvale", originLatitude: 39.6, originLongitude: -98.25, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "3F8DB09C-44F3-4888-8D2B-31EB26F5C487")!, weddingID: weddingID, firstName: "Theo", lastName: "Lark", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Cedar Circle")]), rsvpStatus: .pending, rsvpDate: nil, originLabel: "Willow Coast", originLatitude: 39.4, originLongitude: -98.45, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt),
            Guest(id: UUID(uuidString: "DE25BD36-69A1-4DC3-A5E0-5E0AF076E34E")!, weddingID: weddingID, firstName: "Nora", lastName: "Wynn", email: nil, phone: nil, address: nil, customFields: .object(["group": .string("Juniper Guild")]), rsvpStatus: .notInvited, rsvpDate: nil, originLabel: "Solace Point", originLatitude: 39.45, originLongitude: -98.3, originPrecision: "city", geocodeStatus: "resolved", createdAt: createdAt)
        ]
        selectedVenueID = venueRecords.first?.id
    }
#endif

    var venues: [MVPVenue] {
        venueRecords.map { venue in
            MVPVenue(venue, photoURLs: signedVenuePhotoURLs[venue.id] ?? [])
        }
    }
    var guests: [MVPGuest] { guestRecords.map(MVPGuest.init) }
    var weddingTitle: String { wedding?.coupleNames ?? wedding?.name ?? "Your wedding" }

    /// Map guest locations only when the server marks them as city-precision.
    /// This keeps individual household addresses out of the planning map.
    var clusters: [GuestCluster] {
        let locatedGuests = guestRecords.compactMap { guest -> (String, Double, Double)? in
            guard guest.originPrecision == "city",
                  let city = guest.originLabel,
                  let latitude = guest.originLatitude,
                  let longitude = guest.originLongitude else {
                return nil
            }
            return (city, latitude, longitude)
        }
        return Dictionary(grouping: locatedGuests, by: { $0.0.lowercased() })
            .compactMap { key, entries in
                guard let first = entries.first else { return nil }
                let count = Double(entries.count)
                return GuestCluster(
                    id: key,
                    city: first.0,
                    count: entries.count,
                    latitude: entries.reduce(0) { $0 + $1.1 } / count,
                    longitude: entries.reduce(0) { $0 + $1.2 } / count
                )
            }
            .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    func load() async {
        guard let repositories else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let membership = try await repositories.workspace.memberships().first else {
                venueRecords = []
                guestRecords = []
                wedding = nil
                errorMessage = "This account is not a member of a wedding workspace yet."
                return
            }

            wedding = membership.wedding
            async let venues = repositories.venues.venues(weddingID: membership.weddingId)
            async let guests = repositories.guests.guests(weddingID: membership.weddingId)
            venueRecords = try await venues
            guestRecords = try await guests
            let currentVenueIDs = Set(venueRecords.map(\.id))
            signedVenuePhotoURLs = signedVenuePhotoURLs.filter { currentVenueIDs.contains($0.key) }
            resolveVenuePhotoURLs(for: venueRecords, repositories: repositories)
            if !venueRecords.contains(where: { $0.id == selectedVenueID }) {
                selectedVenueID = venueRecords.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func createVenue(name: String, location: String, status: VenueStatus) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let location = await resolvedLocation(for: location, repositories: repositories)
            let venue = try await repositories.venues.createVenue(
                VenueDraft(
                    name: name.trimmed,
                    status: status,
                    location: location.displayName,
                    address: location.displayName,
                    city: location.city,
                    state: location.region,
                    country: location.country,
                    contactName: nil,
                    contactEmail: nil,
                    contactPhone: nil,
                    website: nil,
                    capacityMin: nil,
                    capacityMax: nil,
                    priceEstimate: nil,
                    priceNotes: nil,
                    ourNotes: nil,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    photoURL: nil
                ),
                weddingID: weddingID
            )
            venueRecords.insert(venue, at: 0)
            selectedVenueID = venue.id
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func updateVenue(_ venue: MVPVenue, name: String, location: String, status: VenueStatus) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            let resolved = await resolvedLocation(for: location, repositories: repositories)
            let updated = try await repositories.venues.updateVenue(
                id: venue.id,
                patch: VenuePatch(
                    name: name.trimmed,
                    status: status,
                    location: resolved.displayName,
                    address: resolved.displayName,
                    city: resolved.city,
                    state: resolved.region,
                    country: resolved.country,
                    contactName: nil,
                    contactEmail: nil,
                    contactPhone: nil,
                    website: nil,
                    capacityMin: nil,
                    capacityMax: nil,
                    priceEstimate: nil,
                    priceNotes: nil,
                    ourNotes: nil,
                    latitude: resolved.latitude,
                    longitude: resolved.longitude,
                    photoURL: nil,
                    rawResearch: nil
                )
            )
            replace(updated, in: &venueRecords)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteVenue(_ venue: MVPVenue) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.venues.deleteVenue(id: venue.id)
            venueRecords.removeAll { $0.id == venue.id }
            signedVenuePhotoURLs[venue.id] = nil
            if selectedVenueID == venue.id {
                selectedVenueID = venueRecords.first?.id
            }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func createGuest(firstName: String, lastName: String, location: String, rsvp: RSVPStatus) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        do {
            let resolved = await resolvedLocation(for: location, repositories: repositories)
            let guest = try await repositories.guests.createGuest(
                GuestDraft(
                    firstName: firstName.trimmed,
                    lastName: lastName.nilIfBlank,
                    address: resolved.displayName,
                    rsvpStatus: rsvp,
                    originLabel: resolved.city ?? resolved.displayName,
                    originLatitude: resolved.latitude,
                    originLongitude: resolved.longitude,
                    originPrecision: resolved.city == nil ? nil : "city",
                    geocodeStatus: resolved.latitude == nil ? nil : "resolved"
                ),
                weddingID: weddingID
            )
            guestRecords.insert(guest, at: 0)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func updateGuest(_ guest: MVPGuest, firstName: String, lastName: String, location: String, rsvp: RSVPStatus) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            let resolved = await resolvedLocation(for: location, repositories: repositories)
            let updated = try await repositories.guests.updateGuest(
                id: guest.id,
                patch: GuestPatch(
                    firstName: firstName.trimmed,
                    lastName: lastName.nilIfBlank.map(NullablePatch.value) ?? .null,
                    address: resolved.displayName.map(NullablePatch.value) ?? .null,
                    rsvpStatus: .value(rsvp),
                    originLabel: (resolved.city ?? resolved.displayName).map(NullablePatch.value) ?? .null,
                    originLatitude: resolved.latitude.map(NullablePatch.value) ?? .null,
                    originLongitude: resolved.longitude.map(NullablePatch.value) ?? .null,
                    originPrecision: resolved.city == nil ? .null : .value("city"),
                    geocodeStatus: resolved.latitude == nil ? .null : .value("resolved")
                )
            )
            replace(updated, in: &guestRecords)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteGuest(_ guest: MVPGuest) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.guests.deleteGuest(id: guest.id)
            guestRecords.removeAll { $0.id == guest.id }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    private func unavailable() -> Bool {
        errorMessage = "Your wedding workspace is not ready yet. Please try again."
        return false
    }

    private func resolveVenuePhotoURLs(
        for venues: [Venue],
        repositories: RepositoryContainer
    ) {
        let resolver = VenuePhotoURLResolver(photoService: repositories.venuePhotos)
        Task { [weak self] in
            for venue in venues {
                guard !Task.isCancelled else { return }
                let gallery = (try? await repositories.venues.venuePhotos(venueID: venue.id)) ?? []
                let references = [venue.photoURL] + gallery.map(\.url)
                var urls = [URL]()
                for reference in references {
                    guard !Task.isCancelled else { return }
                    if let url = await resolver.resolve(venueID: venue.id, photoURL: reference), !urls.contains(url) {
                        urls.append(url)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.signedVenuePhotoURLs[venue.id] = urls
            }
        }
    }

    private func resolvedLocation(
        for input: String,
        repositories: RepositoryContainer
    ) async -> ResolvedLocation {
        let query = input.trimmed
        guard !query.isEmpty else { return .empty }
        guard let result = try? await repositories.maps.geocode(query: query).first else {
            return .init(displayName: query, city: nil, region: nil, country: nil, latitude: nil, longitude: nil)
        }
        return .init(
            displayName: result.displayName,
            city: result.city,
            region: result.region,
            country: result.country,
            latitude: result.latitude,
            longitude: result.longitude
        )
    }

    private func replace<T: Identifiable>(_ value: T, in records: inout [T]) where T.ID: Equatable {
        guard let index = records.firstIndex(where: { $0.id == value.id }) else { return }
        records[index] = value
    }

    private func userMessage(for error: Error) -> String {
        switch error as? BackendError {
        case .forbidden:
            "You don’t have permission to make that change."
        case .networkUnavailable:
            "Vowbase couldn’t reach the server. Check your connection and try again."
        case .authenticationRequired:
            "Your session has ended. Please sign in again."
        default:
            "We couldn’t save that change. Please try again."
        }
    }
}

private struct ResolvedLocation {
    let displayName: String?
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?

    static let empty = ResolvedLocation(
        displayName: nil, city: nil, region: nil, country: nil, latitude: nil, longitude: nil
    )
}

private extension MVPVenue {
    init(_ venue: Venue, photoURLs: [URL] = []) {
        id = venue.id
        name = venue.name
        status = venue.status
        location = venue.locationText?.nilIfBlank ?? venue.location ?? venue.city ?? venue.address ?? "Location not added"
        capacity = venue.capacityText?.nilIfBlank ?? VenueCapacityFormatter.string(minimum: venue.capacityMin, maximum: venue.capacityMax)
        estimate = venue.venueEstimateText?.nilIfBlank ?? venue.priceEstimate.map(VenuePriceFormatter.string) ?? "Not added"
        travel = "Unavailable"
        allInEstimate = venue.allInEstimateText?.nilIfBlank ?? "Not added"
        availableDates = venue.availableDatesText?.nilIfBlank ?? "Not added"
        summary = venue.summary?.nilIfBlank
        website = venue.website?.nilIfBlank
        contactName = venue.contactName?.nilIfBlank
        contactEmail = venue.contactEmail?.nilIfBlank
        contactPhone = venue.contactPhone?.nilIfBlank
        latitude = venue.latitude
        longitude = venue.longitude
        var uniquePhotoURLs = [URL]()
        for url in ([VenuePhotoURLResolver.directPhotoURL(from: venue.photoURL)] + photoURLs).compactMap({ $0 }) where !uniquePhotoURLs.contains(url) {
            uniquePhotoURLs.append(url)
        }
        self.photoURLs = uniquePhotoURLs
        ourNotes = venue.ourNotes?.nilIfBlank
    }
}

private extension MVPGuest {
    init(_ guest: Guest) {
        id = guest.id
        firstName = guest.firstName
        lastName = guest.lastName ?? ""
        group = guest.customFields.stringValue(for: "group")
            ?? guest.customFields.stringValue(for: "group_name")
            ?? "No group"
        location = guest.originLabel ?? guest.address
        email = guest.email
        rsvp = guest.rsvpStatus ?? .notInvited
    }
}

private extension JSONValue {
    func stringValue(for key: String) -> String? {
        guard case let .object(values) = self, case let .string(value)? = values[key] else { return nil }
        return value
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

private enum VenueCapacityFormatter {
    static func string(minimum: Int?, maximum: Int?) -> String {
        switch (minimum, maximum) {
        case let (minimum?, maximum?): "\(minimum)–\(maximum)"
        case let (minimum?, nil): "\(minimum)+"
        case let (nil, maximum?): "Up to \(maximum)"
        case (nil, nil): "Not added"
        }
    }
}

private enum VenuePriceFormatter {
    static func string(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

#Preview("Map") {
    ContentView()
}

#Preview("Venues") {
    WeddingAppShell(store: VowbaseWorkspaceStore(), initialTab: .venues)
}

#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(), initialTab: .guests)
}

#Preview("Add venue") {
    AddVenueSheet(store: VowbaseWorkspaceStore())
}

#Preview("Add guest") {
    AddGuestSheet(store: VowbaseWorkspaceStore())
}
