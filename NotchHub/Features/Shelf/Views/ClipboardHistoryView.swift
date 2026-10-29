import SwiftUI

/// "Pano" segment of the shelf: recent clipboard entries; click copies, drag exports, pin keeps on the shelf.
struct ClipboardHistoryView: View {
    private static let tileSpacing: CGFloat = 6
    private static let copiedFeedback: Duration = .seconds(1.2)
    private static let clockRefresh: TimeInterval = 30

    let history: ClipboardHistoryStore
    let shelf: ShelfStore

    @State private var copiedID: ClipboardEntry.ID?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if !history.isEnabled {
                placeholder(
                    systemImage: "clipboard",
                    title: "Pano geçmişi kapalı",
                    detail: "Ayarlar › Modüller › Pano Geçmişi bölümünden açabilirsin."
                )
            } else if history.entries.isEmpty {
                placeholder(
                    systemImage: "doc.on.clipboard",
                    title: "Henüz kopyalanan bir şey yok",
                    detail: "Kopyaladığın metin ve görseller burada görünür. Parola yöneticileri yok sayılır."
                )
            } else {
                entryRow
            }
        }
        .animation(.snappy(duration: 0.25), value: history.entries)
    }

    private var entryRow: some View {
        TimelineView(.periodic(from: .now, by: Self.clockRefresh)) { context in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.tileSpacing) {
                    ForEach(history.entries) { entry in
                        ClipboardEntryTile(
                            entry: entry,
                            imageURL: history.imageURL(for: entry),
                            timeText: ClipboardRelativeTime.text(for: entry.capturedAt, now: context.date),
                            isCopied: copiedID == entry.id,
                            handlers: handlers(for: entry),
                            actions: actions(for: entry)
                        )
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.never)
        }
    }

    private func placeholder(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Interaction

    private func copy(_ entry: ClipboardEntry) {
        history.copy(entry.id)
        copiedID = entry.id
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(for: Self.copiedFeedback)
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    private func dragItem(for entry: ClipboardEntry) -> ShelfItem? {
        switch entry.kind {
        case .text(let text):
            return ShelfItem(id: entry.id, kind: .text(text), addedAt: entry.capturedAt)
        case .image:
            guard let url = history.imageURL(for: entry) else { return nil }
            return ShelfItem(id: entry.id, kind: .file(url), addedAt: entry.capturedAt)
        }
    }

    private func handlers(for entry: ClipboardEntry) -> ShelfMouseHandlers {
        ShelfMouseHandlers(
            onPress: { _ in },
            onRelease: { _, didDrag in if !didDrag { copy(entry) } },
            onDoubleClick: { copy(entry) },
            dragItems: { dragItem(for: entry).map { [$0] } ?? [] },
            onDragActive: { shelf.isDraggingOut = $0 },
            onHover: { _ in },
            onKey: { command in
                if command == .delete { history.remove(entry.id) }
            },
            menu: { ShelfTileAction.menu(primary: [], secondary: actions(for: entry)) }
        )
    }

    private func actions(for entry: ClipboardEntry) -> [ShelfTileAction] {
        [
            ShelfTileAction(id: "copy", title: "Kopyala", systemImage: "doc.on.doc") { copy(entry) },
            ShelfTileAction(id: "pin", title: "Rafa Sabitle", systemImage: "pin") {
                history.pin(entry.id, to: shelf)
            },
            ShelfTileAction(id: "remove", title: "Geçmişten Sil", systemImage: "xmark", isDestructive: true) {
                history.remove(entry.id)
            },
        ]
    }
}
