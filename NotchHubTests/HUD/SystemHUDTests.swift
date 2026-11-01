import Foundation
import Testing
@testable import NotchHub

@MainActor
private final class FakeVolumeSource: HUDVolumeSource {
    var onChange: (@MainActor (HUDReading) -> Void)?
    var reading: HUDReading? = HUDReading(kind: .volume, level: 0.5)
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
    func currentReading() -> HUDReading? { reading }

    func emit(_ reading: HUDReading) {
        self.reading = reading
        onChange?(reading)
    }
}

@MainActor
private final class FakeKeySource: HUDKeySource {
    var onKey: (@MainActor (SystemDefinedKeyEvent) -> Void)?
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }

    func press(_ key: SystemDefinedKeyEvent.Key) {
        onKey?(SystemDefinedKeyEvent(keyCode: key.rawValue, isKeyDown: true, isRepeat: false))
    }
}

@MainActor
private struct FakeBrightness: HUDBrightnessReading {
    let value: Double?
    func brightness() -> Double? { value }
}

@MainActor
private final class RecordingTap: MediaKeyTapping {
    private(set) var handler: MediaKeyTapHandler?
    var isInstalled: Bool { handler != nil }

    func install(handler: @escaping MediaKeyTapHandler) -> Bool {
        self.handler = handler
        return true
    }

    func remove() { handler = nil }
}

@MainActor
private final class FixedController: MediaKeyControlling {
    let reading: HUDReading

    init(reading: HUDReading) { self.reading = reading }

    func capabilities(for kind: HUDKind) -> MediaKeyCapabilities {
        MediaKeyCapabilities(canSetVolume: true, canSetMute: true, canSetBrightness: true)
    }

    func perform(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        completion(reading)
    }
}

@MainActor
private final class RecordingLevels: HUDLevelSetting {
    var canSet = true
    /// The level the hardware reports back; `nil` echoes the requested one.
    var readBack: Double?
    private(set) var written: [Double] = []

    func canSetLevel(for kind: HUDKind) -> Bool { canSet }

    func setLevel(_ level: Double, for kind: HUDKind, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        written.append(level)
        completion(HUDReading(kind: kind, level: readBack ?? level))
    }
}

@MainActor
struct SystemHUDTests {
    private static let neverSleep: NotchHUDCenter.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
    private static let noSleep: NotchHUDCenter.Sleeper = { _ in }

    private let volume = FakeVolumeSource()
    private let keys = FakeKeySource()
    private let defaults: UserDefaults

    init() {
        defaults = TestDefaults.suite(named: "SystemHUDTests.\(UUID().uuidString)")
    }

    private func makeHUD(brightness: Double? = 0.7) -> SystemHUD {
        SystemHUD(
            defaults: defaults,
            center: NotchHUDCenter(sleep: Self.neverSleep),
            volume: volume,
            keys: keys,
            brightness: FakeBrightness(value: brightness),
            sleep: Self.noSleep
        )
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func enabledByDefaultAndStartsSources() {
        let hud = makeHUD()
        hud.start()

        #expect(hud.isEnabled)
        #expect(volume.isRunning)
        #expect(keys.isRunning)
    }

    @Test func volumeChangeShowsHUDButBaselineDoesNot() {
        let hud = makeHUD()
        hud.start()
        #expect(hud.center.current == nil)

        volume.emit(HUDReading(kind: .volume, level: 0.75))

        #expect(hud.center.current == HUDReading(kind: .volume, level: 0.75))
    }

    @Test func disablingStopsSourcesAndHidesHUD() {
        let hud = makeHUD()
        hud.start()
        volume.emit(HUDReading(kind: .volume, level: 0.9))

        hud.isEnabled = false

        #expect(hud.center.current == nil)
        #expect(!volume.isRunning)
        #expect(!keys.isRunning)
        #expect(defaults.object(forKey: SystemHUD.enabledKey) as? Bool == false)
    }

    @Test func blockedWhileAnAlertIsShowing() {
        let hud = makeHUD()
        hud.isBlocked = { true }
        hud.start()

        volume.emit(HUDReading(kind: .volume, level: 0.2))

        #expect(hud.center.current == nil)
    }

    @Test func brightnessKeyReadsTheDisplay() async {
        let hud = makeHUD(brightness: 0.4)
        hud.start()

        keys.press(.brightnessUp)
        await settle()

        #expect(hud.center.current == HUDReading(kind: .brightness, level: 0.4))
    }

    @Test func brightnessWithoutDisplayServicesShowsNoLevel() async {
        let hud = makeHUD(brightness: nil)
        hud.start()

        keys.press(.brightnessDown)
        await settle()

        #expect(hud.center.current == HUDReading(kind: .brightness, level: nil))
    }

    @Test func centerAutoHides() async {
        let center = NotchHUDCenter(sleep: Self.noSleep)

        center.show(HUDReading(kind: .volume, level: 0.3))
        #expect(center.current != nil)
        await settle()

        #expect(center.current == nil)
    }

    // MARK: - Media key interception

    private func makeInterceptingHUD(tap: RecordingTap, reading: HUDReading) -> SystemHUD {
        let coordinator = MediaKeyCoordinator(
            tap: tap, controller: FixedController(reading: reading), isTrusted: { true }, sleep: Self.neverSleep
        )
        return SystemHUD(
            defaults: defaults,
            center: NotchHUDCenter(sleep: Self.neverSleep),
            volume: volume,
            keys: keys,
            brightness: FakeBrightness(value: 0.5),
            sleep: Self.noSleep,
            mediaKeys: coordinator
        )
    }

    @Test func interceptsByDefaultOnlyWhileRunning() {
        let tap = RecordingTap()
        let hud = makeInterceptingHUD(tap: tap, reading: HUDReading(kind: .volume, level: 0.5))
        #expect(hud.hidesSystemHUD)
        #expect(!tap.isInstalled)

        hud.start()
        #expect(tap.isInstalled)

        hud.stop()
        #expect(!tap.isInstalled)
    }

    @Test func turningOffTheNotchHUDOrTheSettingRemovesTheTap() {
        let tap = RecordingTap()
        let hud = makeInterceptingHUD(tap: tap, reading: HUDReading(kind: .volume, level: 0.5))
        hud.start()

        hud.hidesSystemHUD = false
        #expect(!tap.isInstalled)
        #expect(defaults.object(forKey: SystemHUD.hidesSystemHUDKey) as? Bool == false)

        hud.hidesSystemHUD = true
        #expect(tap.isInstalled)

        hud.isEnabled = false
        #expect(!tap.isInstalled)
    }

    @Test func interceptedKeyShowsTheHUDEvenWithoutAChange() throws {
        let tap = RecordingTap()
        let reading = HUDReading(kind: .volume, level: 1)
        volume.reading = reading
        let hud = makeInterceptingHUD(tap: tap, reading: reading)
        hud.start()
        let handler = try #require(tap.handler)

        let consumed = handler(SystemDefinedKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false), false)

        #expect(consumed)
        #expect(hud.center.current == reading)
    }

    // MARK: - Volume step setting

    @Test func volumeStepDefaultsToTheSystemGridAndPersists() {
        let hud = makeHUD()
        #expect(hud.volumeStep == .system)

        hud.volumeStep = .percent5

        #expect(defaults.string(forKey: SystemHUD.volumeStepKey) == "percent5")
        #expect(makeHUD().volumeStep == .percent5)
    }

    @Test func unknownStoredStepFallsBackToTheSystemGrid() {
        defaults.set("percent7", forKey: SystemHUD.volumeStepKey)
        #expect(makeHUD().volumeStep == .system)
    }

    // MARK: - Output device

    @Test func volumeReadingsCarryTheHeadphones() {
        let airPods = HUDOutputDevice(name: "AirPods", systemImage: "airpods", batteryPercent: 70)
        let hud = makeHUD()
        hud.outputDevice = { airPods }
        hud.start()

        volume.emit(HUDReading(kind: .volume, level: 0.25))

        #expect(hud.center.current == HUDReading(kind: .volume, level: 0.25, output: airPods))
    }

    @Test func brightnessReadingsNeverCarryAnOutput() async {
        let hud = makeHUD(brightness: 0.4)
        hud.outputDevice = { HUDOutputDevice(name: "AirPods", systemImage: "airpods", batteryPercent: nil) }
        hud.start()

        keys.press(.brightnessUp)
        await settle()

        #expect(hud.center.current?.output == nil)
    }

    // MARK: - Scroll and drag

    private func makeAdjustableHUD(levels: RecordingLevels) -> SystemHUD {
        SystemHUD(
            defaults: defaults,
            center: NotchHUDCenter(sleep: Self.neverSleep),
            volume: volume,
            keys: keys,
            brightness: FakeBrightness(value: 0.5),
            sleep: Self.noSleep,
            levels: levels
        )
    }

    @Test func draggingWritesTheLevelAndHoldsTheHUD() {
        let levels = RecordingLevels()
        let hud = makeAdjustableHUD(levels: levels)
        hud.start()
        volume.emit(HUDReading(kind: .volume, level: 0.6))
        #expect(hud.isAdjustableOnScreen)

        hud.setDragging(true)
        hud.adjust(to: 0.8)

        #expect(levels.written == [0.8])
        #expect(hud.center.current == HUDReading(kind: .volume, level: 0.8))
        #expect(hud.center.isHeld)

        hud.setDragging(false)
        #expect(!hud.center.isHeld)
    }

    @Test func consecutiveScrollsBuildOnTheLastWrite() {
        let levels = RecordingLevels()
        // The hardware lags behind: every read-back still says 0.25.
        levels.readBack = 0.25
        let hud = makeAdjustableHUD(levels: levels)
        hud.start()
        volume.emit(HUDReading(kind: .volume, level: 0.25))

        hud.adjust(byScroll: 1, isPrecise: false, isInverted: false)
        hud.adjust(byScroll: 1, isPrecise: false, isInverted: false)

        #expect(levels.written == [0.25 + 1.0 / 16, 0.25 + 2.0 / 16])
    }

    @Test func scrollingUpWhileMutedUnmutesTheBar() {
        let levels = RecordingLevels()
        let hud = makeAdjustableHUD(levels: levels)
        hud.start()
        volume.emit(HUDReading(kind: .volume, level: 0.5, isMuted: true))

        hud.adjust(to: 0.6)

        #expect(hud.center.current?.isMuted == false)
    }

    @Test func nothingIsWrittenWhenTheSettingIsOffOrTheOutputCannotBeSet() {
        let levels = RecordingLevels()
        let hud = makeAdjustableHUD(levels: levels)
        hud.start()
        volume.emit(HUDReading(kind: .volume, level: 0.6))

        hud.isInteractive = false
        hud.adjust(to: 0.9)
        #expect(!hud.isAdjustableOnScreen)
        #expect(defaults.object(forKey: SystemHUD.interactiveKey) as? Bool == false)

        hud.isInteractive = true
        levels.canSet = false
        hud.adjust(byScroll: 3, isPrecise: false, isInverted: false)

        #expect(levels.written.isEmpty)
        #expect(hud.center.current == HUDReading(kind: .volume, level: 0.6))
    }

    @Test func keyboardBacklightIsNeverAdjustable() async {
        let levels = RecordingLevels()
        let hud = makeAdjustableHUD(levels: levels)
        hud.start()

        keys.press(.illuminationUp)
        await settle()
        hud.adjust(to: 0.4)

        #expect(!hud.isAdjustableOnScreen)
        #expect(levels.written.isEmpty)
    }

    @Test func heldCenterDoesNotAutoHideUntilReleased() async {
        let center = NotchHUDCenter(sleep: Self.noSleep)
        center.show(HUDReading(kind: .volume, level: 0.3))

        center.setHeld(true)
        await settle()
        #expect(center.current != nil)

        center.setHeld(false)
        await settle()
        #expect(center.current == nil)
    }

    @Test func holdIsIgnoredWithoutAReading() {
        let center = NotchHUDCenter(sleep: Self.noSleep)
        center.setHeld(true)
        #expect(!center.isHeld)
    }

    @Test func everyShowIsCountedEvenWithoutAChange() {
        let center = NotchHUDCenter(sleep: Self.neverSleep)
        let reading = HUDReading(kind: .volume, level: 1)

        center.show(reading)
        center.show(reading)

        #expect(center.showCount == 2)
    }
}
