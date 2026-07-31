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
/// - Overview's console only ever offers `.peek` — its module stack (§11) is
///   Phase 5. Until then it shows the same venue rail Venues shows at peek.
/// - A `.sheet` always renders above everything in the view it's presented
///   from, so the lens rail lives *inside* the console's own content (pinned
///   to its bottom) rather than as an overlay on the canvas — otherwise the
///   sheet would cover it at every detent. The Quick Add FAB follows suit:
///   at `.peek` it floats on the canvas just above the console, but past
///   peek the console covers most or all of the screen, so the FAB moves
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

    /// Each lens remembers its own detent for the session — spec §7.1.
    @State private var lensDetents: [PlanLens: ConsoleDetent] = [
        .overview: .peek,
        .venues: .peek,
        .guests: .peek,
        .tasks: .half,
    ]

    init(
        store: VowbaseWorkspaceStore,
        taskStore: TaskStore,
        initialLens: PlanLens = .overview,
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

                MapWorkspaceView(store: store, consoleInset: consoleHeight)

                ContextBar(store: store, onSignOut: onSignOut)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if store.isLoading {
                    ProgressView("Loading your wedding")
                        .tint(VowbaseTheme.rose)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // At peek, the console is short enough that the FAB reads as
                // part of the canvas floating just above it. Past peek it
                // moves inside `consoleSheet` itself, or the console would
                // cover it.
                if currentDetent == .peek {
                    QuickAddOverlay(
                        isPresented: $isQuickAddPresented,
                        onAddVenue: { quickAdd = .venue },
                        onAddGuest: { quickAdd = .guest },
                        onAddTask: { taskEditor = .add }
                    )
                    .padding(.trailing, VowbaseControlMetric.screenInset)
                    .padding(.bottom, consoleHeight + 12)
                }
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
            .sheet(isPresented: .constant(true)) {
                consoleSheet
            }
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
        .animation(.snappy(duration: 0.28), value: navigation.selectedLens)
    }

    // MARK: Console

    private var currentDetent: ConsoleDetent {
        lensDetents[navigation.selectedLens] ?? defaultDetent(for: navigation.selectedLens)
    }

    private func defaultDetent(for lens: PlanLens) -> ConsoleDetent {
        lens == .tasks ? .half : .peek
    }

    private func availableDetents(for lens: PlanLens) -> Set<PresentationDetent> {
        switch lens {
        case .overview:
            [ConsoleDetent.peek.presentationDetent]
        case .venues, .guests:
            Set(ConsoleDetent.allCases.map(\.presentationDetent))
        case .tasks:
            [ConsoleDetent.half.presentationDetent, ConsoleDetent.full.presentationDetent]
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

    /// The console: grabber, selection-aware header, per-lens content — and,
    /// pinned to its own bottom, the lens rail. A `.sheet` always presents
    /// above the entire view it's attached to, so the rail has to live
    /// inside the sheet's own content to stay visible at every detent —
    /// as an overlay on the presenting canvas, the sheet would cover it.
    ///
    /// The grabber and header are the console's own chrome for *its* root
    /// content (the rail, or a lens's list). Venues and Guests each own an
    /// inner `NavigationStack`; once one has pushed to a detail screen, that
    /// screen's own toolbar is the header, and stacking the console's chrome
    /// above it just wastes vertical space on a second, redundant header.
    @ViewBuilder
    private var consoleSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isConsoleAtRoot {
                Capsule()
                    .fill(VowbaseTheme.border)
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)

                consoleHeader
                    .padding(.horizontal, 16)
            }

            consoleContent
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if currentDetent != .peek {
                QuickAddOverlay(
                    isPresented: $isQuickAddPresented,
                    onAddVenue: { quickAdd = .venue },
                    onAddGuest: { quickAdd = .guest },
                    onAddTask: { taskEditor = .add }
                )
                .padding(.trailing, VowbaseControlMetric.screenInset)
                .padding(.bottom, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LensRail(selection: selectedLensBinding)
        }
        .presentationDetents(availableDetents(for: navigation.selectedLens), selection: detentBinding)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(true)
    }

    /// Whether the active lens's console is showing its own root content
    /// (rail or list) rather than something it pushed to internally.
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
        Binding(get: { navigation.venuesPath }, set: { navigation.venuesPath = $0 })
    }

    private var guestsPathBinding: Binding<NavigationPath> {
        Binding(get: { navigation.guestsPath }, set: { navigation.guestsPath = $0 })
    }

    @ViewBuilder
    private var consoleHeader: some View {
        switch navigation.selectedLens {
        case .overview, .venues:
            if let venue = store.venues.first(where: { $0.id == store.selectedVenueID }) {
                ConsoleHeader(selectedVenue: venue)
            } else {
                ConsoleHeader(venues: store.venues)
            }
        case .guests:
            ConsoleHeader(guests: store.allGuestRecords)
        case .tasks:
            ConsoleHeader(openTaskCount: openTaskCount, dueSoonCount: dueSoonTaskCount)
        }
    }

    @ViewBuilder
    private var consoleContent: some View {
        switch navigation.selectedLens {
        case .overview:
            VenueRailContent(store: store)
        case .venues:
            if currentDetent == .peek {
                VenueRailContent(store: store)
            } else {
                VenuesView(
                    store: store,
                    onAddVenue: { quickAdd = .venue },
                    onReturnToMap: { navigation.selectedLens = .overview },
                    path: venuesPathBinding
                )
            }
        case .guests:
            if currentDetent == .peek {
                GuestRailContent(store: store)
            } else {
                GuestsView(store: store, path: guestsPathBinding)
            }
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
}

/// The lens rail. Replaces the plain tab bar: each slot is a `PlanLens`, so a
/// new lens (Vendors, Lodging, …) is a new `PlanLens` case, not a new control.
/// See spec §9.
private struct LensRail: View {
    @Binding var selection: PlanLens

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                railContent
                    .glassEffect(
                        .regular.tint(Color.black.opacity(0.54)),
                        in: Capsule()
                    )
            } else {
                railContent
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

    private var railContent: some View {
        HStack(spacing: 4) {
            ForEach(PlanLens.allCases) { lens in
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
        .frame(height: 70)
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: lens.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolVariant(.fill)

            Text(lens.title)
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

#Preview("Venues") {
    WeddingAppShell(store: VowbaseWorkspaceStore(), taskStore: TaskStore(), initialLens: .venues)
}

#if DEBUG
#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(testingWorkspace: true), taskStore: TaskStore(), initialLens: .guests)
}
#endif
