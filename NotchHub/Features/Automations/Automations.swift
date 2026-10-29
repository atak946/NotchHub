import Foundation

/// Facade for the automation features: Focus Guard and Capture Catcher.
@MainActor
final class Automations {
    let focusGuard: FocusGuardService
    let captureCatcher: CaptureCatcherService

    convenience init(alerts: NotchAlertCenter, timer: TimerService, shelf: ShelfStore, defaults: UserDefaults = .standard) {
        self.init(
            alerts: alerts,
            timer: timer,
            shelf: shelf,
            defaults: defaults,
            workspace: SystemFocusWorkspace(),
            watcher: FSEventsCaptureWatcher()
        )
    }

    init(
        alerts: NotchAlertCenter,
        timer: TimerService,
        shelf: ShelfStore,
        defaults: UserDefaults,
        workspace: any FocusWorkspace,
        watcher: any CaptureFileWatching,
        probe: any CaptureFileProbing = SystemCaptureFileProbe(),
        folders: CaptureFolderResolver = CaptureFolderResolver()
    ) {
        focusGuard = FocusGuardService(
            alerts: alerts,
            timerSnapshot: { [weak timer] in Self.snapshot(of: timer) },
            workspace: workspace,
            defaults: defaults
        )
        captureCatcher = CaptureCatcherService(
            alerts: alerts,
            addToShelf: { [weak shelf] urls in shelf?.add(fileURLs: urls) },
            watcher: watcher,
            probe: probe,
            folders: folders,
            defaults: defaults
        )
    }

    /// Idempotent. Each service only observes while its own "enabled" setting is on.
    func start() {
        focusGuard.start()
        captureCatcher.start()
    }

    func stop() {
        focusGuard.stop()
        captureCatcher.stop()
    }

    static func snapshot(of timer: TimerService?) -> FocusTimerSnapshot {
        guard let timer else { return FocusTimerSnapshot(state: .idle, remaining: 0, phaseDuration: 0) }
        return FocusTimerSnapshot(state: timer.state, remaining: timer.remaining, phaseDuration: timer.phaseDuration)
    }
}
