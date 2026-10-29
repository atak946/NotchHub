import AppKit
import Observation

/// Decides which displays get a notch panel and keeps them in sync with settings and screen changes.
@MainActor
final class NotchWindowManager {
    private let settings: SettingsStore
    private let fullScreenDetector: FullScreenDetector
    private let services: ModuleServices
    private let alerts: NotchAlertCenter
    private var controllers: [CGDirectDisplayID: NotchController] = [:]
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private var isStarted = false

    init(
        settings: SettingsStore,
        fullScreenDetector: FullScreenDetector,
        services: ModuleServices,
        alerts: NotchAlertCenter
    ) {
        self.settings = settings
        self.fullScreenDetector = fullScreenDetector
        self.services = services
        self.alerts = alerts
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // The camera mirror opens on the notch under the mouse, like modules opened from alerts.
        services.cameraMirror.service.displayResolver = { [weak self] in
            // Never run the camera behind a hidden notch (paused or full screen).
            guard let controller = self?.activeController(), controller.isVisible else { return nil }
            return controller.displayID
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
        installFollowMouseMonitors()
        trackLayoutSettings()
        trackVisibility()
        rebuild()
    }

    /// Toggles the panel on the display under the mouse, falling back to any active panel.
    func togglePanel() {
        activeController()?.toggle()
    }

    /// Whether the panel on the display under the mouse (or any active panel) is open.
    var isPanelExpanded: Bool {
        activeController()?.isExpanded ?? false
    }

    /// Opens the panel on a module on the display under the mouse (e.g. from an alert action).
    func present(_ module: NotchModule) {
        activeController()?.open(module, makeKey: false)
    }

    /// Opens the camera mirror on the display under the mouse (menu bar "Ayna").
    func openCameraMirror() {
        services.cameraMirror.service.open()
    }

    private func activeController() -> NotchController? {
        let mouseDisplay = NSScreen.screen(containing: NSEvent.mouseLocation)?.displayID
        return mouseDisplay.flatMap { controllers[$0] } ?? controllers.values.first
    }

    // MARK: - Observation

    private func trackLayoutSettings() {
        withObservationTracking {
            _ = settings.displayMode
            _ = settings.showOnScreensWithoutNotch
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuild()
                self?.trackLayoutSettings()
            }
        }
    }

    private func trackVisibility() {
        withObservationTracking {
            _ = settings.isPaused
            _ = settings.hideInFullScreen
            _ = fullScreenDetector.fullScreenDisplayIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateVisibility()
                self?.trackVisibility()
            }
        }
    }

    private func installFollowMouseMonitors() {
        let handler: @MainActor () -> Void = { [weak self] in self?.followMouseIfNeeded() }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in
            MainActor.assumeIsolated { handler() }
        }) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            MainActor.assumeIsolated { handler() }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
    }

    private func followMouseIfNeeded() {
        guard settings.displayMode == .followMouse,
              let displayID = NSScreen.screen(containing: NSEvent.mouseLocation)?.displayID,
              controllers[displayID] == nil
        else { return }
        rebuild()
    }

    // MARK: - Layout

    private func rebuild() {
        let targets = targetScreens()
        let targetIDs = Set(targets.compactMap(\.displayID))

        for (displayID, controller) in controllers where !targetIDs.contains(displayID) {
            controller.tearDown()
            controllers[displayID] = nil
        }

        for screen in targets {
            guard let displayID = screen.displayID else { continue }
            if let controller = controllers[displayID] {
                controller.update(screen: screen)
            } else {
                controllers[displayID] = NotchController(
                    screen: screen,
                    displayID: displayID,
                    settings: settings,
                    services: services,
                    alerts: alerts
                )
            }
        }
        updateVisibility()
    }

    private func updateVisibility() {
        for (displayID, controller) in controllers {
            let isFullScreen = fullScreenDetector.fullScreenDisplayIDs.contains(displayID)
            let shouldHide = settings.isPaused || (settings.hideInFullScreen && isFullScreen)
            if shouldHide {
                controller.hide()
            } else {
                controller.show()
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        let candidates = settings.showOnScreensWithoutNotch
            ? screens
            : screens.filter { $0.notchGeometry.hasPhysicalNotch }

        switch settings.displayMode {
        case .allScreens:
            return candidates
        case .builtIn:
            let builtIn = candidates.filter(\.isBuiltIn)
            return builtIn.isEmpty ? Array(candidates.prefix(1)) : builtIn
        case .main:
            guard let main = screens.first, candidates.contains(main) else {
                return Array(candidates.prefix(1))
            }
            return [main]
        case .followMouse:
            let mouseScreen = NSScreen.screen(containing: NSEvent.mouseLocation)
            if let mouseScreen, candidates.contains(mouseScreen) {
                return [mouseScreen]
            }
            return Array(candidates.prefix(1))
        }
    }
}
