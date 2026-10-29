import Foundation

/// Creates and resolves persistent file references. The app is not sandboxed,
/// so regular (non security-scoped) bookmarks are enough.
protocol ShelfBookmarking: Sendable {
    func bookmarkData(for url: URL) throws -> Data
    /// Returns `nil` when the file can no longer be located.
    func resolve(_ bookmark: Data) -> ShelfResolvedBookmark?
}

struct ShelfResolvedBookmark: Equatable, Sendable {
    let url: URL
    let isStale: Bool
}

struct FileBookmarker: ShelfBookmarking {
    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ bookmark: Data) -> ShelfResolvedBookmark? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return ShelfResolvedBookmark(url: url, isStale: isStale)
    }
}
