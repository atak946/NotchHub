import SwiftUI

struct SystemHUDSettingsSection: View {
    @Bindable var hud: SystemHUD

    var body: some View {
        Section("Göstergeler") {
            Toggle("Ses/parlaklık göstergesi çentikte", isOn: $hud.isEnabled)
            Text("Sistem göstergesi de görünmeye devam eder; çentik uyarısı varken veya panel açıkken gösterilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
