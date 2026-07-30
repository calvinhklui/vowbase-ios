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
    @State private var taskStore: TaskStore
    let onSignOut: () -> Void

    init(
        repositories: RepositoryContainer? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.onSignOut = onSignOut
        _store = State(initialValue: VowbaseWorkspaceStore(repositories: repositories))
        _taskStore = State(initialValue: TaskStore(repository: repositories?.tasks))
    }

#if DEBUG
    init(
        testingWorkspace: Bool,
        onSignOut: @escaping () -> Void = {}
    ) {
        precondition(testingWorkspace)
        self.onSignOut = onSignOut
        _store = State(initialValue: VowbaseWorkspaceStore(testingWorkspace: true))
        let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
        _taskStore = State(initialValue: TaskStore.testingWorkspace(weddingID: weddingID))
    }
#endif

    var body: some View {
        WeddingAppShell(store: store, taskStore: taskStore, onSignOut: onSignOut)
            .task { await store.load() }
    }
}

// MARK: - App shell

private enum QuickAddDestination: String, Identifiable {
    case venue
    case guest

    var id: String { rawValue }
}

private struct SaveFailure: Identifiable {
    let id = UUID()
    let message: String
    let retry: @MainActor () -> Void
    let discard: @MainActor () -> Void
}

@MainActor
private struct WeddingAppShell: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    let onSignOut: () -> Void
    @State private var navigation: AppNavigationModel
    @State private var quickAdd: QuickAddDestination?
    @State private var taskEditor: TaskEditorDestination?
    @State private var isQuickAddPresented = false

    init(
        store: VowbaseWorkspaceStore,
        taskStore: TaskStore,
        initialTab: AppTab = .map,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.store = store
        self.taskStore = taskStore
        self.onSignOut = onSignOut
        _navigation = State(initialValue: AppNavigationModel(selectedTab: initialTab))
    }

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var store = store

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
                case .tasks:
                    TasksView(store: store, taskStore: taskStore, onSignOut: onSignOut, editor: $taskEditor)
                }
            }

            if store.isLoading {
                ProgressView("Loading your wedding")
                    .tint(VowbaseTheme.rose)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                onAddGuest: { quickAdd = .guest },
                onAddTask: { taskEditor = .add }
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
        .sheet(item: $taskEditor) { destination in
            TaskEditorSheet(destination: destination, taskStore: taskStore, weddingID: store.wedding?.id, canManageTasks: store.canManageTasks)
                .presentationDetents([.large])
        }
        .alert(item: $store.saveFailure) { failure in
            Alert(
                title: Text("We couldn’t save that change"),
                message: Text(failure.message),
                primaryButton: .default(Text("Try again")) {
                    Task { @MainActor in failure.retry() }
                },
                secondaryButton: .destructive(Text("Discard changes")) {
                    Task { @MainActor in failure.discard() }
                }
            )
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

struct IdentityBar: View {
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
                deleteVenue()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the venue from your wedding workspace.")
        }
    }

    private func deleteVenue() {
        Task {
            guard await store.deleteVenue(venue) else {
                store.presentSaveFailure(retry: deleteVenue)
                return
            }
            dismiss()
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
    @State private var filters = GuestFilterSet()
    @State private var sort: GuestSortOrder = .nameAscending
    @State private var showsFilter = false
    @State private var path = NavigationPath()

    private var visibleGuests: [MVPGuest] {
        store.filteredGuests(searchText: query, filters: filters, sort: sort)
    }

    private var records: [Guest] { store.allGuestRecords }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IdentityBar(weddingTitle: store.weddingTitle, onSignOut: onSignOut)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GUEST LIST").eyebrow()
                        Text("Guests").displayTitle()
                        Text("\(records.count) guests")
                            .font(.system(size: 18))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                    toolRow
                    if filters.conditionCount > 0 {
                        activeFilterTokens
                    }
                    guestList
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
            .navigationDestination(for: GuestsRoute.self) { route in
                switch route {
                case .customFields:
                    GuestFieldListView(store: store)
                }
            }
            .sheet(isPresented: $showsFilter) {
                GuestFilterSheet(store: store, searchText: query, filters: $filters)
            }
        }
    }

    // MARK: Controls

    private var toolRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                TextField("Search guests", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))

            filtersButton
            overflowMenu
        }
    }

    private var filtersButton: some View {
        Button {
            showsFilter = true
        } label: {
            Label("Filters", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filters.conditionCount > 0 ? .white : VowbaseTheme.ink)
                .frame(width: 52, height: 52)
                .background(
                    filters.conditionCount > 0 ? VowbaseTheme.rose : VowbaseTheme.background,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if filters.conditionCount > 0 {
                        Text("\(filters.conditionCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VowbaseTheme.rose)
                            .padding(4)
                            .background(VowbaseTheme.background, in: Circle())
                            .overlay(Circle().stroke(VowbaseTheme.rose, lineWidth: 1))
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            filters.conditionCount > 0
                ? "Filters, \(filters.conditionCount) active"
                : "Filters"
        )
    }

    private var overflowMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(GuestSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            Divider()
            Button {
                path.append(GuestsRoute.customFields)
            } label: {
                Label("Manage fields", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VowbaseTheme.ink)
                .frame(width: 52, height: 52)
                .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Sort and manage fields")
    }

    /// A filtered list should never look like the whole list. Every active
    /// condition — RSVP included, now that it has no dedicated chip row —
    /// is named here and removable in one tap. One consistent capsule shape
    /// and size for every active filter, not two different components.
    private var activeFilterTokens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tokens, id: \.id) { token in
                    Button {
                        token.remove(&filters)
                    } label: {
                        HStack(spacing: 6) {
                            Text(token.title)
                                .font(.system(size: 16, weight: .medium))
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(VowbaseTheme.rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter \(token.title)")
                }
                Button("Clear all") {
                    filters = GuestFilterSet()
                }
                .font(.system(size: 16, weight: .medium))
                .tint(VowbaseTheme.mutedInk)
            }
        }
    }

    private var tokens: [GuestFilterToken] {
        GuestFilterToken.tokens(for: filters, columns: store.visibleCustomColumns)
    }

    // MARK: List and empty states

    @ViewBuilder
    private var guestList: some View {
        if visibleGuests.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleGuests.enumerated()), id: \.element.id) { index, guest in
                    NavigationLink(value: guest) {
                        GuestRow(guest: guest)
                    }
                    .buttonStyle(.plain)
                    if index < visibleGuests.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Text("Start your guest list.")
            } description: {
                Text("Add the people you want there, then track RSVPs and where they’re travelling from.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if filters.conditionCount > 0 {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No guests match these filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(filterSummary)
                )
                Button("Clear filters") {
                    filters = GuestFilterSet()
                }
                .font(.system(size: 16, weight: .semibold))
                .tint(VowbaseTheme.rose)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            ContentUnavailableView(
                "No guests match “\(query)”",
                systemImage: "magnifyingglass",
                description: Text("Search covers names, email, phone, custom fields, and city.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var filterSummary: String {
        "Active: " + tokens.map(\.title).joined(separator: ", ")
    }
}

private enum GuestsRoute: Hashable {
    case customFields
}

/// One removable condition shown beneath the chips.
private struct GuestFilterToken: Identifiable {
    let id: String
    let title: String
    let remove: (inout GuestFilterSet) -> Void

    static func tokens(
        for filters: GuestFilterSet,
        columns: [GuestCustomColumn]
    ) -> [GuestFilterToken] {
        var tokens = [GuestFilterToken]()

        for status in RSVPStatus.allCases where filters.rsvpStatuses.contains(status) {
            tokens.append(
                GuestFilterToken(id: "rsvp-\(status.rawValue)", title: status.title) { set in
                    set.rsvpStatuses.remove(status)
                }
            )
        }
        for bucket in filters.locations.sorted(by: { $0.title < $1.title }) {
            tokens.append(
                GuestFilterToken(id: "location-\(bucket.title)", title: bucket.title) { set in
                    set.locations.remove(bucket)
                }
            )
        }
        if filters.mappableOnly {
            tokens.append(GuestFilterToken(id: "mappable", title: "Mappable only") { $0.mappableOnly = false })
        }
        if filters.email != .any {
            let title = filters.email == .present ? "Has email" : "No email"
            tokens.append(GuestFilterToken(id: "email", title: title) { $0.email = .any })
        }
        if filters.phone != .any {
            let title = filters.phone == .present ? "Has phone" : "No phone"
            tokens.append(GuestFilterToken(id: "phone", title: title) { $0.phone = .any })
        }
        for column in columns {
            guard let condition = filters.customConditions[column.key], condition.isActive else { continue }
            let value: String
            switch condition {
            case let .anyOf(values):
                value = values
                    .sorted()
                    .map { $0 == GuestCustomCondition.emptyToken ? "Empty" : $0 }
                    .joined(separator: ", ")
            case let .checkbox(expected):
                value = expected ? "Yes" : "No"
            }
            tokens.append(
                GuestFilterToken(id: "custom-\(column.key)", title: "\(column.label): \(value)") { set in
                    set.customConditions.removeValue(forKey: column.key)
                }
            )
        }
        return tokens
    }
}

/// Structured conditions, not a query builder.
///
/// One sentence at the top states the AND/OR rule, which is what lets the sheet
/// omit a boolean operator control entirely.
@MainActor
private struct GuestFilterSheet: View {
    let store: VowbaseWorkspaceStore
    let searchText: String
    @Binding var filters: GuestFilterSet
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GuestFilterSet
    @State private var expandedColumn: String?

    init(store: VowbaseWorkspaceStore, searchText: String, filters: Binding<GuestFilterSet>) {
        self.store = store
        self.searchText = searchText
        _filters = filters
        _draft = State(initialValue: filters.wrappedValue)
    }

    private var records: [Guest] { store.allGuestRecords }

    /// The exact list the button promises, search included, so the count can
    /// never disagree with what appears after applying.
    private var previewCount: Int {
        GuestQuery.apply(
            to: records,
            columns: store.visibleCustomColumns,
            searchText: searchText,
            filters: draft,
            sort: .nameAscending
        ).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Guests match **all** of the conditions below.")
                        .font(.footnote)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .listRowBackground(Color.clear)
                }
                rsvpSection
                locationSection
                detailsSection
                customSection
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
        }
    }

    private var rsvpSection: some View {
        Section("RSVP") {
            ForEach(RSVPStatus.allCases, id: \.self) { status in
                checkRow(
                    title: status.title,
                    count: GuestQuery.count(records, rsvp: status),
                    isOn: draft.rsvpStatuses.contains(status)
                ) {
                    if draft.rsvpStatuses.contains(status) {
                        draft.rsvpStatuses.remove(status)
                    } else {
                        draft.rsvpStatuses.insert(status)
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        Section {
            ForEach(GuestQuery.locationBuckets(in: records), id: \.self) { bucket in
                checkRow(
                    title: bucket.title,
                    count: GuestQuery.count(records, in: bucket),
                    isOn: draft.locations.contains(bucket)
                ) {
                    if draft.locations.contains(bucket) {
                        draft.locations.remove(bucket)
                    } else {
                        draft.locations.insert(bucket)
                    }
                }
            }
            Toggle("Only mappable guests", isOn: $draft.mappableOnly)
                .tint(VowbaseTheme.rose)
        } header: {
            Text("Location")
        } footer: {
            Text("Mappable means the address resolved to city precision, which is all the map ever receives.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            presenceRow("Email", selection: $draft.email)
            presenceRow("Phone", selection: $draft.phone)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        let columns = store.visibleCustomColumns
        if store.customFieldsUnavailable {
            Section("Custom fields") {
                Text("Custom fields couldn’t be loaded, so they can’t be filtered right now.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } else if !columns.isEmpty {
            Section("Custom fields") {
                ForEach(columns) { column in
                    customRows(for: column)
                }
            }
        }
    }

    @ViewBuilder
    private func customRows(for column: GuestCustomColumn) -> some View {
        switch column.kind {
        case .checkbox:
            let current = draft.customConditions[column.key]
            LabeledContent(column.label) {
                Picker(column.label, selection: Binding(
                    get: {
                        if case let .checkbox(flag) = current { return flag ? "yes" : "no" }
                        return "any"
                    },
                    set: { value in
                        switch value {
                        case "yes": draft.customConditions[column.key] = .checkbox(true)
                        case "no": draft.customConditions[column.key] = .checkbox(false)
                        default: draft.customConditions.removeValue(forKey: column.key)
                        }
                    }
                )) {
                    Text("Any").tag("any")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
        case .select, .text, .number:
            let counts = GuestQuery.optionCounts(records, column: column)
            let selected = selectedValues(for: column.key)
            Button {
                expandedColumn = expandedColumn == column.key ? nil : column.key
            } label: {
                HStack {
                    Text(column.label).foregroundStyle(VowbaseTheme.ink)
                    Spacer()
                    Text(summary(for: column))
                        .foregroundStyle(selected.isEmpty ? VowbaseTheme.mutedInk : VowbaseTheme.rose)
                        .lineLimit(1)
                    Image(systemName: expandedColumn == column.key ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            if expandedColumn == column.key {
                ForEach(availableValues(for: column, counts: counts.options), id: \.self) { value in
                    checkRow(
                        title: value,
                        count: counts.options[value] ?? 0,
                        isOn: selected.contains(value),
                        indented: true
                    ) {
                        toggleValue(value, for: column.key)
                    }
                }
                checkRow(
                    title: "Empty",
                    count: counts.empty,
                    isOn: selected.contains(GuestCustomCondition.emptyToken),
                    indented: true
                ) {
                    toggleValue(GuestCustomCondition.emptyToken, for: column.key)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                filters = draft
                dismiss()
            } label: {
                Text(previewCount == 0
                     ? "No guests match"
                     : "Show \(previewCount) guest\(previewCount == 1 ? "" : "s")")
            }
            .buttonStyle(VowbasePrimaryButtonStyle())
            .disabled(previewCount == 0)

            if previewCount == 0 {
                Text("Loosen a condition to get results back.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }

            Button("Clear all") {
                draft = GuestFilterSet()
                expandedColumn = nil
            }
            .font(.system(size: 16))
            .tint(VowbaseTheme.rose)
            .disabled(draft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: Row helpers

    private func checkRow(
        title: String,
        count: Int,
        isOn: Bool,
        indented: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                Text(title)
                    .foregroundStyle(VowbaseTheme.ink)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.leading, indented ? 16 : 0)
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func presenceRow(_ label: String, selection: Binding<GuestPresenceFilter>) -> some View {
        LabeledContent(label) {
            Picker(label, selection: selection) {
                ForEach(GuestPresenceFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        }
    }

    // MARK: Condition plumbing

    private func selectedValues(for key: String) -> Set<String> {
        if case let .anyOf(values) = draft.customConditions[key] { return values }
        return []
    }

    private func toggleValue(_ value: String, for key: String) {
        var values = selectedValues(for: key)
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
        if values.isEmpty {
            draft.customConditions.removeValue(forKey: key)
        } else {
            draft.customConditions[key] = .anyOf(values)
        }
    }

    /// Declared options plus any value guests actually hold, so a renamed or
    /// removed option is still filterable while data references it.
    private func availableValues(for column: GuestCustomColumn, counts: [String: Int]) -> [String] {
        var values = GuestCustomFields.options(in: column)
        for stored in counts.keys where !values.contains(stored) {
            values.append(stored)
        }
        return values
    }

    private func summary(for column: GuestCustomColumn) -> String {
        switch draft.customConditions[column.key] {
        case let .anyOf(values) where !values.isEmpty:
            return values
                .sorted()
                .map { $0 == GuestCustomCondition.emptyToken ? "Empty" : $0 }
                .joined(separator: ", ")
        case let .checkbox(flag):
            return flag ? "Yes" : "No"
        default:
            return "Any"
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
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                if let subtitle = guest.subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            RSVPStatusCapsule(status: guest.rsvp)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

/// The guest record, edited in place.
///
/// There is no view mode and no edit mode: every row is a live control styled
/// to read as static text until focused, and each commits on its own.
@MainActor
private struct GuestDetailView: View {
    let guest: MVPGuest
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    @State private var undo: GuestUndo?

    /// The server-confirmed record. Rows read through this so a successful save
    /// adopts whatever the server actually stored.
    private var record: Guest? { store.guestRecord(id: guest.id) }

    var body: some View {
        List {
            if let record {
                header(record)
                rsvpSection(record)
                contactSection(record)
                locationSection(record)
                customFieldsSection(record)
                metadataSection(record)
            }
        }
        .scrollContentBackground(.hidden)
        .background(VowbaseTheme.blush)
        .navigationTitle("Guest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: GuestsRoute.customFields) {
                        Label("Manage fields", systemImage: "list.bullet.rectangle")
                    }
                    Button("Delete guest", role: .destructive) { isConfirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo {
                GuestUndoToast(undo: undo) { self.undo = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: undo?.id)
        .alert("Delete \(guest.name)?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                deleteGuest()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the guest from your wedding workspace.")
        }
    }

    // MARK: Sections

    private func header(_ record: Guest) -> some View {
        Section {
            HStack(spacing: 16) {
                Text(guest.initials)
                    .font(.system(size: 30, design: .serif))
                    .frame(width: 76, height: 76)
                    .background(VowbaseTheme.blush, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        GuestInlineField(
                            stored: record.firstName,
                            placeholder: "First",
                            isRequired: true,
                            font: .system(size: 21, design: .serif),
                            saveState: store.saveState(.init(guestID: guest.id, field: .firstName)),
                            capitalization: .words,
                            hugsContent: true,
                            commit: { await store.commitField(.firstName, for: guest.id, value: $0) }
                        )
                        GuestInlineField(
                            stored: record.lastName ?? "",
                            placeholder: "Last",
                            font: .system(size: 21, design: .serif),
                            saveState: store.saveState(.init(guestID: guest.id, field: .lastName)),
                            capitalization: .words,
                            hugsContent: true,
                            commit: { await store.commitField(.lastName, for: guest.id, value: $0) }
                        )
                        Spacer(minLength: 0)
                    }
                    RSVPStatusCapsule(status: record.rsvpStatus ?? .notInvited)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func rsvpSection(_ record: Guest) -> some View {
        Section {
            let key = GuestFieldKey(guestID: guest.id, field: "rsvpStatus")
            let current = record.rsvpStatus ?? .notInvited
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    GuestSaveIndicator(state: store.saveState(key))
                    Menu {
                        ForEach(RSVPStatus.allCases, id: \.self) { status in
                            Button {
                                changeRSVP(to: status, from: current)
                            } label: {
                                if status == current {
                                    Label(status.title, systemImage: "checkmark")
                                } else {
                                    Text(status.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(current.title)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VowbaseTheme.ink)
                    }
                }
            }
            if let responded = record.rsvpDate {
                LabeledContent("Responded", value: responded.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } header: {
            Text("RSVP")
        } footer: {
            Text("The response date is set by the server when the status changes.")
        }
    }

    private func contactSection(_ record: Guest) -> some View {
        Section("Contact") {
            inlineRow(.email, stored: record.email ?? "", keyboard: .emailAddress)
            inlineRow(.phone, stored: record.phone ?? "", keyboard: .phonePad)
        }
    }

    private func locationSection(_ record: Guest) -> some View {
        Section("Location") {
            let key = GuestFieldKey(guestID: guest.id, field: "address")
            LabeledContent("Address") {
                GuestInlineField(
                    stored: record.address ?? "",
                    placeholder: "Not added",
                    saveState: store.saveState(key),
                    capitalization: .words,
                    commit: { await store.commitAddress(for: guest.id, value: $0) }
                )
            }
            GuestDerivedLocationRow(record: record, isResolving: store.saveState(key) == .saving)
        }
    }

    @ViewBuilder
    private func customFieldsSection(_ record: Guest) -> some View {
        let columns = store.visibleCustomColumns
        Section {
            if store.customFieldsUnavailable {
                Text("Custom fields couldn’t be loaded. The rest of this guest is up to date.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else if columns.isEmpty {
                NavigationLink(value: GuestsRoute.customFields) {
                    Text("Add a field").foregroundStyle(VowbaseTheme.rose)
                }
            } else {
                ForEach(columns) { column in
                    GuestCustomFieldRow(
                        column: column,
                        record: record,
                        state: store.saveState(.customField(guestID: guest.id, key: column.key)),
                        commit: { value in store.commitCustomField(column, for: guest.id, value: value) },
                        onCleared: { previous in
                            offerUndo("\(column.label) cleared") {
                                store.commitCustomField(column, for: guest.id, value: previous)
                            }
                        }
                    )
                }
                NavigationLink(value: GuestsRoute.customFields) {
                    Text("Add a field").foregroundStyle(VowbaseTheme.rose)
                }
            }
        } header: {
            Text("Custom fields")
        } footer: {
            if !columns.isEmpty {
                Text("Fields appear in the order set on Manage fields. Hidden fields keep their data.")
            }
        }
    }

    private func metadataSection(_ record: Guest) -> some View {
        Section {
            LabeledContent("Added", value: record.createdAt.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(VowbaseTheme.mutedInk)
        }
    }

    // MARK: Helpers

    private func inlineRow(
        _ field: GuestEditableField,
        stored: String,
        keyboard: UIKeyboardType
    ) -> some View {
        LabeledContent(field.label) {
            GuestInlineField(
                stored: stored,
                placeholder: "Not added",
                isRequired: field.isRequired,
                saveState: store.saveState(.init(guestID: guest.id, field: field)),
                keyboard: keyboard,
                commit: { await store.commitField(field, for: guest.id, value: $0) }
            )
        }
    }

    private func changeRSVP(to status: RSVPStatus, from previous: RSVPStatus) {
        Task {
            guard await store.commitRSVP(status, for: guest.id) else { return }
            offerUndo("RSVP set to \(status.title)") {
                Task { await store.commitRSVP(previous, for: guest.id) }
            }
        }
    }

    private func offerUndo(_ message: String, action: @escaping () -> Void) {
        let entry = GuestUndo(message: message, action: action)
        undo = entry
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undo?.id == entry.id { undo = nil }
        }
    }

    private func deleteGuest() {
        Task {
            guard await store.deleteGuest(guest) else {
                store.presentSaveFailure(retry: deleteGuest)
                return
            }
            dismiss()
        }
    }
}

private struct GuestUndo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let action: () -> Void

    static func == (lhs: GuestUndo, rhs: GuestUndo) -> Bool { lhs.id == rhs.id }
}

private struct GuestUndoToast: View {
    let undo: GuestUndo
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(undo.message)
                .font(.system(size: 15))
                .foregroundStyle(VowbaseTheme.background)
            Spacer(minLength: 8)
            Button("Undo") {
                undo.action()
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .tint(VowbaseTheme.rose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(VowbaseTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A value that reads as text and edits as text, with no mode switch.
///
/// Commits on blur or return. A failed save leaves the typed value in place
/// rather than reverting to what the server holds.
/// Reports the natural width of whatever it's attached to, so a sibling can
/// be resized to match. `TextField` alone won't hug its own text reliably
/// when unconstrained — its ideal-size computation isn't as precise as
/// `Text`'s — so measuring a hidden `Text` with the same string is the
/// robust way to size a field to its content rather than to available space.
private struct GuestInlineFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GuestInlineField: View {
    let stored: String
    var placeholder: String = "Not added"
    var isRequired: Bool = false
    var font: Font = .body
    let saveState: GuestFieldSaveState?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    /// When true, the field sizes itself to its own text instead of expanding
    /// to fill the row — for adjacent short fields like First/Last name,
    /// where a flexible TextField would otherwise claim roughly half the row
    /// no matter how short the actual name is, leaving a wide gap between them.
    var hugsContent: Bool = false
    let commit: (String) async -> Void

    @State private var draft = ""
    @State private var showsRequiredWarning = false
    @State private var measuredWidth: CGFloat?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .font(font)
                    .focused($isFocused)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .submitLabel(.done)
                    .onSubmit { isFocused = false }
                    .background(alignment: .leading) {
                        if hugsContent {
                            Text(draft.isEmpty ? placeholder : draft)
                                .font(font)
                                .lineLimit(1)
                                .fixedSize()
                                .hidden()
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: GuestInlineFieldWidthKey.self,
                                            value: proxy.size.width
                                        )
                                    }
                                )
                        }
                    }
                    .onPreferenceChange(GuestInlineFieldWidthKey.self) { width in
                        guard hugsContent else { return }
                        measuredWidth = width
                    }
                    .frame(width: hugsContent ? max(measuredWidth ?? 0, 16) + 6 : nil)
                if saveState == .saving || saveState == .saved {
                    GuestSaveIndicator(state: saveState)
                }
            }
            .padding(.horizontal, isFocused ? 8 : 0)
            .padding(.vertical, isFocused ? 6 : 0)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VowbaseTheme.blush)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(VowbaseTheme.rose, lineWidth: 1.5)
                        )
                }
            }

            if showsRequiredWarning {
                Text("First name can’t be empty.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.rose)
            }
            if case let .failed(pending) = saveState {
                GuestSaveFailureNote {
                    Task { await commit(pending ?? draft) }
                }
            }
        }
        .onAppear { draft = stored }
        .onChange(of: stored) { _, newValue in
            // Adopt the server-confirmed value, but never yank text out from
            // under someone who is still typing.
            if !isFocused { draft = newValue }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            guard wasFocused, !focused else { return }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRequired, trimmed.isEmpty {
                draft = stored
                showsRequiredWarning = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showsRequiredWarning = false
                }
                return
            }
            Task { await commit(draft) }
        }
    }
}

private struct GuestSaveIndicator: View {
    let state: GuestFieldSaveState?

    var body: some View {
        switch state {
        case .saving:
            ProgressView().controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.green)
                .transition(.opacity)
        case .failed, .none:
            EmptyView()
        }
    }
}

private struct GuestSaveFailureNote: View {
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Couldn’t save. Your value is still here.")
                .font(.caption)
                .foregroundStyle(VowbaseTheme.rose)
            Spacer(minLength: 4)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(VowbaseTheme.rose)
        }
        .padding(.top, 2)
    }
}

/// Read-only context derived from the address.
///
/// These are outputs of geocoding, not blanks the user failed to fill, so the
/// row explains their state instead of presenting empty inputs.
private struct GuestDerivedLocationRow: View {
    let record: Guest
    let isResolving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isResolving {
                HStack(spacing: 8) {
                    Text("Locating…").foregroundStyle(VowbaseTheme.mutedInk)
                    ProgressView().controlSize(.mini)
                }
            } else if record.originPrecision == "city", let label = record.originLabel {
                HStack(spacing: 8) {
                    Text(label)
                    Text("City")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VowbaseTheme.guestBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(VowbaseTheme.guestBlue)
                }
                Text("Shown on the map as part of a city cluster. The exact address never leaves this screen.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else if record.address?.nilIfBlank != nil {
                Text("Location not mapped").foregroundStyle(VowbaseTheme.mutedInk)
                Text("This address didn’t resolve to a city, so no map cluster includes this guest.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else {
                Text("No location").foregroundStyle(VowbaseTheme.mutedInk)
                Text("Add an address to include this guest in the map’s city clusters.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One custom field, rendered with the single control its kind allows.
private struct GuestCustomFieldRow: View {
    let column: GuestCustomColumn
    let record: Guest
    let state: GuestFieldSaveState?
    let commit: (JSONValue?) -> Void
    let onCleared: (JSONValue?) -> Void

    private var stored: JSONValue? {
        GuestCustomFields.value(in: record.customFields, for: column.key)
    }

    var body: some View {
        if GuestCustomFields.isUnsupported(stored, kind: column.kind) {
            unsupportedRow
        } else {
            switch column.kind {
            case .checkbox: checkboxRow
            case .select: selectRow
            case .text, .number: textRow
            }
        }
    }

    private var unsupportedRow: some View {
        LabeledContent(column.label) {
            HStack(spacing: 8) {
                Text("Unsupported value")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                Button("Clear") { commit(nil) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(VowbaseTheme.rose)
            }
        }
    }

    private var checkboxRow: some View {
        Toggle(isOn: Binding(
            get: { stored == .bool(true) },
            set: { commit($0 ? .bool(true) : nil) }
        )) {
            HStack(spacing: 8) {
                Text(column.label)
                GuestSaveIndicator(state: state)
            }
        }
        .tint(VowbaseTheme.rose)
    }

    private var selectRow: some View {
        let options = GuestCustomFields.options(in: column)
        let current = GuestCustomFields.displayText(stored, kind: column.kind)
        // A value the column no longer offers is still shown, so the user can
        // see what is there before replacing it.
        let isOrphaned = current.map { !options.contains($0) } ?? false

        return LabeledContent(column.label) {
            HStack(spacing: 8) {
                GuestSaveIndicator(state: state)
                Menu {
                    if let current, isOrphaned {
                        Button {
                        } label: {
                            Label("\(current) — no longer an option", systemImage: "checkmark")
                        }
                        .disabled(true)
                    }
                    ForEach(options, id: \.self) { option in
                        Button {
                            commit(.string(option))
                        } label: {
                            if option == current {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                    if current != nil {
                        Divider()
                        Button("Clear", role: .destructive) {
                            let previous = stored
                            commit(nil)
                            onCleared(previous)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(current ?? "Not set")
                            .foregroundStyle(current == nil ? VowbaseTheme.mutedInk : VowbaseTheme.ink)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
            }
        }
    }

    private var textRow: some View {
        LabeledContent(column.label) {
            GuestInlineField(
                stored: GuestCustomFields.displayText(stored, kind: column.kind) ?? "",
                saveState: state,
                keyboard: column.kind == .number ? .decimalPad : .default,
                capitalization: column.kind == .number ? .never : .sentences,
                commit: { text in
                    commit(GuestCustomFields.encode(text, kind: column.kind))
                }
            )
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
                        saveVenue()
                    }
                    .disabled(name.trimmed.isEmpty || isSaving)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }

    private func saveVenue() {
        isSaving = true
        Task {
            let didSave = await store.createVenue(name: name, location: location, status: status)
            isSaving = false
            guard didSave else {
                store.presentSaveFailure(retry: saveVenue, discard: { dismiss() })
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

/// Creation stays an atomic commit with an explicit Save.
///
/// Inline autosave is right for a record that exists and wrong for one that
/// does not, so this sheet keeps a Save button — but it no longer caps what can
/// be captured. Essentials sit at the medium detent; More details grows the
/// sheet in place so the name you just typed stays visible.
@MainActor
private struct AddGuestSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFirstNameFocused: Bool

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var rsvp: RSVPStatus = .notInvited
    @State private var customValues = [String: JSONValue]()
    @State private var isSaving = false
    @State private var failureMessage: String?
    @State private var detent: PresentationDetent = .medium

    /// Someone who adds one guest with a meal choice is adding forty, so the
    /// disclosure state persists for the session.
    @AppStorage("guestAddShowsMoreDetails") private var showsMoreDetails = false

    private var canSave: Bool { !firstName.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                essentialsSection
                if showsMoreDetails {
                    moreDetailsSection
                }
                if let failureMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(failureMessage)
                                .font(.footnote)
                                .foregroundStyle(VowbaseTheme.rose)
                            Button("Retry") { save() }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(VowbaseTheme.rose)
                        }
                        .padding(.vertical, 2)
                    }
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
                    Button("Save guest") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { isFirstNameFocused = true }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    // MARK: Sections

    private var essentialsSection: some View {
        Section {
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

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    showsMoreDetails.toggle()
                    // Grow in place rather than pushing: the essentials must
                    // stay on screen while the rest is filled in.
                    detent = showsMoreDetails ? .large : .medium
                }
            } label: {
                HStack {
                    Spacer()
                    Text(showsMoreDetails ? "Fewer details" : "More details")
                    Image(systemName: showsMoreDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
            }
            .tint(VowbaseTheme.rose)
            .accessibilityHint(showsMoreDetails
                               ? "Hides contact and custom fields"
                               : "Shows contact and custom fields")
        } header: {
            Text("First, the essentials")
        }
    }

    /// Contact and custom fields share one section rather than three separate
    /// blocks of header/footer chrome — the disclosure button already explains
    /// what "More details" reveals, so the fields don't need their own
    /// sub-headings to be legible.
    private var moreDetailsSection: some View {
        Section {
            TextField("Email (optional)", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            TextField("Phone (optional)", text: $phone)
                .keyboardType(.phonePad)
            ForEach(store.visibleCustomColumns) { column in
                customField(column)
            }
        } header: {
            Text("More details")
        } footer: {
            if store.customFieldsUnavailable {
                Text("Custom fields couldn’t be loaded. You can still save this guest and fill them in later.")
            } else if store.visibleCustomColumns.isEmpty {
                Text("Add custom fields from Manage fields on the Guests tab.")
            }
        }
    }

    @ViewBuilder
    private func customField(_ column: GuestCustomColumn) -> some View {
        switch column.kind {
        case .checkbox:
            Toggle(column.label, isOn: Binding(
                get: { customValues[column.key] == .bool(true) },
                set: { customValues[column.key] = $0 ? .bool(true) : nil }
            ))
            .tint(VowbaseTheme.rose)

        case .select:
            Picker(column.label, selection: Binding(
                get: { GuestCustomFields.displayText(customValues[column.key], kind: column.kind) ?? "" },
                set: { customValues[column.key] = $0.isEmpty ? nil : .string($0) }
            )) {
                Text("Not set").tag("")
                ForEach(GuestCustomFields.options(in: column), id: \.self) { option in
                    Text(option).tag(option)
                }
            }

        case .text, .number:
            // A bare TextField loses its identity once filled in — its
            // placeholder is the only label, and placeholders disappear on
            // input. LabeledContent keeps the field's name pinned in place,
            // matching how Group and Meal choice already read.
            LabeledContent(column.label) {
                TextField("", text: Binding(
                    get: { GuestCustomFields.displayText(customValues[column.key], kind: column.kind) ?? "" },
                    set: { customValues[column.key] = GuestCustomFields.encode($0, kind: column.kind) }
                ))
                .multilineTextAlignment(.trailing)
                .keyboardType(column.kind == .number ? .decimalPad : .default)
            }
        }
    }

    // MARK: Save

    private func save() {
        isSaving = true
        failureMessage = nil
        Task {
            let created = await store.createGuest(
                firstName: firstName,
                lastName: lastName,
                location: location,
                rsvp: rsvp,
                email: email,
                phone: phone,
                customFields: customValues
            )
            isSaving = false
            guard let created else {
                // Everything entered stays on the sheet; only the error is new.
                failureMessage = store.errorMessage ?? "Couldn’t save this guest. Your details are still here."
                return
            }
            _ = created
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
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
                        saveVenue()
                    }
                    .disabled(name.trimmed.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveVenue() {
        isSaving = true
        Task {
            let didSave = await store.updateVenue(venue, name: name, location: location, status: status)
            isSaving = false
            guard didSave else {
                store.presentSaveFailure(retry: saveVenue, discard: { dismiss() })
                return
            }
            dismiss()
        }
    }
}

// MARK: - Custom field administration

private extension GuestCustomColumnKind {
    var title: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .select: "Select"
        case .checkbox: "Checkbox"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .select: "list.bullet"
        case .checkbox: "checkmark.square"
        }
    }

    /// What happens to values already stored when a column changes to this kind.
    var coercionWarning: String {
        switch self {
        case .number: "Values that aren’t numbers will be cleared."
        case .text: "Values are preserved as text."
        case .select: "Existing distinct values become the starting option list."
        case .checkbox: "Any non-empty value becomes checked."
        }
    }
}

/// The wedding's own field schema.
///
/// Order set here drives guest detail, Add guest, and the filter sheet, so this
/// is the one place ordering is decided.
@MainActor
private struct GuestFieldListView: View {
    let store: VowbaseWorkspaceStore
    @State private var editingColumn: GuestCustomColumn?
    @State private var isCreating = false
    @State private var pendingDeletion: GuestCustomColumn?

    private var columns: [GuestCustomColumn] { store.allCustomColumns }

    var body: some View {
        List {
            if columns.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(columns) { column in
                        Button {
                            editingColumn = column
                        } label: {
                            row(column)
                        }
                        .swipeActions(edge: .leading) {
                            Button(column.hidden ? "Show" : "Hide") {
                                Task { await store.updateCustomColumn(column, hidden: !column.hidden) }
                            }
                            .tint(VowbaseTheme.mutedInk)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { pendingDeletion = column }
                        }
                    }
                    .onMove { source, destination in
                        Task { await store.reorderCustomColumns(from: source, to: destination) }
                    }
                    .onDelete { offsets in
                        // Edit mode replaces swipe actions with its own delete
                        // control, so this is the only path to Delete once
                        // reordering is active. Route it through the same
                        // confirmation rather than deleting immediately.
                        if let index = offsets.first {
                            pendingDeletion = columns[index]
                        }
                    }
                } header: {
                    Text("\(columns.count) field\(columns.count == 1 ? "" : "s")")
                } footer: {
                    Text("Drag to reorder. This order controls guest detail, Add guest, and the filter sheet. The number is how many guests hold a value.")
                }
            }

            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Add a field", systemImage: "plus")
                }
                .tint(VowbaseTheme.rose)
            }

            if columns.filter { !$0.hidden }.count > 12 {
                Section {
                    Text("Long field lists make guest rows harder to scan. Consider hiding seasonal fields instead of deleting them.")
                        .font(.footnote)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(VowbaseTheme.groupedBackground)
        .tint(VowbaseTheme.rose)
        .navigationTitle("Manage fields")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(VowbaseTheme.rose) }
        }
        .sheet(item: $editingColumn) { column in
            GuestFieldEditorView(store: store, column: column)
        }
        .sheet(isPresented: $isCreating) {
            GuestFieldEditorView(store: store, column: nil)
        }
        .alert(
            "Delete “\(pendingDeletion?.label ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { column in
            Button("Delete field", role: .destructive) {
                Task { await store.deleteCustomColumn(column) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            let used = store.usageCount(for: column)
            Text(
                used == 0
                    ? "No guests hold a value for this field."
                    : "This permanently removes the value stored for \(used) guest\(used == 1 ? "" : "s"). It can’t be undone."
            )
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No custom fields yet.")
                    .font(.headline)
                Text("Add fields for the things you track per guest — Group, Meal choice, Plus one, Table.")
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ column: GuestCustomColumn) -> some View {
        HStack(spacing: 12) {
            Image(systemName: column.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VowbaseTheme.rose)
                .frame(width: 30, height: 30)
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(column.label)
                    .foregroundStyle(VowbaseTheme.ink)
                Text(column.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            Spacer(minLength: 8)
            if column.hidden {
                Text("Hidden")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(VowbaseTheme.border.opacity(0.5), in: Capsule())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else {
                Text("\(store.usageCount(for: column))")
                    .monospacedDigit()
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .opacity(column.hidden ? 0.55 : 1)
    }
}

/// Creates or edits one column. Both flows share this form because the only
/// real difference is whether the key is still up for grabs.
@MainActor
private struct GuestFieldEditorView: View {
    let store: VowbaseWorkspaceStore
    /// Nil when creating.
    let column: GuestCustomColumn?

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kind: GuestCustomColumnKind
    @State private var options: [String]
    @State private var hidden: Bool
    @State private var newOption = ""
    @State private var pendingKind: GuestCustomColumnKind?
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, column: GuestCustomColumn?) {
        self.store = store
        self.column = column
        _label = State(initialValue: column?.label ?? "")
        _kind = State(initialValue: column?.kind ?? .text)
        _options = State(initialValue: column.map(GuestCustomFields.options(in:)) ?? [])
        _hidden = State(initialValue: column?.hidden ?? false)
    }

    private var isCreating: Bool { column == nil }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                kindSection
                if kind == .select {
                    optionsSection
                }
                visibilitySection
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .tint(VowbaseTheme.rose)
            .navigationTitle(isCreating ? "Add field" : "Edit field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Add" : "Save") { save() }
                        .disabled(label.trimmed.isEmpty || isSaving)
                }
            }
            .alert(
                "Change “\(label)” to \(pendingKind?.title.lowercased() ?? "")?",
                isPresented: Binding(
                    get: { pendingKind != nil },
                    set: { if !$0 { pendingKind = nil } }
                ),
                presenting: pendingKind
            ) { target in
                Button("Change kind") { apply(kind: target) }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                let affected = column.map(store.usageCount(for:)) ?? 0
                Text("\(target.coercionWarning) \(affected) guest\(affected == 1 ? "" : "s") hold a value for this field.")
            }
            .alert(
                "Rename “\(renameTarget ?? "")”",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("Option name", text: $renameText)
                Button("Rename and rewrite") { commitRename(rewriting: true) }
                Button("Rename only") { commitRename(rewriting: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let target = renameTarget, let column {
                    let used = store.usageCount(for: column, option: target)
                    Text("\(used) guest\(used == 1 ? "" : "s") use this option. Rewriting updates them; renaming only leaves them on the old label.")
                }
            }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            TextField("Label", text: $label)
                .textInputAutocapitalization(.words)
            LabeledContent("Key") {
                Text(column?.key ?? store.proposedKey(for: label))
                    .font(.callout.monospaced())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } footer: {
            Text(isCreating
                 ? "The key is generated from the label and shared with the web workspace. It can’t change later."
                 : "The key is shared with the web workspace and can’t change after the field is created. Renaming the label is safe and updates every screen.")
        }
    }

    private var kindSection: some View {
        Section {
            ForEach([GuestCustomColumnKind.text, .number, .select, .checkbox], id: \.self) { option in
                Button {
                    select(kind: option)
                } label: {
                    HStack {
                        Image(systemName: option.symbol)
                            .foregroundStyle(VowbaseTheme.rose)
                            .frame(width: 24)
                        Text(option.title).foregroundStyle(VowbaseTheme.ink)
                        Spacer()
                        if option == kind {
                            Image(systemName: "checkmark").foregroundStyle(VowbaseTheme.rose)
                        }
                    }
                }
            }
        } header: {
            Text("Kind")
        } footer: {
            if !isCreating {
                Text("Changing the kind converts stored values. You’ll see how many guests are affected first.")
            }
        }
    }

    private var optionsSection: some View {
        Section {
            ForEach(options, id: \.self) { option in
                HStack {
                    Text(option)
                    Spacer()
                    if let column {
                        Text("\(store.usageCount(for: column, option: option))")
                            .monospacedDigit()
                            .foregroundStyle(VowbaseTheme.mutedInk)
                        Button {
                            renameTarget = option
                            renameText = option
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .tint(VowbaseTheme.rose)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        options.removeAll { $0 == option }
                    }
                }
            }
            .onMove { source, destination in
                options.move(fromOffsets: source, toOffset: destination)
            }
            HStack {
                TextField("Add an option", text: $newOption)
                Button("Add") {
                    let trimmed = newOption.trimmed
                    guard !trimmed.isEmpty, !options.contains(trimmed) else { return }
                    options.append(trimmed)
                    newOption = ""
                }
                .disabled(newOption.trimmed.isEmpty)
            }
        } header: {
            Text("Options")
        } footer: {
            Text(isCreating
                 ? "Add the choices this field offers."
                 : "Renaming asks whether to rewrite the guests using an option. Removing one leaves their value in place, shown as no longer an option.")
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle("Hidden", isOn: $hidden)
                .tint(VowbaseTheme.rose)
        } footer: {
            Text("Hidden fields keep their data and stay visible in the web workspace. Use this for seasonal fields instead of deleting them.")
        }
    }

    // MARK: Actions

    private func select(kind target: GuestCustomColumnKind) {
        guard target != kind else { return }
        // Creating a field has no stored values to convert, so no warning.
        guard !isCreating, let column, store.usageCount(for: column) > 0 else {
            apply(kind: target)
            return
        }
        pendingKind = target
    }

    private func apply(kind target: GuestCustomColumnKind) {
        if target == .select, options.isEmpty, let column {
            // Seed the option list from what guests already hold.
            let existing = store.allGuestRecords.compactMap { guest -> String? in
                let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
                return GuestCustomFields.displayText(stored, kind: column.kind)
            }
            options = Set(existing).sorted()
        }
        kind = target
        pendingKind = nil
    }

    private func commitRename(rewriting: Bool) {
        guard let column, let original = renameTarget else { return }
        let replacement = renameText.trimmed
        renameTarget = nil
        guard !replacement.isEmpty, replacement != original else { return }
        Task {
            await store.renameOption(
                column,
                from: original,
                to: replacement,
                rewritingGuests: rewriting
            )
            let refreshed = store.allCustomColumns.first { $0.id == column.id } ?? column
            options = GuestCustomFields.options(in: refreshed)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let didSave: Bool
            if let column {
                didSave = await store.updateCustomColumn(
                    column,
                    label: label,
                    kind: kind,
                    options: kind == .select ? options : [],
                    hidden: hidden
                )
            } else {
                didSave = await store.createCustomColumn(
                    label: label,
                    kind: kind,
                    options: kind == .select ? options : []
                )
            }
            isSaving = false
            if didSave { dismiss() }
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

struct MVPVenue: Identifiable, Hashable {
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

struct GuestCluster: Identifiable {
    let id: String
    let city: String
    let count: Int
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct MVPGuest: Identifiable, Hashable {
    let id: UUID
    let firstName: String
    let lastName: String
    /// Row subtitle resolved from this wedding's own column definitions.
    /// Nil when no suitable column exists or the guest has no value for it.
    let subtitle: String?
    let location: String?
    let email: String?
    let phone: String?
    let rsvp: RSVPStatus
    let isMappable: Bool
    /// Flattened custom values so search reaches custom fields too.
    let customSearchText: String

    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var initials: String {
        [firstName.first, lastName.first]
            .compactMap { $0 }
            .map { String($0).uppercased() }
            .joined()
    }
    var searchText: String {
        [name, subtitle, location, email, phone, customSearchText]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

@MainActor
@Observable
final class VowbaseWorkspaceStore {
    private let repositories: RepositoryContainer?
    private var venueRecords = [Venue]()
    private var signedVenuePhotoURLs = [UUID: [URL]]()
    private var guestRecords = [Guest]()
    private var customColumnRecords = [GuestCustomColumn]()

    /// Serializes each guest's custom-field writes. `GuestPatch.customFields`
    /// replaces the whole JSON object, so two concurrent row commits would
    /// clobber one another without this chain.
    private var customFieldWrites = [UUID: Task<Void, Never>]()

    var selectedVenueID: UUID?
    var isGlobalMenuOpen = false
    var wedding: WeddingSummary?
    var activeMembership: WeddingMembership?
    var isLoading = false
    var errorMessage: String?
    fileprivate var saveFailure: SaveFailure?

    var canManageTasks: Bool {
        guard let role = activeMembership?.role else { return false }
        return role == .owner || role == .partner || role == .planner
    }

    /// Set when column definitions fail to load. Custom-field rows are hidden
    /// rather than shown broken, and the guest list stays usable.
    var customFieldsUnavailable = false

    /// Per-row save state for inline editing, keyed by guest and field.
    private(set) var fieldSaveStates = [GuestFieldKey: GuestFieldSaveState]()

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
        activeMembership = WeddingMembership(
            id: UUID(uuidString: "C1175B62-0CD8-43EC-9AC4-A3C2F65A2598")!,
            weddingId: weddingID,
            userId: UUID(uuidString: "3B4C76E4-E7A5-48A3-B351-439E9488273B")!,
            role: .owner,
            status: "active",
            wedding: wedding!
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
        customColumnRecords = [
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C01")!, weddingID: weddingID, key: "group", label: "Group", kind: .select, options: .array([.string("Cedar Circle"), .string("Juniper Guild")]), position: 0, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C02")!, weddingID: weddingID, key: "meal_choice", label: "Meal choice", kind: .select, options: .array([.string("Chicken"), .string("Fish"), .string("Vegetarian")]), position: 1, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C03")!, weddingID: weddingID, key: "plus_one", label: "Plus one", kind: .checkbox, options: .array([]), position: 2, hidden: false, createdAt: createdAt, updatedAt: createdAt),
            GuestCustomColumn(id: UUID(uuidString: "0B2F1C8A-1C1E-4C0B-9E6E-6C5E1A2B3C04")!, weddingID: weddingID, key: "table", label: "Table", kind: .number, options: .array([]), position: 3, hidden: false, createdAt: createdAt, updatedAt: createdAt)
        ]
        selectedVenueID = venueRecords.first?.id
    }
#endif

    var venues: [MVPVenue] {
        venueRecords.map { venue in
            MVPVenue(venue, photoURLs: signedVenuePhotoURLs[venue.id] ?? [])
        }
    }
    var guests: [MVPGuest] {
        let columns = customColumnRecords
        return guestRecords.map { MVPGuest($0, columns: columns) }
    }
    var weddingTitle: String { wedding?.coupleNames ?? wedding?.name ?? "Your wedding" }

    /// Columns offered for editing and filtering, in their configured order.
    /// Empty while definitions are unavailable so rows never render broken.
    var visibleCustomColumns: [GuestCustomColumn] {
        customFieldsUnavailable ? [] : GuestDisplayResolver.visibleColumns(customColumnRecords)
    }

    /// Every column including hidden ones, for the administration screen.
    var allCustomColumns: [GuestCustomColumn] {
        GuestDisplayResolver.orderedColumns(customColumnRecords)
    }

    func guestRecord(id: UUID) -> Guest? {
        guestRecords.first { $0.id == id }
    }

    /// Raw records, for the counts the filter sheet shows before applying.
    var allGuestRecords: [Guest] { guestRecords }

    func filteredGuests(
        searchText: String,
        filters: GuestFilterSet,
        sort: GuestSortOrder
    ) -> [MVPGuest] {
        let columns = customColumnRecords
        return GuestQuery
            .apply(to: guestRecords, columns: columns, searchText: searchText, filters: filters, sort: sort)
            .map { MVPGuest($0, columns: columns) }
    }

    func saveState(_ key: GuestFieldKey) -> GuestFieldSaveState? {
        fieldSaveStates[key]
    }

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
                customColumnRecords = []
                wedding = nil
                activeMembership = nil
                errorMessage = "This account is not a member of a wedding workspace yet."
                presentLoadFailure()
                return
            }

            wedding = membership.wedding
            activeMembership = membership
            async let venues = repositories.venues.venues(weddingID: membership.weddingId)
            async let guests = repositories.guests.guests(weddingID: membership.weddingId)
            // Column definitions degrade on their own: losing them should hide
            // custom fields, never take the guest list down with them.
            async let columns = try? repositories.guests.customColumns(weddingID: membership.weddingId)
            venueRecords = try await venues
            guestRecords = try await guests
            if let loadedColumns = await columns {
                customColumnRecords = GuestDisplayResolver.orderedColumns(loadedColumns)
                customFieldsUnavailable = false
            } else {
                customColumnRecords = []
                customFieldsUnavailable = true
            }
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
            presentLoadFailure()
        }
    }

    func presentSaveFailure(
        retry: @escaping @MainActor () -> Void,
        discard: @escaping @MainActor () -> Void = {}
    ) {
        let message = errorMessage ?? "Something went wrong while saving your changes."
        errorMessage = nil
        saveFailure = SaveFailure(message: message, retry: retry, discard: discard)
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

    /// Creates a guest from every field the Add sheet can capture.
    ///
    /// Returns the created record so the caller can navigate to it. Geocoding
    /// runs first but never blocks the save: an unresolvable address is still
    /// stored, just without a map origin.
    func createGuest(
        firstName: String,
        lastName: String,
        location: String,
        rsvp: RSVPStatus,
        email: String = "",
        phone: String = "",
        customFields: [String: JSONValue] = [:]
    ) async -> Guest? {
        guard let repositories, let weddingID = wedding?.id else {
            _ = unavailable()
            return nil
        }
        do {
            let resolved = await resolvedLocation(for: location, repositories: repositories)
            let guest = try await repositories.guests.createGuest(
                GuestDraft(
                    firstName: firstName.trimmed,
                    lastName: lastName.nilIfBlank,
                    email: email.nilIfBlank,
                    phone: phone.nilIfBlank,
                    address: resolved.displayName,
                    customFields: .object(customFields),
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
            errorMessage = nil
            return guest
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    // MARK: - Inline guest editing

    /// Commits one plain-text field.
    ///
    /// Returns false without touching the network when the value is unchanged
    /// or fails validation, so an unmodified row costs nothing.
    @discardableResult
    func commitField(
        _ field: GuestEditableField,
        for guestID: UUID,
        value: String
    ) async -> Bool {
        guard let record = guestRecord(id: guestID) else { return false }
        let key = GuestFieldKey(guestID: guestID, field: field)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != (field.currentValue(in: record) ?? "") else {
            fieldSaveStates[key] = nil
            return false
        }
        guard let patch = field.patch(newValue: trimmed) else {
            // Required and empty. The row restores itself and says why.
            fieldSaveStates[key] = nil
            return false
        }
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
    }

    /// Commits the address, then re-derives the coarse map origin from it.
    ///
    /// Geocoding runs after the write lands and never blocks or reverts it: an
    /// address that cannot be resolved is still the user's address.
    @discardableResult
    func commitAddress(for guestID: UUID, value: String) async -> Bool {
        guard let repositories, let record = guestRecord(id: guestID) else { return false }
        let key = GuestFieldKey(guestID: guestID, field: "address")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (record.address ?? "") else {
            fieldSaveStates[key] = nil
            return false
        }

        guard !trimmed.isEmpty else {
            // Clearing the address clears everything derived from it.
            let patch = GuestPatch(
                address: .null,
                originLabel: .null,
                originLatitude: .null,
                originLongitude: .null,
                originPrecision: .null,
                geocodeStatus: .null
            )
            return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
        }

        // Show progress across the geocode too, not just the write that follows.
        fieldSaveStates[key] = .saving
        let resolved = await resolvedLocation(for: trimmed, repositories: repositories)
        let patch = GuestPatch(
            address: .value(trimmed),
            originLabel: (resolved.city ?? resolved.displayName).map(NullablePatch.value) ?? .null,
            originLatitude: resolved.latitude.map(NullablePatch.value) ?? .null,
            originLongitude: resolved.longitude.map(NullablePatch.value) ?? .null,
            originPrecision: resolved.city == nil ? .null : .value("city"),
            geocodeStatus: resolved.latitude == nil ? .null : .value("resolved")
        )
        return await applyPatch(patch, guestID: guestID, key: key, pendingValue: trimmed)
    }

    @discardableResult
    func commitRSVP(_ status: RSVPStatus, for guestID: UUID) async -> Bool {
        guard let record = guestRecord(id: guestID), record.rsvpStatus != status else { return false }
        let key = GuestFieldKey(guestID: guestID, field: "rsvpStatus")
        return await applyPatch(
            GuestPatch(rsvpStatus: .value(status)),
            guestID: guestID,
            key: key,
            pendingValue: nil
        )
    }

    /// Queues a custom-field write behind this guest's other custom-field
    /// writes. The merge base is read when the write runs, not when the row was
    /// focused, so edits to different keys cannot erase each other.
    func commitCustomField(_ column: GuestCustomColumn, for guestID: UUID, value: JSONValue?) {
        let previous = customFieldWrites[guestID]
        customFieldWrites[guestID] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.writeCustomField(column, guestID: guestID, value: value)
        }
    }

    private func writeCustomField(
        _ column: GuestCustomColumn,
        guestID: UUID,
        value: JSONValue?
    ) async {
        guard let repositories, let record = guestRecord(id: guestID) else { return }
        let key = GuestFieldKey.customField(guestID: guestID, key: column.key)
        fieldSaveStates[key] = .saving

        let merged = GuestCustomFields.merging(record.customFields, key: column.key, value: value)
        do {
            let updated = try await repositories.guests.updateGuest(
                id: guestID,
                patch: GuestPatch(customFields: merged)
            )
            replace(updated, in: &guestRecords)
            markSaved(key)
        } catch is CancellationError {
            fieldSaveStates[key] = nil
        } catch {
            let pending = GuestCustomFields.displayText(value, kind: column.kind)
            fieldSaveStates[key] = .failed(pendingValue: pending)
        }
    }

    /// Sends a single-field patch and reconciles the row's save state.
    ///
    /// A failure keeps `pendingValue` on the row so the user's input survives;
    /// nothing is reverted and nothing is discarded.
    private func applyPatch(
        _ patch: GuestPatch,
        guestID: UUID,
        key: GuestFieldKey,
        pendingValue: String?
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        guard !patch.isEmpty else { return false }
        fieldSaveStates[key] = .saving
        do {
            let updated = try await repositories.guests.updateGuest(id: guestID, patch: patch)
            replace(updated, in: &guestRecords)
            markSaved(key)
            return true
        } catch is CancellationError {
            fieldSaveStates[key] = nil
            return false
        } catch {
            fieldSaveStates[key] = .failed(pendingValue: pendingValue)
            return false
        }
    }

    /// Shows the confirmation tick briefly, then clears it.
    private func markSaved(_ key: GuestFieldKey) {
        fieldSaveStates[key] = .saved
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.fieldSaveStates[key] == .saved else { return }
            self.fieldSaveStates[key] = nil
        }
    }

    func clearSaveState(_ key: GuestFieldKey) {
        fieldSaveStates[key] = nil
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

    // MARK: - Custom column administration

    /// How many guests hold a value for a column. Every destructive action
    /// quotes this so the blast radius is stated before it happens.
    func usageCount(for column: GuestCustomColumn) -> Int {
        guestRecords.filter { guest in
            GuestCustomFields.value(in: guest.customFields, for: column.key) != nil
        }.count
    }

    func usageCount(for column: GuestCustomColumn, option: String) -> Int {
        guestRecords.filter { guest in
            let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
            return GuestCustomFields.displayText(stored, kind: column.kind) == option
        }.count
    }

    /// Slugifies a label into a key, suffixing on collision.
    ///
    /// Keys are shared with the web workspace and immutable once created, so
    /// this runs only at creation time.
    func proposedKey(for label: String) -> String {
        let slug = label
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }
            .joined()
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        let base = slug.isEmpty ? "field" : slug
        let existing = Set(customColumnRecords.map(\.key))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base)_\(index)") { index += 1 }
        return "\(base)_\(index)"
    }

    @discardableResult
    func createCustomColumn(
        label: String,
        kind: GuestCustomColumnKind,
        options: [String]
    ) async -> Bool {
        guard let repositories, let weddingID = wedding?.id else { return unavailable() }
        let trimmed = label.trimmed
        guard !trimmed.isEmpty else { return false }
        do {
            let column = try await repositories.guests.createCustomColumn(
                GuestCustomColumnDraft(
                    key: proposedKey(for: trimmed),
                    label: trimmed,
                    kind: kind,
                    options: .array(options.map(JSONValue.string)),
                    position: (customColumnRecords.map(\.position).max() ?? -1) + 1,
                    hidden: false
                ),
                weddingID: weddingID
            )
            customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords + [column])
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    @discardableResult
    func updateCustomColumn(
        _ column: GuestCustomColumn,
        label: String? = nil,
        kind: GuestCustomColumnKind? = nil,
        options: [String]? = nil,
        hidden: Bool? = nil
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            let updated = try await repositories.guests.updateCustomColumn(
                id: column.id,
                patch: GuestCustomColumnPatch(
                    label: label?.trimmed.nilIfBlank,
                    kind: kind,
                    options: options.map { .array($0.map(JSONValue.string)) },
                    hidden: hidden
                )
            )
            replace(updated, in: &customColumnRecords)
            customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    /// Persists a new ordering. Position drives guest detail, Add guest, and
    /// the filter sheet, so this is the single place order is decided.
    func reorderCustomColumns(from source: IndexSet, to destination: Int) async {
        guard let repositories else { _ = unavailable(); return }
        var ordered = GuestDisplayResolver.orderedColumns(customColumnRecords)
        ordered.move(fromOffsets: source, toOffset: destination)
        customColumnRecords = ordered

        for (index, column) in ordered.enumerated() where column.position != index {
            do {
                let updated = try await repositories.guests.updateCustomColumn(
                    id: column.id,
                    patch: GuestCustomColumnPatch(position: index)
                )
                replace(updated, in: &customColumnRecords)
            } catch {
                errorMessage = userMessage(for: error)
                // Re-read the server's truth rather than leave a half-applied order.
                await load()
                return
            }
        }
        customColumnRecords = GuestDisplayResolver.orderedColumns(customColumnRecords)
    }

    /// Renames one option of a select column.
    ///
    /// `rewritingGuests` decides what happens to guests already holding the old
    /// label: rewrite them, or leave them pointing at a label the column no
    /// longer offers (where the detail row shows it as no longer an option).
    @discardableResult
    func renameOption(
        _ column: GuestCustomColumn,
        from oldValue: String,
        to newValue: String,
        rewritingGuests: Bool
    ) async -> Bool {
        guard let repositories else { return unavailable() }
        let trimmed = newValue.trimmed
        guard !trimmed.isEmpty, trimmed != oldValue else { return false }

        var options = GuestCustomFields.options(in: column)
        guard let index = options.firstIndex(of: oldValue) else { return false }
        options[index] = trimmed

        guard await updateCustomColumn(column, options: options) else { return false }
        guard rewritingGuests else { return true }

        for guest in guestRecords {
            let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
            guard GuestCustomFields.displayText(stored, kind: column.kind) == oldValue else { continue }
            do {
                let merged = GuestCustomFields.merging(
                    guest.customFields,
                    key: column.key,
                    value: .string(trimmed)
                )
                let updated = try await repositories.guests.updateGuest(
                    id: guest.id,
                    patch: GuestPatch(customFields: merged)
                )
                replace(updated, in: &guestRecords)
            } catch {
                errorMessage = userMessage(for: error)
                return false
            }
        }
        return true
    }

    @discardableResult
    func deleteCustomColumn(_ column: GuestCustomColumn) async -> Bool {
        guard let repositories else { return unavailable() }
        do {
            try await repositories.guests.deleteCustomColumn(id: column.id)
            customColumnRecords.removeAll { $0.id == column.id }
            // The values live on the guests, so refresh them to match.
            await load()
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

    private func presentLoadFailure() {
        presentSaveFailure(retry: { [weak self] in
            Task { await self?.load() }
        })
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
        if let message = (error as? BackendError)?.message?.nilIfBlank {
            return message
        }

        switch error as? BackendError {
        case .networkUnavailable:
            return "Vowbase couldn’t reach the server. Check your connection and try again."
        case .authenticationRequired:
            return "Your session has ended. Please sign in again."
        default:
            return "The server couldn’t complete that change. Please try again."
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
    init(_ guest: Guest, columns: [GuestCustomColumn]) {
        id = guest.id
        firstName = guest.firstName
        lastName = guest.lastName ?? ""
        subtitle = GuestDisplayResolver.subtitle(for: guest, columns: columns)
        location = guest.originLabel ?? guest.address
        email = guest.email
        phone = guest.phone
        rsvp = guest.rsvpStatus ?? .notInvited
        isMappable = guest.originPrecision == "city"
        customSearchText = GuestCustomFields.object(in: guest.customFields)
            .values
            .compactMap { value in
                switch value {
                case let .string(text): text
                case let .number(number): String(number)
                default: nil
                }
            }
            .joined(separator: " ")
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
    WeddingAppShell(store: VowbaseWorkspaceStore(), taskStore: TaskStore(), initialTab: .venues)
}

#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(testingWorkspace: true), taskStore: TaskStore(), initialTab: .guests)
}

#Preview("Guest detail") {
    let store = VowbaseWorkspaceStore(testingWorkspace: true)
    return NavigationStack {
        if let guest = store.guests.first {
            GuestDetailView(guest: guest, store: store)
        }
    }
}

#Preview("Manage fields") {
    NavigationStack {
        GuestFieldListView(store: VowbaseWorkspaceStore(testingWorkspace: true))
    }
}

#Preview("Filters") {
    @Previewable @State var filters = GuestFilterSet()
    return GuestFilterSheet(
        store: VowbaseWorkspaceStore(testingWorkspace: true),
        searchText: "",
        filters: $filters
    )
}

#Preview("Add venue") {
    AddVenueSheet(store: VowbaseWorkspaceStore())
}

#Preview("Add guest") {
    AddGuestSheet(store: VowbaseWorkspaceStore(testingWorkspace: true))
}
