import AppKit
import SwiftUI

/// Deep canvas with large blurred violet, pink and cyan fields that drift slowly, plus fine grain.
/// The drift is driven by a paused-able timeline, so it costs nothing while the window is not key
/// or not visible, and it stays still with Reduce Motion. Reduce Transparency shows a flat canvas.
struct SettingsBackdrop: View {
    /// Seconds for one full drift cycle.
    private static let driftPeriod: Double = 24
    /// The drift is slow, so a low frame rate is indistinguishable from 60 fps.
    private static let frameInterval: Double = 1.0 / 20.0

    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                SettingsTheme.Palette.canvas
            } else {
                TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !isActive || reduceMotion)) { context in
                    BackdropFields(phase: phase(at: context.date))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0...1, eased back and forth over `driftPeriod`.
    private func phase(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let angle = date.timeIntervalSinceReferenceDate / Self.driftPeriod * 2 * .pi
        return (1 - cos(angle)) / 2
    }
}

private struct BackdropFields: View {
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                SettingsTheme.Palette.canvas
                field(SettingsTheme.Palette.brand, diameter: size.width * 0.75, opacity: 0.5)
                    .offset(x: size.width * mix(-0.18, -0.28), y: size.height * mix(-0.22, -0.30))
                field(SettingsTheme.Palette.brandSecondary, diameter: size.width * 0.55, opacity: 0.3)
                    .offset(x: size.width * mix(0.26, 0.34), y: size.height * mix(-0.24, -0.12))
                field(SettingsTheme.Palette.brandTertiary, diameter: size.width * 0.6, opacity: 0.2)
                    .offset(x: size.width * mix(0.22, 0.10), y: size.height * mix(0.36, 0.46))
                // Vignette keeps the edges deep so content stays legible.
                RadialGradient(
                    colors: [.clear, SettingsTheme.Palette.canvas.opacity(0.75)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.3,
                    endRadius: max(size.width, size.height) * 0.85
                )
                GrainOverlay()
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    private func mix(_ start: Double, _ end: Double) -> Double {
        start + (end - start) * phase
    }

    /// A radial gradient looks like a heavily blurred circle but needs no blur pass.
    private func field(_ color: Color, diameter: CGFloat, opacity: Double) -> some View {
        RadialGradient(
            stops: [
                .init(color: color.opacity(opacity), location: 0),
                .init(color: color.opacity(opacity * 0.55), location: 0.35),
                .init(color: color.opacity(opacity * 0.18), location: 0.65),
                .init(color: .clear, location: 1),
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter * 0.8
        )
        .frame(width: diameter * 1.6, height: diameter * 1.6)
    }
}

/// Tiled monochrome noise at very low opacity; removes gradient banding and adds texture.
private struct GrainOverlay: View {
    private static let side = 128
    private static let opacity = 0.05

    var body: some View {
        Rectangle()
            .fill(ImagePaint(image: Image(nsImage: Self.noise), scale: 0.5))
            .opacity(Self.opacity)
            .blendMode(.overlay)
    }

    @MainActor private static let noise: NSImage = {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: side, bitsPerPixel: 8
        ), let data = rep.bitmapData else { return NSImage() }
        var generator = SystemRandomNumberGenerator()
        for index in 0..<(side * side) {
            data[index] = UInt8.random(in: 0...255, using: &generator)
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }()
}
