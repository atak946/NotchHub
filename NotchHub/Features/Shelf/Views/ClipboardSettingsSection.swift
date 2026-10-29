import SwiftUI

/// "Pano Geçmişi" settings: opt-out toggle and clear button.
struct ClipboardSettingsSection: View {
    @Bindable private var history: ClipboardHistoryStore

    init(history: ClipboardHistoryStore) {
        self.history = history
    }

    var body: some View {
        Section("Pano Geçmişi") {
            Toggle("Pano geçmişi", isOn: $history.isEnabled)
            Button("Geçmişi temizle", role: .destructive) {
                history.clear()
            }
            .disabled(!history.hasEntries)
            Text("Son \(ClipboardHistoryPolicy.defaultMaxEntries) metin ve görsel bu Mac'te saklanır. Parola yöneticilerinden ve gizli olarak işaretlenen kopyalamalar kaydedilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
