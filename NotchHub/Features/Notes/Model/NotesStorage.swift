import Foundation
import OSLog

/// Persistence seam for notes so the store can be tested in memory.
protocol NotesStorage: Sendable {
    func load() throws -> [Note]
    func save(_ notes: [Note]) throws
}

/// `notes.json` in Application Support, written atomically.
struct FileNotesStorage: NotesStorage {
    private static let corruptExtension = "corrupt"

    let fileURL: URL

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "NotchHub/notes.json", directoryHint: .notDirectory)
    }

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Missing file → no notes. An unreadable file is moved aside (`notes.json.corrupt`) so it is not overwritten.
    func load() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try Self.decoder.decode([Note].self, from: data)
        } catch {
            let backup = fileURL.appendingPathExtension(Self.corruptExtension)
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: fileURL, to: backup)
            throw error
        }
    }

    func save(_ notes: [Note]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(notes)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
