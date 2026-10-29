import SwiftUI

/// Status tile: last known battery levels of the Bluetooth headset.
struct HeadphoneBatteryStatusTile: View {
    let monitor: HeadphoneBatteryMonitor

    init(monitor: HeadphoneBatteryMonitor) {
        self.monitor = monitor
    }

    private static let lowLevel = 20

    var body: some View {
        SystemStatusTileView(
            systemImage: systemImage,
            title: String(localized: "Kulaklık"),
            value: value,
            detail: detail,
            tint: tint,
            help: monitor.lastReport.flatMap { HeadphoneBatteryFormatter.subtitle($0.levels) } ?? ""
        )
    }

    private var report: HeadphoneBatteryReport? { monitor.lastReport }

    private var systemImage: String {
        if let name = report?.deviceName ?? monitor.connectedOutput?.name {
            return HeadphoneBatteryFormatter.deviceGlyph(for: name)
        }
        return "headphones"
    }

    private var value: String {
        guard monitor.isEnabled else { return String(localized: "Kapalı") }
        guard let report else { return monitor.connectedOutput == nil ? String(localized: "Bağlı değil") : String(localized: "Pil bilinmiyor") }
        let parts = HeadphoneBatteryFormatter.parts(report.levels)
        let buds = parts.filter { $0.kind != .caseLevel }
        return (buds.isEmpty ? parts : buds).map(\.text).joined(separator: " · ")
    }

    private var detail: String? {
        guard monitor.isEnabled else { return nil }
        guard let report else { return monitor.connectedOutput?.name }
        let caseText = HeadphoneBatteryFormatter.parts(report.levels).first { $0.kind == .caseLevel }?.text
        return [caseText, report.deviceName].compactMap { $0 }.joined(separator: " · ")
    }

    private var tint: Color {
        guard monitor.isEnabled, let report, let lowest = HeadphoneBatteryFormatter.lowest(report.levels) else {
            return .gray
        }
        return lowest <= Self.lowLevel ? .orange : .blue
    }
}

/// `Section("Kulaklık")` for the settings Form.
struct HeadphoneBatterySettingsSection: View {
    @Bindable var monitor: HeadphoneBatteryMonitor

    init(monitor: HeadphoneBatteryMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        Section("Kulaklık") {
            Toggle("Kulaklık bağlanınca pil durumunu göster", isOn: $monitor.isEnabled)
            Text("AirPods ve diğer Bluetooth kulaklıklar bağlandığında sol, sağ ve kutu pil seviyeleri çentikte görünür.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
