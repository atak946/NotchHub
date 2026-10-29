import Foundation
import Testing
@testable import NotchHub

struct MicMutePolicyTests {
    private let muteDevice = FakeMicHardwareStates.muteCapable
    private let volumeOnly = FakeMicHardwareStates.volumeOnly

    @Test func prefersMuteProperty() throws {
        let plan = try #require(MicMutePolicy.mutePlan(for: muteDevice))
        #expect(plan.actions == [.setMute(true)])
        #expect(plan.record == MicMuteRecord(deviceUID: "a", method: .mute, previousVolume: nil))
    }

    @Test func fallsBackToVolumeAndRemembersLevel() throws {
        let plan = try #require(MicMutePolicy.mutePlan(for: volumeOnly))
        #expect(plan.actions == [.setVolume(0)])
        #expect(plan.record == MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0.6))
    }

    @Test func noPlanWithoutAnyControl() {
        let state = MicInputState(uid: "x", name: "X", canMute: false, canSetVolume: false, isMuteOn: false, volume: nil)
        #expect(MicMutePolicy.mutePlan(for: state) == nil)
        #expect(!MicMutePolicy.isAvailable(state))
        #expect(!MicMutePolicy.isAvailable(nil))
    }

    @Test func mutedWhenPropertyOnOrVolumeSilent() {
        #expect(!MicMutePolicy.isMuted(muteDevice))
        #expect(MicMutePolicy.isMuted(muteDevice.with(isMuteOn: true)))
        #expect(MicMutePolicy.isMuted(volumeOnly.with(volume: 0)))
        #expect(!MicMutePolicy.isMuted(nil))
    }

    @Test func unmuteRestoresRememberedVolume() {
        let record = MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0.4)
        #expect(MicMutePolicy.unmutePlan(for: volumeOnly.with(volume: 0), record: record) == [.setVolume(0.4)])
    }

    @Test func unmuteUsesFallbackVolumeWithoutRecord() {
        #expect(MicMutePolicy.unmutePlan(for: volumeOnly.with(volume: 0), record: nil)
            == [.setVolume(MicMutePolicy.fallbackRestoreVolume)])
        let silentRecord = MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0)
        #expect(MicMutePolicy.unmutePlan(for: volumeOnly.with(volume: 0), record: silentRecord)
            == [.setVolume(MicMutePolicy.fallbackRestoreVolume)])
    }

    @Test func restoreLeavesUserChangesAlone() {
        let muteRecord = MicMuteRecord(deviceUID: "a", method: .mute, previousVolume: nil)
        #expect(MicMutePolicy.restorePlan(for: muteDevice.with(isMuteOn: true), record: muteRecord) == [.setMute(false)])
        #expect(MicMutePolicy.restorePlan(for: muteDevice, record: muteRecord).isEmpty)

        let volumeRecord = MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0.5)
        #expect(MicMutePolicy.restorePlan(for: volumeOnly.with(volume: 0.3), record: volumeRecord).isEmpty)
        #expect(MicMutePolicy.restorePlan(for: volumeOnly.with(volume: 0), record: volumeRecord) == [.setVolume(0.5)])
        #expect(MicMutePolicy.restorePlan(for: muteDevice.with(isMuteOn: true), record: volumeRecord).isEmpty)
    }

    @Test func recordDroppedOnceUnmutedElsewhere() {
        let record = MicMuteRecord(deviceUID: "a", method: .mute, previousVolume: nil)
        #expect(MicMutePolicy.reconciledRecord(record, state: muteDevice.with(isMuteOn: true)) == record)
        #expect(MicMutePolicy.reconciledRecord(record, state: muteDevice) == nil)
        #expect(MicMutePolicy.reconciledRecord(record, state: volumeOnly) == record)
        #expect(MicMutePolicy.reconciledRecord(nil, state: muteDevice) == nil)
    }

    @Test func recordStoreRoundTrips() {
        let store = MicMuteRecordStore(defaults: SystemTestSupport.makeDefaults())
        let record = MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0.5)
        store.save(record)
        #expect(store.load() == record)
        store.save(nil)
        #expect(store.load() == nil)
    }
}

enum FakeMicHardwareStates {
    static let muteCapable = MicInputState(uid: "a", name: "A", canMute: true, canSetVolume: true, isMuteOn: false, volume: 0.6)
    static let volumeOnly = MicInputState(uid: "v", name: "V", canMute: false, canSetVolume: true, isMuteOn: false, volume: 0.6)
}

extension MicInputState {
    func with(isMuteOn: Bool? = nil, volume: Float? = nil) -> MicInputState {
        MicInputState(
            uid: uid, name: name, canMute: canMute, canSetVolume: canSetVolume,
            isMuteOn: isMuteOn ?? self.isMuteOn, volume: volume ?? self.volume
        )
    }
}

@MainActor
struct MicMuteControllerTests {
    private let hardware = FakeMicHardware()
    private let alerts = SystemTestSupport.makeAlertCenter()
    private let defaults = SystemTestSupport.makeDefaults()

    private func makeController() -> MicMuteController {
        MicMuteController(alerts: alerts, hardware: hardware, defaults: defaults)
    }

    @Test func togglesViaMutePropertyAndPostsFeedback() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.start()
        #expect(controller.isAvailable)
        #expect(!controller.isMuted)

        controller.toggle()
        #expect(controller.isMuted)
        #expect(hardware.devices["a"]?.isMuteOn == true)
        #expect(controller.record?.method == .mute)
        #expect(alerts.current?.title == "Mikrofon kapalı")
        #expect(alerts.current?.autoDismissAfter == MicMuteController.feedbackDuration)

        controller.toggle()
        #expect(!controller.isMuted)
        #expect(hardware.devices["a"]?.isMuteOn == false)
        #expect(controller.record == nil)
        #expect(alerts.current?.title == "Mikrofon açık")
    }

    @Test func volumeFallbackRestoresPreviousLevel() {
        hardware.add(FakeMicHardware.device("v", canMute: false, volume: 0.42))
        let controller = makeController()
        controller.start()

        controller.setMuted(true)
        #expect(controller.isMuted)
        #expect(hardware.devices["v"]?.volume == 0)

        controller.setMuted(false)
        #expect(!controller.isMuted)
        #expect(hardware.devices["v"]?.volume == 0.42)
    }

    @Test func stopRestoresOriginalState() {
        hardware.add(FakeMicHardware.device("v", canMute: false, volume: 0.42))
        let controller = makeController()
        controller.start()
        controller.setMuted(true)

        controller.stop()
        #expect(hardware.devices["v"]?.volume == 0.42)
        #expect(MicMuteRecordStore(defaults: defaults).load() == nil)
    }

    @Test func recoversAfterCrashOnNextLaunch() {
        hardware.add(FakeMicHardware.device("a"))
        let crashed = makeController()
        crashed.start()
        crashed.setMuted(true)
        // Crash: no stop(), the record stays persisted.
        #expect(MicMuteRecordStore(defaults: defaults).load()?.deviceUID == "a")

        let relaunched = makeController()
        relaunched.start()
        #expect(hardware.devices["a"]?.isMuteOn == false)
        #expect(!relaunched.isMuted)
        #expect(MicMuteRecordStore(defaults: defaults).load() == nil)
    }

    @Test func crashRecoveryRestoresVolume() {
        hardware.add(FakeMicHardware.device("v", canMute: false, volume: 0))
        MicMuteRecordStore(defaults: defaults).save(MicMuteRecord(deviceUID: "v", method: .volume, previousVolume: 0.7))

        makeController().start()
        #expect(hardware.devices["v"]?.volume == 0.7)
    }

    @Test func persistsRecordBeforeWriting() {
        hardware.add(FakeMicHardware.device("a"))
        hardware.failingActions = true
        let controller = makeController()
        controller.start()

        controller.setMuted(true)
        #expect(!controller.isMuted)
        #expect(controller.record == nil)
        #expect(alerts.current == nil)
    }

    @Test func externalUnmuteDropsRecord() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.start()
        controller.setMuted(true)

        hardware.setExternally("a", isMuteOn: false)
        hardware.fireChange()
        #expect(!controller.isMuted)
        #expect(controller.record == nil)

        controller.stop()
        #expect(hardware.appliedActions.count == 1)
    }

    @Test func externalMuteIsReflected() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.start()

        hardware.setExternally("a", isMuteOn: true)
        hardware.fireChange()
        #expect(controller.isMuted)
        #expect(controller.record == nil)
    }

    @Test func deviceSwitchWhileMutedMovesTheMute() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.start()
        controller.setMuted(true)

        hardware.add(FakeMicHardware.device("b", canMute: false, volume: 0.5))
        hardware.fireChange()

        #expect(hardware.devices["a"]?.isMuteOn == false)
        #expect(hardware.devices["b"]?.volume == 0)
        #expect(controller.isMuted)
        #expect(controller.record == MicMuteRecord(deviceUID: "b", method: .volume, previousVolume: 0.5))
    }

    @Test func deviceSwitchWhileLiveChangesNothing() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.start()

        hardware.add(FakeMicHardware.device("b"))
        hardware.fireChange()
        #expect(hardware.appliedActions.isEmpty)
        #expect(controller.deviceName == "Mic b")
    }

    @Test func noInputDeviceIsUnavailable() {
        let controller = makeController()
        controller.start()
        controller.toggle()
        #expect(!controller.isAvailable)
        #expect(!controller.isMuted)
        #expect(alerts.current == nil)
    }

    @Test func feedbackRespectsAlertGate() {
        hardware.add(FakeMicHardware.device("a"))
        let controller = makeController()
        controller.canPostAlert = { false }
        controller.start()
        controller.toggle()
        #expect(controller.isMuted)
        #expect(alerts.current == nil)
    }

    @Test func hotKeySettingPersists() {
        let controller = makeController()
        #expect(controller.isHotKeyEnabled)
        controller.isHotKeyEnabled = false
        #expect(!makeController().isHotKeyEnabled)
    }
}
