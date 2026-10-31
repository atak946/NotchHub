import CoreGraphics
import Testing
@testable import NotchHub

struct MediaKeyPolicyTests {
    private static let everything = MediaKeyCapabilities(canSetVolume: true, canSetMute: true, canSetBrightness: true)
    private static let nothing = MediaKeyCapabilities()

    private func down(_ key: SystemDefinedKeyEvent.Key, isRepeat: Bool = false) -> SystemDefinedKeyEvent {
        SystemDefinedKeyEvent(keyCode: key.rawValue, isKeyDown: true, isRepeat: isRepeat)
    }

    private func up(_ key: SystemDefinedKeyEvent.Key) -> SystemDefinedKeyEvent {
        SystemDefinedKeyEvent(keyCode: key.rawValue, isKeyDown: false, isRepeat: false)
    }

    // MARK: - Activation

    @Test(arguments: [
        (true, true, true, true),
        (false, true, true, false),
        (true, false, true, false),
        (true, true, false, false),
    ])
    func activeOnlyWithHUDSettingAndTrust(hud: Bool, setting: Bool, trusted: Bool, expected: Bool) {
        #expect(MediaKeyPolicy.isActive(hudEnabled: hud, hidesSystemHUD: setting, isTrusted: trusted) == expected)
    }

    // MARK: - Decisions

    @Test func consumesVolumeKeysWhenVolumeIsSettable() {
        #expect(MediaKeyPolicy.decide(down(.soundUp), isFine: false, capabilities: Self.everything) == .consume(.volumeUp(fine: false)))
        #expect(MediaKeyPolicy.decide(down(.soundDown), isFine: true, capabilities: Self.everything) == .consume(.volumeDown(fine: true)))
        #expect(MediaKeyPolicy.decide(down(.mute), isFine: false, capabilities: Self.everything) == .consume(.toggleMute))
    }

    @Test func passesVolumeKeysForOutputsWithoutVolume() {
        for key in [SystemDefinedKeyEvent.Key.soundUp, .soundDown, .mute] {
            #expect(MediaKeyPolicy.decide(down(key), isFine: false, capabilities: Self.nothing) == .pass)
        }
    }

    @Test func muteKeyNeedsSettableMute() {
        let volumeOnly = MediaKeyCapabilities(canSetVolume: true)

        #expect(MediaKeyPolicy.decide(down(.mute), isFine: false, capabilities: volumeOnly) == .pass)
        #expect(MediaKeyPolicy.decide(down(.soundUp), isFine: false, capabilities: volumeOnly) == .consume(.volumeUp(fine: false)))
    }

    @Test func brightnessKeysNeedReadableAndSettableBrightness() {
        let brightness = MediaKeyCapabilities(canSetBrightness: true)

        #expect(MediaKeyPolicy.decide(down(.brightnessUp), isFine: false, capabilities: brightness) == .consume(.brightnessUp(fine: false)))
        #expect(MediaKeyPolicy.decide(down(.brightnessDown), isFine: true, capabilities: brightness) == .consume(.brightnessDown(fine: true)))
        #expect(MediaKeyPolicy.decide(down(.brightnessUp), isFine: false, capabilities: Self.nothing) == .pass)
    }

    @Test func keyboardBacklightAndUnknownKeysAlwaysPass() {
        for key in [SystemDefinedKeyEvent.Key.illuminationUp, .illuminationDown, .illuminationToggle] {
            #expect(MediaKeyPolicy.decide(down(key), isFine: false, capabilities: Self.everything) == .pass)
            #expect(MediaKeyPolicy.controlledKind(of: key) == nil)
        }
        let playPause = SystemDefinedKeyEvent(keyCode: 16, isKeyDown: true, isRepeat: false)
        #expect(MediaKeyPolicy.decide(playPause, isFine: false, capabilities: Self.everything) == .pass)
    }

    @Test func repeatActsLikeKeyDown() {
        #expect(MediaKeyPolicy.decide(down(.soundUp, isRepeat: true), isFine: false, capabilities: Self.everything) == .consume(.volumeUp(fine: false)))
    }

    @Test func keyUpIsConsumedWithoutActionWhenDownWouldBe() {
        #expect(MediaKeyPolicy.decide(up(.soundUp), isFine: false, capabilities: Self.everything) == .consume(nil))
        #expect(MediaKeyPolicy.decide(up(.brightnessDown), isFine: false, capabilities: Self.everything) == .consume(nil))
        #expect(MediaKeyPolicy.decide(up(.soundUp), isFine: false, capabilities: Self.nothing) == .pass)
        #expect(MediaKeyPolicy.decide(up(.illuminationUp), isFine: false, capabilities: Self.everything) == .pass)
    }

    @Test func fineModifierNeedsOptionAndShift() {
        #expect(MediaKeyPolicy.isFineModifier([.maskAlternate, .maskShift]))
        #expect(MediaKeyPolicy.isFineModifier([.maskAlternate, .maskShift, .maskCommand]))
        #expect(!MediaKeyPolicy.isFineModifier(.maskAlternate))
        #expect(!MediaKeyPolicy.isFineModifier(.maskShift))
        #expect(!MediaKeyPolicy.isFineModifier([]))
    }

    // MARK: - Step math

    @Test func stepsAreSixteenthsAndSixtyFourths() {
        #expect(MediaKeyPolicy.stepSize(isFine: false) == 1.0 / 16)
        #expect(MediaKeyPolicy.stepSize(isFine: true) == 1.0 / 64)
        #expect(MediaKeyPolicy.stepped(0.5, up: true, isFine: false) == 9.0 / 16)
        #expect(MediaKeyPolicy.stepped(0.5, up: false, isFine: false) == 7.0 / 16)
        #expect(MediaKeyPolicy.stepped(0.5, up: true, isFine: true) == 33.0 / 64)
        #expect(MediaKeyPolicy.stepped(0.5, up: false, isFine: true) == 31.0 / 64)
    }

    @Test func offGridLevelsSnapToTheNextGridPoint() {
        #expect(MediaKeyPolicy.stepped(0.34, up: true, isFine: false) == 6.0 / 16)
        #expect(MediaKeyPolicy.stepped(0.34, up: false, isFine: false) == 5.0 / 16)
    }

    @Test func floatNoiseOnTheGridStillMovesOneStep() {
        #expect(MediaKeyPolicy.stepped(0.5 - 1e-9, up: true, isFine: false) == 9.0 / 16)
        #expect(MediaKeyPolicy.stepped(0.5 + 1e-9, up: false, isFine: false) == 7.0 / 16)
        // DisplayServices Float readback just below the grid (0.75 → 0.7499999) must still step up.
        #expect(MediaKeyPolicy.stepped(Double(Float(0.7499999)), up: true, isFine: false) == 13.0 / 16)
        #expect(MediaKeyPolicy.stepped(Double(Float(0.7500001)), up: false, isFine: false) == 11.0 / 16)
    }

    @Test func clampsAtBothEnds() {
        #expect(MediaKeyPolicy.stepped(1, up: true, isFine: false) == 1)
        #expect(MediaKeyPolicy.stepped(0.99, up: true, isFine: true) == 1)
        #expect(MediaKeyPolicy.stepped(0, up: false, isFine: false) == 0)
        #expect(MediaKeyPolicy.stepped(0.01, up: false, isFine: true) == 0)
        #expect(MediaKeyPolicy.stepped(1.4, up: false, isFine: false) == 15.0 / 16)
    }

    @Test func brightnessNeverReachesZero() {
        #expect(MediaKeyPolicy.brightnessLevel(0) == 1.0 / 16)
        #expect(MediaKeyPolicy.brightnessLevel(-0.3) == 1.0 / 16)
        #expect(MediaKeyPolicy.brightnessLevel(.nan) == 1.0 / 16)
        #expect(MediaKeyPolicy.brightnessLevel(0.5) == 0.5)
        #expect(MediaKeyPolicy.brightnessLevel(1.7) == 1)
        // Stepping down from the floor stays on the floor.
        #expect(MediaKeyPolicy.brightnessLevel(MediaKeyPolicy.stepped(1.0 / 16, up: false, isFine: false)) == 1.0 / 16)
        #expect(MediaKeyPolicy.brightnessLevel(MediaKeyPolicy.stepped(1.0 / 16, up: false, isFine: true)) == 1.0 / 16)
    }

    // MARK: - Volume state

    @Test func volumeUpWhileMutedUnmutesAndRaises() {
        let next = MediaKeyPolicy.apply(.volumeUp(fine: false), to: VolumeState(level: 0.5, isMuted: true), canSetMute: true)

        #expect(next == VolumeState(level: 9.0 / 16, isMuted: false))
    }

    @Test func volumeUpWhileMutedWithoutSettableMuteOnlyRaises() {
        let next = MediaKeyPolicy.apply(.volumeUp(fine: false), to: VolumeState(level: 0.5, isMuted: true), canSetMute: false)

        #expect(next == VolumeState(level: 9.0 / 16, isMuted: true))
    }

    @Test func volumeDownKeepsMute() {
        let next = MediaKeyPolicy.apply(.volumeDown(fine: true), to: VolumeState(level: 0.5, isMuted: true), canSetMute: true)

        #expect(next == VolumeState(level: 31.0 / 64, isMuted: true))
    }

    @Test func muteKeyTogglesAndKeepsLevel() {
        let state = VolumeState(level: 0.25, isMuted: false)
        let muted = MediaKeyPolicy.apply(.toggleMute, to: state, canSetMute: true)
        let unmuted = MediaKeyPolicy.apply(.toggleMute, to: muted, canSetMute: true)

        #expect(muted == VolumeState(level: 0.25, isMuted: true))
        #expect(unmuted == state)
        #expect(MediaKeyPolicy.apply(.toggleMute, to: state, canSetMute: false) == state)
    }

    @Test func brightnessCommandsLeaveVolumeAlone() {
        let state = VolumeState(level: 0.25, isMuted: false)

        #expect(MediaKeyPolicy.apply(.brightnessUp(fine: false), to: state, canSetMute: true) == state)
    }

    // MARK: - Configurable volume step

    @Test(arguments: [
        (VolumeKeyStep.system, 16, 64),
        (.percent2, 50, 200),
        (.percent5, 20, 80),
        (.percent10, 10, 40),
    ])
    func stepCountsAndQuarterFineSteps(step: VolumeKeyStep, coarse: Int, fine: Int) {
        #expect(step.stepCount(isFine: false) == coarse)
        #expect(step.stepCount(isFine: true) == fine)
    }

    @Test func percentStepsMoveByTheirSize() {
        let state = VolumeState(level: 0.5, isMuted: false)

        let up = MediaKeyPolicy.apply(.volumeUp(fine: false), to: state, canSetMute: true, step: .percent10)
        let down = MediaKeyPolicy.apply(.volumeDown(fine: false), to: state, canSetMute: true, step: .percent5)

        #expect(abs(up.level - 0.6) < 1e-9)
        #expect(abs(down.level - 0.45) < 1e-9)
    }

    @Test func systemStepMatchesTheMacOSGrid() {
        let state = VolumeState(level: 0.5, isMuted: false)

        #expect(MediaKeyPolicy.apply(.volumeUp(fine: false), to: state, canSetMute: true, step: .system).level == 9.0 / 16)
        #expect(MediaKeyPolicy.apply(.volumeUp(fine: true), to: state, canSetMute: true, step: .system).level == 33.0 / 64)
    }

    @Test func offGridLevelsSnapToTheChosenGrid() {
        // 0.34 on the 10 % grid: up lands on 40 %, down on 30 %.
        #expect(abs(MediaKeyPolicy.stepped(0.34, up: true, stepCount: 10) - 0.4) < 1e-9)
        #expect(abs(MediaKeyPolicy.stepped(0.34, up: false, stepCount: 10) - 0.3) < 1e-9)
        #expect(MediaKeyPolicy.stepped(0.99, up: true, stepCount: 50) == 1)
        #expect(MediaKeyPolicy.stepped(0.01, up: false, stepCount: 50) == 0)
    }

    @Test func percentStepsStillUnmuteOnVolumeUp() {
        let next = MediaKeyPolicy.apply(
            .volumeUp(fine: false), to: VolumeState(level: 0.2, isMuted: true), canSetMute: true, step: .percent2
        )
        #expect(!next.isMuted)
        #expect(abs(next.level - 0.22) < 1e-9)
    }
}
