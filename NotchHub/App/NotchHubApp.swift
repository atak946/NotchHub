import SwiftUI

@main
struct NotchHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            // Screenshot rendering must never build the live services (they read the user's stores).
            if ScreenshotMode.isActive {
                EmptyView()
            } else {
                SettingsView(
                    settings: appDelegate.settings,
                    language: appDelegate.language,
                    services: appDelegate.services,
                    updater: appDelegate.updater
                )
                    .environment(\.supportActions, appDelegate.supportActions)
            }
        }
        .windowResizability(.contentMinSize)
    }
}
