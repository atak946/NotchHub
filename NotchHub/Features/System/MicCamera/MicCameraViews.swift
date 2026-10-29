import SwiftUI

/// Status tile: microphone / camera usage, with the system-wide mute toggle in the corner.
struct MicCameraStatusTile: View {
    private static let muteButtonInset: CGFloat = 6

    let monitor: MicCameraMonitor
    let micMute: MicMuteController?

    init(monitor: MicCameraMonitor, micMute: MicMuteController? = nil) {
        self.monitor = monitor
        self.micMute = micMute
    }

    var body: some View {
        SystemStatusTileView(
            systemImage: systemImage,
            title: "Mik. ve Kamera",
            value: value,
            detail: detail,
            tint: tint,
            help: "Mikrofon gizlilik ayarlarını aç",
            action: { monitor.openPrivacySettings() }
        )
        .overlay(alignment: .topTrailing) {
            if let micMute {
                MicMuteTileButton(controller: micMute)
                    .padding(Self.muteButtonInset)
            }
        }
    }

    private var systemImage: String {
        if monitor.isCameraInUse { return "video.fill" }
        return monitor.isMicrophoneInUse ? "mic.fill" : "mic.slash"
    }

    private var value: String {
        guard monitor.isEnabled else { return "Kapalı" }
        switch (monitor.isMicrophoneInUse, monitor.isCameraInUse) {
        case (true, true): return "Mik. + Kamera açık"
        case (true, false): return "Mikrofon açık"
        case (false, true): return "Kamera açık"
        case (false, false): return "Kullanılmıyor"
        }
    }

    private var detail: String? {
        guard monitor.isEnabled else { return nil }
        let names = monitor.snapshot.activeCameras + monitor.snapshot.activeMicrophones
        return names.first
    }

    private var tint: Color {
        guard monitor.isEnabled else { return .gray }
        if monitor.isMicrophoneInUse { return .red }
        return monitor.isCameraInUse ? .green : .gray
    }
}

/// Red mic dot and / or green camera dot beside the closed notch.
struct MicCameraCompactIndicator: View {
    let monitor: MicCameraMonitor

    init(monitor: MicCameraMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        if monitor.hasCompactIndicator {
            HStack(spacing: 2) {
                if monitor.isMicrophoneInUse {
                    SystemIndicatorDot(systemImage: "mic.fill", tint: .red, help: "Microphone in use")
                }
                if monitor.isCameraInUse {
                    SystemIndicatorDot(systemImage: "video.fill", tint: .green, help: "Camera in use")
                }
            }
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
