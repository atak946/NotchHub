import SwiftUI

@main
struct NotchHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: appDelegate.settings,
                language: appDelegate.language,
                services: appDelegate.services,
                updater: appDelegate.updater
            )
                .environment(\.supportActions, appDelegate.supportActions)
        }
        .windowResizability(.contentMinSize)
    }
}
