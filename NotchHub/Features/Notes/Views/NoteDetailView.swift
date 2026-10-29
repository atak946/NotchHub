import SwiftUI

/// Right column: context badges, actions and the editor (or the checklist preview).
struct NoteDetailView: View {
    private static let feedbackDuration: Duration = .seconds(1.2)

    let note: Note
    let store: NoteStore
    let shelf: ShelfStore

    @State private var isPreviewing: Bool
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    init(note: Note, store: NoteStore, shelf: ShelfStore) {
        self.note = note
        self.store = store
        self.shelf = shelf
        _isPreviewing = State(initialValue: NoteChecklist.hasChecklist(note.body))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: NotesStyle.cornerRadius))
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            contextBadges
            Spacer(minLength: 4)
            if let feedback {
                Text(feedback)
                    .font(.system(size: NotesStyle.captionFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            NotesCapsuleButton(
                title: isPreviewing ? "Düzenle" : "Önizleme",
                systemImage: isPreviewing ? "pencil" : "checklist",
                showsTitle: false
            ) {
                isPreviewing.toggle()
            }
            NotesCapsuleButton(
                title: note.isPinned ? "Sabitlemeyi kaldır" : "Sabitle",
                systemImage: note.isPinned ? "pin.slash" : "pin",
                showsTitle: false
            ) {
                store.togglePinned(note.id)
            }
            NotesCapsuleButton(title: "Kopyala", systemImage: "doc.on.doc") {
                store.copyBody(note.id)
                show(String(localized: "Kopyalandı"))
            }
            .disabled(note.body.isEmpty)
            NotesCapsuleButton(title: "Rafa ekle", systemImage: "tray.and.arrow.down") {
                addToShelf()
            }
            dragHandle
        }
        .animation(.snappy(duration: 0.15), value: feedback)
    }

    @ViewBuilder
    private var contextBadges: some View {
        HStack(spacing: 4) {
            if let meeting = note.meetingTitle {
                badge(meeting, systemImage: "person.2.wave.2")
            }
            if let client = note.clientName {
                badge(client, systemImage: "briefcase")
            }
        }
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: NotesStyle.captionFontSize, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .help(text)
    }

    /// Drag this out (Finder, Mail, …) to get the note as a `.md` file.
    private var dragHandle: some View {
        Image(systemName: "arrow.up.doc")
            .font(.system(size: NotesStyle.buttonFontSize, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: .capsule)
            .contentShape(.capsule)
            .help("Markdown dosyası olarak sürükle")
            .accessibilityLabel("Markdown dosyası olarak sürükle")
            .onDrag {
                guard let url = store.exportMarkdown(note.id), let provider = NSItemProvider(contentsOf: url) else {
                    return NSItemProvider()
                }
                provider.suggestedName = url.lastPathComponent
                return provider
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isPreviewing {
            NoteChecklistPreview(text: note.body) { line in
                store.toggleChecklistItem(line: line, in: note.id)
            }
        } else {
            NoteTextEditor(text: bodyBinding) { isFocused in
                store.isEditorFocused = isFocused
            }
        }
    }

    private var bodyBinding: Binding<String> {
        let id = note.id
        return Binding(
            get: { store.note(id: id)?.body ?? "" },
            set: { store.updateBody($0, for: id) }
        )
    }

    // MARK: - Actions

    private func addToShelf() {
        guard let url = store.exportMarkdown(note.id) else {
            show(String(localized: "Dışa aktarılamadı"))
            return
        }
        shelf.add(fileURLs: [url])
        show(String(localized: "Rafa eklendi"))
    }

    private func show(_ message: String) {
        feedbackTask?.cancel()
        feedback = message
        feedbackTask = Task {
            try? await Task.sleep(for: Self.feedbackDuration)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }
}
