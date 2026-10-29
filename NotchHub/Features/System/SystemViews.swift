import SwiftUI

/// All System tiles (≈ 140 × 70 pt each). Children are flattened into the parent container,
/// so place this inside a `LazyVGrid` / `HStack` / `VStack`.
struct SystemStatusTiles: View {
    let monitors: SystemMonitors

    init(monitors: SystemMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        Group {
            MeetingModeStatusTile(controller: monitors.meetingMode)
            MicCameraStatusTile(monitor: monitors.micCamera, micMute: monitors.micMute)
            HeadphoneBatteryStatusTile(monitor: monitors.headphones)
            VPNStatusTile(monitor: monitors.vpn)
            NetworkStatusTile(monitor: monitors.network)
            SystemPressureStatusTile(monitor: monitors.pressure)
        }
    }
}

/// Compact glyphs beside the closed notch: meeting timer, mic / camera dots, VPN and offline dots.
/// Renders `EmptyView` when nothing is active. At most ~40 + 3 × 14 pt wide.
struct SystemCompactIndicators: View {
    let monitors: SystemMonitors

    init(monitors: SystemMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        if monitors.hasCompactIndicator {
            HStack(spacing: 3) {
                MeetingModeCompactIndicator(controller: monitors.meetingMode)
                MicCameraCompactIndicator(monitor: monitors.micCamera)
                VPNCompactIndicator(monitor: monitors.vpn)
                NetworkCompactIndicator(monitor: monitors.network)
            }
            .environment(\.colorScheme, .dark)
        } else {
            EmptyView()
        }
    }
}

/// Every System settings section for the grouped settings Form.
struct SystemSettingsSection: View {
    let monitors: SystemMonitors

    init(monitors: SystemMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        MeetingModeSettingsSection(controller: monitors.meetingMode)
        MicCameraSettingsSection(monitor: monitors.micCamera)
        MicMuteSettingsSection(controller: monitors.micMute)
        HeadphoneBatterySettingsSection(monitor: monitors.headphones)
        VPNSettingsSection(monitor: monitors.vpn)
        NetworkSettingsSection(monitor: monitors.network)
        SystemPressureSettingsSection(monitor: monitors.pressure)
    }
}
