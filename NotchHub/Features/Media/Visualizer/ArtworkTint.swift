import CoreGraphics
import CoreImage
import OSLog

/// An sRGB color with components in 0...1, independent of SwiftUI so it can be computed off the main actor.
struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = RGBColor(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue > 0 ? delta / maxValue : 0
        guard delta > 0 else { return (0, saturation, maxValue) }
        var hue: Double
        if maxValue == red {
            hue = (green - blue) / delta
        } else if maxValue == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, maxValue)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch sector {
        case 0: self.init(red: brightness, green: t, blue: p)
        case 1: self.init(red: q, green: brightness, blue: p)
        case 2: self.init(red: p, green: brightness, blue: t)
        case 3: self.init(red: p, green: q, blue: brightness)
        case 4: self.init(red: t, green: p, blue: brightness)
        default: self.init(red: brightness, green: p, blue: q)
        }
    }
}

/// Average artwork color via Core Image `CIAreaAverage`, then tuned to read well on the black notch.
enum ArtworkTint {
    /// Below this saturation the artwork is effectively gray and the bars fall back to white.
    static let minimumSaturation = 0.15
    /// Dark averages are lifted so the bars stay visible against black.
    static let minimumBrightness = 0.75

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MediaVisualizer")
    /// `CIContext` is thread-safe (Sendable); one shared instance avoids per-artwork setup cost.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    /// The bar tint for an artwork, or white when there is none or extraction fails.
    static func tint(for image: CGImage?) -> RGBColor {
        guard let image else { return .white }
        return tint(fromAverage: averageColor(of: image))
    }

    /// Mean color of the whole image, nil when Core Image cannot render it.
    static func averageColor(of image: CGImage) -> RGBColor? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            logger.error("CIAreaAverage filter is unavailable")
            return nil
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else {
            logger.error("CIAreaAverage produced no output")
            return nil
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return RGBColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// White for missing or grayish averages; otherwise the hue, brightened for the black notch.
    static func tint(fromAverage average: RGBColor?) -> RGBColor {
        guard let average else { return .white }
        let hsb = average.hsb
        guard hsb.saturation >= minimumSaturation else { return .white }
        return RGBColor(hue: hsb.hue, saturation: hsb.saturation, brightness: max(hsb.brightness, minimumBrightness))
    }
}
