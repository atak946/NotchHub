import Foundation
import OSLog
import UniformTypeIdentifiers

/// Keeps copies of dropped files that have no on-disk original (file promises, raw data drags).
/// Each copy lives in its own folder so the original file name can be preserved.
enum ShelfDroppedFiles {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Shelf")
    private static let fallbackName = "Dropped Item"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "NotchHub/ShelfDrops", directoryHint: .isDirectory)
    }

    /// Copies `source` into the shelf's drop folder. Safe to call from any thread.
    static func copy(_ source: URL, suggestedName: String?, type: String, in root: URL = directory) -> URL? {
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let destination = folder.appending(path: fileName(for: source, suggestedName: suggestedName, type: type))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            logger.error("Cannot keep dropped file: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    /// Deletes the copy's folder when `url` is a copy owned by the shelf; other files are left untouched.
    static func removeCopy(at url: URL, in root: URL = directory) {
        let folder = url.standardizedFileURL.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func fileName(for source: URL, suggestedName: String?, type: String) -> String {
        let trimmed = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? source.lastPathComponent : trimmed
        let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = safe.isEmpty ? fallbackName : safe
        guard (name as NSString).pathExtension.isEmpty,
              let ext = UTType(type)?.preferredFilenameExtension else { return name }
        return "\(name).\(ext)"
    }
}
