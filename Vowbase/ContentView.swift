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

#Preview("Overview") {
    ContentView()
}
