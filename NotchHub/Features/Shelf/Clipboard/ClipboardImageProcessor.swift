import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales captured images to PNG and fingerprints captured content.
enum ClipboardImageProcessor {
    static let maxPixelSide = 1600

    /// Decodes PNG/TIFF/etc., limits the longest side to `maxPixelSide` and re-encodes as PNG.
    static func downscaledPNG(from data: Data, maxPixelSide: Int = maxPixelSide) -> Data? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func fingerprint(text: String) -> String {
        "t:" + sha256Hex(Data(text.utf8))
    }

    static func fingerprint(imageData: Data) -> String {
        "i:" + sha256Hex(imageData)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
