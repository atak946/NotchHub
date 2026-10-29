import SwiftUI

struct SystemHUDSettingsSection: View {
    @Bindable var hud: SystemHUD

    var body: some View {
        Section("Göstergeler") {
            Toggle("Ses/parlaklık göstergesi çentikte", isOn: $hud.isEnabled)
            Text("Çentik uyarısı varken veya panel açıkken gösterilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("macOS ses/parlaklık kutusunu gizle (tuşları NotchHub yönetir)", isOn: $hud.hidesSystemHUD)
                .disabled(!hud.isEnabled)
            Text("Erişilebilirlik izni gerekir; izin yoksa macOS kutusu da görünür. Harici ekranlar ve HDMI/DisplayPort ses çıkışı macOS'ta kalır.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
