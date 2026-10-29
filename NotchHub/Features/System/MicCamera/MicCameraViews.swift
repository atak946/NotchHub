import AppKit
import SwiftUI

/// Status tile: microphone / camera usage, with the system-wide mute toggle in the corner.
struct MicCameraStatusTile: View {
    private static let muteButtonInset: CGFloat = 6
    private static let appIconSize: CGFloat = 16
    private static let appIconInset: CGFloat = 8

    let monitor: MicCameraMonitor
    let micMute: MicMuteController?

    init(monitor: MicCameraMonitor, micMute: MicMuteController? = nil) {
        self.monitor = monitor
        self.micMute = micMute
    }

    var body: some View {
        SystemStatusTileView(
            systemImage: systemImage,
            title: String(localized: "Mik. ve Kamera"),
            value: value,
            detail: detail,
            tint: tint,
            help: String(localized: "Mikrofon gizlilik ayarlarını aç"),
            action: { monitor.openPrivacySettings() }
        )
        .overlay(alignment: .topTrailing) {
            if let micMute {
                MicMuteTileButton(controller: micMute)
                    .padding(Self.muteButtonInset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let icon = microphoneAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Self.appIconSize, height: Self.appIconSize)
                    .padding(Self.appIconInset)
                    .accessibilityHidden(true)
            }
        }
    }

    private var microphoneAppIcon: NSImage? {
        guard monitor.isEnabled, monitor.isMicrophoneInUse, let app = monitor.microphoneApps.first else { return nil }
        return AppIconResolver.shared.icon(bundleID: app.bundleID, appName: app.name)
    }

    private var systemImage: String {
        if monitor.isCameraInUse { return "video.fill" }
        return monitor.isMicrophoneInUse ? "mic.fill" : "mic.slash"
    }

    private var value: String {
        guard monitor.isEnabled else { return String(localized: "Kapalı") }
        switch (monitor.isMicrophoneInUse, monitor.isCameraInUse) {
        case (true, true): return String(localized: "Mik. + Kamera açık")
        case (true, false): return String(localized: "Mikrofon açık")
        case (false, true): return String(localized: "Kamera açık")
        case (false, false): return String(localized: "Kullanılmıyor")
        }
    }

    private var detail: String? {
        guard monitor.isEnabled else { return nil }
        if let usage = monitor.microphoneUsageText { return usage }
        if monitor.isCameraInUse { return String(localized: "Kamera kullanımda") }
        return monitor.snapshot.activeMicrophones.first
    }

    private var tint: Color {
        guard monitor.isEnabled else { return .gray }
        if monitor.isMicrophoneInUse { return Color(nsColor: .systemOrange) }
        return monitor.isCameraInUse ? Color(nsColor: .systemGreen) : .gray
    }
}

/// macOS-style privacy dot beside the closed notch: green while the camera is on, otherwise orange for the mic.
struct MicCameraCompactIndicator: View {
    let monitor: MicCameraMonitor

    init(monitor: MicCameraMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        if monitor.hasCompactIndicator, let kind = monitor.privacyIndicatorKind {
            // `.id` restarts the appear pulse when the dot switches between camera and microphone.
            PrivacyIndicatorDot(kind: kind, help: monitor.privacyIndicatorHelp)
                .id(kind)
        } else {
            EmptyView()
        }
    }
}

/// `Section("Mikrofon ve Kamera")` for the settings Form.
struct MicCameraSettingsSection: View {
    @Bindable var monitor: MicCameraMonitor

    init(monitor: MicCameraMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        Section("Mikrofon ve Kamera") {
            Toggle("Mikrofon ve kamera göstergesini göster", isOn: $monitor.isEnabled)
            Toggle("Gizlilik göstergesi", isOn: $monitor.privacyIndicatorEnabled)
                .disabled(!monitor.isEnabled)
            Text("Mikrofon veya kamera kullanılırken kapalı çentikte macOS renklerinde bir nokta gösterir.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Mikrofon açık kalırsa uyar", isOn: $monitor.alertsEnabled)
                .disabled(!monitor.isEnabled)
            Picker("Uyarı süresi", selection: $monitor.idleAlertMinutes) {
                ForEach(MicCameraMonitor.idleAlertMinuteOptions, id: \.self) { minutes in
                    Text("\(minutes) dakika").tag(minutes)
                }
            }
            .disabled(!monitor.isEnabled || !monitor.alertsEnabled)
            Text("Zoom, Teams, Webex veya FaceTime açıkken uyarı verilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
