import Foundation
import Testing
@testable import NotchHub

struct NoteMarkdownExporterTests {
    @Test(arguments: [
        ("Weekly sync", "Weekly sync.md"),
        ("a/b\\c:d*e?f\"g<h>i|j", "a b c d e f g h i j.md"),
        ("  lots   of\tspace  ", "lots of space.md"),
        ("...hidden", "hidden.md"),
        ("", "Not.md"),
        ("///", "Not.md"),
        ("Toplantı: Müşteri · 10:30", "Toplantı Müşteri · 10 30.md"),
    ])
    func sanitisesFileNames(title: String, expected: String) {
        #expect(NoteMarkdownExporter.fileName(for: title) == expected)
    }

    @Test func capsLongNames() {
        let name = NoteMarkdownExporter.fileName(for: String(repeating: "x", count: 200))
        #expect(name == String(repeating: "x", count: NoteMarkdownExporter.maxNameLength) + ".md")
    }

    @Test func controlCharactersAreRemoved() {
        #expect(NoteMarkdownExporter.fileName(for: "a\u{0}b\u{7}c") == "a b c.md")
    }

    @Test func exportOverwritesPreviousFileForSameNote() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NotesExport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = NoteMarkdownExporter(directory: directory)
        var note = Note(body: "First title", createdAt: .distantPast)
        let first = try exporter.export(note)

        note.body = "Second title"
        let second = try exporter.export(note)

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(second.lastPathComponent == "Second title.md")
        #expect(try String(contentsOf: second, encoding: .utf8) == "Second title")
    }
}
