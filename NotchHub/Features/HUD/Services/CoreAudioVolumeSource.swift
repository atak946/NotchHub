import AudioToolbox
import CoreAudio
import OSLog

/// Listens to the default output device's volume and mute, re-attaching when the default device changes.
@MainActor
final class CoreAudioVolumeSource: HUDVolumeSource {
    var onChange: (@MainActor (HUDReading) -> Void)?

    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")
    private var defaultDeviceListener: Listener?
    private var deviceListeners: [Listener] = []
    private var deviceID: AudioObjectID?

    func start() {
        guard defaultDeviceListener == nil else { return }
        let address = CoreAudioReader.globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
        defaultDeviceListener = addListener(on: AudioObjectID(kAudioObjectSystemObject), address: address) { [weak self] in
            self?.attachToDefaultDevice()
        }
        attachToDefaultDevice()
    }

    func stop() {
        if let defaultDeviceListener { remove(defaultDeviceListener) }
        defaultDeviceListener = nil
        detachDevice()
    }

    func currentReading() -> HUDReading? {
        guard let deviceID = deviceID ?? CoreAudioReader.defaultOutputDevice() else { return nil }
        return Self.reading(of: deviceID)
    }

    // MARK: - Private

    private func attachToDefaultDevice() {
        detachDevice()
        guard let id = CoreAudioReader.defaultOutputDevice() else { return }
        deviceID = id
        for address in Self.observedAddresses(of: id) {
            if let listener = addListener(on: id, address: address, handler: { [weak self] in self?.deviceDidChange() }) {
                deviceListeners.append(listener)
            }
        }
    }

    private func detachDevice() {
        deviceListeners.forEach(remove)
        deviceListeners.removeAll()
        deviceID = nil
    }

    private func deviceDidChange() {
        guard let reading = currentReading() else { return }
        onChange?(reading)
    }

    private func addListener(
        on object: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping @MainActor () -> Void
    ) -> Listener? {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        var mutableAddress = address
        let status = AudioObjectAddPropertyListenerBlock(object, &mutableAddress, .main, block)
        guard status == noErr else {
            logger.error("Adding HUD CoreAudio listener failed: \(status)")
            return nil
        }
        return (object, address, block)
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        let status = AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
        if status != noErr {
            logger.error("Removing HUD CoreAudio listener failed: \(status)")
        }
    }

    // MARK: - HAL reads

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        CoreAudioReader.globalAddress(selector, scope: kAudioDevicePropertyScopeOutput)
    }

    /// The virtual main volume when the device has one, else the main-element scalar; plus mute.
    private static func volumeAddress(of id: AudioObjectID) -> AudioObjectPropertyAddress? {
        var virtual = outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if AudioObjectHasProperty(id, &virtual) { return virtual }
        var scalar = outputAddress(kAudioDevicePropertyVolumeScalar)
        if AudioObjectHasProperty(id, &scalar) { return scalar }
        return nil
    }

    private static func muteAddress(of id: AudioObjectID) -> AudioObjectPropertyAddress? {
        var mute = outputAddress(kAudioDevicePropertyMute)
        return AudioObjectHasProperty(id, &mute) ? mute : nil
    }

    private static func observedAddresses(of id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        [volumeAddress(of: id), muteAddress(of: id)].compactMap { $0 }
    }

    private static func reading(of id: AudioObjectID) -> HUDReading {
        HUDReading(kind: .volume, level: volume(of: id), isMuted: isMuted(id))
    }

    private static func volume(of id: AudioObjectID) -> Double? {
        guard var address = volumeAddress(of: id) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
    }

    private static func isMuted(_ id: AudioObjectID) -> Bool {
        guard var address = muteAddress(of: id) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }
}
