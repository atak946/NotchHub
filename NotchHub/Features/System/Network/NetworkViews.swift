import SwiftUI

/// Status tile: online state, interface / Wi-Fi name, expensive / constrained flags.
struct NetworkStatusTile: View {
    let monitor: NetworkMonitor

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        SystemStatusTileView(
            systemImage: monitor.snapshot?.interface.systemImage ?? "network",
            title: "Ağ",
            value: value,
            detail: detail,
            tint: tint,
            help: "Ağ ayarlarını aç",
            action: { monitor.openNetworkSettings() }
        )
    }

    private var value: String {
        guard monitor.isEnabled else { return "Kapalı" }
        return monitor.snapshot?.displayName ?? "Denetleniyor…"
    }

    private var detail: String? {
        guard monitor.isEnabled, let snapshot = monitor.snapshot, snapshot.isOnline else { return nil }
        var flags: [String] = []
        if snapshot.isExpensive { flags.append("Ücretli") }
        if snapshot.isConstrained { flags.append("Düşük Veri") }
        return flags.isEmpty ? "Çevrimiçi" : flags.joined(separator: " · ")
    }

    private var tint: Color {
        guard monitor.isEnabled, let snapshot = monitor.snapshot else { return .gray }
        guard snapshot.isOnline else { return .red }
        return snapshot.isExpensive || snapshot.isConstrained ? .orange : .blue
    }
}

/// Red "no network" dot beside the closed notch while offline.
struct NetworkCompactIndicator: View {
    let monitor: NetworkMonitor

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        if monitor.hasCompactIndicator {
            SystemIndicatorDot(systemImage: "wifi.slash", tint: .red, help: "Offline")
        } else {
            EmptyView()
        }
    }
}

/// `Section("Ağ")` for the settings Form.
struct NetworkSettingsSection: View {
    @Bindable var monitor: NetworkMonitor

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        Section("Ağ") {
            Toggle("Ağ bağlantısını izle", isOn: $monitor.isEnabled)
            Toggle("Çevrimdışı olunca / tekrar çevrimiçi olunca uyar", isOn: $monitor.alertsEnabled)
                .disabled(!monitor.isEnabled)
            Toggle("Ağ değişince uyar", isOn: $monitor.changeAlertsEnabled)
                .disabled(!monitor.isEnabled)
            Text("Wi-Fi adları yalnızca NotchHub'a Konum izni verildiyse gösterilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
