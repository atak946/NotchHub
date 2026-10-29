import Foundation
import Observation

/// Volume and brightness HUD in the notch: wires the level sources to `NotchHUDCenter` behind one setting.
@MainActor
@Observable
final class SystemHUD {
    static let enabledKey = "hud.enabled"
    /// Lets the system apply the key press before the level is read back.
    static let keyReadDelay: Duration = .milliseconds(60)

    let center: NotchHUDCenter

    /// "Ses/parlaklık göstergesi çentikte" (default on). Off stops every listener.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { center.hide() }
            updateSources()
        }
    }

    /// Set by the integrator: `true` while readings must be dropped (paused, or an alert is on screen).
    @ObservationIgnored var isBlocked: @MainActor () -> Bool = { false }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let volume: any HUDVolumeSource
    @ObservationIgnored private let keys: any HUDKeySource
    @ObservationIgnored private let brightness: any HUDBrightnessReading
    @ObservationIgnored private let sleep: NotchHUDCenter.Sleeper
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var sourcesRunning = false
    @ObservationIgnored private var lastVolume: HUDReading?
    @ObservationIgnored private var keyReadTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        center: NotchHUDCenter = NotchHUDCenter(),
        volume: any HUDVolumeSource = CoreAudioVolumeSource(),
        keys: any HUDKeySource = SystemDefinedKeyMonitor(),
        brightness: any HUDBrightnessReading = DisplayServicesBrightnessReader(),
        sleep: @escaping NotchHUDCenter.Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.defaults = defaults
        self.center = center
        self.volume = volume
        self.keys = keys
        self.brightness = brightness
        self.sleep = sleep
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        center.canShow = { [weak self] in
            guard let self else { return false }
            return self.isEnabled && !self.isBlocked()
        }
        volume.onChange = { [weak self] reading in self?.handleVolume(reading) }
        keys.onKey = { [weak self] event in self?.handleKey(event) }
    }

    func start() {
        isStarted = true
        updateSources()
    }

    func stop() {
        isStarted = false
        updateSources()
    }

    // MARK: - Private

    private func updateSources() {
        let shouldRun = isStarted && isEnabled
        guard shouldRun != sourcesRunning else { return }
        sourcesRunning = shouldRun
        if shouldRun {
            volume.start()
            keys.start()
            lastVolume = volume.currentReading()
        } else {
            volume.stop()
            keys.stop()
            keyReadTask?.cancel()
            keyReadTask = nil
            lastVolume = nil
            center.hide()
        }
    }

    private func handleVolume(_ reading: HUDReading) {
        let previous = lastVolume
        lastVolume = reading
        guard HUDLevel.isMeaningfulChange(from: previous, to: reading) else { return }
        center.show(reading)
    }

    /// Keys also cover presses that do not change the value (volume already at max, brightness at min).
    private func handleKey(_ event: SystemDefinedKeyEvent) {
        guard let kind = event.hudKind else { return }
        keyReadTask?.cancel()
        let sleep = self.sleep
        keyReadTask = Task { [weak self] in
            do {
                try await sleep(Self.keyReadDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.keyReadTask = nil
            guard let reading = self.reading(for: kind) else { return }
            self.center.show(reading)
        }
    }

    private func reading(for kind: HUDKind) -> HUDReading? {
        switch kind {
        case .volume:
            let reading = volume.currentReading()
            if let reading { lastVolume = reading }
            return reading
        case .brightness:
            return HUDReading(kind: .brightness, level: brightness.brightness())
        case .keyboardBacklight:
            // No public API for the backlight level; the HUD shows the icon only.
            return HUDReading(kind: .keyboardBacklight, level: nil)
        }
    }
}

extension SystemHUD {
    /// Production wiring: no HUD while paused or while a notch alert is on screen (it never interrupts one).
    static func live(settings: SettingsStore, alerts: NotchAlertCenter) -> SystemHUD {
        let hud = SystemHUD()
        hud.isBlocked = { [weak settings, weak alerts] in
            guard let settings, let alerts else { return true }
            return settings.isPaused || alerts.current != nil
        }
        return hud
    }
}
