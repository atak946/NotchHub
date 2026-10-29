import Foundation

/// Stores text and image payloads as files (`<id>.txt` / `<id>.png`).
struct ShelfPayloadStorage: Sendable {
    enum PayloadType: String, Sendable {
        case text = "txt"
        case image = "png"
    }

    let directory: URL

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "NotchHub/Shelf", directoryHint: .isDirectory)
    }

    func url(for id: UUID, type: PayloadType) -> URL {
        directory.appending(path: "\(id.uuidString).\(type.rawValue)", directoryHint: .notDirectory)
    }

    func write(_ data: Data, for id: UUID, type: PayloadType) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id, type: type), options: .atomic)
    }

    func read(_ id: UUID, type: PayloadType) -> Data? {
        try? Data(contentsOf: url(for: id, type: type))
    }

    func delete(_ id: UUID, type: PayloadType) {
        try? FileManager.default.removeItem(at: url(for: id, type: type))
    }

    /// Removes payload files that no persisted item refers to.
    func removeOrphans(keeping ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if id.map(ids.contains) != true {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
