import SwiftUI

/// "Güncellemeler" section in the General tab; hidden when the build has no update feed.
struct UpdatesSettingsSection: View {
    @Bindable var updater: UpdaterService

    var body: some View {
        if updater.isAvailable {
            Section("Güncellemeler") {
                Toggle("Otomatik olarak denetle", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Otomatik indir ve kur", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                LabeledContent("Sürüm", value: updater.currentVersion)
                Button("Şimdi denetle") {
                    updater.checkForUpdates()
                }
            }
        }
    }
}
