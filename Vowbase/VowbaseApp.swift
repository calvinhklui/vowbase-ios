import SwiftUI

@main
struct VowbaseApp: App {
    private let dependencies: AppDependencies?
    private let authCallbackHandler: AuthCallbackHandler?
    @State private var deepLinkRouter = VowbaseDeepLinkRouter()

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
                        presentsInitialVenueDetail: ProcessInfo.processInfo.arguments.contains("-testingVenueDetail"),
                        presentsInitialGuestInsight: ProcessInfo.processInfo.arguments.contains("-testingGuestInsight"),
                        presentsInitialTimelineMomentEditor: ProcessInfo.processInfo.arguments.contains("-testingTimelineMomentEditor"),
                        presentsInitialTimelineRequirementEditor: ProcessInfo.processInfo.arguments.contains("-testingTimelineRequirementEditor")
                    )
                } else if let dependencies {
                    VowbaseAppRoot(dependencies: dependencies, deepLinkRouter: deepLinkRouter)
                } else {
                    VowbaseConfigurationErrorView()
                }
#else
                if let dependencies {
                    VowbaseAppRoot(dependencies: dependencies, deepLinkRouter: deepLinkRouter)
                } else {
                    VowbaseConfigurationErrorView()
                }
#endif
            }
            .onOpenURL { [authCallbackHandler] url in
                if deepLinkRouter.handle(url) { return }
                guard let authCallbackHandler else { return }
                Task {
                    _ = await authCallbackHandler.enqueue(url)
                }
            }
        }
    }
}
