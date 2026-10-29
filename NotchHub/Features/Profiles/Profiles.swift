import Foundation
import Observation

/// Facade for the Profiles feature: client profiles (runner + launcher) and remote-session awareness.
/// Integrator: create once, call `start()` / `stop()` with the module, place the views below.
@MainActor
final class Profiles {
    let store: ProfilesStore
    let service: ProfilesService
    let remoteMonitor: RemoteSessionMonitor

    private var isStarted = false

    init(alerts: NotchAlertCenter, defaults: UserDefaults = .standard) {
        let store = ProfilesStore(defaults: defaults)
        self.store = store
        service = ProfilesService(store: store, alerts: alerts)
        remoteMonitor = RemoteSessionMonitor(store: store, alerts: alerts)
    }

    /// Internal seam for tests.
    init(store: ProfilesStore, service: ProfilesService, remoteMonitor: RemoteSessionMonitor) {
        self.store = store
        self.service = service
        self.remoteMonitor = remoteMonitor
    }

    /// Starts remote-session polling. Profiles themselves only run on demand. Idempotent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        remoteMonitor.start()
    }

    /// Stops polling and cancels a running profile. Idempotent.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        remoteMonitor.stop()
        service.stop()
    }

    /// True while a remote session is detected or a profile run is in progress.
    var hasCompactIndicator: Bool {
        remoteMonitor.hasCompactIndicator || service.isRunning
    }
}
