import AppKit
import Quartz

/// Drives the shared Quick Look panel for shelf items.
@MainActor
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = ShelfQuickLook()

    private var urls: [URL] = []

    func toggle(_ newURLs: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, newURLs.isEmpty || newURLs == urls {
            panel.orderOut(nil)
            return
        }
        guard !newURLs.isEmpty else { return }
        urls = newURLs
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url: URL? = MainActor.assumeIsolated {
            urls.indices.contains(index) ? urls[index] : nil
        }
        return url.map { $0 as NSURL }
    }
}
