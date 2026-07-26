import SwiftUI

@main
struct VowbaseApp: App {
    private let dependencies: AppDependencies

    init() {
        do {
            dependencies = AppDependencies.live(
                configuration: try AppConfiguration.live()
            )
        } catch {
            fatalError("Invalid Vowbase backend configuration: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { [auth = dependencies.auth] url in
                    Task {
                        try? await auth.handle(url: url)
                    }
                }
        }
    }
}
