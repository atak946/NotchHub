import SwiftUI

/// Notes module: list on the left (pinned first, then most recent), editor or checklist preview on the right.
struct NotesModuleView: View {
    let store: NoteStore
    let shelf: ShelfStore

    var body: some View {
        HStack(alignment: .top, spacing: NotesStyle.columnSpacing) {
            NoteListView(store: store)
                .frame(width: NotesStyle.listWidth)
            Divider()
                .opacity(0.4)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
        .onAppear(perform: selectFirstIfNeeded)
    }

    @ViewBuilder
    private var detail: some View {
        if let note = store.selectedNote {
            NoteDetailView(note: note, store: store, shelf: shelf)
                .id(note.id)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(store.notes.isEmpty ? "Henüz not yok" : "Bir not seç")
                .font(.system(size: NotesStyle.headerFontSize, weight: .semibold))
            Text("Notlar yalnızca bu Mac'te düz metin olarak saklanır.")
                .font(.system(size: NotesStyle.captionFontSize))
                .foregroundStyle(.secondary)
            NotesCapsuleButton(title: "Yeni not", systemImage: "square.and.pencil", isProminent: true) {
                store.createNote()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectFirstIfNeeded() {
        if store.selectedNote == nil {
            store.selectedID = store.visibleNotes.first?.id
        }
    }
}
