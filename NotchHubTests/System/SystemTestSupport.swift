import Foundation
import Observation
import Synchronization
@testable import NotchHub

/// Manually advanced clock; `sleep` never returns before cancellation, so tests call `settle()` explicitly.
final class SystemTestClock: SystemClock {
    private let storage: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        storage = Mutex(start)
    }

    var now: Date { storage.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

enum SystemTestSupport {
    /// Never returns, so alerts never auto-dismiss during tests.
    static let neverSleep: NotchAlertCenter.Sleeper = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    @MainActor
    static func makeAlertCenter() -> NotchAlertCenter {
        NotchAlertCenter(sleep: neverSleep)
    }

    static func makeDefaults() -> UserDefaults {
        let (suiteName, defaults) = TestDefaults.makeSuite("System.\(UUID().uuidString)")
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
final class SystemTestCaptureReader: CaptureDeviceReading {
    var current: CaptureSnapshot = .idle
    private(set) var onChange: (@MainActor () -> Void)?

    func snapshot() -> CaptureSnapshot { current }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }
}

@MainActor
final class SystemTestVPNReader: VPNSystemReading {
    var current = VPNSample(isNetworkReachable: true, primaryInterface: "en0", tunnelInterfaces: [])
    private(set) var isObserving = false

    func sample() -> VPNSample { current }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        isObserving = true
    }

    func stopObserving() {
        isObserving = false
    }

    func setConnected(_ connected: Bool) {
        current = VPNSample(
            isNetworkReachable: true,
            primaryInterface: "en0",
            tunnelInterfaces: connected ? ["utun4"] : []
        )
    }
}

@MainActor
final class SystemTestNetworkReader: NetworkPathReading {
    private(set) var onUpdate: (@MainActor (NetworkSnapshot) -> Void)?

    func startObserving(_ onUpdate: @escaping @MainActor (NetworkSnapshot) -> Void) {
        self.onUpdate = onUpdate
    }

    func stopObserving() {
        onUpdate = nil
    }
}

@MainActor
final class SystemTestPressureReader: SystemPressureReading {
    var memory: MemoryPressureLevel = .normal
    var thermal: SystemThermalLevel = .nominal
    var freeBytes: Int64? = 500 * DiskSpacePolicy.bytesPerGigabyte

    func currentMemoryPressure() -> MemoryPressureLevel { memory }
    func currentThermalLevel() -> SystemThermalLevel { thermal }
    func freeDiskBytes() -> Int64? { freeBytes }

    func startObserving(
        memory: @escaping @MainActor (MemoryPressureLevel) -> Void,
        thermal: @escaping @MainActor (SystemThermalLevel) -> Void
    ) {}

    func stopObserving() {}
}

@MainActor
@Observable
final class SystemTestMeetingInputs: MeetingModeInputs {
    var isMicrophoneInUse = false
    var runningMeetingApps: [MeetingApp] = []
    var calendarEvents: [CalendarEvent] = []
}

@MainActor
final class SystemTestMedia: MeetingMediaControlling {
    var isMediaPlaying: Bool
    private(set) var playPauseCount = 0

    init(isPlaying: Bool) {
        isMediaPlaying = isPlaying
    }

    func playPause() {
        playPauseCount += 1
        isMediaPlaying.toggle()
    }
}

extension MeetingApp {
    static var zoom: MeetingApp {
        MeetingApp(bundleIdentifier: "us.zoom.xos", name: "Zoom")
    }
}
