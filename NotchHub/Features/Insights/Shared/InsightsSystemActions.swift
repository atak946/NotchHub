import OSLog
import AppKit

/// Brings an app to the front by its display name (e.g. "WhatsApp").
@MainActor
protocol InsightsAppActivating: AnyObject {
    func activate(appNamed name: String)
}

/// Writes plain text to the general pasteboard.
@MainActor
protocol InsightsPasteboard: AnyObject {
    func copy(_ text: String)
}

@MainActor
final class SystemInsightsAppActivator: InsightsAppActivating {
    static let searchDirectories = ["/Applications", "/System/Applications", "/Applications/Utilities", "/System/Applications/Utilities"]
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    func activate(appNamed name: String) {
        guard let url = Self.appURL(named: name) else {
            logger.error("No app found to open for \(name, privacy: .public)")
            return
        }
        logger.info("Opening \(url.path, privacy: .public)")
        // NSRunningApplication.activate() is ignored when requested by a background (LSUIElement) app;
        // opening the bundle through NSWorkspace brings it to the front like a Dock click.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Running app by localized name, then known bundle id, then the app folders.
    static func appURL(named name: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }), let url = running.bundleURL {
            return url
        }
        if let bundleID = KnownApps.bundleID(forName: name),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return installedAppURL(named: name) ?? localizedAppURL(named: name)
    }

    /// Matches the Finder display name, so localized names like "Betik Düzenleyici" resolve too.
    static func localizedAppURL(named name: String) -> URL? {
        let fileManager = FileManager.default
        for directory in searchDirectories {
            let apps = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for app in apps where app.hasSuffix(".app") {
                let path = (directory as NSString).appendingPathComponent(app)
                let displayName = (fileManager.displayName(atPath: path) as NSString).deletingPathExtension
                if displayName.caseInsensitiveCompare(name) == .orderedSame {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }

    /// Only plain names are accepted so a user-edited entry can never point outside the app folders.
    static func installedAppURL(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        let fileManager = FileManager.default
        return searchDirectories
            .map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app") }
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}

@MainActor
final class SystemInsightsPasteboard: InsightsPasteboard {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
