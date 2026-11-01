import CoreAudio
import Foundation

/// Performs intercepted media keys and HUD scroll/drag levels: CoreAudio writes on a serial background queue,
/// brightness on the main actor after the tap callback has returned.
@MainActor
final class SystemMediaKeyController: MediaKeyControlling, HUDLevelSetting {
    /// Set by the integrator: the "Ses tuşu adımı" setting, read once per key press.
    var volumeStep: @MainActor () -> VolumeKeyStep = { .system }

    private let brightness: DisplayServicesBrightnessReader
    private let audioQueue = DispatchQueue(label: "\(AppIdentity.logSubsystem).media-keys", qos: .userInteractive)

    init(brightness: DisplayServicesBrightnessReader) {
        self.brightness = brightness
    }

    func capabilities(for kind: HUDKind) -> MediaKeyCapabilities {
        switch kind {
        case .volume:
            guard let id = CoreAudioReader.defaultOutputDevice() else { return MediaKeyCapabilities() }
            return CoreAudioVolumeWriter.capabilities(of: id)
        case .brightness:
            return MediaKeyCapabilities(canSetBrightness: brightness.canSetBrightness)
        case .keyboardBacklight:
            return MediaKeyCapabilities()
        }
    }

    func perform(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        switch command {
        case .volumeUp, .volumeDown, .toggleMute:
            performVolume(command, completion: completion)
        case .brightnessUp(let fine):
            performBrightness(up: true, isFine: fine, completion: completion)
        case .brightnessDown(let fine):
            performBrightness(up: false, isFine: fine, completion: completion)
        }
    }

    func canSetLevel(for kind: HUDKind) -> Bool {
        switch kind {
        case .volume: capabilities(for: .volume).canSetVolume
        case .brightness: capabilities(for: .brightness).canSetBrightness
        case .keyboardBacklight: false
        }
    }

    func setLevel(_ level: Double, for kind: HUDKind, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        switch kind {
        case .volume:
            guard let id = CoreAudioReader.defaultOutputDevice() else {
                completion(nil)
                return
            }
            audioQueue.async {
                let reading = CoreAudioVolumeWriter.setLevel(level, on: id)
                Task { @MainActor in completion(reading) }
            }
        case .brightness:
            let target = MediaKeyPolicy.brightnessLevel(level)
            guard brightness.setBrightness(target) else {
                completion(brightness.brightness().map { HUDReading(kind: .brightness, level: $0) })
                return
            }
            completion(HUDReading(kind: .brightness, level: target))
        case .keyboardBacklight:
            completion(nil)
        }
    }

    // MARK: - Private

    private func performVolume(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        guard let id = CoreAudioReader.defaultOutputDevice() else {
            completion(nil)
            return
        }
        let step = volumeStep()
        audioQueue.async {
            let reading = CoreAudioVolumeWriter.perform(command, on: id, step: step)
            Task { @MainActor in completion(reading) }
        }
    }

    /// Brightness has no change listener, so the new level goes to the HUD directly.
    private func performBrightness(up: Bool, isFine: Bool, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        Task { @MainActor [brightness] in
            guard let current = brightness.brightness() else {
                completion(nil)
                return
            }
            let target = MediaKeyPolicy.brightnessLevel(MediaKeyPolicy.stepped(current, up: up, isFine: isFine))
            guard brightness.setBrightness(target) else {
                completion(HUDReading(kind: .brightness, level: current))
                return
            }
            completion(HUDReading(kind: .brightness, level: target))
        }
    }
}
