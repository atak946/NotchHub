import SwiftUI

struct MenuBarContent: View {
    @Bindable var settings: SettingsStore
    let windowManager: NotchWindowManager
    let updater: UpdaterService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Paneli Aç/Kapat") {
            windowManager.togglePanel()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Toggle("NotchHub'ı Duraklat", isOn: $settings.isPaused)

        Divider()

        Button("Ayarlar…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        if updater.isAvailable {
            Button("Güncellemeleri denetle…") {
                updater.checkForUpdates()
            }
        }

        Button("NotchHub'dan Çık") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
