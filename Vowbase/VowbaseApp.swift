import SwiftUI

@main
struct VowbaseApp: App {
    private let authCallbackHandler: AuthCallbackHandler?

    init() {
        do {
            let dependencies = AppDependencies.live(
                configuration: try AppConfiguration.live()
            )
            authCallbackHandler = AuthCallbackHandler(auth: dependencies.auth)
        } catch {
            // The local-first MVP is usable before an authenticated workspace
            // has been configured. Production configuration still enables
            // authenticated callback handling when it is available.
            authCallbackHandler = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { [authCallbackHandler] url in
                    guard let authCallbackHandler else { return }
                    Task {
                        _ = await authCallbackHandler.enqueue(url)
                    }
                }
        }
    }
}
