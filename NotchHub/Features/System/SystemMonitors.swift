import Foundation
import Observation

/// Facade owning the System feature services (mic/camera, VPN, network, pressure, meeting mode).
@MainActor
final class SystemMonitors {
    let runningApps: SystemRunningApps
    let micCamera: MicCameraMonitor
    let vpn: VPNMonitor
    let network: NetworkMonitor
    let pressure: SystemPressureMonitor
    let meetingMode: MeetingModeController
    /// System-wide mic mute; started by `ModuleServices` regardless of module toggles.
    let micMute: MicMuteController
    let headphones: HeadphoneBatteryMonitor

    private var isStarted = false

    init(alerts: NotchAlertCenter, media: MediaService, calendar: CalendarService, defaults: UserDefaults = .standard) {
        let runningApps = SystemRunningApps()
        let micCamera = MicCameraMonitor(alerts: alerts, runningApps: runningApps, defaults: defaults)
        self.runningApps = runningApps
        self.micCamera = micCamera
        vpn = VPNMonitor(alerts: alerts, runningApps: runningApps, defaults: defaults)
        network = NetworkMonitor(alerts: alerts, defaults: defaults)
        pressure = SystemPressureMonitor(alerts: alerts, defaults: defaults)
        meetingMode = MeetingModeController(
            inputs: SystemMeetingInputs(micCamera: micCamera, calendar: calendar),
            media: media,
            defaults: defaults
        )
        micMute = MicMuteController(alerts: alerts, defaults: defaults)
        headphones = HeadphoneBatteryMonitor(alerts: alerts, defaults: defaults)
    }

    /// True when at least one compact indicator has something to show.
    var hasCompactIndicator: Bool {
        micCamera.hasCompactIndicator || vpn.hasCompactIndicator
            || network.hasCompactIndicator || meetingMode.hasCompactIndicator
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        runningApps.start()
        syncMeetingRequirement()
        micCamera.start()
        vpn.start()
        network.start()
        pressure.start()
        meetingMode.start()
        headphones.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        meetingMode.stop()
        headphones.stop()
        micCamera.stop()
        vpn.stop()
        network.stop()
        pressure.stop()
        runningApps.stop()
    }

    /// Meeting mode needs microphone state even when the mic indicator is switched off.
    private func syncMeetingRequirement() {
        micCamera.keepsMonitoringForMeetings = withObservationTracking {
            meetingMode.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.syncMeetingRequirement()
            }
        }
    }
}

/// Feeds meeting mode from the mic monitor, running apps and the calendar.
@MainActor
final class SystemMeetingInputs: MeetingModeInputs {
    private let micCamera: MicCameraMonitor
    private let calendar: CalendarService

    init(micCamera: MicCameraMonitor, calendar: CalendarService) {
        self.micCamera = micCamera
        self.calendar = calendar
    }

    var isMicrophoneInUse: Bool { micCamera.isMicrophoneInUse }

    var runningMeetingApps: [MeetingApp] { micCamera.runningMeetingApps }

    var calendarEvents: [CalendarEvent] {
        let today = calendar.todayEvents
        guard let next = calendar.nextEvent, !today.contains(where: { $0.id == next.id }) else { return today }
        return [next] + today
    }
}
