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
    private enum WorkspacePresentationState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @State private var store: VowbaseWorkspaceStore
    @State private var taskStore: TaskStore
    @State private var timelineStore: TimelineStore
    @State private var presentationState = WorkspacePresentationState.loading
    private let initialLens: PlanLens
    private let presentsInitialVenueInsight: Bool
    private let presentsInitialGuestInsight: Bool
    let onSignOut: () -> Void

    init(
        repositories: RepositoryContainer? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.onSignOut = onSignOut
        initialLens = .venues
        presentsInitialVenueInsight = false
        presentsInitialGuestInsight = false
        _store = State(initialValue: VowbaseWorkspaceStore(repositories: repositories))
        _taskStore = State(initialValue: TaskStore(repository: repositories?.tasks))
        _timelineStore = State(initialValue: TimelineStore(
            repository: repositories?.timeline,
            inspirationRepository: repositories?.inspiration
        ))
    }

#if DEBUG
    init(
        testingWorkspace: Bool,
        presentsInitialVenueInsight: Bool = false,
        presentsInitialGuestInsight: Bool = false,
        onSignOut: @escaping () -> Void = {}
    ) {
        precondition(testingWorkspace)
        self.onSignOut = onSignOut
        initialLens = .venues
        self.presentsInitialVenueInsight = presentsInitialVenueInsight
        self.presentsInitialGuestInsight = presentsInitialGuestInsight
        _store = State(initialValue: VowbaseWorkspaceStore(testingWorkspace: true))
        let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
        _taskStore = State(initialValue: TaskStore.testingWorkspace(weddingID: weddingID))
        _timelineStore = State(initialValue: TimelineStore())
    }
#endif

    var body: some View {
        Group {
            switch presentationState {
            case .loading:
                VowbaseLoadingView(
                    title: "Opening your wedding",
                    detail: "Bringing your plans together"
                )
                .transition(.opacity)
            case .ready:
                WeddingAppShell(
                    store: store,
                    taskStore: taskStore,
                    timelineStore: timelineStore,
                    initialLens: initialLens,
                    presentsInitialVenueInsight: presentsInitialVenueInsight,
                    presentsInitialGuestInsight: presentsInitialGuestInsight,
                    onSignOut: onSignOut
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case let .failed(message):
                WorkspaceLoadingFailureView(message: message) {
                    Task { await loadWorkspace() }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: presentationState)
        .task { await loadWorkspace() }
    }

    @MainActor
    private func loadWorkspace() async {
        presentationState = .loading
        let loaded = await store.load(presentsFailure: false)
        guard !Task.isCancelled else { return }

        if loaded {
            presentationState = .ready
        } else {
            presentationState = .failed(
                store.errorMessage ?? "We couldn’t open your wedding workspace. Please try again."
            )
        }
    }
}

private struct WorkspaceLoadingFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            VowbaseTheme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(VowbaseTheme.rose)
                    .frame(width: 64, height: 64)
                    .background(VowbaseTheme.blush, in: Circle())

                VStack(spacing: 8) {
                    Text("We couldn’t open your plans")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(VowbaseTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Try again", action: retry)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseDesign.onRose)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(VowbaseTheme.rose, in: Capsule())
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
    }
}

#Preview("Overview") {
    ContentView()
}
