import SwiftUI

/// Settings for the shelf, meant to be embedded in a grouped `Form`.
struct ShelfSettingsSection: View {
    @Bindable private var store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
    }

    var body: some View {
        Section("Dosya Rafı") {
            Picker("Öğeleri otomatik kaldır", selection: $store.retention) {
                ForEach(ShelfRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }
            Text("Yalnızca raf girişi kaldırılır; özgün dosyaların asla silinmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
