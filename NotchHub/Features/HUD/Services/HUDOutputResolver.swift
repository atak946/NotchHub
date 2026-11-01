import CoreAudio
import Foundation

/// The default output for the volume HUD. Prefers `AudioOutputService` (kept current while the media module runs)
/// and reads CoreAudio itself otherwise, once per output device. Battery comes from the headphone monitor's last read.
@MainActor
final class HUDOutputResolver {
    private let audio: AudioOutputService
    private let headphones: HeadphoneBatteryMonitor
    private var cached: AudioOutputDevice?

    init(audio: AudioOutputService, headphones: HeadphoneBatteryMonitor) {
        self.audio = audio
        self.headphones = headphones
    }

    func current() -> HUDOutputDevice? {
        guard let id = CoreAudioReader.defaultOutputDevice() else { return nil }
        return HUDOutputPolicy.output(for: device(id: id), battery: headphones.lastReport, now: .now)
    }

    private func device(id: AudioObjectID) -> AudioOutputDevice? {
        if let known = audio.defaultDevice, known.id == id { return known }
        if let cached, cached.id == id { return cached }
        let device = AudioOutputDeviceList.make(from: CoreAudioReader.deviceSnapshots(), defaultID: id)
            .first(where: \.isDefault)
        cached = device
        return device
    }
}
