import Observation
import OSLog

/// Registers the user's "show / hide the notch" shortcut and re-registers whenever it changes.
/// Hiding uses the session pause, the same state as "NotchHub'ı Duraklat".
@MainActor
final class NotchVisibilityHotKey {
    /// Distinct from the panel (1) and mic mute (2) hot keys.
    static let hotKeyID: UInt32 = 3

    private let settings: SettingsStore
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HotKey")
    private var hotKey: GlobalHotKey?
    private var registered: HotKeyShortcut?
    private var isStarted = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        applySetting()
    }

    func stop() {
        isStarted = false
        unregister()
    }

    private func applySetting() {
        let shortcut = withObservationTracking {
            settings.notchToggleShortcut
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.applySetting()
            }
        }
        guard shortcut != registered else { return }
        unregister()
        if let shortcut { register(shortcut) }
    }

    private func register(_ shortcut: HotKeyShortcut) {
        let hotKey = GlobalHotKey(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers,
            id: Self.hotKeyID
        ) { [weak settings] in
            settings?.isPaused.toggle()
        }
        guard hotKey.register() else {
            logger.error("Failed to register notch visibility hot key \(shortcut.displayName, privacy: .public)")
            return
        }
        self.hotKey = hotKey
        registered = shortcut
    }

    private func unregister() {
        hotKey?.unregister()
        hotKey = nil
        registered = nil
    }
}
