import AppKit

/// What the history store needs from a pasteboard; faked in tests.
@MainActor
protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var typeIdentifiers: [String] { get }
    func readString() -> String?
    /// PNG or TIFF data, whichever is present first.
    func readImageData() -> Data?
    /// Replaces the contents; returns the resulting change count.
    func write(text: String) -> Int
    func write(png: Data) -> Int
}

/// `NSPasteboard.general` adapter.
@MainActor
final class SystemClipboardPasteboard: ClipboardPasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var typeIdentifiers: [String] {
        (pasteboard.types ?? []).map(\.rawValue)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func readImageData() -> Data? {
        pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    func write(text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    func write(png: Data) -> Int {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        return pasteboard.changeCount
    }
}

/// Pure choice of what to record from a pasteboard change, based on its type identifiers.
enum ClipboardCaptureKind: Equatable, Sendable {
    case text
    case image
    case none

    static let fileURLType = "public.file-url"
    static let textTypes: Set<String> = ["public.utf8-plain-text", "NSStringPboardType", "public.plain-text"]
    static let imageTypes: Set<String> = ["public.png", "public.tiff", "NeXT TIFF v4.0 pasteboard type"]

    /// Files are ignored (the shelf handles them); text wins over image previews of rich content.
    static func preferred(for types: [String]) -> ClipboardCaptureKind {
        if types.contains(fileURLType) { return .none }
        if types.contains(where: textTypes.contains) { return .text }
        if types.contains(where: imageTypes.contains) { return .image }
        return .none
    }
}
