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
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-testingWorkspace") {
                    VowbaseAuthenticatedContent(
                        testingWorkspace: true,
                        presentsInitialVenueInsight: ProcessInfo.processInfo.arguments.contains("-testingVenueInsight")
                    )
                } else if let dependencies {
                    VowbaseAppRoot(dependencies: dependencies)
                } else {
                    VowbaseConfigurationErrorView()
                }
#else
                if let dependencies {
                    VowbaseAppRoot(dependencies: dependencies)
                } else {
                    VowbaseConfigurationErrorView()
                }
#endif
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
