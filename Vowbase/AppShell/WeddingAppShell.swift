import SwiftUI
import UIKit

// MARK: - App shell

private enum QuickAddDestination: Identifiable {
    case venue
    case guest
    case moment(weddingID: UUID, moment: PlanningMoment?)
    case requirement(weddingID: UUID, requirement: MoodboardRequirement?)

    var id: String {
        switch self {
        case .venue: "venue"
        case .guest: "guest"
        case let .moment(_, moment): moment.map { "moment-\($0.id.uuidString)" } ?? "moment-add"
        case let .requirement(_, requirement): requirement.map { "requirement-\($0.id.uuidString)" } ?? "requirement-add"
        }
    }
}

/// The console owns one modal route at a time. Keeping every editor and
/// insight on one sheet host avoids competing presentation transactions from
/// sibling `.sheet` modifiers on the persistent console.
private enum WorkspaceModal: Identifiable {
    case quickAdd(QuickAddDestination)
    case task(TaskEditorDestination)
    case guestCluster(GuestCluster)

    var id: String {
        switch self {
        case let .quickAdd(destination): "quick-add-\(destination.id)"
        case let .task(destination): "task-\(destination.id)"
        case let .guestCluster(cluster): "guest-cluster-\(cluster.id)"
        }
    }
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
///   from, so the app navigation bar lives *inside* the console's own content
///   (pinned to its bottom) rather than as an overlay on the canvas. Its
///   contextual Quick Add action is a standalone trailing circle in that bar,
///   keeping the action reachable at every detent without moving it between
///   presentation layers.
@MainActor
struct WeddingAppShell: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    let timelineStore: TimelineStore
    let onSignOut: () -> Void
    @State private var navigation: AppNavigationModel
    @State private var presentedModal: WorkspaceModal?
    @State private var guestClusterModalWasPresented = false
    @State private var pendingGuestDetail: MVPGuest?
    @State private var isQuickAddPresented = false
    @State private var isVenueNoteEditing = false
    @State private var isSignOutConfirmationPresented = false
    @State private var mapFocusToken = 0
    /// Venue details preserve their launch detent. Back returns to the detent
    /// captured by the shared list/map selection route.
    @State private var venueDetailReturnDetent: ConsoleDetent?
    @State private var guestDetailReturnDetent: ConsoleDetent?

    /// Each lens remembers its own detent for the session — spec §7.1.
    @State private var lensDetents: [PlanLens: ConsoleDetent] = [
        .overview: .peek,
        .venues: .half,
        .guests: .half,
        .tasks: .full,
        .timeline: .half,
    ]

    init(
        store: VowbaseWorkspaceStore,
        taskStore: TaskStore,
        timelineStore: TimelineStore,
        initialLens: PlanLens = .timeline,
        presentsInitialVenueDetail: Bool = false,
        presentsInitialGuestInsight: Bool = false,
        presentsInitialTimelineMomentEditor: Bool = false,
        presentsInitialTimelineRequirementEditor: Bool = false,
        initialDeepLink: VowbaseDeepLink? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.store = store
        self.taskStore = taskStore
        self.timelineStore = timelineStore
        self.onSignOut = onSignOut
        let linkedVenue: MVPVenue? = if case let .venue(_, venueID) = initialDeepLink {
            store.venues.first { $0.id == venueID }
        } else {
            nil
        }
        let linkedGuest: MVPGuest? = if case let .guest(_, guestID) = initialDeepLink {
            store.guests.first { $0.id == guestID }
        } else {
            nil
        }
        let initialVenue = linkedVenue ?? (presentsInitialVenueDetail ? store.venues.first : nil)
        let initialGuestCluster = initialVenue == nil && linkedGuest == nil && presentsInitialGuestInsight ? store.clusters.first : nil
        let initialNavigation = AppNavigationModel(
            selectedLens: initialVenue != nil ? .venues : (linkedGuest != nil || initialGuestCluster != nil ? .guests : initialLens)
        )
        if let initialVenue {
            initialNavigation.venuesPath.append(initialVenue)
            store.selectedVenueID = initialVenue.id
        }
        if let linkedGuest {
            initialNavigation.guestsPath.append(linkedGuest)
        }
        initialNavigation.selectedGuestClusterID = initialGuestCluster?.id
        _navigation = State(initialValue: initialNavigation)
        _venueDetailReturnDetent = State(initialValue: initialVenue == nil ? nil : .half)
        _guestDetailReturnDetent = State(initialValue: linkedGuest == nil ? nil : .half)
        var initialDetents: [PlanLens: ConsoleDetent] = [
            .overview: .peek,
            .venues: .half,
            .guests: .half,
            .tasks: .full,
            .timeline: .half,
        ]
        if linkedGuest != nil {
            initialDetents[.guests] = .full
        }
        _lensDetents = State(initialValue: initialDetents)
        if presentsInitialTimelineMomentEditor, let moment = timelineStore.moments.first {
            _presentedModal = State(initialValue: .quickAdd(.moment(weddingID: moment.weddingID, moment: moment)))
        } else if presentsInitialTimelineRequirementEditor, let requirement = timelineStore.requirements.first {
            _presentedModal = State(initialValue: .quickAdd(.requirement(weddingID: requirement.weddingID, requirement: requirement)))
        } else if let initialGuestCluster {
            _presentedModal = State(initialValue: .guestCluster(initialGuestCluster))
            _guestClusterModalWasPresented = State(initialValue: true)
        }
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
                    selectedGuestClusterID: navigation.selectedGuestClusterID,
                    focusToken: mapFocusToken,
                    onSelectVenue: selectVenue,
                    onSelectGuestCluster: selectGuestCluster,
                    onOpenVenueInMaps: openInMaps,
                    onClearFocus: clearMapFocus
                )
                // Lens changes affect the map canvas, but must not carry an
                // explicit animation transaction into the persistent sheet.
                // In particular, Tasks replaces the allowed detents with
                // `.full`; animating that transaction through the sheet made
                // its bottom-safe-area rail briefly interpolate at mid-screen.
                .animation(.snappy(duration: 0.28), value: navigation.selectedLens)

                ContextBar(
                    store: store,
                    onRefresh: refreshCurrentLens,
                    isRefreshing: isRefreshingCurrentLens
                ) {
                    isSignOutConfirmationPresented = true
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if store.isLoading {
                    WeddingLoadingOverlay()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                }
            }
            // Recomputes the impact readout whenever the selected venue
            // changes. `.task(id:)` cancels the previous run automatically,
            // so switching venues mid-request can't let a stale response
            // land after a fresher one already has.
            .task(id: store.selectedVenueID) {
                await store.refreshTravelImpact()
            }
            .task(id: navigation.selectedGuestClusterID) {
                await store.refreshClusterTravel(clusterID: navigation.selectedGuestClusterID)
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
        case .timeline:
            .half
        }
    }

    private func availableDetents(for lens: PlanLens) -> Set<PresentationDetent> {
        switch lens {
        case .overview:
            Set([ConsoleDetent.peek, .half, .full].map(\.presentationDetent))
        case .venues, .guests:
            Set([ConsoleDetent.peek, .half, .full].map(\.presentationDetent))
        case .tasks:
            [ConsoleDetent.full.presentationDetent]
        case .timeline:
            Set([ConsoleDetent.peek, .half, .full].map(\.presentationDetent))
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
    /// The grabber is console chrome. Venues and Guests place their titles
    /// inside their root scroll views so those titles move with the metrics,
    /// controls, and list. Each focused lens owns an
    /// inner `NavigationStack`; once one has pushed to a detail screen, that
    /// screen's own toolbar is the header, and stacking the console's chrome
    /// above it just wastes vertical space on a second, redundant header.
    @ViewBuilder
    private var consoleSheet: some View {
        VStack(alignment: .leading, spacing: consoleContentSpacing) {
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
        .overlay {
            if showsNavigationFAB && supportsQuickAddMenu && isQuickAddPresented {
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
        // Apply the inset after the scrim so the native navigation glass and
        // its expanded Quick Add panel remain above the dismiss layer.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isVenueNoteEditing {
                LensRail(
                    selection: selectedLensBinding,
                    showsTrailingAction: showsNavigationFAB
                ) {
                    activeLensFAB
                }
            }
        }
        .presentationDetents(availableDetents(for: navigation.selectedLens), selection: detentBinding)
        // Let vertical swipes resize through peek/half before the root content
        // scrolls. At full height SwiftUI hands gestures to the ScrollView;
        // pulling down again from its top edge collapses back to half.
        .presentationContentInteraction(.resizes)
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
        .sheet(item: $presentedModal, onDismiss: finishGuestClusterInsightDismissal) { modal in
            switch modal {
            case let .quickAdd(destination):
                quickAddSheet(destination)
            case let .task(destination):
                TaskEditorSheet(destination: destination, taskStore: taskStore, weddingID: store.wedding?.id, canManageTasks: store.canManageTasks)
                    .presentationDetents([.large])
            case let .guestCluster(cluster):
                TravelCoverageConsole(
                    store: store,
                    cluster: cluster,
                    onOpenGuestDetails: { guest in
                        pendingGuestDetail = guest
                        presentedModal = nil
                    }
                )
                    .presentationDetents([.fraction(0.52), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(VowbaseTheme.background)
            }
        }
    }

    @ViewBuilder
    private func quickAddSheet(_ destination: QuickAddDestination) -> some View {
        switch destination {
        case .venue:
            AddVenueSheet(store: store)
                .presentationDetents([.medium, .large])
        case .guest:
            AddGuestSheet(store: store)
                .presentationDetents([.medium, .large])
        case let .moment(weddingID, moment):
            TimelineComposer(
                timelineStore: timelineStore,
                weddingID: weddingID,
                venues: store.venues,
                moment: moment
            )
            .presentationDetents([.medium, .large])
        case let .requirement(weddingID, requirement):
            RequirementComposer(
                timelineStore: timelineStore,
                weddingID: weddingID,
                requirement: requirement
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// The contextual action occupies the standalone trailing circle in the
    /// app navigation bar. Pushed venue/guest details and venue-note editing
    /// suppress it just as they did when it floated above the bar.
    private var showsNavigationFAB: Bool {
        isConsoleAtRoot && !isVenueNoteEditing
    }

    /// Overview and Timeline use multi-action quick-add menus. The other
    /// focused lenses route the same floating control to their matching form.
    @ViewBuilder
    private var activeLensFAB: some View {
        switch navigation.selectedLens {
        case .overview:
            QuickAddOverlay(
                isPresented: $isQuickAddPresented,
                onAddVenue: { presentQuickAdd(.venue) },
                onAddGuest: { presentQuickAdd(.guest) },
                onAddTask: { presentTaskEditor(.add()) }
            )
        case .venues:
            DirectAddFAB(title: "Add Venue", systemImage: "plus") {
                presentQuickAdd(.venue)
            }
        case .guests:
            DirectAddFAB(title: "Add Guest", systemImage: "plus") {
                presentQuickAdd(.guest)
            }
        case .tasks:
            DirectAddFAB(title: "Add Task", systemImage: "plus") {
                presentTaskEditor(.add())
            }
        case .timeline:
            QuickAddOverlay(
                isPresented: $isQuickAddPresented,
                actions: [
                    QuickAddAction(id: "moment", title: "Add Moment", icon: "sparkles", tint: VowbaseTheme.rose) {
                        guard let weddingID = store.wedding?.id else { return }
                        presentQuickAdd(.moment(weddingID: weddingID, moment: nil))
                    },
                    QuickAddAction(id: "requirement", title: "Add Requirement", icon: "list.bullet.clipboard", tint: VowbaseTheme.rose) {
                        guard let weddingID = store.wedding?.id else { return }
                        presentQuickAdd(.requirement(weddingID: weddingID, requirement: nil))
                    },
                    QuickAddAction(id: "venue", title: "Add Venue", icon: "mappin.and.ellipse", tint: VowbaseTheme.rose) {
                        presentQuickAdd(.venue)
                    },
                    QuickAddAction(id: "guest", title: "Add Guest", icon: "person.badge.plus", tint: VowbaseTheme.guestBlue) {
                        presentQuickAdd(.guest)
                    },
                    QuickAddAction(id: "task", title: "Add Task", icon: "checkmark.circle.badge.plus", tint: VowbaseTheme.rose) {
                        presentTaskEditor(.add())
                    },
                ]
            )
        }
    }

    private var supportsQuickAddMenu: Bool {
        navigation.selectedLens == .overview || navigation.selectedLens == .timeline
    }

    /// Whether the active lens's console is showing its own root content
    /// rather than something it pushed to internally.
    /// Overview and Tasks never push from the console, so they're always
    /// "at root" — Overview's rail has no detail destination, and Tasks
    /// edits via the shared modal route, not a push.
    private var isConsoleAtRoot: Bool {
        switch navigation.selectedLens {
        case .overview, .tasks, .timeline:
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
            set: { selectedLens in
                let isReselection = navigation.selectedLens == selectedLens
                navigation.selectLens(selectedLens)
                guard isReselection else { return }

                switch selectedLens {
                case .venues:
                    venuesPathBinding.wrappedValue = NavigationPath()
                case .guests:
                    guestsPathBinding.wrappedValue = NavigationPath()
                case .overview, .tasks, .timeline:
                    navigation.resetNavigation(for: selectedLens)
                }
            }
        )
    }

    private var taskEditorBinding: Binding<TaskEditorDestination?> {
        Binding(
            get: {
                guard case let .task(destination)? = presentedModal else { return nil }
                return destination
            },
            set: { destination in
                if let destination {
                    presentTaskEditor(destination)
                } else if case .task? = presentedModal {
                    presentedModal = nil
                }
            }
        )
    }

    private func presentQuickAdd(_ destination: QuickAddDestination) {
        presentedModal = .quickAdd(destination)
    }

    private func presentTaskEditor(_ destination: TaskEditorDestination) {
        presentedModal = .task(destination)
    }

    private var venuesPathBinding: Binding<NavigationPath> {
        Binding(
            get: { navigation.venuesPath },
            set: { newPath in
                let wasShowingDetail = !navigation.venuesPath.isEmpty
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

    /// Tasks keeps its count subline in the shell-owned header. Its content
    /// therefore uses the same title-to-content rhythm as Timeline, whose
    /// title lives at the root of its content view.
    private var consoleContentSpacing: CGFloat {
        navigation.selectedLens == .tasks ? VowbaseSpace.small : 14
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
            EmptyView()
        case .guests:
            EmptyView()
        case .tasks:
            ConsoleHeader(openTaskCount: openTaskCount, dueSoonCount: dueSoonTaskCount)
        case .timeline:
            EmptyView()
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
            presentQuickAdd(.guest)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CountdownModule(store: store)
                    NeedsYouModule(
                        store: store,
                        taskStore: taskStore,
                        onSelectTask: { task in presentTaskEditor(.edit(task.id)) },
                        onSelectNudge: { nudge in navigation.selectedLens = nudge.destination },
                        onPromoteNudge: { nudge in presentTaskEditor(.add(prefillTitle: nudge.message)) }
                    )
                    ReachModule(store: store, onTapReadout: handleImpactRowTap)
                    GuestsModule(store: store, onAddGuest: { presentQuickAdd(.guest) })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        case .venues:
            VenuesView(
                store: store,
                onAddVenue: { presentQuickAdd(.venue) },
                onReturnToMap: { navigation.selectedLens = .venues },
                onSelectVenue: selectVenue,
                onViewOnMap: showVenueOnMap,
                onOpenAdministration: openVenueAdministration,
                allowsVerticalScrolling: currentDetent == .full,
                onRequestExpansion: expandCurrentConsole,
                onRequestCollapse: collapseCurrentConsole,
                isNoteEditing: $isVenueNoteEditing,
                path: venuesPathBinding
            )
        case .guests:
            GuestsView(
                store: store,
                allowsVerticalScrolling: currentDetent == .full,
                onRequestExpansion: expandCurrentConsole,
                onRequestCollapse: collapseCurrentConsole,
                path: guestsPathBinding
            )
        case .tasks:
            TasksView(store: store, taskStore: taskStore, editor: taskEditorBinding)
        case .timeline:
            PlanningTimelineView(
                store: store,
                taskStore: taskStore,
                timelineStore: timelineStore,
                allowsVerticalScrolling: currentDetent == .full,
                onRequestExpansion: expandCurrentConsole,
                onRequestCollapse: collapseCurrentConsole,
                onOpenMoment: { moment in
                    presentQuickAdd(.moment(weddingID: moment.weddingID, moment: moment))
                },
                onAddRequirement: {
                    guard let weddingID = store.wedding?.id else { return }
                    presentQuickAdd(.requirement(weddingID: weddingID, requirement: nil))
                },
                onOpenRequirement: { requirement in
                    presentQuickAdd(.requirement(weddingID: requirement.weddingID, requirement: requirement))
                },
                onOpenVenue: selectVenue,
                onOpenGuest: openGuestDetails
            )
        }
    }

    private var openTaskCount: Int {
        taskStore.tasks.filter { $0.effectiveStatus != .done }.count
    }

    private var isRefreshingCurrentLens: Bool {
        switch navigation.selectedLens {
        case .tasks:
            taskStore.isLoading
        case .timeline:
            timelineStore.isLoading || taskStore.isLoading || store.isLoading
        case .overview, .venues, .guests:
            store.isLoading
        }
    }

    private func refreshCurrentLens() {
        if navigation.selectedLens == .tasks, let weddingID = store.wedding?.id {
            Task { await taskStore.load(weddingID: weddingID) }
        } else if navigation.selectedLens == .timeline, let weddingID = store.wedding?.id {
            Task {
                async let workspace: Bool = store.load(presentsFailure: false)
                async let tasks: Void = taskStore.load(weddingID: weddingID)
                async let timeline: Void = timelineStore.load(weddingID: weddingID)
                _ = await (workspace, tasks, timeline)
            }
        } else {
            Task { await store.load() }
        }
    }

    private func expandCurrentConsole() {
        let nextDetent: ConsoleDetent? = switch currentDetent {
        case .peek: .half
        case .half: .full
        case .full: nil
        }
        guard let nextDetent else { return }
        withAnimation(.snappy(duration: 0.28)) {
            lensDetents[navigation.selectedLens] = nextDetent
        }
    }

    private func collapseCurrentConsole() {
        guard currentDetent == .full else { return }
        withAnimation(.snappy(duration: 0.28)) {
            lensDetents[navigation.selectedLens] = .half
        }
    }

    /// Venue field and metric administration are long-form screens. Promote
    /// the persistent console directly to its full detent before their route
    /// appears, matching the Guests lens while leaving ordinary venue detail
    /// presentation unchanged.
    private func openVenueAdministration() {
        withAnimation(.snappy(duration: 0.28)) {
            lensDetents[.venues] = .full
        }
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
        let preservedDetent = currentDetent
        let requiresRecentering = store.selectedVenueID == venue.id
        navigation.selectedGuestID = nil
        navigation.selectedGuestClusterID = nil
        store.selectedVenueID = venue.id
        navigation.selectedLens = .venues
        navigation.venuesPath = NavigationPath()
        venueDetailReturnDetent = preservedDetent
        lensDetents[.venues] = preservedDetent
        navigation.venuesPath.append(venue)
        // A changed venue ID already changes MapWorkspaceView's camera key.
        // Recenter only for the rare same-venue selection, avoiding a second
        // camera update for the normal list/map selection path.
        if requiresRecentering {
            mapFocusToken += 1
        }
    }

    private func selectGuestCluster(_ cluster: GuestCluster) {
        navigation.selectedGuestID = nil
        navigation.selectedGuestClusterID = cluster.id
        store.selectedVenueID = nil
        guestClusterModalWasPresented = true
        presentedModal = .guestCluster(cluster)
    }

    private func clearGuestClusterInsight() {
        navigation.selectedGuestClusterID = nil
        store.clusterTravel = .idle
    }

    private func finishGuestClusterInsightDismissal() {
        guard guestClusterModalWasPresented else { return }
        guestClusterModalWasPresented = false
        clearGuestClusterInsight()
        guard let guest = pendingGuestDetail else { return }
        pendingGuestDetail = nil
        openGuestDetails(guest)
    }

    private func openGuestDetails(_ guest: MVPGuest) {
        navigation.selectedLens = .guests
        navigation.guestsPath = NavigationPath()
        guestDetailReturnDetent = lensDetents[.guests] ?? defaultDetent(for: .guests)
        lensDetents[.guests] = .full
        navigation.guestsPath.append(guest)
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
        navigation.selectedGuestClusterID = nil
        if case .guestCluster? = presentedModal {
            presentedModal = nil
        }
    }
}

/// Global workspace loads keep a single, quiet progress affordance centered
/// over the canvas. The system progress control supplies motion appropriate
/// to the user's accessibility settings; no decorative animation is added.
private struct WeddingLoadingOverlay: View {
    var body: some View {
        VStack(spacing: VowbaseSpace.standard) {
            ZStack {
                Circle()
                    .fill(VowbaseTheme.blush)
                    .frame(width: 76, height: 76)

                Circle()
                    .stroke(VowbaseTheme.rose.opacity(0.18), lineWidth: 1)
                    .frame(width: 62, height: 62)

                ProgressView()
                    .controlSize(.large)
                    .tint(VowbaseTheme.rose)
            }

            VStack(spacing: VowbaseSpace.xSmall) {
                Text("Loading your wedding")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)

                Text("Bringing your plans together")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .multilineTextAlignment(.center)
        }
        .padding(VowbaseSpace.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VowbaseRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VowbaseRadius.large, style: .continuous)
                .stroke(VowbaseTheme.border.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(VowbaseSpace.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your wedding")
        .accessibilityValue("Bringing your plans together")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct TravelCoverageConsole: View {
    let store: VowbaseWorkspaceStore
    let cluster: GuestCluster
    let onOpenGuestDetails: (MVPGuest) -> Void

    private var guests: [MVPGuest] { store.guests(in: cluster) }
    private var comparisons: [ClusterVenueTravel] {
        guard case let .ready(values) = store.clusterTravel else { return [] }
        return Array(values.prefix(2))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(cluster.city) guests")
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(VowbaseTheme.ink)
                    Text(rsvpSummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }

                guestStrip

                if let best = comparisons.first {
                    Text("\(best.venueName) is the easier trip for \(cluster.count) \(cluster.count == 1 ? "guest" : "guests").")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(VowbaseTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Group {
                    switch store.clusterTravel {
                    case .loading:
                        HStack(spacing: 10) {
                            ProgressView().tint(VowbaseTheme.rose)
                            Text("Comparing venue travel…")
                        }
                        .foregroundStyle(VowbaseTheme.mutedInk)
                    case .unavailable:
                        Text("Travel comparison isn’t available right now.")
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    case .ready:
                        VStack(spacing: 0) {
                            ForEach(Array(comparisons.enumerated()), id: \.element.id) { index, comparison in
                                if index > 0 { Divider().padding(.leading, 42) }
                                venueRow(comparison, rank: index)
                            }
                        }
                        .background(VowbaseTheme.blush.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
                    case .idle:
                        EmptyView()
                    }
                }

                Label("Guest locations are shown at city level for privacy.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 18)
        }
    }

    private var rsvpSummary: String {
        let accepted = guests.filter { $0.rsvp == .accepted }.count
        let maybe = guests.filter { $0.rsvp == .maybe }.count
        let pending = guests.filter { $0.rsvp == .pending }.count
        return "Accepted \(accepted)  ·  Maybe \(maybe)  ·  Pending \(pending)"
    }

    private var guestStrip: some View {
        HStack(spacing: -7) {
            ForEach(Array(guests.prefix(5))) { guest in
                Button {
                    onOpenGuestDetails(guest)
                } label: {
                    Text(guest.initials)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VowbaseTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(VowbaseTheme.blush, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(guest.name) details")
            }
            if guests.count > 5 {
                Text("+\(guests.count - 5)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(VowbaseTheme.guestBlue, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }

    private func venueRow(_ comparison: ClusterVenueTravel, rank: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(rank == 0 ? VowbaseTheme.rose : VowbaseTheme.guestBlue)
            Text(comparison.venueName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VowbaseTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(TravelDurationFormatter.string(fromSeconds: comparison.travelTime.durationSeconds))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(rank == 0 ? VowbaseTheme.rose : VowbaseTheme.guestBlue)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }
}

/// The lens rail. Replaces the plain tab bar: each slot is a `PlanLens`, so a
/// new lens (Vendors, Lodging, …) is a new `PlanLens` case, not a new control.
/// See spec §9.
private struct LensRail<TrailingAction: View>: View {
    @Binding var selection: PlanLens
    let showsTrailingAction: Bool
    let trailingAction: TrailingAction

    static var contentHeight: CGFloat { 70 }

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

    init(
        selection: Binding<PlanLens>,
        showsTrailingAction: Bool,
        @ViewBuilder trailingAction: () -> TrailingAction
    ) {
        _selection = selection
        self.showsTrailingAction = showsTrailingAction
        self.trailingAction = trailingAction()
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 8) {
                    navigationContent {
                        railContent
                            .glassEffect(.regular.tint(railTint), in: Capsule())
                    }
                }
            } else {
                navigationContent {
                    railContent
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(railStroke, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    }
            }
        }
        .padding(.horizontal, VowbaseControlMetric.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func navigationContent<Rail: View>(
        @ViewBuilder rail: () -> Rail
    ) -> some View {
        HStack(alignment: .bottom, spacing: VowbaseSpace.medium) {
            rail()
                .frame(maxWidth: .infinity)

            if showsTrailingAction {
                trailingAction
                    .frame(width: VowbaseControlMetric.fabDiameter, height: VowbaseControlMetric.fabDiameter)
            }
        }
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
        // Keep the selected-item feedback, but confine it to the rail's
        // static contents. The selection also changes sheet detents for
        // Tasks, whose full-only presentation must remain under UIKit's
        // native sheet transition rather than this animation transaction.
        .animation(
            reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08),
            value: selection
        )
    }

    private func select(_ lens: PlanLens) {
        UISelectionFeedbackGenerator().selectionChanged()
        selection = lens
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
    WeddingAppShell(store: VowbaseWorkspaceStore(), taskStore: TaskStore(), timelineStore: TimelineStore(), initialLens: .venues)
}

#if DEBUG
#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(testingWorkspace: true), taskStore: TaskStore(), timelineStore: TimelineStore(), initialLens: .guests)
}
#endif
