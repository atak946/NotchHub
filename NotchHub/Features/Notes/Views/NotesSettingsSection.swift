import AppKit
import SwiftUI

/// Settings › Modules: the quick calculator toggle, where notes live and a shortcut to reveal the file.
struct NotesSettingsSection: View {
    let store: NoteStore
    @Bindable var calculator: QuickCalcService

    var body: some View {
        Section("Notlar") {
            Toggle("Hızlı hesap", isOn: $calculator.isEnabled)
            Text("Notlar'da \"Hesap\" sekmesi: 12,5*3, 5 km mil, 100 usd tl. Kurlar open.er-api.com'dan alınır ve 12 saat saklanır.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
