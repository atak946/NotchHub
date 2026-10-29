import CoreAudio
import Foundation

/// Performs intercepted media keys: CoreAudio writes on a serial background queue, brightness on the main actor
/// after the tap callback has returned.
@MainActor
final class SystemMediaKeyController: MediaKeyControlling {
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

    // MARK: - Private

    private func performVolume(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void) {
        guard let id = CoreAudioReader.defaultOutputDevice() else {
            completion(nil)
            return
        }
        audioQueue.async {
            let reading = CoreAudioVolumeWriter.perform(command, on: id)
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
            let target = MediaKeyPolicy.stepped(current, up: up, isFine: isFine)
            guard brightness.setBrightness(target) else {
                completion(HUDReading(kind: .brightness, level: current))
                return
            }
            completion(HUDReading(kind: .brightness, level: target))
        }
    }
}
