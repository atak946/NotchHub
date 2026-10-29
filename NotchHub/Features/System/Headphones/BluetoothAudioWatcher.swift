import CoreAudio
import OSLog

/// Bluetooth audio outputs and the default output; side-effect boundary of `HeadphoneBatteryMonitor`.
@MainActor
protocol BluetoothAudioWatching: AnyObject {
    func snapshot() -> BluetoothAudioSnapshot
    /// Fires when devices appear / disappear or the default output changes. Event driven, no polling.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

@MainActor
final class CoreAudioBluetoothWatcher: BluetoothAudioWatching {
    private static let observedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Headphones")
    private var listeners: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []

    func snapshot() -> BluetoothAudioSnapshot {
        let outputs = CoreAudioReader.deviceSnapshots()
            .filter { $0.outputStreamCount > 0 && !$0.name.isEmpty }
            .filter { AudioTransportKind(transportType: $0.transportType) == .bluetooth }
            .map { BluetoothAudioOutput(id: $0.id, name: $0.name) }
        return BluetoothAudioSnapshot(outputs: outputs, defaultOutputID: CoreAudioReader.defaultOutputDevice())
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard listeners.isEmpty else { return }
        for selector in Self.observedSelectors {
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { onChange() }
            }
            var address = CoreAudioReader.globalAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            if status == noErr {
                listeners.append((selector, block))
            } else {
                logger.error("Adding Bluetooth audio listener failed: \(status)")
            }
        }
    }

    func stopObserving() {
        for listener in listeners {
            var address = CoreAudioReader.globalAddress(listener.selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener.block)
        }
        listeners.removeAll()
    }
}
