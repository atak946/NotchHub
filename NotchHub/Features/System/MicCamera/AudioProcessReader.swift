import AppKit
import CoreAudio
import OSLog

/// A process that CoreAudio reports as currently capturing audio input.
struct AudioInputProcess: Equatable, Sendable {
    let pid: Int32
    /// `kAudioProcessPropertyBundleID`; helpers report their own id (e.g. `com.google.Chrome.helper`).
    let bundleID: String?
    /// `NSRunningApplication.localizedName` for the pid, when it has one.
    let name: String?
}

/// Lists processes that capture audio input. Side-effect boundary of the privacy indicator.
@MainActor
protocol AudioInputProcessReading: AnyObject {
    func inputProcesses() -> [AudioInputProcess]
    /// Fires when the process list or any process's input state changes.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// CoreAudio process objects (macOS 14+). Reads HAL metadata only, so it needs no microphone permission.
@MainActor
final class SystemAudioProcessReader: AudioInputProcessReading {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicCamera")
    private var onChange: (@MainActor () -> Void)?
    private var listListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    func inputProcesses() -> [AudioInputProcess] {
        AudioProcessHAL.processIDs()
            .filter(AudioProcessHAL.isRunningInput)
            .compactMap(Self.makeProcess)
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        addListListener()
        rebuildProcessListeners()
    }

    func stopObserving() {
        guard onChange != nil else { return }
        removeProcessListeners()
        removeListListener()
        onChange = nil
    }

    private static func makeProcess(_ id: AudioObjectID) -> AudioInputProcess? {
        guard let pid = AudioProcessHAL.pid(of: id) else { return nil }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName
        return AudioInputProcess(pid: pid, bundleID: AudioProcessHAL.bundleID(of: id), name: name)
    }

    // MARK: - Listeners

    private func addListListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleListChange() }
        }
        var address = AudioProcessHAL.address(kAudioHardwarePropertyProcessObjectList)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block
        )
        if status == noErr {
            listListener = block
        } else {
            logger.error("Adding audio process list listener failed: \(status)")
        }
    }

    private func removeListListener() {
        guard let block = listListener else { return }
        var address = AudioProcessHAL.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        listListener = nil
    }

    private func handleListChange() {
        rebuildProcessListeners()
        onChange?()
    }

    private func rebuildProcessListeners() {
        removeProcessListeners()
        for id in AudioProcessHAL.processIDs() {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            var address = AudioProcessHAL.address(kAudioProcessPropertyIsRunningInput)
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                processListeners[id] = block
            }
        }
    }

    private func removeProcessListeners() {
        for (id, block) in processListeners {
            var address = AudioProcessHAL.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        processListeners = [:]
    }
}

/// Thin CoreAudio process-object wrappers (not unit tested; they need a live HAL).
enum AudioProcessHAL {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func processIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, base)
        }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func isRunningInput(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    static func pid(of id: AudioObjectID) -> Int32? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr && value > 0 ? value : nil
    }

    static func bundleID(of id: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let bundleID = value.takeRetainedValue() as String
        return bundleID.isEmpty ? nil : bundleID
    }
}
