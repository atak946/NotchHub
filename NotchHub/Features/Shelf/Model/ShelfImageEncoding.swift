import AppKit

/// Normalises pasted or dropped image data (TIFF, JPEG, HEIC…) to PNG.
enum ShelfImageEncoding {
    static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func pngData(from data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        if data.starts(with: pngSignature) { return data }
        let bitmap = NSBitmapImageRep(data: data)
            ?? NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        return bitmap?.representation(using: .png, properties: [:])
    }
}
