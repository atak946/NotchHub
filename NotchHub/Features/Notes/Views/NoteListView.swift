import SwiftUI

/// Left column: "Yeni not", client filter chips and the note rows.
struct NoteListView: View {
    let store: NoteStore

    /// Row currently asking "Sil?"; confirmation is inline, never a modal.
    @State private var pendingDeleteID: Note.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !store.clientNames.isEmpty {
                NoteClientChips(store: store)
            }
            rows
        }
        .onChange(of: store.selectedID) { _, _ in pendingDeleteID = nil }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("Notlar", systemImage: "note.text")
                .font(.system(size: NotesStyle.headerFontSize, weight: .semibold))
            Spacer(minLength: 0)
            NotesCapsuleButton(title: "Yeni not", systemImage: "square.and.pencil") {
                pendingDeleteID = nil
                store.createNote()
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let notes = store.visibleNotes
        if notes.isEmpty {
            Text(store.notes.isEmpty ? "Not eklemek için \"Yeni not\"a bas." : "Bu müşteri için not yok.")
                .font(.system(size: NotesStyle.captionFontSize))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(notes) { note in
                        NoteRow(
                            note: note,
                            isSelected: store.selectedID == note.id,
                            isConfirmingDelete: pendingDeleteID == note.id,
                            onSelect: { store.selectedID = note.id },
                            onRequestDelete: { pendingDeleteID = note.id },
                            onCancelDelete: { pendingDeleteID = nil },
                            onConfirmDelete: {
                                pendingDeleteID = nil
                                store.delete(note.id)
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .animation(.snappy(duration: 0.2), value: notes.map(\.id))
        }
    }
}

/// Filter chips by client, shown only when at least one note has a client.
private struct NoteClientChips: View {
    let store: NoteStore

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                chip(title: String(localized: "Tümü"), value: nil)
                ForEach(store.clientNames, id: \.self) { name in
                    chip(title: name, value: name)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func chip(title: String, value: String?) -> some View {
        let isSelected = store.clientFilter == value
        return Button {
            store.clientFilter = value
        } label: {
            Text(title)
                .font(.system(size: NotesStyle.captionFontSize, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .capsule)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let isConfirmingDelete: Bool
    let onSelect: () -> Void
    let onRequestDelete: () -> Void
    let onCancelDelete: () -> Void
    let onConfirmDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if isConfirmingDelete {
                confirmation
            } else {
                summary
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: NotesStyle.rowCornerRadius))
        .contentShape(.rect(cornerRadius: NotesStyle.rowCornerRadius))
        .onTapGesture { if !isConfirmingDelete { onSelect() } }
        .onHover { isHovered = $0 }
        .animation(NotesStyle.hoverAnimation, value: isHovered)
        .animation(.snappy(duration: 0.15), value: isConfirmingDelete)
    }

    private var summary: some View {
        Group {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Text(note.displayTitle())
                        .font(.system(size: NotesStyle.rowTitleFontSize, weight: .semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: NotesStyle.captionFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered {
                Button(action: onRequestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Notu sil")
                .transition(.opacity)
            }
        }
    }

    private var confirmation: some View {
        Group {
            Text("Silinsin mi?")
                .font(.system(size: NotesStyle.rowTitleFontSize, weight: .semibold))
            Spacer(minLength: 0)
            Button("Vazgeç", action: onCancelDelete)
                .buttonStyle(.plain)
                .font(.system(size: NotesStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Sil", action: onConfirmDelete)
                .buttonStyle(.plain)
                .font(.system(size: NotesStyle.captionFontSize, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.85), in: .capsule)
                .foregroundStyle(.white)
        }
    }

    private var subtitle: String {
        let time = note.updatedAt.formatted(.relative(presentation: .named))
        guard let client = note.clientName else { return time }
        return "\(client) · \(time)"
    }

    private var background: AnyShapeStyle {
        if isConfirmingDelete { return AnyShapeStyle(Color.red.opacity(0.15)) }
        if isSelected { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(.quaternary.opacity(isHovered ? 0.5 : 0))
    }
}
