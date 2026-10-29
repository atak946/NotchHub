import SwiftUI

/// Status tile: memory pressure, thermal state and free disk space.
struct SystemPressureStatusTile: View {
    let monitor: SystemPressureMonitor

    init(monitor: SystemPressureMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        SystemStatusTileView(
            systemImage: "gauge.with.dots.needle.67percent",
            title: String(localized: "Sistem"),
            value: monitor.isEnabled ? String(localized: "Bellek \(monitor.memoryPressure.title)") : String(localized: "Kapalı"),
            detail: detail,
            tint: tint,
            help: String(localized: "Etkinlik Monitörü'nü aç"),
            action: { monitor.openActivityMonitor() }
        )
    }

    private var detail: String? {
        guard monitor.isEnabled else { return nil }
        let disk = monitor.freeDiskBytes.map { String(localized: "\(SystemFormat.bytes($0)) boş") } ?? String(localized: "Disk —")
        return "\(monitor.thermalLevel.title) · \(disk)"
    }

    private var tint: Color {
        guard monitor.isEnabled else { return .gray }
        switch monitor.worstSeverity {
        case .none: return .green
        case .elevated: return .orange
        case .critical: return .red
        }
    }
}

/// `Section("Sistem Sağlığı")` for the settings Form.
struct SystemPressureSettingsSection: View {
    @Bindable var monitor: SystemPressureMonitor

    init(monitor: SystemPressureMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        Section("Sistem Sağlığı") {
            Toggle("Bellek, sıcaklık ve diski izle", isOn: $monitor.isEnabled)
            Toggle("Yüksek baskıda veya düşük diskte uyar", isOn: $monitor.alertsEnabled)
                .disabled(!monitor.isEnabled)
            Picker("Düşük disk alanı eşiği", selection: $monitor.diskThresholdGigabytes) {
                ForEach(DiskSpacePolicy.thresholdGigabyteOptions, id: \.self) { gigabytes in
                    Text("\(gigabytes) GB").tag(gigabytes)
                }
            }
            .disabled(!monitor.isEnabled)
        }
    }
}
