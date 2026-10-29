import Foundation

/// Files under Application Support/<bundle id>/Clipboard: `history.json` plus one PNG per image entry.
struct ClipboardHistoryStorage: Sendable {
    static let indexFileName = "history.json"
    private static let ownerOnlyPermissions = 0o700

    let directory: URL

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: AppIdentity.bundleID, directoryHint: .isDirectory)
            .appending(path: "Clipboard", directoryHint: .isDirectory)
    }

    func imageURL(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// `nil` when there is no index yet; throws when it exists but cannot be decoded.
    func loadIndex() throws -> [ClipboardEntry]? {
        let url = directory.appending(path: Self.indexFileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: url))
    }

    func saveIndex(_ entries: [ClipboardEntry]) throws {
        try ensureDirectory()
        let url = directory.appending(path: Self.indexFileName, directoryHint: .notDirectory)
        try JSONEncoder().encode(entries).write(to: url, options: [.atomic])
    }

    func writeImage(_ data: Data, fileName: String) throws {
        try ensureDirectory()
        try data.write(to: imageURL(for: fileName), options: [.atomic])
    }

    func readImage(fileName: String) -> Data? {
        try? Data(contentsOf: imageURL(for: fileName))
    }

    func deleteImage(fileName: String) {
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    /// Removes the whole folder (index and images).
    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Deletes image files that no entry refers to.
    func removeOrphans(keeping fileNames: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != Self.indexFileName {
            if !fileNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.ownerOnlyPermissions]
        )
    }
}
