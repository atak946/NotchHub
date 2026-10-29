import Foundation
import UniformTypeIdentifiers

enum CaptureKind: String, Equatable, Sendable {
    case screenshot
    case download
}

/// One file-level FSEvents record.
struct CaptureFileEvent: Equatable, Sendable {
    struct Flags: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let created = Flags(rawValue: 1 << 0)
        static let removed = Flags(rawValue: 1 << 1)
        static let renamed = Flags(rawValue: 1 << 2)
        static let modified = Flags(rawValue: 1 << 3)
        static let isFile = Flags(rawValue: 1 << 4)
        static let isDirectory = Flags(rawValue: 1 << 5)
    }

    let path: String
    let flags: Flags
}

/// What the file system says about a path right now.
struct CaptureFileInfo: Equatable, Sendable {
    let isRegularFile: Bool
    let size: Int64
    let creationDate: Date?
}

/// File system reads behind a protocol so classification is testable.
protocol CaptureFileProbing {
    func info(atPath path: String) -> CaptureFileInfo?
    func exists(atPath path: String) -> Bool
}

struct SystemCaptureFileProbe: CaptureFileProbing {
    func info(atPath path: String) -> CaptureFileInfo? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let type = attributes[.type] as? FileAttributeType
        return CaptureFileInfo(
            isRegularFile: type == .typeRegular,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            creationDate: attributes[.creationDate] as? Date
        )
    }

    func exists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// A file confirmed as a finished screenshot or download.
struct CaptureDetection: Equatable, Sendable {
    let url: URL
    let kind: CaptureKind

    var fileName: String { url.lastPathComponent }

    /// SF Symbol by file type, used as the alert "thumbnail".
    var systemImage: String { Self.systemImage(forExtension: url.pathExtension, kind: kind) }

    static func systemImage(forExtension ext: String, kind: CaptureKind) -> String {
        if kind == .screenshot { return "camera.viewfinder" }
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return "doc" }
        let symbols: [(UTType, String)] = [
            (.image, "photo"),
            (.movie, "film"),
            (.audio, "waveform"),
            (.pdf, "doc.richtext"),
            (.diskImage, "externaldrive"),
            (.archive, "doc.zipper"),
            (.applicationBundle, "app.badge"),
            (.sourceCode, "chevron.left.forwardslash.chevron.right"),
            (.presentation, "rectangle.on.rectangle"),
            (.spreadsheet, "tablecells"),
            (.text, "doc.text"),
        ]
        return symbols.first { type.conforms(to: $0.0) }?.1 ?? "doc"
    }
}
