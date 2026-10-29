import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    static let hoverDelayRange: ClosedRange<Double> = 0...0.6
    static let defaultHoverDelay = 0.15

    private enum Keys {
        static let hoverDelay = "hoverDelay"
        static let displayMode = "displayMode"
        static let hideInFullScreen = "hideInFullScreen"
        static let showOnScreensWithoutNotch = "showOnScreensWithoutNotch"
        static let theme = "theme"
        static let enabledModules = "enabledModules"
        static let knownModules = "knownModules"
        static let alertsEnabled = "alertsEnabled"
        static let showTrackChangeAlerts = "showTrackChangeAlerts"
        static let showsCompactMediaControls = "showsCompactMediaControls"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Seconds the pointer must rest on the notch before the panel opens.
    var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    var hideInFullScreen: Bool {
        didSet { defaults.set(hideInFullScreen, forKey: Keys.hideInFullScreen) }
    }

    var showOnScreensWithoutNotch: Bool {
        didSet { defaults.set(showOnScreensWithoutNotch, forKey: Keys.showOnScreensWithoutNotch) }
    }

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    private(set) var enabledModules: Set<NotchModule> {
        didSet { defaults.set(enabledModules.map(\.rawValue).sorted(), forKey: Keys.enabledModules) }
    }

    /// Animated banners from the notch for reminders, finished timers and so on.
    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var showTrackChangeAlerts: Bool {
        didSet { defaults.set(showTrackChangeAlerts, forKey: Keys.showTrackChangeAlerts) }
    }

    /// Previous / play-pause / next beside the closed notch while a track is active.
    var showsCompactMediaControls: Bool {
        didSet { defaults.set(showsCompactMediaControls, forKey: Keys.showsCompactMediaControls) }
    }

    /// Session-only: hides every panel until resumed.
    var isPaused = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedDelay = defaults.object(forKey: Keys.hoverDelay) as? Double ?? Self.defaultHoverDelay
        hoverDelay = min(max(storedDelay, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        displayMode = defaults.string(forKey: Keys.displayMode).flatMap(DisplayMode.init) ?? .builtIn
        hideInFullScreen = defaults.object(forKey: Keys.hideInFullScreen) as? Bool ?? true
        showOnScreensWithoutNotch = defaults.object(forKey: Keys.showOnScreensWithoutNotch) as? Bool ?? true
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init) ?? .dark
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        showTrackChangeAlerts = defaults.object(forKey: Keys.showTrackChangeAlerts) as? Bool ?? true
        showsCompactMediaControls = defaults.object(forKey: Keys.showsCompactMediaControls) as? Bool ?? true

        if let stored = defaults.stringArray(forKey: Keys.enabledModules) {
            let known = defaults.stringArray(forKey: Keys.knownModules).map { Set($0.compactMap(NotchModule.init)) }
                ?? Self.modulesBeforeTracking
            let added = Set(NotchModule.allCases).subtracting(known)
            enabledModules = Set(stored.compactMap(NotchModule.init)).union(added)
        } else {
            enabledModules = Set(NotchModule.allCases)
        }
        defaults.set(NotchModule.allCases.map(\.rawValue), forKey: Keys.knownModules)
    }

    /// Modules that shipped before `knownModules` was tracked; anything newer starts enabled.
    private static let modulesBeforeTracking: Set<NotchModule> = [.shelf, .media, .timer, .calendar, .status]

    func isEnabled(_ module: NotchModule) -> Bool {
        enabledModules.contains(module)
    }

    func setModule(_ module: NotchModule, enabled: Bool) {
        enabledModules = enabled ? enabledModules.union([module]) : enabledModules.subtracting([module])
    }
}
