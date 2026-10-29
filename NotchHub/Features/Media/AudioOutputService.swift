import CoreAudio
import Observation
import OSLog

/// Lists audio output devices and switches the system default output.
@MainActor
@Observable
final class AudioOutputService {
    private(set) var devices: [AudioOutputDevice] = []

    var defaultDevice: AudioOutputDevice? { devices.first(where: \.isDefault) }

    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Media")
    @ObservationIgnored private var listeners: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []

    private static let observedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]

    func start() {
        guard listeners.isEmpty else { return }
        for selector in Self.observedSelectors {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reload() }
            }
            var address = CoreAudioReader.globalAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            if status == noErr {
                listeners.append((selector, block))
            } else {
                logger.error("Adding CoreAudio listener failed: \(status)")
            }
        }
        reload()
    }

    func stop() {
        for listener in listeners {
            var address = CoreAudioReader.globalAddress(listener.selector)
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, listener.block
            )
            if status != noErr {
                logger.error("Removing CoreAudio listener failed: \(status)")
            }
        }
        listeners.removeAll()
    }

    func setDefault(_ device: AudioOutputDevice) {
        guard !device.isDefault else { return }
        let status = CoreAudioReader.setDefaultOutput(device.id)
        guard status == noErr else {
            logger.error("Switching output to \(device.name, privacy: .public) failed: \(status)")
            return
        }
        devices = AudioOutputDeviceList.markingDefault(devices, defaultID: device.id)
    }

    func reload() {
        let updated = AudioOutputDeviceList.make(
            from: CoreAudioReader.deviceSnapshots(),
            defaultID: CoreAudioReader.defaultOutputDevice()
        )
        if updated != devices {
            devices = updated
        }
    }
}

/// Thin CoreAudio HAL wrappers. Not unit tested; classification lives in `AudioOutputDeviceList`.
enum CoreAudioReader {
    static func globalAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func deviceSnapshots() -> [AudioDeviceSnapshot] {
        deviceIDs().map { id in
            AudioDeviceSnapshot(
                id: id,
                name: name(of: id) ?? "",
                transportType: transportType(of: id),
                outputStreamCount: outputStreamCount(of: id)
            )
        }
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var address = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    static func setDefaultOutput(_ id: AudioObjectID) -> OSStatus {
        var address = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceID)
    }

    private static func deviceIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = globalAddress(kAudioHardwarePropertyDevices)
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

    private static func name(of id: AudioObjectID) -> String? {
        var address = globalAddress(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transportType(of id: AudioObjectID) -> UInt32 {
        var address = globalAddress(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return status == noErr ? transport : 0
    }

    private static func outputStreamCount(of id: AudioObjectID) -> Int {
        var address = globalAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}
