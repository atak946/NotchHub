import Foundation

/// One captured clipboard item. Text lives in the index; images are PNG files next to it.
struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case text(String)
        /// `byteCount` is the PNG file size, used for the total size budget.
        case image(fileName: String, byteCount: Int)
    }

    static let previewLength = 120

    let id: UUID
    let kind: Kind
    let capturedAt: Date
    /// Content hash used for de-duplication (never logged).
    let fingerprint: String

    init(id: UUID = UUID(), kind: Kind, capturedAt: Date, fingerprint: String) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.fingerprint = fingerprint
    }

    var text: String? {
        if case .text(let string) = kind { return string }
        return nil
    }

    var imageFileName: String? {
        if case .image(let fileName, _) = kind { return fileName }
        return nil
    }

    var imageByteCount: Int {
        if case .image(_, let byteCount) = kind { return byteCount }
        return 0
    }

    var isImage: Bool { imageFileName != nil }

    /// Single-line preview for tiles and tooltips.
    var previewText: String {
        guard let text else { return String(localized: "Görsel") }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(Self.previewLength))
    }
}
