import Foundation
import Testing
@testable import NotchHub

@MainActor
final class TestAudioProcessReader: AudioInputProcessReading {
    var current: [AudioInputProcess] = []
    private(set) var onChange: (@MainActor () -> Void)?
    private(set) var readCount = 0

    func inputProcesses() -> [AudioInputProcess] {
        readCount += 1
        return current
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }
}

struct PrivacyAppMapperTests {
    private let zoom = SystemRunningApp(bundleIdentifier: "us.zoom.xos", name: "zoom.us")
    private let chrome = SystemRunningApp(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    private let safari = SystemRunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari")

    private func process(_ bundleID: String?, name: String? = nil, pid: Int32 = 100) -> AudioInputProcess {
        AudioInputProcess(pid: pid, bundleID: bundleID, name: name)
    }

    @Test func mapsExactBundleIDToRunningApp() {
        let apps = PrivacyAppMapper.apps(from: [process("us.zoom.xos")], runningApps: [zoom], ownBundleID: nil)
        #expect(apps == [CaptureApp(bundleID: "us.zoom.xos", name: "zoom.us")])
    }

    @Test func foldsHelperIntoParentAppAndDeduplicates() {
        let processes = [
            process("com.google.Chrome.helper", name: "Google Chrome Helper", pid: 1),
            process("com.google.Chrome.helper.renderer", pid: 2),
            process("com.google.Chrome", pid: 3),
        ]
        let apps = PrivacyAppMapper.apps(from: processes, runningApps: [chrome, zoom], ownBundleID: nil)
        #expect(apps == [CaptureApp(bundleID: "com.google.Chrome", name: "Google Chrome")])
    }

    @Test func prefixMatchRequiresDotBoundary() {
        let lookalike = SystemRunningApp(bundleIdentifier: "com.google.Chro", name: "Fake")
        let apps = PrivacyAppMapper.apps(
            from: [process("com.google.Chrome.helper", name: "Helper")], runningApps: [lookalike], ownBundleID: nil
        )
        #expect(apps == [CaptureApp(bundleID: "com.google.Chrome.helper", name: "Helper")])
    }

    @Test func attributesWebKitToSafari() {
        let apps = PrivacyAppMapper.apps(
            from: [process("com.apple.WebKit.GPU")], runningApps: [safari], ownBundleID: nil
        )
        #expect(apps.map(\.name) == ["Safari"])
    }

    @Test func fallsBackToProcessNameAndSkipsUnnamed() {
        let processes = [process("com.example.recorder", name: " Recorder "), process("com.apple.daemon"), process(nil)]
        let apps = PrivacyAppMapper.apps(from: processes, runningApps: [], ownBundleID: nil)
        #expect(apps == [CaptureApp(bundleID: "com.example.recorder", name: "Recorder")])
    }

    @Test func excludesOwnProcess() {
        let own = SystemRunningApp(bundleIdentifier: "app.self", name: "Self")
        let apps = PrivacyAppMapper.apps(
            from: [process("app.self"), process("us.zoom.xos")], runningApps: [own, zoom], ownBundleID: "app.self"
        )
        #expect(apps.map(\.name) == ["zoom.us"])
    }
}

struct PrivacyIndicatorStateTests {
    private let zoom = CaptureApp(bundleID: "us.zoom.xos", name: "Zoom")
    private let chrome = CaptureApp(bundleID: "com.google.Chrome", name: "Chrome")

    @Test func cameraWinsOverMicrophone() {
        #expect(PrivacyIndicatorKind.current(isMicrophoneInUse: true, isCameraInUse: true) == .camera)
        #expect(PrivacyIndicatorKind.current(isMicrophoneInUse: false, isCameraInUse: true) == .camera)
        #expect(PrivacyIndicatorKind.current(isMicrophoneInUse: true, isCameraInUse: false) == .microphone)
        #expect(PrivacyIndicatorKind.current(isMicrophoneInUse: false, isCameraInUse: false) == nil)
    }

    @Test func microphoneText() {
        #expect(PrivacyIndicatorText.microphone(apps: []) == nil)
        #expect(PrivacyIndicatorText.microphone(apps: [zoom]) == "Zoom mikrofonu kullanıyor")
        #expect(PrivacyIndicatorText.microphone(apps: [zoom, chrome]) == "Zoom ve 1 uygulama daha mikrofonu kullanıyor")
    }

    @Test func helpCombinesMicAndGenericCamera() {
        let both = PrivacyIndicatorText.help(isMicrophoneInUse: true, isCameraInUse: true, microphoneApps: [zoom])
        #expect(both == "Zoom mikrofonu kullanıyor\nKamera kullanımda")
        let unknownMic = PrivacyIndicatorText.help(isMicrophoneInUse: true, isCameraInUse: false, microphoneApps: [])
        #expect(unknownMic == "Mikrofon kullanımda")
    }
}

@MainActor
struct MicCameraPrivacyIndicatorTests {
    private let reader = SystemTestCaptureReader()
    private let processReader = TestAudioProcessReader()
    private let defaults = SystemTestSupport.makeDefaults()
    private let micOn = CaptureSnapshot(activeMicrophones: ["MacBook Pro Microphone"], activeCameras: [])

    private func makeMonitor() -> MicCameraMonitor {
        let runningApps = SystemRunningApps(source: {
            [SystemRunningApp(bundleIdentifier: "us.zoom.xos", name: "Zoom")]
        })
        runningApps.reload()
        let monitor = MicCameraMonitor(
            alerts: SystemTestSupport.makeAlertCenter(), runningApps: runningApps, reader: reader,
            processReader: processReader, clock: SystemTestClock(), defaults: defaults, ownBundleID: nil
        )
        monitor.start()
        return monitor
    }

    @Test func identifiesMicrophoneAppAndClearsWhenReleased() {
        let monitor = makeMonitor()
        processReader.current = [AudioInputProcess(pid: 42, bundleID: "us.zoom.xos", name: "zoom.us")]
        reader.current = micOn
        processReader.onChange?()

        #expect(monitor.microphoneApps.map(\.name) == ["Zoom"])
        #expect(monitor.microphoneUsageText == "Zoom mikrofonu kullanıyor")
        #expect(monitor.privacyIndicatorKind == .microphone)
        #expect(monitor.hasCompactIndicator)

        reader.current = .idle
        monitor.refresh()
        #expect(monitor.microphoneApps.isEmpty)
        #expect(monitor.microphoneUsageText == nil)
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func skipsProcessReadWhileMicrophoneIsOff() {
        let monitor = makeMonitor()
        reader.current = CaptureSnapshot(activeMicrophones: [], activeCameras: ["FaceTime HD Camera"])
        monitor.refresh()

        #expect(processReader.readCount == 0)
        #expect(monitor.privacyIndicatorKind == .camera)
        #expect(monitor.privacyIndicatorHelp == "Kamera kullanımda")
    }

    @Test func settingIsOnByDefaultPersistsAndHidesDot() {
        let monitor = makeMonitor()
        #expect(monitor.privacyIndicatorEnabled)
        reader.current = micOn
        monitor.refresh()
        #expect(monitor.hasCompactIndicator)

        monitor.privacyIndicatorEnabled = false
        #expect(!monitor.hasCompactIndicator)
        #expect(monitor.isMicrophoneInUse)
        #expect(defaults.bool(forKey: MicCameraMonitor.Keys.privacyIndicatorEnabled) == false)
    }

    @Test func stopsObservingProcessesWhenDisabled() {
        let monitor = makeMonitor()
        #expect(processReader.onChange != nil)
        monitor.isEnabled = false
        #expect(processReader.onChange == nil)
    }
}
