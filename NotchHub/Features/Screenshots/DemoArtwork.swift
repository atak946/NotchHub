import AppKit

/// Generated stand-ins for album artwork and shelf images: gradients with soft light, no real media.
enum DemoArtwork {
    static let size = 300

    struct Palette {
        let top: NSColor
        let bottom: NSColor
        let glow: NSColor
    }

    static let album = Palette(
        top: NSColor(srgbRed: 0.98, green: 0.36, blue: 0.53, alpha: 1),
        bottom: NSColor(srgbRed: 0.27, green: 0.16, blue: 0.62, alpha: 1),
        glow: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.42, alpha: 0.85)
    )

    static let photo = Palette(
        top: NSColor(srgbRed: 0.20, green: 0.74, blue: 0.86, alpha: 1),
        bottom: NSColor(srgbRed: 0.09, green: 0.24, blue: 0.52, alpha: 1),
        glow: NSColor(srgbRed: 0.85, green: 1.0, blue: 0.90, alpha: 0.7)
    )

    /// PNG bytes of a square gradient artwork.
    static func pngData(_ palette: Palette = album) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(palette, in: CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(_ palette: Palette, in rect: CGRect) {
        NSGradient(starting: palette.bottom, ending: palette.top)?.draw(in: rect, angle: 60)
        let glowRect = CGRect(x: rect.width * 0.35, y: rect.height * 0.35, width: rect.width * 0.9, height: rect.height * 0.9)
        NSGradient(colors: [palette.glow, palette.glow.withAlphaComponent(0)])?
            .draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        for index in 0..<3 {
            let inset = CGFloat(40 + index * 34)
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset).offsetBy(dx: -50, dy: -60))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
