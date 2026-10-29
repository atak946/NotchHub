import Foundation

/// Panel control the intents need; `NotchWindowManager` provides it.
@MainActor
protocol IntentPanelPresenting: AnyObject {
    var isPanelExpanded: Bool { get }
    func present(_ module: NotchModule)
    func togglePanel()
}

extension NotchWindowManager: IntentPanelPresenting {}

/// Routes intents to the real, in-process services.
@MainActor
final class LiveIntentRoutes: IntentRouting {
    static let alertAppName = "Kestirmeler"

    private let services: ModuleServices
    private let settings: SettingsStore
    private let alerts: NotchAlertCenter
    private weak var panel: (any IntentPanelPresenting)?

    init(services: ModuleServices, settings: SettingsStore, alerts: NotchAlertCenter, panel: any IntentPanelPresenting) {
        self.services = services
        self.settings = settings
        self.alerts = alerts
        self.panel = panel
    }

    func isModuleEnabled(_ module: NotchModule) -> Bool {
        settings.isEnabled(module)
    }

    var canPostAlerts: Bool {
        settings.alertsEnabled && !settings.isPaused
    }

    var profiles: [IntentProfile] {
        services.profiles.store.profiles.map { IntentProfile(id: $0.id, name: $0.displayName) }
    }

    func startTimer(duration: TimeInterval) {
        services.timer.start(duration: duration)
    }

    func addNote(text: String) {
        let note = services.notes.createNote()
        services.notes.updateBody(text, for: note.id)
    }

    func runProfile(id: UUID) -> Bool {
        let service = services.profiles.service
        guard !service.isRunning else { return false }
        // A profile without steps finishes immediately (and reports so in the notch).
        service.activate(id)
        return true
    }

    func postAlert(title: String, message: String?, style: NotchAlert.Style) {
        alerts.post(NotchAlert(
            module: nil,
            systemImage: Self.systemImage(for: style),
            title: title,
            subtitle: message,
            style: style,
            autoDismissAfter: style.pulses ? NotchAlert.importantDuration : NotchAlert.defaultDuration,
            appName: Self.alertAppName
        ))
    }

    func open(_ module: NotchModule) {
        panel?.present(module)
    }

    /// Closes the panel when it is open, otherwise opens it on `module`.
    func toggle(_ module: NotchModule) {
        guard let panel else { return }
        if panel.isPanelExpanded {
            panel.togglePanel()
        } else {
            panel.present(module)
        }
    }

    var isMicMuteAvailable: Bool {
        let micMute = services.system.micMute
        return micMute.isStarted && micMute.isAvailable
    }

    func toggleMicMute() -> Bool {
        let micMute = services.system.micMute
        micMute.toggle()
        return micMute.isMuted
    }

    static func systemImage(for style: NotchAlert.Style) -> String {
        switch style {
        case .info: "info.circle.fill"
        case .reminder: "bell.fill"
        case .success: "checkmark.circle.fill"
        case .urgent: "exclamationmark.triangle.fill"
        }
    }
}
