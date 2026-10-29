import Foundation

/// Folders to watch and how strictly to filter them. Paths are standardized absolute paths without a trailing slash.
struct CaptureWatchConfig: Equatable, Sendable {
    var screenshotFolders: [String]
    var downloadFolders: [String]
    var includeSubfolders = false

    var allFolders: [String] {
        var seen = Set<String>()
        return (screenshotFolders + downloadFolders).filter { seen.insert($0).inserted }
    }
}

/// Turns raw file events into finished screenshots / downloads.
///
/// A path becomes *pending* when it is created or renamed into place with a final (non-temp, non-hidden) name.
/// `poll` confirms it once its size is non-zero, unchanged for `stableInterval` and no in-progress sibling
/// (`name.part`, `name.crdownload`, `name.download`) exists.
struct CaptureClassifier {
    static let stableInterval: TimeInterval = 1
    /// A screenshot must have been created this recently (moving an old image onto the Desktop is not a capture).
    static let screenshotMaxAge: TimeInterval = 5
    /// Older files that merely appear (moved in, edited, coalesced events) are not downloads.
    static let downloadMaxAge: TimeInterval = 6 * 3600
    static let maxPendingAge: TimeInterval = 2 * 3600
    static let maxPendingCount = 200

    static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
    static let tempExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "tmp", "temp", "opdownload", "filepart", "aria2", "!ut",
    ]
    static let tempSiblingSuffixes = [".part", ".crdownload", ".download", ".opdownload"]

    private struct Pending {
        let kind: CaptureKind
        let firstSeen: Date
        var lastSize: Int64
        var lastChange: Date
    }

    var config: CaptureWatchConfig {
        didSet { pending = [:] }
    }

    private var pending: [String: Pending] = [:]

    init(config: CaptureWatchConfig) {
        self.config = config
    }

    var hasPending: Bool { !pending.isEmpty }
    var pendingPaths: Set<String> { Set(pending.keys) }

    // MARK: - Ingest

    mutating func ingest(_ events: [CaptureFileEvent], now: Date, probe: any CaptureFileProbing) {
        for event in events {
            ingest(event, now: now, probe: probe)
        }
    }

    private mutating func ingest(_ event: CaptureFileEvent, now: Date, probe: any CaptureFileProbing) {
        let path = Self.normalized(event.path)
        let isTracked = pending[path] != nil
        guard isTracked || Self.isWatched(path, in: config.allFolders, includeSubfolders: config.includeSubfolders) else {
            return
        }
        guard let info = probe.info(atPath: path), info.isRegularFile else {
            pending[path] = nil
            return
        }
        if var existing = pending[path] {
            if existing.lastSize != info.size {
                existing.lastSize = info.size
                existing.lastChange = now
                pending[path] = existing
            }
            return
        }
        guard event.flags.contains(.created) || event.flags.contains(.renamed),
              !event.flags.contains(.isDirectory),
              pending.count < Self.maxPendingCount,
              let kind = classify(path: path, info: info, now: now)
        else { return }
        pending[path] = Pending(kind: kind, firstSeen: now, lastSize: info.size, lastChange: now)
    }

    /// Screenshot (recent image in a screenshot folder) wins over download when both folders coincide.
    func classify(path: String, info: CaptureFileInfo, now: Date) -> CaptureKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        if Self.isWatched(path, in: config.screenshotFolders, includeSubfolders: config.includeSubfolders),
           Self.screenshotExtensions.contains(ext),
           Self.isRecent(info.creationDate, now: now, maxAge: Self.screenshotMaxAge) {
            return .screenshot
        }
        if Self.isWatched(path, in: config.downloadFolders, includeSubfolders: config.includeSubfolders),
           Self.isRecent(info.creationDate, now: now, maxAge: Self.downloadMaxAge) {
            return .download
        }
        return nil
    }

    // MARK: - Poll

    /// Confirms pending files whose size has settled; call periodically while `hasPending`.
    mutating func poll(now: Date, probe: any CaptureFileProbing) -> [CaptureDetection] {
        var confirmed: [CaptureDetection] = []
        for (path, item) in pending.sorted(by: { $0.value.firstSeen < $1.value.firstSeen }) {
            guard let info = probe.info(atPath: path), info.isRegularFile,
                  now.timeIntervalSince(item.firstSeen) < Self.maxPendingAge
            else {
                pending[path] = nil
                continue
            }
            if info.size != item.lastSize {
                pending[path] = Pending(kind: item.kind, firstSeen: item.firstSeen, lastSize: info.size, lastChange: now)
                continue
            }
            guard info.size > 0,
                  now.timeIntervalSince(item.lastChange) >= Self.stableInterval,
                  !Self.hasInProgressSibling(path, probe: probe)
            else { continue }
            pending[path] = nil
            confirmed.append(CaptureDetection(url: URL(filePath: path), kind: item.kind))
        }
        return confirmed
    }

    // MARK: - Name rules

    static func isIgnoredName(_ name: String) -> Bool {
        if name.isEmpty || name.hasPrefix(".") || name.hasPrefix("~$") || name.hasPrefix("Icon\r") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return tempExtensions.contains(ext)
    }

    static func isWatched(_ path: String, in folders: [String], includeSubfolders: Bool) -> Bool {
        folders.contains { folder in
            guard path.hasPrefix(folder + "/") else { return false }
            let relative = path.dropFirst(folder.count + 1).split(separator: "/").map(String.init)
            guard let name = relative.last, includeSubfolders || relative.count == 1 else { return false }
            return !isIgnoredName(name) && relative.dropLast().allSatisfy { !isIgnoredName($0) }
        }
    }

    static func hasInProgressSibling(_ path: String, probe: any CaptureFileProbing) -> Bool {
        tempSiblingSuffixes.contains { probe.exists(atPath: path + $0) }
    }

    static func normalized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    private static func isRecent(_ date: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let date else { return true }
        // Dates slightly in the future (clock skew) count as recent.
        return now.timeIntervalSince(date) <= maxAge
    }
}
