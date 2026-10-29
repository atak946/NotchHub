import AppKit

/// System side effects for shelf items (sharing, Finder, opening).
@MainActor
enum ShelfActions {
    static var airDropService: NSSharingService? {
        NSSharingService(named: .sendViaAirDrop)
    }

    static func airDrop(_ items: [ShelfItem], store: ShelfStore) {
        let shareables = items.compactMap { shareable(for: $0, store: store) }
        guard let service = airDropService, !shareables.isEmpty, service.canPerform(withItems: shareables) else {
            store.logger.error("AirDrop is not available for the selected items")
            return
        }
        NSApp.activate()
        service.perform(withItems: shareables)
    }

    static func revealInFinder(_ items: [ShelfItem]) {
        let urls = items.compactMap(\.fileURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ items: [ShelfItem], store: ShelfStore) {
        items.compactMap(store.previewURL(for:)).forEach { NSWorkspace.shared.open($0) }
    }

    private static func shareable(for item: ShelfItem, store: ShelfStore) -> Any? {
        switch item.kind {
        case .file(let url): url
        case .text(let string): string
        case .image: store.previewURL(for: item)
        }
    }
}
