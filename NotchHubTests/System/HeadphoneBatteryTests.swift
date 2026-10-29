import Foundation
import Synchronization
import Testing
@testable import NotchHub

struct HeadphoneBatteryParserTests {
    private static let airPodsJSON = """
    {
      "SPBluetoothDataType": [{
        "controller_properties": { "controller_state": "attrib_on" },
        "device_connected": [
          { "Magic Mouse": { "device_minorType": "Mouse" } },
          { "AirPods Pro": {
              "device_batteryLevelCase": "40%",
              "device_batteryLevelLeft": "80%",
              "device_batteryLevelRight": "%75",
              "device_minorType": "Headphones"
          } }
        ],
        "device_not_connected": [
          { "Studio Headset": { "device_batteryLevelMain": "10%" } }
        ]
      }]
    }
    """

    private static let headsetJSON = """
    {"SPBluetoothDataType":[{"device_connected":[{"Studio Headset":{"device_batteryLevelMain":"60 %"}}]}]}
    """

    @Test func parsesAirPodsLeftRightCase() {
        let levels = HeadphoneBatteryParser.parseSystemProfiler(Data(Self.airPodsJSON.utf8), deviceName: "AirPods Pro")
        #expect(levels == HeadphoneBatteryLevels(left: 80, right: 75, caseLevel: 40, main: nil))
    }

    @Test func parsesSingleBatteryHeadset() {
        let levels = HeadphoneBatteryParser.parseSystemProfiler(Data(Self.headsetJSON.utf8), deviceName: "Studio Headset")
        #expect(levels == HeadphoneBatteryLevels(left: nil, right: nil, caseLevel: nil, main: 60))
    }

    @Test func ignoresDisconnectedAndUnknownDevices() {
        let data = Data(Self.airPodsJSON.utf8)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(data, deviceName: "Studio Headset") == nil)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(data, deviceName: "Magic Mouse") == nil)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(data, deviceName: "Other") == nil)
    }

    @Test func matchesNamesLoosely() {
        let data = Data(Self.airPodsJSON.utf8)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(data, deviceName: "airpods  pro") != nil)
        #expect(HeadphoneBatteryParser.namesMatch("Kim\u{2019}s AirPods", "kim's airpods"))
    }

    @Test func rejectsMalformedInput() {
        #expect(HeadphoneBatteryParser.parseSystemProfiler(Data("not json".utf8), deviceName: "AirPods Pro") == nil)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(Data("{}".utf8), deviceName: "AirPods Pro") == nil)
        #expect(HeadphoneBatteryParser.parseSystemProfiler(Data("[]".utf8), deviceName: "AirPods Pro") == nil)
    }

    @Test func parsesPercentFormats() {
        #expect(HeadphoneBatteryParser.percent(from: "80%") == 80)
        #expect(HeadphoneBatteryParser.percent(from: "%5") == 5)
        #expect(HeadphoneBatteryParser.percent(from: 100) == 100)
        #expect(HeadphoneBatteryParser.percent(from: "250%") == nil)
        #expect(HeadphoneBatteryParser.percent(from: "n/a") == nil)
        #expect(HeadphoneBatteryParser.percent(from: nil) == nil)
    }
}

struct HeadphoneBatteryFormatterTests {
    @Test func formatsAirPodsSubtitle() {
        let levels = HeadphoneBatteryLevels(left: 80, right: 75, caseLevel: 40, main: nil)
        #expect(HeadphoneBatteryFormatter.subtitle(levels) == "Sol %80 · Sağ %75 · Kutu %40")
        #expect(HeadphoneBatteryFormatter.lowest(levels) == 75)
    }

    @Test func formatsSingleLevel() {
        let levels = HeadphoneBatteryLevels(left: nil, right: nil, caseLevel: nil, main: 60)
        #expect(HeadphoneBatteryFormatter.subtitle(levels) == "Pil %60")
        #expect(HeadphoneBatteryFormatter.subtitle(HeadphoneBatteryLevels(left: nil, right: nil, caseLevel: nil, main: nil)) == nil)
    }

    @Test func picksGlyphs() {
        #expect(HeadphoneBatteryFormatter.batteryGlyph(for: 5) == "battery.0percent")
        #expect(HeadphoneBatteryFormatter.batteryGlyph(for: 50) == "battery.50percent")
        #expect(HeadphoneBatteryFormatter.batteryGlyph(for: 100) == "battery.100percent")
        #expect(HeadphoneBatteryFormatter.deviceGlyph(for: "AirPods Pro") == "airpodspro")
    }
}

struct HeadphoneConnectPolicyTests {
    private let pods = BluetoothAudioOutput(id: 7, name: "AirPods Pro")
    private let speaker = BluetoothAudioOutput(id: 9, name: "Desk Speaker")

    @Test func newDeviceTriggers() {
        let current = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 1)
        #expect(HeadphoneConnectPolicy.connectedDevice(previous: .empty, current: current) == pods)
    }

    @Test func defaultSwitchToBluetoothTriggers() {
        let previous = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 1)
        let current = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7)
        #expect(HeadphoneConnectPolicy.connectedDevice(previous: previous, current: current) == pods)
    }

    @Test func prefersNewDefaultAmongAdded() {
        let current = BluetoothAudioSnapshot(outputs: [speaker, pods], defaultOutputID: 7)
        #expect(HeadphoneConnectPolicy.connectedDevice(previous: .empty, current: current) == pods)
    }

    @Test func disconnectAndBuiltInSwitchDoNotTrigger() {
        let connected = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7)
        #expect(HeadphoneConnectPolicy.connectedDevice(previous: connected, current: .empty) == nil)
        let builtIn = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 1)
        #expect(HeadphoneConnectPolicy.connectedDevice(previous: connected, current: builtIn) == nil)
    }

    @Test func duplicateWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let last = ["AirPods Pro": now.addingTimeInterval(-5)]
        #expect(HeadphoneConnectPolicy.isDuplicate(name: "AirPods Pro", lastTriggered: last, now: now, window: 15))
        #expect(!HeadphoneConnectPolicy.isDuplicate(name: "AirPods Pro", lastTriggered: last, now: now.addingTimeInterval(20), window: 15))
        #expect(!HeadphoneConnectPolicy.isDuplicate(name: "Other", lastTriggered: last, now: now, window: 15))
    }
}

/// Clock whose sleep returns at once, so the settle delay does not block tests.
private final class ImmediateClock: SystemClock {
    private let storage = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))

    var now: Date { storage.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    func sleep(for duration: Duration) async throws {}
}

@MainActor
private final class FakeBluetoothWatcher: BluetoothAudioWatching {
    var current: BluetoothAudioSnapshot = .empty
    private(set) var onChange: (@MainActor () -> Void)?

    func snapshot() -> BluetoothAudioSnapshot { current }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }

    func set(_ snapshot: BluetoothAudioSnapshot) {
        current = snapshot
        onChange?()
    }
}

private final class FakeBatteryReader: HeadphoneBatteryReading {
    private let state = Mutex<(levels: HeadphoneBatteryLevels?, calls: Int)>((nil, 0))

    init(levels: HeadphoneBatteryLevels?) {
        state.withLock { $0.levels = levels }
    }

    var calls: Int { state.withLock { $0.calls } }

    func readLevels(deviceName: String, timeout: Duration) async -> HeadphoneBatteryLevels? {
        state.withLock { value in
            value.calls += 1
            return value.levels
        }
    }
}

@MainActor
struct HeadphoneBatteryMonitorTests {
    private let pods = BluetoothAudioOutput(id: 7, name: "AirPods Pro")
    private let levels = HeadphoneBatteryLevels(left: 80, right: 75, caseLevel: 40, main: nil)
    private let watcher = FakeBluetoothWatcher()
    private let clock = ImmediateClock()
    private let alerts = SystemTestSupport.makeAlertCenter()

    private func makeMonitor(reader: FakeBatteryReader, defaults: UserDefaults = SystemTestSupport.makeDefaults()) -> HeadphoneBatteryMonitor {
        HeadphoneBatteryMonitor(alerts: alerts, watcher: watcher, reader: reader, clock: clock, defaults: defaults)
    }

    @Test func connectPostsBatteryAlertOnce() async {
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader)
        monitor.start()

        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 1))
        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        await monitor.pendingRead?.value

        #expect(reader.calls == 1)
        #expect(alerts.current?.title == "AirPods Pro")
        #expect(alerts.current?.subtitle == "Sol %80 · Sağ %75 · Kutu %40")
        #expect(alerts.current?.autoDismissAfter == HeadphoneBatteryMonitor.alertDuration)
        #expect(monitor.lastReport?.levels == levels)
    }

    @Test func alreadyConnectedAtLaunchIsSilent() async {
        watcher.current = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7)
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader)
        monitor.start()
        await monitor.pendingRead?.value

        #expect(reader.calls == 0)
        #expect(alerts.current == nil)
    }

    @Test func disconnectShowsNothing() async {
        watcher.current = BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7)
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader)
        monitor.start()

        watcher.set(.empty)
        await monitor.pendingRead?.value
        #expect(reader.calls == 0)
        #expect(alerts.current == nil)
    }

    @Test func missingLevelsShowNothing() async {
        let reader = FakeBatteryReader(levels: nil)
        let monitor = makeMonitor(reader: reader)
        monitor.start()

        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        await monitor.pendingRead?.value
        #expect(reader.calls == 1)
        #expect(alerts.current == nil)
        #expect(monitor.lastReport == nil)
    }

    @Test func reconnectAfterWindowReadsAgain() async {
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader)
        monitor.start()

        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        await monitor.pendingRead?.value
        watcher.set(.empty)
        clock.advance(by: HeadphoneBatteryMonitor.duplicateWindow + 1)
        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        await monitor.pendingRead?.value
        #expect(reader.calls == 2)
    }

    @Test func disabledDoesNotObserveAndDefaultsOn() async {
        let defaults = SystemTestSupport.makeDefaults()
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader, defaults: defaults)
        #expect(monitor.isEnabled)
        monitor.isEnabled = false
        monitor.start()

        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        #expect(!monitor.isMonitoring)
        #expect(reader.calls == 0)
        #expect(!makeMonitor(reader: reader, defaults: defaults).isEnabled)
    }

    @Test func alertGateSuppressesAlertButKeepsReport() async {
        let reader = FakeBatteryReader(levels: levels)
        let monitor = makeMonitor(reader: reader)
        monitor.canPostAlert = { false }
        monitor.start()

        watcher.set(BluetoothAudioSnapshot(outputs: [pods], defaultOutputID: 7))
        await monitor.pendingRead?.value
        #expect(alerts.current == nil)
        #expect(monitor.lastReport?.deviceName == "AirPods Pro")
    }
}
