import SwiftUI

/// Status tile: meeting state and elapsed time.
struct MeetingModeStatusTile: View {
    let controller: MeetingModeController

    init(controller: MeetingModeController) {
        self.controller = controller
    }

    var body: some View {
        // Ticks every second only while a meeting runs; otherwise the text is static.
        TimelineView(.periodic(every: 1, paused: !controller.isInMeeting)) { context in
            SystemStatusTileView(
                systemImage: controller.isInMeeting ? "person.wave.2.fill" : "person.wave.2",
                title: "Toplantı",
                value: value(at: context.date),
                detail: detail,
                tint: controller.isEnabled && controller.isInMeeting ? .red : .gray
            )
        }
        .id(controller.isInMeeting)
    }

    private func value(at date: Date) -> String {
        guard controller.isEnabled else { return "Kapalı" }
        guard controller.isInMeeting else { return "Toplantıda değil" }
        return SystemFormat.elapsed(controller.elapsed(at: date))
    }

    private var detail: String? {
        guard controller.isEnabled, let session = controller.session else { return nil }
        return controller.didPauseMedia ? "\(session.source) · Müzik duraklatıldı" : session.source
    }
}

/// Elapsed meeting time (mm:ss) beside the closed notch, ≤ 40 × 14 pt.
struct MeetingModeCompactIndicator: View {
    static let size = CGSize(width: 40, height: 14)

    let controller: MeetingModeController

    init(controller: MeetingModeController) {
        self.controller = controller
    }

    var body: some View {
        if controller.hasCompactIndicator {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let text = SystemFormat.elapsed(controller.elapsed(at: context.date))
                HStack(spacing: 2) {
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                    Text(text)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .frame(width: Self.size.width, height: Self.size.height)
                .help("\(text) süredir toplantıda")
                .accessibilityElement()
                .accessibilityLabel("Toplantıda, \(text)")
            }
        } else {
            EmptyView()
        }
    }
}

/// `Section("Toplantı Modu")` for the settings Form.
struct MeetingModeSettingsSection: View {
    @Bindable var controller: MeetingModeController

    init(controller: MeetingModeController) {
        self.controller = controller
    }

    var body: some View {
        Section("Toplantı Modu") {
            Toggle("Toplantıları algıla", isOn: $controller.isEnabled)
            Toggle("Toplantılarda Spotify / Müzik'i duraklat", isOn: $controller.autoPauseMusic)
                .disabled(!controller.isEnabled)
            Text("Toplantı; Zoom, Teams, Webex veya FaceTime çalışırken mikrofonun aktif olması "
                + "ya da toplantı bağlantılı bir takvim etkinliği sırasında sayılır. Müzik yalnızca NotchHub duraklattıysa devam eder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
