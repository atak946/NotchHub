import Foundation

/// How NotchHub silenced the input device.
enum MicMuteMethod: String, Codable, Sendable {
    /// `kAudioDevicePropertyMute` on the input scope.
    case mute
    /// Input volume scalar set to 0 (device has no settable mute).
    case volume
}

/// Persisted "muted by NotchHub" marker, so a crash never leaves the microphone silenced.
struct MicMuteRecord: Codable, Equatable, Sendable {
    let deviceUID: String
    let method: MicMuteMethod
    /// Input volume before muting; only for `.volume`.
    let previousVolume: Float?
}

/// What the HAL reports for one input device.
struct MicInputState: Equatable, Sendable {
    let uid: String
    let name: String
    let canMute: Bool
    let canSetVolume: Bool
    let isMuteOn: Bool
    /// Input volume scalar 0...1, nil when the device exposes none.
    let volume: Float?
}

/// One HAL write.
enum MicMuteAction: Equatable, Sendable {
    case setMute(Bool)
    case setVolume(Float)
}

/// Pure mute / unmute decisions; `MicMuteController` performs the actions.
enum MicMutePolicy {
    /// Volume used on unmute when nothing better is known (e.g. muted to 0 by someone else).
    static let fallbackRestoreVolume: Float = 0.75
    /// Volumes at or below this count as silent.
    static let silentVolume: Float = 0.001

    static func isAvailable(_ state: MicInputState?) -> Bool {
        guard let state else { return false }
        return state.canMute || state.canSetVolume
    }

    static func isMuted(_ state: MicInputState?) -> Bool {
        guard let state else { return false }
        if state.canMute, state.isMuteOn { return true }
        guard state.canSetVolume, let volume = state.volume else { return false }
        return volume <= silentVolume
    }

    /// Prefers the mute property; falls back to volume 0 and remembers the previous level.
    static func mutePlan(for state: MicInputState) -> (actions: [MicMuteAction], record: MicMuteRecord)? {
        if state.canMute {
            return ([.setMute(true)], MicMuteRecord(deviceUID: state.uid, method: .mute, previousVolume: nil))
        }
        guard state.canSetVolume else { return nil }
        let record = MicMuteRecord(deviceUID: state.uid, method: .volume, previousVolume: state.volume)
        return ([.setVolume(0)], record)
    }

    /// Undoes whatever silences the device, restoring the remembered volume when there is one.
    static func unmutePlan(for state: MicInputState, record: MicMuteRecord?) -> [MicMuteAction] {
        var actions: [MicMuteAction] = []
        if state.canMute, state.isMuteOn {
            actions.append(.setMute(false))
        }
        if state.canSetVolume, let volume = state.volume, volume <= silentVolume {
            actions.append(.setVolume(restoreVolume(for: record, deviceUID: state.uid)))
        }
        return actions
    }

    /// Restores only what NotchHub changed (used on quit and after a crash); leaves user changes alone.
    static func restorePlan(for state: MicInputState, record: MicMuteRecord) -> [MicMuteAction] {
        guard state.uid == record.deviceUID else { return [] }
        switch record.method {
        case .mute:
            return state.canMute && state.isMuteOn ? [.setMute(false)] : []
        case .volume:
            guard state.canSetVolume, let volume = state.volume, volume <= silentVolume else { return [] }
            return [.setVolume(restoreVolume(for: record, deviceUID: state.uid))]
        }
    }

    /// Drops the record once the device was unmuted by someone else, so quitting never touches it again.
    static func reconciledRecord(_ record: MicMuteRecord?, state: MicInputState?) -> MicMuteRecord? {
        guard let record, let state, state.uid == record.deviceUID else { return record }
        return isMuted(state) ? record : nil
    }

    private static func restoreVolume(for record: MicMuteRecord?, deviceUID: String) -> Float {
        guard let record, record.deviceUID == deviceUID, let previous = record.previousVolume,
              previous > silentVolume else { return fallbackRestoreVolume }
        return min(previous, 1)
    }
}

/// Persists the `MicMuteRecord` in UserDefaults.
struct MicMuteRecordStore {
    static let key = "MicMute.record"

    let defaults: UserDefaults

    func load() -> MicMuteRecord? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(MicMuteRecord.self, from: data)
    }

    func save(_ record: MicMuteRecord?) {
        guard let record, let data = try? JSONEncoder().encode(record) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
