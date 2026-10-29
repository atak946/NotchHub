// Renders the NotchHub app icon (1024×1024 PNG) with CoreGraphics.
// Usage: swift tools/Icon/render-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let space = CGColorSpaceCreateDeviceRGB()

    // macOS icon grid: 824pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.16, blue: 0.42, alpha: 1),
        CGColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Soft glow under the notch.
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.45, green: 0.62, blue: 1.0, alpha: 0.55),
        CGColor(red: 0.45, green: 0.62, blue: 1.0, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 760), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 760), endRadius: 420, options: [])

    // Expanded notch panel hanging from the top edge.
    let panel = CGRect(x: 232, y: 520, width: 560, height: 420)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: 96, cornerHeight: 96, transform: nil)
    ctx.addPath(panelPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()

    // Three module tiles inside the panel.
    let tileColors = [
        CGColor(red: 0.36, green: 0.80, blue: 0.55, alpha: 1),
        CGColor(red: 0.42, green: 0.60, blue: 1.00, alpha: 1),
        CGColor(red: 1.00, green: 0.62, blue: 0.30, alpha: 1),
    ]
    for (index, color) in tileColors.enumerated() {
        let tile = CGRect(x: 286 + CGFloat(index) * 156, y: 580, width: 140, height: 140)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    // Status bar line.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 286, y: 760, width: 452, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 286, y: 760, width: 280, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
    ctx.fillPath()
    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode icon")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
