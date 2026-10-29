import CoreAudio
import OSLog

/// Settable-property checks and writes for the default output device. Thread-safe; runs off the main thread.
enum CoreAudioVolumeWriter {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")

    /// Only the flags for volume keys; HDMI/DisplayPort outputs usually report nothing settable.
    static func capabilities(of id: AudioObjectID) -> MediaKeyCapabilities {
        MediaKeyCapabilities(
            canSetVolume: settableVolumeAddress(of: id) != nil,
            canSetMute: settableMuteAddress(of: id) != nil
        )
    }

    /// Reads, applies `command` and writes back; returns the level read back afterwards.
    static func perform(_ command: MediaKeyCommand, on id: AudioObjectID) -> HUDReading? {
        guard let volumeAddress = settableVolumeAddress(of: id) else { return nil }
        let muteAddress = settableMuteAddress(of: id)
        let current = VolumeState(
            level: CoreAudioVolumeSource.volume(of: id) ?? 0,
            isMuted: CoreAudioVolumeSource.isMuted(id)
        )
        let next = MediaKeyPolicy.apply(command, to: current, canSetMute: muteAddress != nil)
        if next.level != current.level {
            write(Float32(next.level), to: volumeAddress, on: id)
        }
        if next.isMuted != current.isMuted, let muteAddress {
            write(UInt32(next.isMuted ? 1 : 0), to: muteAddress, on: id)
        }
        return CoreAudioVolumeSource.reading(of: id)
    }

    // MARK: - Private

    private static func settableVolumeAddress(of id: AudioObjectID) -> AudioObjectPropertyAddress? {
        guard let address = CoreAudioVolumeSource.volumeAddress(of: id), isSettable(address, on: id) else { return nil }
        return address
    }

    private static func settableMuteAddress(of id: AudioObjectID) -> AudioObjectPropertyAddress? {
        guard let address = CoreAudioVolumeSource.muteAddress(of: id), isSettable(address, on: id) else { return nil }
        return address
    }

    private static func isSettable(_ address: AudioObjectPropertyAddress, on id: AudioObjectID) -> Bool {
        var mutableAddress = address
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(id, &mutableAddress, &settable)
        return status == noErr && settable.boolValue
    }

    private static func write(_ value: Float32, to address: AudioObjectPropertyAddress, on id: AudioObjectID) {
        var mutableAddress = address
        var mutableValue = value
        let size = UInt32(MemoryLayout<Float32>.size)
        report(AudioObjectSetPropertyData(id, &mutableAddress, 0, nil, size, &mutableValue))
    }

    private static func write(_ value: UInt32, to address: AudioObjectPropertyAddress, on id: AudioObjectID) {
        var mutableAddress = address
        var mutableValue = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        report(AudioObjectSetPropertyData(id, &mutableAddress, 0, nil, size, &mutableValue))
    }

    private static func report(_ status: OSStatus) {
        if status != noErr {
            logger.error("Writing output volume/mute failed: \(status)")
        }
    }
}
