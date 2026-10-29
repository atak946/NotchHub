import Foundation
@testable import NotchHub

/// In-memory input devices; `apply` mutates them like the HAL would. Tests call `fireChange()`
/// to simulate a CoreAudio listener callback.
@MainActor
final class FakeMicHardware: MicInputHardware {
    var devices: [String: MicInputState] = [:]
    var defaultUID: String?
    var failingActions = false
    private(set) var appliedActions: [(uid: String, action: MicMuteAction)] = []
    private(set) var onChange: (@MainActor () -> Void)?

    static func device(
        _ uid: String,
        canMute: Bool = true,
        canSetVolume: Bool = true,
        isMuteOn: Bool = false,
        volume: Float? = 0.6
    ) -> MicInputState {
        MicInputState(uid: uid, name: "Mic \(uid)", canMute: canMute, canSetVolume: canSetVolume, isMuteOn: isMuteOn, volume: volume)
    }

    func add(_ state: MicInputState, asDefault: Bool = true) {
        devices[state.uid] = state
        if asDefault { defaultUID = state.uid }
    }

    func defaultInputState() -> MicInputState? {
        defaultUID.flatMap { devices[$0] }
    }

    func state(forUID uid: String) -> MicInputState? {
        devices[uid]
    }

    func apply(_ action: MicMuteAction, toUID uid: String) -> Bool {
        guard !failingActions, let state = devices[uid] else { return false }
        appliedActions.append((uid, action))
        switch action {
        case .setMute(let muted):
            devices[uid] = MicInputState(
                uid: uid, name: state.name, canMute: state.canMute, canSetVolume: state.canSetVolume,
                isMuteOn: muted, volume: state.volume
            )
        case .setVolume(let volume):
            devices[uid] = MicInputState(
                uid: uid, name: state.name, canMute: state.canMute, canSetVolume: state.canSetVolume,
                isMuteOn: state.isMuteOn, volume: volume
            )
        }
        return true
    }

    /// Simulates another app changing the device.
    func setExternally(_ uid: String, isMuteOn: Bool? = nil, volume: Float? = nil) {
        guard let state = devices[uid] else { return }
        devices[uid] = MicInputState(
            uid: uid, name: state.name, canMute: state.canMute, canSetVolume: state.canSetVolume,
            isMuteOn: isMuteOn ?? state.isMuteOn, volume: volume ?? state.volume
        )
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func fireChange() {
        onChange?()
    }
}
