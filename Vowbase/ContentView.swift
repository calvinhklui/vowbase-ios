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
    @State private var store = VowbaseMVPStore()
    let onSignOut: () -> Void

    init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        WeddingAppShell(store: store, onSignOut: onSignOut)
    }
}

// MARK: - App shell

private enum AppTab: String, CaseIterable, Identifiable {
    case map
    case venues
    case guests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: "Map"
        case .venues: "Venues"
        case .guests: "Guests"
        }
    }

    var icon: String {
        switch self {
        case .map: "map"
        case .venues: "mappin"
        case .guests: "person.2"
        }
    }
}

private enum QuickAddDestination: String, Identifiable {
    case venue
    case guest

    var id: String { rawValue }
}

@MainActor
private struct WeddingAppShell: View {
    let store: VowbaseMVPStore
    let onSignOut: () -> Void
    @State private var selectedTab: AppTab = .map
    @State private var quickAdd: QuickAddDestination?
    @State private var isActionMenuOpen = false

    init(
        store: VowbaseMVPStore,
        initialTab: AppTab = .map,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onSignOut = onSignOut
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            VowbaseTheme.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .map:
                    MapWorkspaceView(
                        store: store,
                        isActionMenuOpen: $isActionMenuOpen,
                        addAction: openQuickAdd,
                        onSignOut: onSignOut
                    )
                case .venues:
                    VenuesView(store: store, openQuickAdd: openQuickAdd, onSignOut: onSignOut)
                case .guests:
                    GuestsView(store: store, openQuickAdd: openQuickAdd, onSignOut: onSignOut)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VowbaseTabBar(selection: $selectedTab)
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
        .animation(.snappy(duration: 0.28), value: selectedTab)
    }

    private func openQuickAdd(_ destination: QuickAddDestination) {
        isActionMenuOpen = false
        quickAdd = destination
    }
}

private struct VowbaseTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22, weight: .medium))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.title)
                            .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        Circle()
                            .fill(selection == tab ? VowbaseTheme.rose : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(selection == tab ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }
}

private struct IdentityBar: View {
    let onSignOut: () -> Void
    @State private var isAccountMenuPresented = false

    var body: some View {
        HStack(spacing: 14) {
            Text("A&C")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .frame(width: 58, height: 58)
                .background(VowbaseTheme.blush)
                .clipShape(Circle())

            Button {
                isAccountMenuPresented = true
            } label: {
                HStack(spacing: 8) {
                    Text("Andey & Calvin")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(VowbaseTheme.ink)
            }
            .accessibilityLabel("Current wedding: Andey and Calvin")

            Spacer(minLength: 0)

            Button(action: {}) {
                Image(systemName: "person")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(VowbaseTheme.rose)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(VowbaseTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Account")
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
}

// MARK: - Map

@MainActor
private struct MapWorkspaceView: View {
    let store: VowbaseMVPStore
    @Binding var isActionMenuOpen: Bool
    let addAction: (QuickAddDestination) -> Void
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
                        Annotation(venue.name, coordinate: venue.coordinate, anchor: .bottom) {
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
                IdentityBar(onSignOut: onSignOut)
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
            ShortlistPanel(
                store: store,
                isActionMenuOpen: $isActionMenuOpen,
                addAction: addAction
            )
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
    let store: VowbaseMVPStore
    @Binding var isActionMenuOpen: Bool
    let addAction: (QuickAddDestination) -> Void

    private var selectedVenue: MVPVenue {
        store.venues.first(where: { $0.id == store.selectedVenueID }) ?? store.venues[0]
    }

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
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if isActionMenuOpen {
                    QuickAddMenu(addAction: addAction)
                        .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                }
                AddButton(isOpen: isActionMenuOpen) { isActionMenuOpen.toggle() }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 18)
        }
        .animation(.snappy(duration: 0.24), value: isActionMenuOpen)
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
    let store: VowbaseMVPStore
    let openQuickAdd: (QuickAddDestination) -> Void
    let onSignOut: () -> Void
    @State private var mode: VenueMode = .shortlist
    @State private var statusFilter: VenueStatusFilter = .all
    @State private var showsFilter = false
    @State private var comparison: [UUID] = []

    private var visibleVenues: [MVPVenue] {
        store.venues.filter { statusFilter == .all || $0.status == statusFilter.status }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IdentityBar(onSignOut: onSignOut)
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
                            // Selection state is already the comparison's source of truth.
                        } label: {
                            Label("Compare \(comparison.count) venues", systemImage: "rectangle.split.3x1")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(.white)
                                .background(VowbaseTheme.rose, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
            .navigationBarHidden(true)
            .navigationDestination(for: MVPVenue.self) { venue in
                VenueDetailView(venue: venue)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    if store.isGlobalMenuOpen {
                        QuickAddMenu(addAction: openQuickAdd)
                    }
                    AddButton(isOpen: store.isGlobalMenuOpen) { store.isGlobalMenuOpen.toggle() }
                }
                .padding(.trailing, 22)
                .padding(.bottom, 86)
            }
            .sheet(isPresented: $showsFilter) {
                VenueFilterSheet(selection: $statusFilter)
                    .presentationDetents([.height(380)])
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
                    Label("View on map", systemImage: "map")
                        .foregroundStyle(VowbaseTheme.rose)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VowbaseVenueImage(url: venue.photoURL)
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text(venue.name).displayTitle()
                StatusCapsule(status: venue.status)
                Label(venue.location, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                HStack {
                    VenueFact(icon: "person.2", value: venue.capacity, caption: "guests")
                    VenueFact(icon: "dollarsign.circle", value: venue.estimate, caption: "venue est.")
                    VenueFact(icon: "airplane", value: venue.travel, caption: "guest travel")
                }
                .padding()
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Notes")
                    .font(.title2.weight(.semibold))
                Text("A spacious, light-filled setting with room for the ceremony and dinner in one beautifully connected experience.")
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(16)
        }
        .navigationTitle("Venue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Guests

@MainActor
private struct GuestsView: View {
    let store: VowbaseMVPStore
    let openQuickAdd: (QuickAddDestination) -> Void
    let onSignOut: () -> Void
    @State private var query = ""
    @State private var filter: GuestFilter = .all
    @State private var onlyLocated = false

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
                    IdentityBar(onSignOut: onSignOut)
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
                            onlyLocated.toggle()
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
            .navigationBarHidden(true)
            .navigationDestination(for: MVPGuest.self) { guest in
                GuestDetailView(guest: guest)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    if store.isGlobalMenuOpen { QuickAddMenu(addAction: openQuickAdd) }
                    AddButton(isOpen: store.isGlobalMenuOpen) { store.isGlobalMenuOpen.toggle() }
                }
                .padding(.trailing, 22)
                .padding(.bottom, 86)
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
    let store: VowbaseMVPStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var location = ""
    @State private var status: VenueStatus = .considering

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
            .navigationTitle("Add venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save venue") {
                        store.addVenue(name: name, location: location, status: status)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}

@MainActor
private struct AddGuestSheet: View {
    let store: VowbaseMVPStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFirstNameFocused: Bool
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    @State private var rsvp: RSVPStatus = .notInvited

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
            .navigationTitle("Add guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save guest") {
                        store.addGuest(firstName: firstName, lastName: lastName, location: location, rsvp: rsvp)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFirstNameFocused = true }
        }
    }
}

// MARK: - Reusable views and MVP fixtures

private struct VowbaseVenueImage: View {
    let url: URL?

    var body: some View {
        Image("GlasshouseVenue")
            .resizable()
            .scaledToFill()
        .clipped()
        .accessibilityHidden(true)
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
    static let background = Color(red: 1.0, green: 0.995, blue: 0.99)
    static let ink = Color(red: 0.15, green: 0.135, blue: 0.13)
    static let mutedInk = Color(red: 0.42, green: 0.42, blue: 0.47)
    static let rose = Color(red: 0.77, green: 0.22, blue: 0.40)
    static let blush = Color(red: 0.985, green: 0.94, blue: 0.95)
    static let border = Color(red: 0.89, green: 0.875, blue: 0.89)
    static let guestBlue = Color(red: 0.15, green: 0.39, blue: 0.92)
}

private extension Text {
    func displayTitle() -> some View {
        font(.system(size: 46, weight: .regular, design: .serif))
            .foregroundStyle(VowbaseTheme.ink)
    }

    func eyebrow() -> some View {
        font(.system(size: 13, weight: .bold))
            .tracking(2.1)
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
    let latitude: Double
    let longitude: Double
    let photoURL: URL?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
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
private final class VowbaseMVPStore {
    var selectedVenueID: UUID?
    var isGlobalMenuOpen = false
    var venues: [MVPVenue] = [
        MVPVenue(
            id: UUID(), name: "Glasshouse Chelsea", status: .toured,
            location: "Chelsea, New York", capacity: "150–350", estimate: "$53.7K", travel: "1 hr 19 min",
            latitude: 40.746, longitude: -74.003,
            photoURL: URL(string: "https://images.unsplash.com/photo-1519167758481-83f550bb49b3?auto=format&fit=crop&w=1200&q=85")
        ),
        MVPVenue(
            id: UUID(), name: "Brooklyn Museum", status: .toured,
            location: "Brooklyn, New York", capacity: "120–300", estimate: "$48K", travel: "1 hr 12 min",
            latitude: 40.671, longitude: -73.964,
            photoURL: URL(string: "https://images.unsplash.com/photo-1564399579883-451a5d44ec08?auto=format&fit=crop&w=1200&q=85")
        ),
        MVPVenue(
            id: UUID(), name: "The Lakehouse", status: .considering,
            location: "Hudson Valley, New York", capacity: "100–220", estimate: "$39K", travel: "1 hr 31 min",
            latitude: 42.653, longitude: -73.757,
            photoURL: URL(string: "https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?auto=format&fit=crop&w=1200&q=85")
        ),
        MVPVenue(
            id: UUID(), name: "Water's Edge", status: .shortlisted,
            location: "Long Island, New York", capacity: "130–250", estimate: "$45K", travel: "1 hr 8 min",
            latitude: 40.758, longitude: -73.83,
            photoURL: URL(string: "https://images.unsplash.com/photo-1507504031003-b417219a0fde?auto=format&fit=crop&w=1200&q=85")
        )
    ]
    var guests: [MVPGuest] = [
        MVPGuest(id: UUID(), firstName: "Calvin", lastName: "Khuat", group: "Ng Family", location: "Bay Area", email: nil, rsvp: .pending),
        MVPGuest(id: UUID(), firstName: "Kyle", lastName: "Ng", group: "Ng Family", location: "Fremont, CA", email: nil, rsvp: .pending),
        MVPGuest(id: UUID(), firstName: "Dan", lastName: "Jung", group: "Calvin Friends", location: "New York", email: nil, rsvp: .pending),
        MVPGuest(id: UUID(), firstName: "Lulu", lastName: "Lui", group: "Lui Family", location: "Commack, NY", email: nil, rsvp: .pending),
        MVPGuest(id: UUID(), firstName: "Yusuf", lastName: "Mehkri", group: "Calvin Friends", location: "Florida", email: nil, rsvp: .notInvited),
        MVPGuest(id: UUID(), firstName: "Maya", lastName: "Chen", group: "Andey Friends", location: "Boston, MA", email: nil, rsvp: .accepted),
        MVPGuest(id: UUID(), firstName: "Priya", lastName: "Shah", group: "Andey Friends", location: "New York", email: nil, rsvp: .notInvited)
    ]
    let clusters: [GuestCluster] = [
        GuestCluster(id: "hudson", city: "Hudson Valley", count: 12, latitude: 42.65, longitude: -73.75),
        GuestCluster(id: "boston", city: "Boston", count: 8, latitude: 42.36, longitude: -71.06),
        GuestCluster(id: "new-york", city: "New York", count: 28, latitude: 40.72, longitude: -74.0),
        GuestCluster(id: "philadelphia", city: "Philadelphia", count: 6, latitude: 39.95, longitude: -75.17),
        GuestCluster(id: "dc", city: "Washington", count: 9, latitude: 38.91, longitude: -77.04),
        GuestCluster(id: "virginia", city: "Virginia Beach", count: 4, latitude: 36.85, longitude: -75.98)
    ]

    init() {
        selectedVenueID = venues.first?.id
    }

    func addVenue(name: String, location: String, status: VenueStatus) {
        let venue = MVPVenue(
            id: UUID(), name: name, status: status,
            location: location.isEmpty ? "Location not added" : location,
            capacity: "Not added", estimate: "Not added", travel: "Unavailable",
            latitude: 40.73, longitude: -74.01, photoURL: nil
        )
        venues.insert(venue, at: 0)
        selectedVenueID = venue.id
    }

    func addGuest(firstName: String, lastName: String, location: String, rsvp: RSVPStatus) {
        guests.insert(
            MVPGuest(
                id: UUID(), firstName: firstName, lastName: lastName,
                group: "Ungrouped", location: location.isEmpty ? nil : location,
                email: nil, rsvp: rsvp
            ),
            at: 0
        )
    }
}

#Preview("Map") {
    ContentView()
}

#Preview("Venues") {
    WeddingAppShell(store: VowbaseMVPStore(), initialTab: .venues)
}

#Preview("Guests") {
    WeddingAppShell(store: VowbaseMVPStore(), initialTab: .guests)
}

#Preview("Add venue") {
    AddVenueSheet(store: VowbaseMVPStore())
}

#Preview("Add guest") {
    AddGuestSheet(store: VowbaseMVPStore())
}
