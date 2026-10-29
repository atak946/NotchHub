import CoreAudio
import OSLog

/// Default input device control; side-effect boundary of `MicMuteController`.
@MainActor
protocol MicInputHardware: AnyObject {
    /// State of the current default input device, nil when there is none.
    func defaultInputState() -> MicInputState?
    /// State of a (possibly non-default) device by UID, nil when it is gone.
    func state(forUID uid: String) -> MicInputState?
    func apply(_ action: MicMuteAction, toUID uid: String) -> Bool
    /// Fires on default input device changes and on mute / volume changes of the default device.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// CoreAudio HAL implementation. Needs no microphone permission (it never records).
@MainActor
final class CoreAudioMicInput: MicInputHardware {
    /// Main element plus the first stereo channels; built-in mics often expose volume per channel only.
    private static let volumeElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicMute")
    private var onChange: (@MainActor () -> Void)?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(device: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    func defaultInputState() -> MicInputState? {
        guard let id = Self.defaultInputDevice() else { return nil }
        return Self.state(of: id)
    }

    func state(forUID uid: String) -> MicInputState? {
        guard let id = Self.device(forUID: uid) else { return nil }
        return Self.state(of: id)
    }

    func apply(_ action: MicMuteAction, toUID uid: String) -> Bool {
        guard let id = Self.device(forUID: uid) else { return false }
        let status: OSStatus
        switch action {
        case .setMute(let muted):
            var address = Self.inputAddress(kAudioDevicePropertyMute)
            var value: UInt32 = muted ? 1 : 0
            status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        case .setVolume(let volume):
            status = Self.setVolume(volume, of: id)
        }
        if status != noErr {
            logger.error("Applying mic mute action failed: \(status)")
        }
        return status == noErr
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleDefaultDeviceChange() }
        }
        var address = MicCameraHAL.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        if status == noErr {
            defaultDeviceListener = block
        } else {
            logger.error("Adding default input listener failed: \(status)")
        }
        rebuildDeviceListeners()
    }

    func stopObserving() {
        guard onChange != nil else { return }
        removeDeviceListeners()
        if let block = defaultDeviceListener {
            var address = MicCameraHAL.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            defaultDeviceListener = nil
        }
        onChange = nil
    }

    // MARK: - Listeners

    private func handleDefaultDeviceChange() {
        rebuildDeviceListeners()
        onChange?()
    }

    private func rebuildDeviceListeners() {
        removeDeviceListeners()
        guard let id = Self.defaultInputDevice() else { return }
        var addresses = [Self.inputAddress(kAudioDevicePropertyMute)]
        addresses += Self.volumeElements.map { Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: $0) }
        for var address in addresses where AudioObjectHasProperty(id, &address) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                deviceListeners.append((id, address, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for listener in deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.device, &address, .main, listener.block)
        }
        deviceListeners = []
    }

    // MARK: - HAL reads and writes

    private static func inputAddress(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: element)
    }

    private static func defaultInputDevice() -> AudioObjectID? {
        var address = MicCameraHAL.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func device(forUID uid: String) -> AudioObjectID? {
        if let id = defaultInputDevice(), deviceUID(id) == uid { return id }
        return MicCameraHAL.inputDeviceIDs().first { deviceUID($0) == uid }
    }

    private static func state(of id: AudioObjectID) -> MicInputState? {
        guard let uid = deviceUID(id) else { return nil }
        var muteAddress = inputAddress(kAudioDevicePropertyMute)
        let volumeElement = settableVolumeElement(of: id)
        return MicInputState(
            uid: uid,
            name: MicCameraHAL.audioDeviceName(id) ?? uid,
            canMute: isSettable(id, &muteAddress),
            canSetVolume: volumeElement != nil,
            isMuteOn: readUInt32(id, &muteAddress).map { $0 != 0 } ?? false,
            volume: volumeElement.flatMap { readVolume(id, element: $0) }
        )
    }

    private static func deviceUID(_ id: AudioObjectID) -> String? {
        var address = MicCameraHAL.audioAddress(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func settableVolumeElement(of id: AudioObjectID) -> AudioObjectPropertyElement? {
        volumeElements.first { element in
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            return isSettable(id, &address)
        }
    }

    private static func setVolume(_ volume: Float, of id: AudioObjectID) -> OSStatus {
        var lastStatus = OSStatus(kAudioHardwareUnknownPropertyError)
        var didSet = false
        for element in volumeElements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            guard isSettable(id, &address) else { continue }
            var value = Float32(volume)
            lastStatus = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            didSet = didSet || lastStatus == noErr
        }
        return didSet ? noErr : lastStatus
    }

    private static func readVolume(_ id: AudioObjectID, element: AudioObjectPropertyElement) -> Float? {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? Float(value) : nil
    }

    private static func readUInt32(_ id: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func isSettable(_ id: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(id, &address, &settable)
        return status == noErr && settable.boolValue
    }
}
