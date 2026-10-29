import SwiftUI

@main
struct NotchHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchHub", systemImage: "rectangle.topthird.inset.filled") {
            MenuBarContent(
                settings: appDelegate.settings,
                windowManager: appDelegate.windowManager,
                updater: appDelegate.updater,
                micMute: appDelegate.services.system.micMute
            )
            .environment(\.supportActions, appDelegate.supportActions)
        }

        Settings {
            SettingsView(settings: appDelegate.settings, services: appDelegate.services, updater: appDelegate.updater)
                .environment(\.supportActions, appDelegate.supportActions)
        }
    }
}
