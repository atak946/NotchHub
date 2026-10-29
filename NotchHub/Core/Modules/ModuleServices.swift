import Observation

/// Shared feature services (one instance for all displays), started and stopped with module toggles.
@MainActor
final class ModuleServices {
    let shelf: ShelfStore
    /// Clipboard history shown in the shelf's "Pano" segment; runs with the shelf module.
    let clipboard: ClipboardHistoryStore
    let media: MediaService
    let audio: AudioOutputService
    let timer: TimerService
    let calendar: CalendarService
    let notes: NoteStore
    /// Quick calculation and conversion in the Notes module's "Hesap" segment.
    let calculator: QuickCalcService

    // Background monitors shown in the Status tab.
    let system: SystemMonitors
    let devOps: DevOpsMonitors
    let automations: Automations
    let insights: Insights
    let profiles: Profiles
    /// External alert API (URL scheme + socket); runs regardless of module toggles.
    let externalAlerts: ExternalAlertService
    /// Volume/brightness level HUD in the notch; runs regardless of module toggles.
    let hud: SystemHUD
    /// Pre-meeting camera mirror and its reminder.
    let cameraMirror: CameraMirror
    /// Weather beside the header clock; runs with its own setting, regardless of module toggles.
    let weather: WeatherService
    /// Charging / unplug / low-battery presentations in the notch; runs regardless of module toggles.
    let charging: ChargingPresenter

    private let settings: SettingsStore
    private var runningModules: Set<NotchModule> = []

    /// `core` defaults to the live services; screenshot rendering passes demo ones (see `ModuleCoreServices`).
    init(settings: SettingsStore, alerts: NotchAlertCenter, core: ModuleCoreServices? = nil) {
        let core = core ?? ModuleCoreServices.live()
        let defaults = core.defaults
        self.settings = settings
        shelf = core.shelf
        clipboard = core.clipboard
        media = core.media
        audio = core.audio
        timer = core.timer
        calendar = core.calendar
        notes = core.notes
        calculator = core.calculator
        weather = core.weather
        system = SystemMonitors(alerts: alerts, media: core.media, calendar: core.calendar, defaults: defaults)
        devOps = DevOpsMonitors(alerts: alerts, defaults: defaults)
        automations = Automations(alerts: alerts, timer: core.timer, shelf: core.shelf, defaults: defaults)
        insights = Insights(alerts: alerts, defaults: defaults)
        profiles = Profiles(alerts: alerts, defaults: defaults)
        let noteContext = LiveNoteContextProvider(calendar: core.calendar, profiles: profiles.store)
        core.notes.contextProvider = { noteContext.context(at: $0) }
        externalAlerts = ExternalAlertService(alerts: alerts, defaults: defaults)
        hud = SystemHUD.live(settings: settings, alerts: alerts, permission: insights.permission)
        cameraMirror = CameraMirror.live(settings: settings, alerts: alerts, calendar: core.calendar)
        charging = ChargingPresenter(alerts: alerts, defaults: defaults)
        // Native banners are only taken over (and closed) while notch alerts can actually be shown.
        insights.mirror.shouldPostAlert = { [weak settings] in
            guard let settings else { return false }
            return settings.alertsEnabled && !settings.isPaused && settings.isEnabled(.status)
        }
        let canPostSystemAlert: @MainActor () -> Bool = { [weak settings] in
            guard let settings else { return false }
            return settings.alertsEnabled && !settings.isPaused
        }
        system.micMute.canPostAlert = canPostSystemAlert
        system.headphones.canPostAlert = canPostSystemAlert
        charging.canPostAlert = canPostSystemAlert
    }

    var hasCompactMedia: Bool {
        settings.isEnabled(.media) && media.hasCompactContent
    }

    var hasCompactTimer: Bool {
        settings.isEnabled(.timer) && timer.hasCompactContent
    }

    var hasCompactIndicators: Bool {
        settings.isEnabled(.status) && (
            system.hasCompactIndicator
                || devOps.hasCompactIndicator
                || insights.hasCompactIndicator
                || profiles.hasCompactIndicator
        )
    }

    func start() {
        externalAlerts.start()
        system.micMute.start()
        hud.start()
        cameraMirror.start()
        weather.start()
        charging.start()
        applyModuleStates()
        trackModuleToggles()
    }

    func stop() {
        externalAlerts.stop()
        // Restores a microphone NotchHub muted, so quitting never leaves it silenced.
        system.micMute.stop()
        hud.stop()
        cameraMirror.stop()
        weather.stop()
        charging.stop()
        for module in runningModules {
            stop(module)
        }
        runningModules = []
    }

    private func trackModuleToggles() {
        withObservationTracking {
            _ = settings.enabledModules
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyModuleStates()
                self?.trackModuleToggles()
            }
        }
    }

    private func applyModuleStates() {
        for module in NotchModule.allCases {
            let shouldRun = settings.isEnabled(module)
            let isRunning = runningModules.contains(module)
            if shouldRun, !isRunning {
                start(module)
                runningModules.insert(module)
            } else if !shouldRun, isRunning {
                stop(module)
                runningModules.remove(module)
            }
        }
    }

    private func start(_ module: NotchModule) {
        switch module {
        case .shelf:
            shelf.start()
            clipboard.start()
        case .media:
            media.start()
            audio.start()
        case .timer:
            break
        case .calendar:
            calendar.start()
        case .notes:
            notes.start()
        case .status:
            system.start()
            devOps.start()
            automations.start()
            insights.start()
            profiles.start()
        }
    }

    private func stop(_ module: NotchModule) {
        switch module {
        case .shelf:
            shelf.stop()
            clipboard.stop()
        case .timer:
            timer.cancel()
        case .media:
            media.stop()
            audio.stop()
        case .calendar:
            calendar.stop()
        case .notes:
            notes.stop()
        case .status:
            system.stop()
            devOps.stop()
            automations.stop()
            insights.stop()
            profiles.stop()
        }
    }
}
