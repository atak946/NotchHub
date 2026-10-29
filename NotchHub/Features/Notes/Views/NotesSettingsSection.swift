import AppKit
import SwiftUI

/// Settings › Modules: where notes live and a shortcut to reveal the file.
struct NotesSettingsSection: View {
    let store: NoteStore

    var body: some View {
        Section("Notlar") {
            LabeledContent("Not sayısı", value: "\(store.notes.count)")
            LabeledContent("Konum") {
                Text(FileNotesStorage.defaultFileURL.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Finder'da Göster", action: revealInFinder)
            Text("Notlar düz metin olarak yalnızca bu Mac'te saklanır; eşitleme yapılmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func revealInFinder() {
        let url = FileNotesStorage.defaultFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
