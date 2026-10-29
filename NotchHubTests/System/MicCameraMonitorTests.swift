import Foundation
import Testing
@testable import NotchHub

struct MicIdlePolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func alertsAfterThresholdWithoutMeetingApp() {
        let now = start.addingTimeInterval(600)
        #expect(MicIdlePolicy.shouldAlert(
            activeSince: start, now: now, threshold: 600, isMeetingAppRunning: false, alreadyAlerted: false
        ))
        #expect(!MicIdlePolicy.shouldAlert(
            activeSince: start, now: now.addingTimeInterval(-1), threshold: 600, isMeetingAppRunning: false, alreadyAlerted: false
        ))
        #expect(!MicIdlePolicy.shouldAlert(
            activeSince: start, now: now, threshold: 600, isMeetingAppRunning: true, alreadyAlerted: false
        ))
        #expect(!MicIdlePolicy.shouldAlert(
            activeSince: start, now: now, threshold: 600, isMeetingAppRunning: false, alreadyAlerted: true
        ))
        #expect(!MicIdlePolicy.shouldAlert(
            activeSince: nil, now: now, threshold: 600, isMeetingAppRunning: false, alreadyAlerted: false
        ))
    }
}

@MainActor
struct MicCameraMonitorTests {
    private let clock = SystemTestClock()
    private let reader = SystemTestCaptureReader()
    private let alerts = SystemTestSupport.makeAlertCenter()
    private let micOn = CaptureSnapshot(activeMicrophones: ["MacBook Pro Microphone"], activeCameras: [])

    private func makeMonitor(apps: [SystemRunningApp] = []) -> MicCameraMonitor {
        let runningApps = SystemRunningApps(source: { apps })
        runningApps.reload()
        let monitor = MicCameraMonitor(
            alerts: alerts, runningApps: runningApps, reader: reader,
            processReader: TestAudioProcessReader(), clock: clock,
            defaults: SystemTestSupport.makeDefaults()
        )
        monitor.start()
        return monitor
    }

    private var threshold: TimeInterval {
        TimeInterval(MicCameraMonitor.defaultIdleAlertMinutes * 60)
    }

    @Test func reflectsReaderState() {
        let monitor = makeMonitor()
        #expect(!monitor.hasCompactIndicator)

        reader.current = CaptureSnapshot(activeMicrophones: [], activeCameras: ["FaceTime HD Camera"])
        reader.onChange?()

        #expect(monitor.isCameraInUse)
        #expect(!monitor.isMicrophoneInUse)
        #expect(monitor.hasCompactIndicator)
    }

    @Test func warnsOnceWhenMicStaysOn() {
        let monitor = makeMonitor()
        reader.current = micOn
        monitor.refresh()

        clock.advance(by: threshold - 1)
        monitor.evaluateIdleAlert()
        #expect(alerts.current == nil)

        clock.advance(by: 1)
        monitor.evaluateIdleAlert()
        #expect(alerts.current?.title == "Mikrofon hâlâ kullanımda")
        #expect(alerts.current?.style == .info)

        alerts.dismissAll()
        clock.advance(by: threshold)
        monitor.evaluateIdleAlert()
        #expect(alerts.current == nil)
    }

    @Test func newMicSessionCanWarnAgain() {
        let monitor = makeMonitor()
        reader.current = micOn
        monitor.refresh()
        clock.advance(by: threshold)
        monitor.evaluateIdleAlert()
        alerts.dismissAll()

        reader.current = .idle
        monitor.refresh()
        reader.current = micOn
        monitor.refresh()
        clock.advance(by: threshold)
        monitor.evaluateIdleAlert()

        #expect(alerts.current?.title == "Mikrofon hâlâ kullanımda")
    }

    @Test func noWarningWhileMeetingAppRuns() {
        let monitor = makeMonitor(apps: [SystemRunningApp(bundleIdentifier: "us.zoom.xos", name: "zoom.us")])
        reader.current = micOn
        monitor.refresh()

        clock.advance(by: threshold * 2)
        monitor.evaluateIdleAlert()

        #expect(alerts.current == nil)
        #expect(monitor.runningMeetingApps.map(\.name) == ["Zoom"])
    }

    @Test func disabledMonitorKeepsRunningForMeetings() {
        let monitor = makeMonitor()
        monitor.keepsMonitoringForMeetings = true

        monitor.isEnabled = false
        #expect(monitor.isMonitoring)
        #expect(!monitor.hasCompactIndicator)

        monitor.keepsMonitoringForMeetings = false
        #expect(!monitor.isMonitoring)
        #expect(reader.onChange == nil)
    }
}
