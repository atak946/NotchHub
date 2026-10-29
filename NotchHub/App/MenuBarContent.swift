import SwiftUI

struct MenuBarContent: View {
    @Bindable var settings: SettingsStore
    let windowManager: NotchWindowManager
    let updater: UpdaterService
    var micMute: MicMuteController?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.supportActions) private var supportActions

    var body: some View {
        Button("Paneli Aç/Kapat") {
            windowManager.togglePanel()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button("Ayna (kamerayı kontrol et)") {
            windowManager.openCameraMirror()
        }
        .disabled(settings.isPaused)

        Toggle("NotchHub'ı Duraklat", isOn: $settings.isPaused)

        if let micMute {
            Button("Mikrofonu sustur/aç") {
                micMute.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!micMute.isAvailable)
        }

        Divider()

        Button("Ayarlar…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Kurulum sihirbazı…") {
            supportActions.openOnboarding()
        }

        Button("Sorun bildir…") {
            supportActions.reportIssue()
        }

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
