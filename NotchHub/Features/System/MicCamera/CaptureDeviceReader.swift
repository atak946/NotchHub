import CoreAudio
import CoreMediaIO
import OSLog

/// Which capture devices are currently in use by any process.
struct CaptureSnapshot: Equatable, Sendable {
    static let idle = CaptureSnapshot(activeMicrophones: [], activeCameras: [])

    let activeMicrophones: [String]
    let activeCameras: [String]

    var isMicrophoneInUse: Bool { !activeMicrophones.isEmpty }
    var isCameraInUse: Bool { !activeCameras.isEmpty }
}

/// Reads microphone / camera usage and reports changes. Side-effect boundary of `MicCameraMonitor`.
@MainActor
protocol CaptureDeviceReading: AnyObject {
    func snapshot() -> CaptureSnapshot
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// CoreAudio + CoreMediaIO "running somewhere" reader. Needs no microphone or camera permission.
@MainActor
final class SystemCaptureDeviceReader: CaptureDeviceReading {
    private static let fallbackMicrophoneName = "Microphone"
    private static let fallbackCameraName = "Camera"

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicCamera")
    private var onChange: (@MainActor () -> Void)?
    private var audioListListener: AudioObjectPropertyListenerBlock?
    private var audioDeviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var cameraListListener: CMIOObjectPropertyListenerBlock?
    private var cameraDeviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]

    func snapshot() -> CaptureSnapshot {
        let microphones = MicCameraHAL.inputDeviceIDs()
            .filter(MicCameraHAL.isAudioDeviceRunning)
            .map { MicCameraHAL.audioDeviceName($0) ?? Self.fallbackMicrophoneName }
        let cameras = MicCameraHAL.cameraIDs()
            .filter(MicCameraHAL.isCameraRunning)
            .map { MicCameraHAL.cameraName($0) ?? Self.fallbackCameraName }
        return CaptureSnapshot(activeMicrophones: microphones, activeCameras: cameras)
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        addDeviceListListeners()
        rebuildDeviceListeners()
    }

    func stopObserving() {
        guard onChange != nil else { return }
        removeDeviceListeners()
        removeDeviceListListeners()
        onChange = nil
    }

    // MARK: - Device lists

    private func addDeviceListListeners() {
        let audioBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleDeviceListChange() }
        }
        var audioAddress = MicCameraHAL.audioAddress(kAudioHardwarePropertyDevices)
        let audioStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &audioAddress, .main, audioBlock
        )
        if audioStatus == noErr {
            audioListListener = audioBlock
        } else {
            logger.error("Adding audio device list listener failed: \(audioStatus)")
        }

        let cameraBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleDeviceListChange() }
        }
        var cameraAddress = MicCameraHAL.cmioAddress(kCMIOHardwarePropertyDevices)
        let cameraStatus = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &cameraAddress, .main, cameraBlock
        )
        if cameraStatus == noErr {
            cameraListListener = cameraBlock
        } else {
            logger.error("Adding camera device list listener failed: \(cameraStatus)")
        }
    }

    private func removeDeviceListListeners() {
        if let block = audioListListener {
            var address = MicCameraHAL.audioAddress(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            audioListListener = nil
        }
        if let block = cameraListListener {
            var address = MicCameraHAL.cmioAddress(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block)
            cameraListListener = nil
        }
    }

    private func handleDeviceListChange() {
        rebuildDeviceListeners()
        onChange?()
    }

    // MARK: - Per-device "running somewhere"

    private func rebuildDeviceListeners() {
        removeDeviceListeners()
        for id in MicCameraHAL.inputDeviceIDs() {
            addAudioRunningListener(id)
        }
        for id in MicCameraHAL.cameraIDs() {
            addCameraRunningListener(id)
        }
    }

    private func addAudioRunningListener(_ id: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        var address = MicCameraHAL.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
            audioDeviceListeners[id] = block
        }
    }

    private func addCameraRunningListener(_ id: CMIOObjectID) {
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        var address = MicCameraHAL.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        if CMIOObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
            cameraDeviceListeners[id] = block
        }
    }

    private func removeDeviceListeners() {
        for (id, block) in audioDeviceListeners {
            var address = MicCameraHAL.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        audioDeviceListeners = [:]
        for (id, block) in cameraDeviceListeners {
            var address = MicCameraHAL.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        cameraDeviceListeners = [:]
    }
}

/// Thin CoreAudio / CoreMediaIO HAL wrappers (not unit tested; they need real hardware).
enum MicCameraHAL {
    // MARK: CoreAudio

    static func audioAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func inputDeviceIDs() -> [AudioObjectID] {
        audioDeviceIDs().filter(hasInputStreams)
    }

    static func isAudioDeviceRunning(_ id: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    static func audioDeviceName(_ id: AudioObjectID) -> String? {
        var address = audioAddress(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func audioDeviceIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = audioAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, base)
        }
        return status == noErr ? ids : []
    }

    private static func hasInputStreams(_ id: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    // MARK: CoreMediaIO

    static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func cameraIDs() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = cmioAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = ids.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return OSStatus(kCMIOHardwareBadObjectError) }
            return CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, base)
        }
        return status == noErr ? Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size)) : []
    }

    static func isCameraRunning(_ id: CMIOObjectID) -> Bool {
        var address = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = CMIOObjectGetPropertyData(id, &address, 0, nil, size, &used, &value)
        return status == noErr && value != 0
    }

    static func cameraName(_ id: CMIOObjectID) -> String? {
        var address = cmioAddress(kCMIOObjectPropertyName)
        var name: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            CMIOObjectGetPropertyData(id, &address, 0, nil, size, &used, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
