import SwiftUI

@main
struct VowbaseApp: App {
    private let dependencies: AppDependencies?
    private let authCallbackHandler: AuthCallbackHandler?

    init() {
        do {
            let dependencies = AppDependencies.live(
                configuration: try AppConfiguration.live()
            )
            self.dependencies = dependencies
            authCallbackHandler = AuthCallbackHandler(auth: dependencies.auth)
        } catch {
            dependencies = nil
            authCallbackHandler = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let dependencies {
                    VowbaseAppRoot(auth: dependencies.auth)
                } else {
                    VowbaseConfigurationErrorView()
                }
            }
            .onOpenURL { [authCallbackHandler] url in
                    guard let authCallbackHandler else { return }
                    Task {
                        _ = await authCallbackHandler.enqueue(url)
                    }
                }
        }
    }
}
