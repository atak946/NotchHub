import CoreFoundation
import Foundation

/// Reads other apps' preference values (screenshot location, Shottr save folder).
protocol CapturePreferencesReading {
    func string(forKey key: String, domain: String) -> String?
}

struct SystemCapturePreferences: CapturePreferencesReading {
    func string(forKey key: String, domain: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }
}

/// Works out which folders Capture Catcher watches.
struct CaptureFolderResolver {
    static let screenCaptureDomain = "com.apple.screencapture"
    static let screenCaptureKey = "location"
    /// Shottr stores its "save to" folder here (empty string when unset). Heuristic: undocumented key.
    static let shottrDomain = "cc.ffitch.shottr"
    static let shottrKey = "defaultFolder"

    let preferences: any CapturePreferencesReading
    let homeDirectory: URL
    let isDirectory: (String) -> Bool

    init(
        preferences: any CapturePreferencesReading = SystemCapturePreferences(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isDirectory: @escaping (String) -> Bool = CaptureFolderResolver.directoryExists
    ) {
        self.preferences = preferences
        self.homeDirectory = homeDirectory
        self.isDirectory = isDirectory
    }

    var desktopFolder: String { CaptureClassifier.normalized(homeDirectory.appending(path: "Desktop").path) }
    var downloadsFolder: String { CaptureClassifier.normalized(homeDirectory.appending(path: "Downloads").path) }

    /// macOS screenshot location (`defaults read com.apple.screencapture location`), falling back to ~/Desktop.
    var systemScreenshotFolder: String {
        resolvedFolder(preferences.string(forKey: Self.screenCaptureKey, domain: Self.screenCaptureDomain))
            ?? desktopFolder
    }

    var shottrFolder: String? {
        resolvedFolder(preferences.string(forKey: Self.shottrKey, domain: Self.shottrDomain))
    }

    func screenshotFolders(customFolder: String?) -> [String] {
        let candidates = [systemScreenshotFolder, shottrFolder, resolvedFolder(customFolder)].compactMap { $0 }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    func config(watchScreenshots: Bool, watchDownloads: Bool, customFolder: String?, includeSubfolders: Bool)
        -> CaptureWatchConfig {
        CaptureWatchConfig(
            screenshotFolders: watchScreenshots ? screenshotFolders(customFolder: customFolder) : [],
            downloadFolders: watchDownloads && isDirectory(downloadsFolder) ? [downloadsFolder] : [],
            includeSubfolders: includeSubfolders
        )
    }

    /// Folders protected by TCC ("Files and Folders") that watching will touch.
    func protectedFolders(in config: CaptureWatchConfig) -> [String] {
        let protectedRoots = ["Desktop", "Downloads", "Documents"].map {
            CaptureClassifier.normalized(homeDirectory.appending(path: $0).path)
        }
        return config.allFolders.filter { folder in
            protectedRoots.contains { folder == $0 || folder.hasPrefix($0 + "/") }
        }
    }

    /// Accepts plain paths, `~/…` and `file://` URLs; returns `nil` unless it is an existing directory.
    func resolvedFolder(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let path: String
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            path = url.path
        } else if raw == "~" || raw.hasPrefix("~/") {
            path = homeDirectory.path + raw.dropFirst()
        } else {
            path = raw
        }
        guard path.hasPrefix("/") else { return nil }
        let normalized = CaptureClassifier.normalized(path)
        return isDirectory(normalized) ? normalized : nil
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
