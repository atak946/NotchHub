import Foundation

/// One `.ips` file on disk.
struct CrashReportFile: Equatable, Sendable {
    let url: URL
    let modified: Date

    var name: String { url.lastPathComponent }
}

/// Lists candidate report files; faked in tests.
protocol CrashReportListing: Sendable {
    func files(in directory: URL) throws -> [CrashReportFile]
    func contents(of file: URL) throws -> String
}

struct FileManagerCrashReportLister: CrashReportListing {
    func files(in directory: URL) throws -> [CrashReportFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { return nil }
            return CrashReportFile(url: url, modified: modified)
        }
    }

    func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}

/// Persisted launch bookkeeping: last launch time, the "running" sentinel and handled report names.
final class CrashReportLedger {
    static let maxHandledNames = 50
    static let promptEnabledKey = "crashReports.promptEnabled"

    private enum Keys {
        static let lastLaunch = "crashReports.lastLaunch"
        static let isRunning = "crashReports.isRunning"
        static let handled = "crashReports.handledNames"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "Çökme sonrası rapor öner"; on by default.
    var isPromptEnabled: Bool {
        defaults.object(forKey: Self.promptEnabledKey) as? Bool ?? true
    }

    var lastLaunch: Date? {
        defaults.object(forKey: Keys.lastLaunch) as? Date
    }

    /// `true` when the previous run never reached a clean exit (crash, force quit or power loss).
    var wasRunning: Bool {
        defaults.bool(forKey: Keys.isRunning)
    }

    var handledNames: [String] {
        defaults.stringArray(forKey: Keys.handled) ?? []
    }

    func recordLaunch(at date: Date) {
        defaults.set(date, forKey: Keys.lastLaunch)
        defaults.set(true, forKey: Keys.isRunning)
    }

    func recordCleanExit() {
        defaults.set(false, forKey: Keys.isRunning)
    }

    func markHandled(_ name: String) {
        guard !handledNames.contains(name) else { return }
        let updated = Array((handledNames + [name]).suffix(Self.maxHandledNames))
        defaults.set(updated, forKey: Keys.handled)
    }
}

/// Finds this app's newest unhandled crash report written since the previous launch.
struct CrashReportLocator {
    let directories: [URL]
    let processName: String
    let lister: any CrashReportListing

    static var liveDirectories: [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        return [base, base.appending(path: "Retired", directoryHint: .isDirectory)]
    }

    /// `NotchHub-2026-10-29-192744.ips` or `NotchHub.ips`, but not `NotchHubHelper-….ips`.
    func isOwnReport(_ name: String) -> Bool {
        guard name.hasSuffix(".ips"), name.hasPrefix(processName) else { return false }
        let rest = name.dropFirst(processName.count)
        return rest.hasPrefix("-") || rest.hasPrefix(".")
    }

    /// `nil` before the first recorded launch, so reports from older installs never prompt.
    func newestUnhandled(since lastLaunch: Date?, handled: [String]) -> CrashReportFile? {
        guard let lastLaunch else { return nil }
        let handledSet = Set(handled)
        return directories
            .flatMap { (try? lister.files(in: $0)) ?? [] }
            .filter { isOwnReport($0.name) && $0.modified > lastLaunch && !handledSet.contains($0.name) }
            .max { $0.modified < $1.modified }
    }
}
