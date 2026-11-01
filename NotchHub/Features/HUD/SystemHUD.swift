import Foundation
import Observation

/// Volume and brightness HUD in the notch: wires the level sources to `NotchHUDCenter` behind one setting.
@MainActor
@Observable
final class SystemHUD {
    static let enabledKey = "hud.enabled"
    static let hidesSystemHUDKey = "hud.hideSystemHUD"
    static let volumeStepKey = "hud.volumeStep"
    static let interactiveKey = "hud.interactive"
    /// Lets the system apply the key press before the level is read back.
    static let keyReadDelay: Duration = .milliseconds(60)
    /// Scrolls within this window build on the level just written, not on a reading still in flight.
    static let adjustmentWindow: Duration = .milliseconds(500)

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

    /// "macOS ses/parlaklık kutusunu gizle" (default on): NotchHub handles the keys itself. Needs `isEnabled`.
    var hidesSystemHUD: Bool {
        didSet {
            guard hidesSystemHUD != oldValue else { return }
            defaults.set(hidesSystemHUD, forKey: Self.hidesSystemHUDKey)
            updateInterception()
        }
    }

    /// "Ses tuşu adımı" (default: the macOS grid). Applies to volume keys NotchHub performs itself.
    var volumeStep: VolumeKeyStep {
        didSet {
            guard volumeStep != oldValue else { return }
            defaults.set(volumeStep.rawValue, forKey: Self.volumeStepKey)
        }
    }

    /// "Göstergede kaydırarak veya sürükleyerek ayarla" (default on).
    var isInteractive: Bool {
        didSet {
            guard isInteractive != oldValue else { return }
            defaults.set(isInteractive, forKey: Self.interactiveKey)
            if !isInteractive { center.setHeld(false) }
        }
    }

    /// Set by the integrator: `true` while readings must be dropped (paused, or an alert is on screen).
    @ObservationIgnored var isBlocked: @MainActor () -> Bool = { false }
    /// Set by the integrator: the headphones the volume plays on, or `nil` for speakers.
    @ObservationIgnored var outputDevice: @MainActor () -> HUDOutputDevice? = { nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let volume: any HUDVolumeSource
    @ObservationIgnored private let keys: any HUDKeySource
    @ObservationIgnored private let brightness: any HUDBrightnessReading
    @ObservationIgnored private let sleep: NotchHUDCenter.Sleeper
    @ObservationIgnored private let mediaKeys: MediaKeyCoordinator?
    @ObservationIgnored private let levels: (any HUDLevelSetting)?
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var sourcesRunning = false
    @ObservationIgnored private var lastVolume: HUDReading?
    @ObservationIgnored private var keyReadTask: Task<Void, Never>?
    @ObservationIgnored private var adjustment: (kind: HUDKind, level: Double, at: ContinuousClock.Instant)?
    /// Only the newest scroll/drag write may correct the bar; older ones finish behind it.
    @ObservationIgnored private var adjustmentGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        center: NotchHUDCenter = NotchHUDCenter(),
        volume: any HUDVolumeSource = CoreAudioVolumeSource(),
        keys: any HUDKeySource = SystemDefinedKeyMonitor(),
        brightness: any HUDBrightnessReading = DisplayServicesBrightnessReader(),
        sleep: @escaping NotchHUDCenter.Sleeper = { try await Task.sleep(for: $0) },
        mediaKeys: MediaKeyCoordinator? = nil,
        levels: (any HUDLevelSetting)? = nil
    ) {
        self.defaults = defaults
        self.center = center
        self.volume = volume
        self.keys = keys
        self.brightness = brightness
        self.sleep = sleep
        self.mediaKeys = mediaKeys
        self.levels = levels
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        hidesSystemHUD = defaults.object(forKey: Self.hidesSystemHUDKey) as? Bool ?? true
        volumeStep = defaults.string(forKey: Self.volumeStepKey).flatMap(VolumeKeyStep.init(rawValue:)) ?? .system
        isInteractive = defaults.object(forKey: Self.interactiveKey) as? Bool ?? true
        center.canShow = { [weak self] in
            guard let self else { return false }
            return self.isEnabled && !self.isBlocked()
        }
        volume.onChange = { [weak self] reading in self?.handleVolume(reading) }
        keys.onKey = { [weak self] event in self?.handleKey(event) }
        mediaKeys?.onReading = { [weak self] reading in self?.handleInterceptedReading(reading) }
    }

    func start() {
        isStarted = true
        updateSources()
    }

    func stop() {
        isStarted = false
        updateSources()
    }

    // MARK: - Scroll and drag

    /// A volume/brightness HUD is up and the setting is on. Cheap (no hardware query), so hit-testing can poll it.
    var isAdjustableOnScreen: Bool {
        guard isInteractive, sourcesRunning, let current = center.current else { return false }
        return HUDInteractionMath.isAdjustable(current.kind)
    }

    /// Whether the reading on screen can be changed from the HUD right now.
    func canAdjust(_ reading: HUDReading) -> Bool {
        guard isInteractive, sourcesRunning, HUDInteractionMath.isAdjustable(reading.kind) else { return false }
        return levels?.canSetLevel(for: reading.kind) ?? false
    }

    /// Dragging the bar: the level under the pointer.
    func adjust(to level: Double) {
        guard let current = center.current, canAdjust(current) else { return }
        set(level, for: current)
    }

    /// Scrolling over the HUD, from `NSEvent.scrollingDeltaY`.
    func adjust(byScroll deltaY: Double, isPrecise: Bool, isInverted: Bool) {
        guard let current = center.current, canAdjust(current) else { return }
        let base = recentAdjustment(for: current.kind) ?? current.level ?? 0
        set(HUDInteractionMath.scrolled(base, deltaY: deltaY, isPrecise: isPrecise, isInverted: isInverted), for: current)
    }

    /// A drag holds the HUD on screen; letting go restarts its hide timer.
    func setDragging(_ isDragging: Bool) {
        center.setHeld(isDragging && isInteractive)
    }

    // MARK: - Private

    /// Every reading reaches the center through here so volume readings carry the output device.
    private func present(_ reading: HUDReading) {
        guard reading.kind == .volume, reading.output == nil else {
            center.show(reading)
            return
        }
        center.show(reading.with(output: outputDevice()))
    }

    /// Shows the new level at once, then writes it; the read-back corrects the bar if the write fell short.
    private func set(_ level: Double, for reading: HUDReading) {
        guard let levels else { return }
        let target = HUDLevel.clamped(level)
        adjustment = (reading.kind, target, clock.now)
        adjustmentGeneration += 1
        let generation = adjustmentGeneration
        let unmutes = reading.kind == .volume && target > 0
        let optimistic = HUDReading(kind: reading.kind, level: target, isMuted: unmutes ? false : reading.isMuted)
        if optimistic.kind == .volume { lastVolume = optimistic }
        present(optimistic)
        levels.setLevel(target, for: reading.kind) { [weak self] result in
            guard let self, let result, generation == self.adjustmentGeneration else { return }
            if result.kind == .volume { self.lastVolume = result }
            self.present(result)
        }
    }

    private func recentAdjustment(for kind: HUDKind) -> Double? {
        guard let adjustment, adjustment.kind == kind, clock.now - adjustment.at < Self.adjustmentWindow else { return nil }
        return adjustment.level
    }

    private func updateSources() {
        defer { updateInterception() }
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
            adjustment = nil
            center.hide()
        }
    }

    /// Media keys are only taken over while the notch HUD runs; otherwise macOS keeps them (and its HUD).
    private func updateInterception() {
        mediaKeys?.setWanted(sourcesRunning && hidesSystemHUD)
    }

    /// A key NotchHub performed itself; shown even when the level did not change (already at max/min).
    private func handleInterceptedReading(_ reading: HUDReading) {
        if reading.kind == .volume { lastVolume = reading }
        adjustment = nil
        present(reading)
    }

    private func handleVolume(_ reading: HUDReading) {
        let previous = lastVolume
        lastVolume = reading
        guard HUDLevel.isMeaningfulChange(from: previous, to: reading) else { return }
        present(reading)
    }

    /// Keys also cover presses that do not change the value (volume already at max, brightness at min).
    private func handleKey(_ event: SystemDefinedKeyEvent) {
        guard let kind = event.hudKind else { return }
        adjustment = nil
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
            self.present(reading)
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
    /// Media keys are intercepted only with Accessibility trust, re-checked silently (never prompts).
    static func live(
        settings: SettingsStore,
        alerts: NotchAlertCenter,
        permission: AccessibilityPermission,
        audio: AudioOutputService,
        headphones: HeadphoneBatteryMonitor
    ) -> SystemHUD {
        let brightness = DisplayServicesBrightnessReader()
        let controller = SystemMediaKeyController(brightness: brightness)
        let mediaKeys = MediaKeyCoordinator(
            tap: MediaKeyInterceptor(),
            controller: controller,
            isTrusted: { [weak permission] in permission?.refresh() ?? false }
        )
        let hud = SystemHUD(brightness: brightness, mediaKeys: mediaKeys, levels: controller)
        controller.volumeStep = { [weak hud] in hud?.volumeStep ?? .system }
        let outputs = HUDOutputResolver(audio: audio, headphones: headphones)
        hud.outputDevice = { outputs.current() }
        hud.isBlocked = { [weak settings, weak alerts] in
            guard let settings, let alerts else { return true }
            return settings.isPaused || alerts.current != nil
        }
        return hud
    }
}
