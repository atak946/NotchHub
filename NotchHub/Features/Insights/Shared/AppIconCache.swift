import AppKit

/// Resolves and caches app icons by display/Dock name so views never hit NSWorkspace per frame.
/// Lookup order: running app with that name, known bundle id, then the standard app folders.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    /// `nil` entries remember misses so unresolvable names are not retried every render.
    private var icons: [String: NSImage?] = [:]

    func icon(forApp name: String) -> NSImage? {
        let key = name.lowercased()
        if let cached = icons[key] { return cached }
        let icon = Self.appURL(forName: name).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[key] = icon
        return icon
    }

    static func appURL(forName name: String) -> URL? {
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }), let url = running.bundleURL {
            return url
        }
        if let bundleID = KnownApps.bundleID(forName: name),
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return SystemInsightsAppActivator.installedAppURL(named: name)
    }
}
