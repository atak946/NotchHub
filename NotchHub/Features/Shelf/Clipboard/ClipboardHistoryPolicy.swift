import Foundation

/// Pure rules for the history list: de-duplication, entry cap and total image size budget.
struct ClipboardHistoryPolicy: Equatable, Sendable {
    static let defaultMaxEntries = 30
    static let defaultMaxImageBytes = 20 * 1024 * 1024
    static let defaultMaxTextBytes = 10 * 1024

    /// Result of inserting an entry: the new list and entries that must have their files removed.
    struct Insertion: Equatable, Sendable {
        let entries: [ClipboardEntry]
        let evicted: [ClipboardEntry]
    }

    var maxEntries = Self.defaultMaxEntries
    var maxImageBytes = Self.defaultMaxImageBytes
    var maxTextBytes = Self.defaultMaxTextBytes

    /// Puts `entry` first. An existing entry with the same fingerprint is replaced (moved to the top),
    /// then the oldest entries are dropped until both the count and the image budget fit.
    func inserting(_ entry: ClipboardEntry, into entries: [ClipboardEntry]) -> Insertion {
        let duplicates = entries.filter { $0.fingerprint == entry.fingerprint }
        let remaining = entries.filter { $0.fingerprint != entry.fingerprint }
        let trimmed = trim([entry] + remaining)
        return Insertion(entries: trimmed.kept, evicted: duplicates + trimmed.dropped)
    }

    /// Applies the caps to an already ordered (newest first) list, e.g. after loading from disk.
    func trim(_ entries: [ClipboardEntry]) -> (kept: [ClipboardEntry], dropped: [ClipboardEntry]) {
        var kept: [ClipboardEntry] = []
        var dropped: [ClipboardEntry] = []
        var imageBytes = 0
        for entry in entries {
            let nextImageBytes = imageBytes + entry.imageByteCount
            if kept.count >= maxEntries || (entry.isImage && nextImageBytes > maxImageBytes) {
                dropped.append(entry)
                continue
            }
            imageBytes = nextImageBytes
            kept.append(entry)
        }
        return (kept, dropped)
    }

    /// Trims whitespace; returns `nil` for blank text or text above `maxTextBytes` (UTF-8).
    func normalizedText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxTextBytes else { return nil }
        return trimmed
    }

    /// `false` for a single image that alone exceeds the budget.
    func acceptsImage(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= maxImageBytes
    }
}
