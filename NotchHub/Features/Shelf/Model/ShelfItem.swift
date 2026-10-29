import Foundation

/// One entry on the file shelf: a file reference, a text snippet or a PNG image.
struct ShelfItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case file(URL)
        case text(String)
        case image(Data)
    }

    static let snippetLength = 80

    let id: UUID
    let kind: Kind
    let addedAt: Date

    init(id: UUID = UUID(), kind: Kind, addedAt: Date) {
        self.id = id
        self.kind = kind
        self.addedAt = addedAt
    }

    var fileURL: URL? {
        if case .file(let url) = kind { return url }
        return nil
    }

    var text: String? {
        if case .text(let string) = kind { return string }
        return nil
    }

    var imageData: Data? {
        if case .image(let data) = kind { return data }
        return nil
    }

    var isFile: Bool { fileURL != nil }

    /// Short, single-line title for tiles, tooltips and menus.
    var displayName: String {
        switch kind {
        case .file(let url):
            url.lastPathComponent
        case .text(let string):
            String(string.split(whereSeparator: \.isNewline).first ?? "").prefix(Self.snippetLength).description
        case .image:
            "Görsel"
        }
    }
}
