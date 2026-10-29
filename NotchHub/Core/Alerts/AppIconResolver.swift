import AppKit

/// Finds installed or running apps; the live implementation wraps `NSWorkspace`.
@MainActor
protocol AppLocating {
    func applicationURL(bundleID: String) -> URL?
    func runningApplicationURL(named name: String) -> URL?
    func installedApplicationURL(named name: String) -> URL?
}

/// Resolves and caches real app icons for alerts (by bundle id first, then by name).
@MainActor
final class AppIconResolver {
    static let shared = AppIconResolver()

    private static let maxBundleIDLength = 255
    private static let maxNameLength = 80

    private let locator: any AppLocating
    private let loadIcon: (URL) -> NSImage
    /// Misses are cached too, so an unknown app is looked up once per launch.
    private var cache: [String: NSImage?] = [:]

    init(
        locator: any AppLocating = WorkspaceAppLocator(),
        loadIcon: @escaping (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) }
    ) {
        self.locator = locator
        self.loadIcon = loadIcon
    }

    func icon(bundleID: String?, appName: String?) -> NSImage? {
        let key = "\(bundleID ?? "")|\(appName ?? "")"
        if let cached = cache[key] { return cached }
        let image = applicationURL(bundleID: bundleID, appName: appName).map(loadIcon)
        cache[key] = image
        return image
    }

    /// Bundle id, then a running app with that name, then an installed `<name>.app`.
    func applicationURL(bundleID: String?, appName: String?) -> URL? {
        if let bundleID = Self.validBundleID(bundleID), let url = locator.applicationURL(bundleID: bundleID) {
            return url
        }
        guard let name = Self.validName(appName) else { return nil }
        return locator.runningApplicationURL(named: name) ?? locator.installedApplicationURL(named: name)
    }

    static func validBundleID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= maxBundleIDLength else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }

    /// Names come from other apps' notifications, so path-like input is rejected.
    static func validName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNameLength,
              !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.hasPrefix(".")
        else { return nil }
        return trimmed
    }
}

struct WorkspaceAppLocator: AppLocating {
    private static let searchDirectories: [URL] = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
    ]

    func applicationURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Exact name first, then a whole-word match so "Teams" finds "Microsoft Teams".
    func runningApplicationURL(named name: String) -> URL? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL != nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let exact = apps.first { $0.localizedName?.compare(name, options: options) == .orderedSame }
        let wordMatch = apps.first { app in
            app.localizedName?.split(separator: " ").contains { $0.compare(name, options: options) == .orderedSame } ?? false
        }
        return (exact ?? wordMatch)?.bundleURL
    }

    func installedApplicationURL(named name: String) -> URL? {
        let fileManager = FileManager.default
        return Self.searchDirectories
            .map { $0.appending(path: "\(name).app", directoryHint: .isDirectory) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}
