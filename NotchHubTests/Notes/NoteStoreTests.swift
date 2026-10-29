import Foundation
import Testing
@testable import NotchHub

@MainActor
struct NoteStoreTests {
    @Test func createNoteSelectsItAndCarriesContext() {
        let fixture = NotesFixture()
        let store = fixture.makeStore()
        store.contextProvider = { _ in NoteContext(meetingTitle: "Sprint review", clientName: "Acme") }

        let note = store.createNote()

        #expect(store.selectedID == note.id)
        #expect(note.meetingTitle == "Sprint review")
        #expect(note.clientName == "Acme")
        #expect(note.createdAt == fixture.clock.now)
        #expect(store.clientNames == ["Acme"])
    }

    @Test func debounceCoalescesRapidEditsIntoOneSave() async {
        let fixture = NotesFixture()
        let store = fixture.makeStore()
        let note = store.createNote()

        for text in ["a", "ab", "abc"] {
            store.updateBody(text, for: note.id)
        }
        #expect(fixture.storage.saveCount == 0)

        await fixture.flushDebounce(store)

        #expect(fixture.storage.saveCount == 1)
        #expect(fixture.storage.lastSaved?.first?.body == "abc")
        #expect(fixture.sleeper.requestedDurations.allSatisfy { $0 == NoteStore.saveDebounce })
    }

    @Test func stopFlushesPendingChangeImmediately() {
        let fixture = NotesFixture()
        let store = fixture.makeStore()
        let note = store.createNote()
        store.updateBody("draft", for: note.id)

        store.stop()

        #expect(fixture.storage.saveCount == 1)
        #expect(fixture.storage.lastSaved?.first?.body == "draft")
        #expect(store.pendingSave == nil)
    }

    @Test func unchangedBodyDoesNotScheduleSave() {
        let existing = Note(body: "same", createdAt: .distantPast)
        let fixture = NotesFixture(notes: [existing])
        let store = fixture.makeStore()

        store.updateBody("same", for: existing.id)

        #expect(store.pendingSave == nil)
        #expect(store.note(id: existing.id)?.updatedAt == .distantPast)
    }

    @Test func orderingIsPinnedFirstThenMostRecent() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let old = Note(body: "old", createdAt: base, updatedAt: base)
        let recent = Note(body: "recent", createdAt: base, updatedAt: base.addingTimeInterval(60))
        let pinnedOld = Note(body: "pinned", createdAt: base, updatedAt: base.addingTimeInterval(-60), isPinned: true)
        let fixture = NotesFixture(notes: [old, recent, pinnedOld])
        let store = fixture.makeStore()

        #expect(store.sortedNotes.map(\.body) == ["pinned", "recent", "old"])

        store.updateBody("old edited", for: old.id)
        #expect(store.sortedNotes.map(\.body) == ["pinned", "old edited", "recent"])
    }

    @Test func pinningDoesNotChangeUpdatedAt() {
        let note = Note(body: "x", createdAt: .distantPast)
        let fixture = NotesFixture(notes: [note])
        let store = fixture.makeStore()

        store.togglePinned(note.id)

        #expect(store.note(id: note.id)?.isPinned == true)
        #expect(store.note(id: note.id)?.updatedAt == .distantPast)
    }

    @Test func clientFilterNarrowsAndResetsWhenClientDisappears() {
        let acme = Note(body: "a", createdAt: .distantPast, clientName: "Acme")
        let plain = Note(body: "b", createdAt: .distantPast)
        let fixture = NotesFixture(notes: [acme, plain])
        let store = fixture.makeStore()

        store.clientFilter = "Acme"
        #expect(store.visibleNotes.map(\.id) == [acme.id])

        store.delete(acme.id)
        #expect(store.clientFilter == nil)
        #expect(store.clientNames.isEmpty)
    }

    @Test func deleteSelectsNextVisibleNote() {
        let first = Note(body: "first", createdAt: .distantPast, updatedAt: Date(timeIntervalSinceReferenceDate: 2))
        let second = Note(body: "second", createdAt: .distantPast, updatedAt: Date(timeIntervalSinceReferenceDate: 1))
        let fixture = NotesFixture(notes: [first, second])
        let store = fixture.makeStore()
        store.selectedID = first.id

        store.delete(first.id)

        #expect(store.selectedID == second.id)
        #expect(store.notes.count == 1)
    }

    @Test func toggleChecklistRewritesBody() {
        let note = Note(body: "Todo\n[ ] one\n[x] two", createdAt: .distantPast)
        let fixture = NotesFixture(notes: [note])
        let store = fixture.makeStore()

        store.toggleChecklistItem(line: 1, in: note.id)

        #expect(store.note(id: note.id)?.body == "Todo\n[x] one\n[x] two")
    }

    @Test func exportWritesMarkdownFile() throws {
        let note = Note(body: "Plan: Q3/Q4\nDetails", createdAt: .distantPast)
        let fixture = NotesFixture(notes: [note])
        let store = fixture.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.exportDirectory) }

        let url = try #require(store.exportMarkdown(note.id))

        #expect(url.lastPathComponent == "Plan Q3 Q4.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == note.body)
    }
}
