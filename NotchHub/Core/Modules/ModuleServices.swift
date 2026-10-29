import Observation

/// Shared feature services (one instance for all displays), started and stopped with module toggles.
@MainActor
final class ModuleServices {
    let shelf = ShelfStore()
    /// Clipboard history shown in the shelf's "Pano" segment; runs with the shelf module.
    let clipboard = ClipboardHistoryStore()
    let media = MediaService()
    let audio = AudioOutputService()
    let timer = TimerService()
    let calendar = CalendarService()
    let notes = NoteStore()

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

    private let settings: SettingsStore
    private var runningModules: Set<NotchModule> = []

    init(settings: SettingsStore, alerts: NotchAlertCenter) {
        self.settings = settings
        system = SystemMonitors(alerts: alerts, media: media, calendar: calendar)
        devOps = DevOpsMonitors(alerts: alerts)
        automations = Automations(alerts: alerts, timer: timer, shelf: shelf)
        insights = Insights(alerts: alerts)
        profiles = Profiles(alerts: alerts)
        let noteContext = LiveNoteContextProvider(calendar: calendar, profiles: profiles.store)
        notes.contextProvider = { noteContext.context(at: $0) }
        externalAlerts = ExternalAlertService(alerts: alerts)
        hud = SystemHUD.live(settings: settings, alerts: alerts, permission: insights.permission)
        cameraMirror = CameraMirror.live(settings: settings, alerts: alerts, calendar: calendar)
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
        applyModuleStates()
        trackModuleToggles()
    }

    func stop() {
        externalAlerts.stop()
        // Restores a microphone NotchHub muted, so quitting never leaves it silenced.
        system.micMute.stop()
        hud.stop()
        cameraMirror.stop()
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
