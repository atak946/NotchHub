import SwiftUI

/// App-level entry points for the setup wizard and issue reporting, passed through the environment
/// so the menu bar and Settings can reach them without new init parameters.
struct SupportActions: Sendable {
    var openOnboarding: @MainActor @Sendable () -> Void = {}
    var reportIssue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    @Entry var supportActions = SupportActions()
}

/// "Destek" section for Settings › Genel.
struct SupportSettingsSection: View {
    @Environment(\.supportActions) private var supportActions

    var body: some View {
        Section("Destek") {
            Button("Kurulum sihirbazı…") { supportActions.openOnboarding() }
            Button("Sorun bildir…") { supportActions.reportIssue() }
            Text("Rapor gizlilik için temizlenir: e-posta, bağlantı parametreleri, IP adresleri ve ev klasörü yolu çıkarılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
