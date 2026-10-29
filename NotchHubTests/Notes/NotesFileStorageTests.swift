import Foundation
import Testing
@testable import NotchHub

struct NotesFileStorageTests {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NotesStorage-\(UUID().uuidString)/NotchHub/notes.json", directoryHint: .notDirectory)
    }

    @Test func roundTripPreservesEveryField() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let storage = FileNotesStorage(fileURL: url)
        let notes = [
            Note(
                body: "Line 1\n[ ] task",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_600),
                meetingTitle: "Standup",
                clientName: "Acme",
                isPinned: true
            ),
            Note(body: "", createdAt: Date(timeIntervalSince1970: 1_700_001_000)),
        ]

        try storage.save(notes)
        let loaded = try storage.load()

        #expect(loaded == notes)
    }

    @Test func missingFileLoadsEmpty() throws {
        #expect(try FileNotesStorage(fileURL: makeURL()).load().isEmpty)
    }

    @Test func corruptFileIsMovedAsideInsteadOfOverwritten() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        #expect(throws: (any Error).self) { try FileNotesStorage(fileURL: url).load() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    @MainActor
    @Test func storeRoundTripThroughFile() async throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = NoteStore(storage: FileNotesStorage(fileURL: url))
        store.start()
        let note = store.createNote()
        store.updateBody("Persisted", for: note.id)
        store.stop()

        let reloaded = NoteStore(storage: FileNotesStorage(fileURL: url))
        reloaded.start()

        #expect(reloaded.notes.map(\.body) == ["Persisted"])
        #expect(reloaded.notes.first?.id == note.id)
    }
}
