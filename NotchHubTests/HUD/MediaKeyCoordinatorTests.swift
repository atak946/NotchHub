import Foundation
import Testing
@testable import NotchHub

@MainActor
private final class FakeTap: MediaKeyTapping {
    var canInstall = true
    private(set) var handler: MediaKeyTapHandler?
    private(set) var installCount = 0

    var isInstalled: Bool { handler != nil }

    func install(handler: @escaping MediaKeyTapHandler) -> Bool {
        guard canInstall else { return false }
        installCount += 1
        self.handler = handler
        return true
    }

    func remove() { handler = nil }

    func send(_ key: SystemDefinedKeyEvent.Key, isKeyDown: Bool = true, isFine: Bool = false) -> Bool {
        handler?(SystemDefinedKeyEvent(keyCode: key.rawValue, isKeyDown: isKeyDown, isRepeat: false), isFine) ?? false
    }
}

@MainActor
private final class FakeController: MediaKeyControlling {
    var capabilities = MediaKeyCapabilities(canSetVolume: true, canSetMute: true, canSetBrightness: true)
    var reading: HUDReading? = HUDReading(kind: .volume, level: 0.5625)
    private(set) var performed: [MediaKeyCommand] = []

    func capabilities(for kind: HUDKind) -> MediaKeyCapabilities { capabilities }

    func perform(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        performed.append(command)
        completion(reading)
    }
}

@MainActor
private final class TrustFlag {
    var value = true
}

@MainActor
struct MediaKeyCoordinatorTests {
    private static let neverSleep: NotchHUDCenter.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }

    private let tap = FakeTap()
    private let controller = FakeController()
    private let trust = TrustFlag()

    private func makeCoordinator() -> MediaKeyCoordinator {
        let trust = self.trust
        return MediaKeyCoordinator(tap: tap, controller: controller, isTrusted: { trust.value }, sleep: Self.neverSleep)
    }

    @Test func installsWhenWantedAndTrusted() {
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)

        #expect(tap.isInstalled)
    }

    @Test func doesNotInstallWithoutTrustThenInstallsOnceGranted() {
        trust.value = false
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)
        #expect(!tap.isInstalled)

        trust.value = true
        coordinator.recheck()

        #expect(tap.isInstalled)
        #expect(tap.installCount == 1)
    }

    @Test func removesWhenNoLongerWanted() {
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)
        coordinator.setWanted(false)

        #expect(!tap.isInstalled)
    }

    @Test func doesNotReinstallAnInstalledTap() {
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)
        coordinator.recheck()

        #expect(tap.installCount == 1)
    }

    @Test func retriesWhenTapCreationFails() {
        tap.canInstall = false
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)
        #expect(!tap.isInstalled)

        tap.canInstall = true
        coordinator.recheck()

        #expect(tap.isInstalled)
    }

    @Test func consumedKeyIsPerformedAndReported() {
        let coordinator = makeCoordinator()
        var readings: [HUDReading] = []
        coordinator.onReading = { readings.append($0) }
        coordinator.setWanted(true)

        #expect(tap.send(.soundUp, isFine: true))
        #expect(controller.performed == [.volumeUp(fine: true)])
        #expect(readings == [HUDReading(kind: .volume, level: 0.5625)])
    }

    @Test func keyUpIsConsumedButNotPerformed() {
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)

        #expect(tap.send(.soundDown, isKeyDown: false))
        #expect(controller.performed.isEmpty)
    }

    @Test func passesKeysTheHardwareCannotHandle() {
        controller.capabilities = MediaKeyCapabilities()
        let coordinator = makeCoordinator()
        coordinator.setWanted(true)

        #expect(!tap.send(.soundUp))
        #expect(!tap.send(.brightnessUp))
        #expect(!tap.send(.illuminationUp))
        #expect(controller.performed.isEmpty)
    }
}
