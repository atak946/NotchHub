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
}
