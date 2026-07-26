import SwiftUI

@main
struct VowbaseApp: App {
    private let dependencies: AppDependencies
    private let authCallbackHandler: AuthCallbackHandler

    init() {
        do {
            let dependencies = AppDependencies.live(
                configuration: try AppConfiguration.live()
            )
            self.dependencies = dependencies
            authCallbackHandler = AuthCallbackHandler(auth: dependencies.auth)
        } catch {
            fatalError("Invalid Vowbase backend configuration: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { [authCallbackHandler] url in
                    Task {
                        _ = await authCallbackHandler.enqueue(url)
                    }
                }
        }
    }
}
