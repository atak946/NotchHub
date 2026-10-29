import Foundation

/// Writes a note as a `.md` file for drag-out and the shelf.
struct NoteMarkdownExporter: Sendable {
    static let fileExtension = "md"
    static let fallbackName = "Not"
    static let maxNameLength = 60
    /// Characters that are unsafe in file names on macOS (and common sync targets).
    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        .union(.controlCharacters)
        .union(.newlines)

    let directory: URL

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "NotchHub/NoteExports", directoryHint: .isDirectory)
    }

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// A safe "<title>.md" name: forbidden characters become spaces, whitespace is collapsed,
    /// leading dots are dropped (no hidden files) and the stem is capped at `maxNameLength`.
    static func fileName(for title: String) -> String {
        let replaced = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        let collapsed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let withoutDots = collapsed.drop { $0 == "." || $0 == " " }
        let capped = String(withoutDots.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        let stem = capped.isEmpty ? fallbackName : capped
        return "\(stem).\(fileExtension)"
    }

    /// Writes the body to `<directory>/<note id>/<title>.md` (one folder per note avoids name clashes).
    func export(_ note: Note) throws -> URL {
        let folder = directory.appending(path: note.id.uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let title = note.displayTitle()
        let url = folder.appending(path: Self.fileName(for: title), directoryHint: .notDirectory)
        let contents = note.body.isEmpty ? title : note.body
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}
