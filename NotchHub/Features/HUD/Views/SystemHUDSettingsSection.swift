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
            Picker("Ses tuşu adımı", selection: $hud.volumeStep) {
                ForEach(VolumeKeyStep.allCases) { step in
                    Text(step.title).tag(step)
                }
            }
            .disabled(!hud.isEnabled || !hud.hidesSystemHUD)
            Text("Tuşları NotchHub yönetirken geçerlidir. Option+Shift ile dörtte bir adım.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Göstergede kaydırarak veya sürükleyerek ayarla", isOn: $hud.isInteractive)
                .disabled(!hud.isEnabled)
            Text("Gösterge açıkken üzerinde kaydırın veya çubuğu sürükleyin; çubuğun dışındaki tıklamalar menü çubuğuna geçer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
