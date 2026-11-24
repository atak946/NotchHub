import CoreGraphics
import Foundation

/// What is known about an icon's click, so the next one takes the short way. Windows need no entry.
enum MenuBarOpenStrategy: String, Sendable {
    /// Opens a menu that is shown as a copy below the chevron.
    case copyMenu
    /// Opens something that can neither be moved nor copied, so the icon has to be on screen.
    case reveal
}

/// Persisted strategy per bundle identifier and mouse button.
struct MenuBarStrategyStore {
    private static let key = "MenuBarContainer.strategies"

    private let defaults: UserDefaults
    private var rawValues: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        rawValues = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    subscript(bundleID: String?, button: CGMouseButton) -> MenuBarOpenStrategy? {
        get { bundleID.flatMap { rawValues[Self.entry($0, button)] }.flatMap(MenuBarOpenStrategy.init) }
        set {
            guard let bundleID else { return }
            rawValues[Self.entry(bundleID, button)] = newValue?.rawValue
            defaults.set(rawValues, forKey: Self.key)
        }
    }

    private static func entry(_ bundleID: String, _ button: CGMouseButton) -> String {
        button == .left ? bundleID : "\(bundleID)#right"
    }
}
