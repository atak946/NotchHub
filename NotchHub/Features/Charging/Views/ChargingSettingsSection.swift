import SwiftUI

struct ChargingSettingsSection: View {
    @Bindable var charging: ChargingPresenter

    var body: some View {
        Section("Pil") {
            Toggle("Şarj animasyonu", isOn: $charging.showsCharging)
            Toggle("Düşük pil uyarısı", isOn: $charging.warnsLowBattery)
            Text("Güç adaptörü takılınca veya çıkarılınca çentikte kısa bir gösterim yapar; pil yüzde 20 ve yüzde 10'a düştüğünde uyarır. Pili olmayan Mac'lerde gösterilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
