import AppKit
import UniformTypeIdentifiers

extension ShelfStore {
    static let acceptedDropTypes: [UTType] = [.fileURL, .image, .url, .plainText, .text]

    /// Accepts file URLs, images and text from a SwiftUI/AppKit drop. Returns whether anything is loadable.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isDraggingOut else { return false }
        return providers.map(load).contains(true)
    }

    /// Copies the given items to the pasteboard (files as file URLs, text as string, images as PNG).
    func copyToPasteboard(_ ids: [ShelfItem.ID], pasteboard: NSPasteboard = .general) {
        let writers = items(with: ids).map(Self.pasteboardWriter)
        guard !writers.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(writers)
    }

    static func pasteboardWriter(for item: ShelfItem) -> any NSPasteboardWriting {
        switch item.kind {
        case .file(let url):
            return url as NSURL
        case .text(let string):
            return string as NSString
        case .image(let data):
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .png)
            return pasteboardItem
        }
    }

    // MARK: - Item providers

    private func load(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard let url else { return self.logLoadFailure(error) }
                    self.add(fileURLs: [url])
                }
            }
            return true
        }
        if let imageType = Self.imageType(of: provider) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard let data else { return self.logLoadFailure(error) }
                    self.add(imageData: data)
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard let url else { return self.logLoadFailure(error) }
                    self.add(text: url.absoluteString)
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: String.self) { [weak self] string, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard let string else { return self.logLoadFailure(error) }
                    self.add(text: string)
                }
            }
            return true
        }
        return false
    }

    private static func imageType(of provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
    }

    private func logLoadFailure(_ error: (any Error)?) {
        logger.error("Dropped item could not be loaded: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    }
}
