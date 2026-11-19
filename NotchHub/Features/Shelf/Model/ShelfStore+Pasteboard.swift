import AppKit
import UniformTypeIdentifiers

extension ShelfStore {
    /// `.item` keeps SwiftUI from rejecting drops whose only representation is a file content type
    /// (e.g. `public.json`), which it may hand over without a `public.file-url`.
    static let acceptedDropTypes: [UTType] = [.fileURL, .image, .url, .plainText, .text, .item]

    /// Accepts file URLs, images and text from a SwiftUI/AppKit drop. Returns whether anything is loadable.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isDraggingOut else { return false }
        let accepted = providers.map(load).contains(true)
        if !accepted {
            let types = providers.map(\.registeredTypeIdentifiers)
            logger.error("Rejected drop with types: \(types.description, privacy: .public)")
        }
        return accepted
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
        if Self.hasPlainText(provider), provider.canLoadObject(ofClass: NSString.self) {
            loadString(from: provider)
            return true
        }
        if let fileType = Self.fileContentType(of: provider) {
            loadFile(from: provider, type: fileType)
            return true
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            loadString(from: provider)
            return true
        }
        return false
    }

    private func loadString(from provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: String.self) { [weak self] string, error in
            Task { @MainActor in
                guard let self else { return }
                guard let string else { return self.logLoadFailure(error) }
                self.add(text: string)
            }
        }
    }

    /// Loads a file-backed representation: the original file when it can be opened in place,
    /// otherwise a copy kept by the shelf (the provider deletes its temporary file after the callback).
    private func loadFile(from provider: NSItemProvider, type: String) {
        let suggestedName = provider.suggestedName
        let dropsDirectory = dropsDirectory
        _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { [weak self] url, isInPlace, error in
            guard let url else {
                Task { @MainActor in self?.logLoadFailure(error) }
                return
            }
            if isInPlace {
                Task { @MainActor in self?.add(fileURLs: [url]) }
                return
            }
            guard let copy = ShelfDroppedFiles.copy(url, suggestedName: suggestedName, type: type, in: dropsDirectory) else {
                Task { @MainActor in self?.logLoadFailure(nil) }
                return
            }
            Task { @MainActor in self?.add(fileURLs: [copy]) }
        }
    }

    private static func hasPlainText(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .plainText) == true }
    }

    /// Prefers a declared data/content type; undeclared custom identifiers are still loadable as files.
    private static func fileContentType(of provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        let declared = identifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .data) || type.conforms(to: .content)
        }
        return declared ?? identifiers.first
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
