import AppKit
import Foundation
import Observation
import OSLog

/// Owns the notes list, the selection and debounced persistence to `notes.json`.
@MainActor
@Observable
final class NoteStore {
    static let saveDebounce: Duration = .milliseconds(600)

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Unsorted; use `sortedNotes` / `visibleNotes` for display.
    private(set) var notes: [Note] = []
    var selectedID: Note.ID?
    /// Client chip filter; nil shows every note.
    var clientFilter: String?
    /// True while the note editor is first responder. The panel stays open on mouse exit while this is set.
    var isEditorFocused = false

    @ObservationIgnored private let storage: any NotesStorage
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let exporter: NoteMarkdownExporter
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Notes")
    @ObservationIgnored private var hasLoaded = false
    /// Current debounced save; internal so tests can await it.
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?
    /// Supplies meeting / client context for new notes.
    @ObservationIgnored var contextProvider: @MainActor (Date) -> NoteContext = { _ in .none }

    init(
        storage: any NotesStorage = FileNotesStorage(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        debounce: Duration = NoteStore.saveDebounce,
        exporter: NoteMarkdownExporter = NoteMarkdownExporter()
    ) {
        self.storage = storage
        self.now = now
        self.sleep = sleep
        self.debounce = debounce
        self.exporter = exporter
    }

    // MARK: - Lifecycle

    func start() {
        ensureLoaded()
    }

    /// Writes any pending change immediately (module turned off or app quitting).
    func stop() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        saveNow()
    }

    // MARK: - Queries

    var sortedNotes: [Note] {
        notes.sorted(by: Note.displayOrder)
    }

    /// Sorted notes, narrowed by `clientFilter`.
    var visibleNotes: [Note] {
        guard let clientFilter else { return sortedNotes }
        return sortedNotes.filter { $0.clientName == clientFilter }
    }

    /// Distinct client names, alphabetically; empty when no note has a client.
    var clientNames: [String] {
        Set(notes.compactMap(\.clientName)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var selectedNote: Note? {
        selectedID.flatMap(note(id:))
    }

    func note(id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    // MARK: - Editing

    /// Creates an empty note tagged with the current meeting / client and selects it.
    @discardableResult
    func createNote() -> Note {
        ensureLoaded()
        let date = now()
        let context = contextProvider(date)
        let note = Note(createdAt: date, meetingTitle: context.meetingTitle, clientName: context.clientName)
        notes.append(note)
        selectedID = note.id
        if let clientFilter, clientFilter != note.clientName { self.clientFilter = nil }
        scheduleSave()
        return note
    }

    func updateBody(_ body: String, for id: Note.ID) {
        mutate(id) { note in
            guard note.body != body else { return false }
            note.body = body
            return true
        }
    }

    func togglePinned(_ id: Note.ID) {
        mutate(id, touchesUpdatedAt: false) { note in
            note.isPinned.toggle()
            return true
        }
    }

    func toggleChecklistItem(line: Int, in id: Note.ID) {
        mutate(id) { note in
            let toggled = NoteChecklist.toggle(lineAt: line, in: note.body)
            guard toggled != note.body else { return false }
            note.body = toggled
            return true
        }
    }

    func delete(_ id: Note.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = visibleNotes.first?.id }
        if let clientFilter, !clientNames.contains(clientFilter) { self.clientFilter = nil }
        scheduleSave()
    }

    // MARK: - Export

    /// Writes the note as `.md` into the temp export folder.
    func exportMarkdown(_ id: Note.ID) -> URL? {
        guard let note = note(id: id) else { return nil }
        do {
            return try exporter.export(note)
        } catch {
            logger.error("Note export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func copyBody(_ id: Note.ID, to pasteboard: NSPasteboard = .general) {
        guard let note = note(id: id) else { return }
        pasteboard.clearContents()
        pasteboard.setString(note.body, forType: .string)
    }

    // MARK: - Persistence

    private func mutate(_ id: Note.ID, touchesUpdatedAt: Bool = true, _ change: (inout Note) -> Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        guard change(&note) else { return }
        if touchesUpdatedAt { note.updatedAt = now() }
        notes[index] = note
        scheduleSave()
    }

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            notes = try storage.load()
        } catch {
            logger.error("Notes could not be loaded: \(error.localizedDescription, privacy: .public)")
            notes = []
        }
    }

    /// Restarts the debounce window; only the last change in a burst writes the file.
    private func scheduleSave() {
        pendingSave?.cancel()
        let sleep = sleep
        let debounce = debounce
        pendingSave = Task { [weak self] in
            do {
                try await sleep(debounce)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingSave = nil
            self.saveNow()
        }
    }

    private func saveNow() {
        do {
            try storage.save(notes)
        } catch {
            logger.error("Notes could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
