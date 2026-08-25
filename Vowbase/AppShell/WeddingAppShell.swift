import SwiftUI
import UIKit

// MARK: - App shell

private enum QuickAddDestination: String, Identifiable {
    case venue
    case guest

    var id: String { rawValue }
}

/// The authenticated app: one persistent map canvas, one persistent console
/// sheet whose content depends on the active lens. See
/// `docs/vowbase-ios-map-command-center-ux-spec.md` §2, §7.
///
/// Two things worth knowing about how this maps onto SwiftUI's real API
/// surface, both flagged in the spec rather than silently skipped:
/// - Overview shows its full module stack (§11) — Countdown, Needs You,
///   Reach, Guests — at every detent, scrolling within whatever height the
///   current detent gives it rather than swapping in a separate peek-only
///   view.
/// - A `.sheet` always renders above everything in the view it's presented
///   from, so the lens rail lives *inside* the console's own content (pinned
///   to its bottom) rather than as an overlay on the canvas — otherwise the
///   sheet would cover it at every detent. The Quick Add FAB follows suit:
///   at `.peek` it floats on the canvas just above the console, but past
///   peek the console covers most or all of the screen, so the same FAB moves
///   inside the console itself (bottom-trailing, above the rail) or it would
///   be unreachable. Both the FAB's position and the map's camera inset are
///   driven off `currentDetent` rather than the live drag position — SwiftUI
///   exposes no API for the latter on a system sheet, so both snap to
///   wherever the console has settled rather than tracking it continuously.
@MainActor
struct WeddingAppShell: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    let onSignOut: () -> Void
    @State private var navigation: AppNavigationModel
    @State private var quickAdd: QuickAddDestination?
    @State private var taskEditor: TaskEditorDestination?
    @State private var isQuickAddPresented = false
    @State private var isVenueNoteEditing = false
    @State private var isSignOutConfirmationPresented = false
    @State private var mapFocusToken = 0
    /// A pushed detail needs a full-height navigation host, but Back should
    /// return the couple to the exact detent they were using rather than
    /// permanently promoting its console to full.
    @State private var venueDetailReturnDetent: ConsoleDetent?
    @State private var guestDetailReturnDetent: ConsoleDetent?

    /// Each lens remembers its own detent for the session — spec §7.1.
    @State private var lensDetents: [PlanLens: ConsoleDetent] = [
        .overview: .peek,
        .venues: .half,
        .guests: .half,
        .tasks: .full,
    ]

    init(
        store: VowbaseWorkspaceStore,
        taskStore: TaskStore,
        initialLens: PlanLens = .venues,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.store = store
        self.taskStore = taskStore
        self.onSignOut = onSignOut
        _navigation = State(initialValue: AppNavigationModel(selectedLens: initialLens))
    }

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var store = store

        GeometryReader { proxy in
            let screenHeight = proxy.size.height
            let consoleHeight = currentDetent.pointHeight(in: screenHeight)

            ZStack(alignment: .top) {
                VowbaseTheme.background.ignoresSafeArea()

                MapWorkspaceView(
                    store: store,
                    lens: navigation.selectedLens,
                    consoleInset: consoleHeight,
                    selectedGuestID: navigation.selectedGuestID,
                    focusToken: mapFocusToken,
                    onSelectVenue: selectVenue,
                    onOpenVenueInMaps: openInMaps,
                    onClearFocus: clearMapFocus
                )

                ContextBar(store: store) {
                    isSignOutConfirmationPresented = true
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if store.isLoading {
                    ProgressView("Loading your wedding")
                        .tint(VowbaseTheme.rose)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            // Recomputes the impact readout whenever the selected venue
            // changes. `.task(id:)` cancels the previous run automatically,
            // so switching venues mid-request can't let a stale response
            // land after a fresher one already has.
            .task(id: store.selectedVenueID) {
                await store.refreshTravelImpact()
            }
            // The scrim is applied *before* the FAB overlay so it layers
            // underneath it. Applied after, it covered the expanded panel and
            // swallowed every tap — the menu appeared to work, dismissed on
            // selection, and silently never ran the action.
            .overlay {
                if navigation.selectedLens == .overview && isQuickAddPresented {
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
                // At peek, the console is short enough that the FAB reads as
                // part of the canvas floating just above it. Past peek it
                // moves inside `consoleSheet` itself, or the console would
                // cover it.
                if showsPeekFAB {
                    activeLensFAB
                        .padding(.trailing, VowbaseControlMetric.screenInset)
                        .padding(.bottom, consoleHeight + 12)
                }
            }
            .sheet(isPresented: .constant(true)) {
                consoleSheet
            }
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
        .animation(.snappy(duration: 0.28), value: navigation.selectedLens)
        .onChange(of: navigation.selectedLens) {
            isQuickAddPresented = false
        }
    }

    // MARK: Console

    private var currentDetent: ConsoleDetent {
        lensDetents[navigation.selectedLens] ?? defaultDetent(for: navigation.selectedLens)
    }

    private func defaultDetent(for lens: PlanLens) -> ConsoleDetent {
        switch lens {
        case .overview:
            .peek
        case .venues, .guests:
            .half
        case .tasks:
            .full
        }
    }

    private func availableDetents(for lens: PlanLens) -> Set<PresentationDetent> {
        switch lens {
        case .overview:
            Set(ConsoleDetent.allCases.map(\.presentationDetent))
        case .venues:
            if !navigation.venuesPath.isEmpty {
                [ConsoleDetent.full.presentationDetent]
            } else {
                Set(ConsoleDetent.allCases.map(\.presentationDetent))
            }
        case .guests:
            if !navigation.guestsPath.isEmpty {
                [ConsoleDetent.full.presentationDetent]
            } else {
                Set(ConsoleDetent.allCases.map(\.presentationDetent))
            }
        case .tasks:
            [ConsoleDetent.full.presentationDetent]
        }
    }

    private var detentBinding: Binding<PresentationDetent> {
        Binding(
            get: { currentDetent.presentationDetent },
            set: { newValue in
                guard let matched = ConsoleDetent.allCases.first(where: { $0.presentationDetent == newValue }) else { return }
                lensDetents[navigation.selectedLens] = matched
            }
        )
    }

    /// The console: grabber, per-lens header, per-lens content — and,
    /// pinned to its own bottom, the lens rail. A `.sheet` always presents
    /// above the entire view it's attached to, so the rail has to live
    /// inside the sheet's own content to stay visible at every detent —
    /// as an overlay on the presenting canvas, the sheet would cover it.
    ///
    /// The grabber and header are the console's own chrome for *its* root
    /// content (the Overview modules or a focused lens's list). Venues and
    /// Guests each own an
    /// inner `NavigationStack`; once one has pushed to a detail screen, that
    /// screen's own toolbar is the header, and stacking the console's chrome
    /// above it just wastes vertical space on a second, redundant header.
    @ViewBuilder
    private var consoleSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isConsoleAtRoot {
                // `VowbaseTheme.border` reads as a hairline separator, not a
                // grab handle — too faint at this size against the console's
                // own material. `mutedInk` at partial opacity stays adaptive
                // across light/dark and Increased Contrast while actually
                // being visible.
                Capsule()
                    .fill(VowbaseTheme.mutedInk.opacity(0.5))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                consoleHeader
                    .padding(.horizontal, 16)
            }

            consoleContent
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isVenueNoteEditing {
                LensRail(selection: selectedLensBinding)
            }
        }
        .overlay {
            if showsConsoleFAB && navigation.selectedLens == .overview && isQuickAddPresented {
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
            if showsConsoleFAB {
                activeLensFAB
                    .padding(.trailing, VowbaseControlMetric.screenInset)
                    .padding(.bottom, LensRail.occupiedHeight + VowbaseSpace.medium)
            }
        }
        .presentationDetents(availableDetents(for: navigation.selectedLens), selection: detentBinding)
        .presentationDragIndicator(.hidden)
        .presentationBackground {
            ConsolePresentationBackground()
        }
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(true)
        // The console is the persistent presentation context. Keeping this
        // dialog here lets its modal hierarchy preserve the console, lens
        // rail, and the rest of the shell until the user confirms sign out.
        .confirmationDialog(
            "Your Vowbase account",
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with Apple or Google at any time.")
        }
        // Creation sheets present from *inside* the console, not from the
        // shell around it. The console is itself a permanently-presented
        // sheet, so a second sheet attached to the shell has no free
        // presentation context and UIKit silently drops it — which is what
        // made every Quick Add action a no-op. Presenting from the console
        // stacks the new sheet on top of it instead.
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
    }

    /// Past peek, keep the same full-size FAB inside the console and above the
    /// lens rail. Pushed venue/guest details and venue-note editing suppress it.
    private var showsConsoleFAB: Bool {
        currentDetent != .peek && isConsoleAtRoot && !isVenueNoteEditing
    }

    /// At peek, focused-lens actions float above the map just like they do at
    /// taller detents inside the console. Overview keeps its legacy quick-add
    /// placement because it is the only multi-action entry point.
    private var showsPeekFAB: Bool {
        currentDetent == .peek
            && isConsoleAtRoot
            && !isVenueNoteEditing
            && navigation.selectedLens != .tasks
    }

    /// Overview keeps the multi-action quick-add menu. Each focused lens uses
    /// the same floating placement but routes directly to its matching form.
    @ViewBuilder
    private var activeLensFAB: some View {
        switch navigation.selectedLens {
        case .overview:
            QuickAddOverlay(
                isPresented: $isQuickAddPresented,
                onAddVenue: { quickAdd = .venue },
                onAddGuest: { quickAdd = .guest },
                onAddTask: { taskEditor = .add() }
            )
        case .venues:
            DirectAddFAB(title: "Add Venue", systemImage: "plus") {
                quickAdd = .venue
            }
        case .guests:
            DirectAddFAB(title: "Add Guest", systemImage: "plus") {
                quickAdd = .guest
            }
        case .tasks:
            DirectAddFAB(title: "Add Task", systemImage: "plus") {
                taskEditor = .add()
            }
        }
    }

    /// Whether the active lens's console is showing its own root content
    /// rather than something it pushed to internally.
    /// Overview and Tasks never push from the console, so they're always
    /// "at root" — Overview's rail has no detail destination, and Tasks
    /// edits via a sheet (`taskEditor`), not a push.
    private var isConsoleAtRoot: Bool {
        switch navigation.selectedLens {
        case .overview, .tasks:
            true
        case .venues:
            navigation.venuesPath.isEmpty
        case .guests:
            navigation.guestsPath.isEmpty
        }
    }

    private var selectedLensBinding: Binding<PlanLens> {
        Binding(
            get: { navigation.selectedLens },
            set: { navigation.selectedLens = $0 }
        )
    }

    private var venuesPathBinding: Binding<NavigationPath> {
        Binding(
            get: { navigation.venuesPath },
            set: { newPath in
                let wasShowingDetail = !navigation.venuesPath.isEmpty
                if !wasShowingDetail, !newPath.isEmpty {
                    // A detail can also be opened from the expanded venue
                    // list, which mutates this binding rather than calling
                    // `openVenueDetails(_:)`. Capture that full detent too.
                    venueDetailReturnDetent = currentDetent
                    lensDetents[.venues] = .full
                }
                navigation.venuesPath = newPath
                guard wasShowingDetail, newPath.isEmpty else { return }

                lensDetents[.venues] = venueDetailReturnDetent ?? defaultDetent(for: .venues)
                venueDetailReturnDetent = nil
            }
        )
    }

    private var guestsPathBinding: Binding<NavigationPath> {
        Binding(
            get: { navigation.guestsPath },
            set: { newPath in
                let wasShowingDetail = !navigation.guestsPath.isEmpty
                if !wasShowingDetail, !newPath.isEmpty {
                    guestDetailReturnDetent = currentDetent
                    lensDetents[.guests] = .full
                }
                navigation.guestsPath = newPath
                guard wasShowingDetail, newPath.isEmpty else { return }

                lensDetents[.guests] = guestDetailReturnDetent ?? defaultDetent(for: .guests)
                guestDetailReturnDetent = nil
            }
        )
    }

    @ViewBuilder
    private var consoleHeader: some View {
        switch navigation.selectedLens {
        case .overview:
            // The module stack supplies its own titles — Countdown reads as
            // the header at peek, and stacking a second one above the other
            // three modules at half/full would just waste vertical space.
            EmptyView()
        case .venues:
            ConsoleHeader(venues: store.venues)
        case .guests:
            ConsoleHeader(guests: store.allGuestRecords)
        case .tasks:
            ConsoleHeader(openTaskCount: openTaskCount, dueSoonCount: dueSoonTaskCount)
        }
    }

    /// Routes the impact readout's tap per spec §8/§8.1 — each unavailable
    /// reason has its own fix; a real number goes to "who does this hurt."
    private func handleImpactRowTap() {
        switch store.travelImpact {
        case .unavailable(.venueMissingCoordinate):
            navigation.selectedLens = .venues
        case .unavailable(.noMappableGuests):
            navigation.selectedLens = .guests
            quickAdd = .guest
        case .unavailable(.requestFailed):
            Task { await store.refreshTravelImpact() }
        case .ready:
            // The venue stays selected and its clusters stay badged — the
            // canvas doesn't change, only which lens's console is showing.
            navigation.selectedLens = .guests
        case .idle, .loading:
            break
        }
    }

    @ViewBuilder
    private var consoleContent: some View {
        switch navigation.selectedLens {
        case .overview:
            // The full stack at every detent, not just a peek teaser — at
            // `.peek` this shows Countdown plus however much of Needs You
            // fits before the sheet's edge, scrollable for the rest, rather
            // than reserving peek's height for Countdown alone and leaving
            // the remainder empty.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CountdownModule(store: store)
                    NeedsYouModule(
                        store: store,
                        taskStore: taskStore,
                        onSelectTask: { task in taskEditor = .edit(task.id) },
                        onSelectNudge: { nudge in navigation.selectedLens = nudge.destination },
                        onPromoteNudge: { nudge in taskEditor = .add(prefillTitle: nudge.message) }
                    )
                    ReachModule(store: store, onTapReadout: handleImpactRowTap)
                    GuestsModule(store: store, onAddGuest: { quickAdd = .guest })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        case .venues:
            VenuesView(
                store: store,
                onAddVenue: { quickAdd = .venue },
                onReturnToMap: { navigation.selectedLens = .overview },
                onViewOnMap: showVenueOnMap,
                isNoteEditing: $isVenueNoteEditing,
                path: venuesPathBinding
            )
        case .guests:
            GuestsView(store: store, path: guestsPathBinding)
        case .tasks:
            TasksView(store: store, taskStore: taskStore, editor: $taskEditor)
        }
    }

    private var openTaskCount: Int {
        taskStore.tasks.filter { $0.effectiveStatus != .done }.count
    }

    private var dueSoonTaskCount: Int {
        let calendar = Calendar.current
        let boundary = calendar.date(byAdding: .day, value: 7, to: Date())
        return taskStore.tasks.filter { task in
            guard task.effectiveStatus != .done, let raw = task.dueDate,
                  let due = TaskDueDateFormatter.date(from: raw), let boundary
            else { return false }
            return due <= boundary
        }.count
    }

    private func selectVenue(_ venue: MVPVenue) {
        navigation.selectedGuestID = nil
        store.selectedVenueID = venue.id
    }

    private func openInMaps(_ venue: MVPVenue) {
        let location = venue.mapSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else { return }

        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        guard let url = components?.url else { return }
        UIApplication.shared.open(url)
    }

    /// Returns from a venue detail to the focused map state. Resetting the
    /// path first makes the root venue list the active content; the focus
    /// token makes MapKit recenter even if this venue was already selected.
    private func showVenueOnMap(_ venue: MVPVenue) {
        navigation.selectedGuestID = nil
        navigation.venuesPath = NavigationPath()
        venueDetailReturnDetent = nil
        lensDetents[.venues] = .peek
        store.selectedVenueID = venue.id
        mapFocusToken += 1
    }

    private func clearMapFocus() {
        store.selectedVenueID = nil
        navigation.selectedGuestID = nil
    }
}

/// The lens rail. Replaces the plain tab bar: each slot is a `PlanLens`, so a
/// new lens (Vendors, Lodging, …) is a new `PlanLens` case, not a new control.
/// See spec §9.
private struct LensRail: View {
    @Binding var selection: PlanLens

    static let contentHeight: CGFloat = 70
    static let occupiedHeight = contentHeight + 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The tint used to be black at 54% regardless of scheme, which read as a
    /// heavy charcoal slab sitting on the console's white surface in light
    /// mode. Each scheme now gets a tint that deepens its own ground rather
    /// than inverting it.
    private var railTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.54) : Color.white.opacity(0.60)
    }

    private var railStroke: Color {
        colorScheme == .dark ? .white.opacity(0.18) : VowbaseTheme.ink.opacity(0.08)
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                railContent
                    .glassEffect(.regular.tint(railTint), in: Capsule())
            } else {
                railContent
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(railStroke, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
        }
        .padding(.horizontal, VowbaseControlMetric.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var railContent: some View {
        HStack(spacing: 4) {
            ForEach(PlanLens.visibleRailCases) { lens in
                Button {
                    select(lens)
                } label: {
                    LensRailItem(lens: lens, isSelected: selection == lens)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: Self.contentHeight)
    }

    private func select(_ lens: PlanLens) {
        guard selection != lens else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08)) {
            selection = lens
        }
    }
}

private struct LensRailItem: View {
    let lens: PlanLens
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Labels were hardcoded white, which only worked because the rail forced
    /// a dark tint underneath. With an adaptive rail they have to follow the
    /// scheme too, or light mode renders white-on-white.
    private var foreground: Color {
        if colorScheme == .dark {
            return isSelected ? .white : .white.opacity(0.72)
        }
        return isSelected ? VowbaseTheme.ink : VowbaseTheme.mutedInk
    }

    private var selectionFill: Color {
        colorScheme == .dark ? .white.opacity(0.16) : VowbaseTheme.ink.opacity(0.07)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: lens.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolVariant(.fill)

            Text(lens.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background {
            if isSelected {
                Capsule()
                    .fill(selectionFill)
                    .overlay {
                        Capsule()
                            .stroke(colorScheme == .dark ? .white.opacity(0.16) : VowbaseTheme.ink.opacity(0.06), lineWidth: 1)
                    }
            }
        }
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Venues") {
    WeddingAppShell(store: VowbaseWorkspaceStore(), taskStore: TaskStore(), initialLens: .venues)
}

#if DEBUG
#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(testingWorkspace: true), taskStore: TaskStore(), initialLens: .guests)
}
#endif
