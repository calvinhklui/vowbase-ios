import SwiftUI
import UIKit

// MARK: - App shell

private enum QuickAddDestination: String, Identifiable {
    case venue
    case guest

    var id: String { rawValue }
}

@MainActor
struct WeddingAppShell: View {
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

        ZStack {
            VowbaseTheme.background.ignoresSafeArea()

            Group {
                switch navigation.selectedLens {
                case .overview:
                    MapWorkspaceView(
                        store: store,
                        onSignOut: onSignOut
                    )
                case .venues:
                    VenuesView(
                        store: store,
                        onSignOut: onSignOut,
                        onAddVenue: { quickAdd = .venue },
                        onReturnToMap: { navigation.selectedLens = .overview }
                    )
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
            LensRail(selection: $navigation.selectedLens)
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
            .padding(.bottom, LensRail.fabBottomClearance)
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

}

/// The lens rail. Replaces the plain tab bar: each slot is a `PlanLens`, so a
/// new lens (Vendors, Lodging, …) is a new `PlanLens` case, not a new control.
/// See spec §9.
private struct LensRail: View {
    static let fabBottomClearance: CGFloat = 90

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

#Preview("Venues") {
    WeddingAppShell(store: VowbaseWorkspaceStore(), taskStore: TaskStore(), initialLens: .venues)
}

#Preview("Guests") {
    WeddingAppShell(store: VowbaseWorkspaceStore(testingWorkspace: true), taskStore: TaskStore(), initialLens: .guests)
}
