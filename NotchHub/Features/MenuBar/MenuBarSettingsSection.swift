import SwiftUI

/// `Section("Menü Çubuğu")` for the settings Form.
struct MenuBarSettingsSection: View {
    @Bindable var container: MenuBarContainer
    let insights: Insights

    var body: some View {
        Section("Menü Çubuğu") {
            Toggle("Simgeleri kutuda topla", isOn: $container.isEnabled)
            Text("Menü çubuğuna bir ok ekler; solundaki simgeler gizlenir ve oka basınca aşağı açılan kutuda görünür. Neyin gizleneceğini kutudaki Düzenle ile, simgeleri ⌘ basılıyken ayracın soluna veya sağına sürükleyerek seç.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if container.isEnabled, !insights.isAccessibilityTrusted {
                LabeledContent("Simgeleri okumak ve açmak için Erişilebilirlik izni gerekir.") {
                    Button("Erişilebilirlik İzni Ver") { insights.requestAccessibilityAccess() }
                }
            }
            Toggle("Simgeleri çubuktaki gibi göster", isOn: $container.showsLiveIcons)
                .disabled(!container.isEnabled)
            if container.isEnabled, container.needsCaptureAccess {
                LabeledContent("Ekran Kaydı izni") {
                    HStack {
                        Button("İzin ver") { container.requestCaptureAccess() }
                        Button("Yeniden başlat") { AppRelauncher.relaunch() }
                    }
                }
            }
            Text("CPU/RAM değeri ve VPN işareti gibi canlı görünümler için Ekran Kaydı izni gerekir. Görüntüler yalnızca kutu açıkken alınır ve bu Mac'ten çıkmaz. İzin verdikten sonra NotchHub'ı yeniden aç.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
