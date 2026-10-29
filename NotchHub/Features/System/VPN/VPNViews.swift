import SwiftUI

/// Status tile: VPN tunnel state and which known VPN client is running.
struct VPNStatusTile: View {
    let monitor: VPNMonitor

    init(monitor: VPNMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        SystemStatusTileView(
            systemImage: systemImage,
            title: "VPN",
            value: monitor.isEnabled ? monitor.state.title : String(localized: "Kapalı"),
            detail: detail,
            tint: tint,
            help: String(localized: "\(monitor.displayName) uygulamasını aç"),
            action: { monitor.openClient() }
        )
    }

    private var systemImage: String {
        switch monitor.state {
        case .connected: "lock.shield.fill"
        case .disconnected: "lock.slash.fill"
        case .unknown: "lock.shield"
        }
    }

    private var detail: String? {
        guard monitor.isEnabled else { return nil }
        if let client = monitor.runningClient { return String(localized: "\(client.displayName) çalışıyor") }
        return monitor.tunnelInterfaces.first
    }

    private var tint: Color {
        guard monitor.isEnabled else { return .gray }
        switch monitor.state {
        case .connected: return .green
        case .disconnected: return monitor.hasCompactIndicator ? .red : .orange
        case .unknown: return .gray
        }
    }
}

/// Red shield dot while the VPN is down after it was connected.
struct VPNCompactIndicator: View {
    let monitor: VPNMonitor

    init(monitor: VPNMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        if monitor.hasCompactIndicator {
            SystemIndicatorDot(systemImage: "lock.slash.fill", tint: .red, help: String(localized: "VPN bağlantısı koptu"))
        } else {
            EmptyView()
        }
    }
}

/// `Section("VPN")` for the settings Form.
struct VPNSettingsSection: View {
    private static var detectionHint: String {
        let clients = VPNClientCatalog.all.map(\.displayName).joined(separator: ", ")
        return String(localized: "Bilinen VPN istemcilerini (\(clients)) ve IPv4 adresi taşıyan utun/ipsec tünellerini algılar.")
    }

    @Bindable var monitor: VPNMonitor

    init(monitor: VPNMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        Section("VPN") {
            Toggle("VPN bağlantısını izle", isOn: $monitor.isEnabled)
            Toggle("VPN koptuğunda veya yeniden bağlandığında uyar", isOn: $monitor.alertsEnabled)
                .disabled(!monitor.isEnabled)
            LabeledContent("Algılanan istemci", value: monitor.clientDisplayName ?? String(localized: "Yok"))
            Text(Self.detectionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
