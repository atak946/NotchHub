import SwiftUI

/// Soft accent glow spilling out under the notch; urgent alerts breathe gently.
struct AlertGlow: View {
    private static let blurRadius: CGFloat = 16
    private static let verticalOffset: CGFloat = 8
    private static let pulseFloor = 0.5
    private static let pulseDuration = 1.1

    let style: NotchAlert.Style
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let glow = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(style.tint)
            .blur(radius: Self.blurRadius)
            .offset(y: Self.verticalOffset)
            .opacity(style.glowOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        if style.glowPulses, !reduceMotion {
            glow.phaseAnimator([false, true]) { view, isBright in
                view.opacity(isBright ? 1 : Self.pulseFloor)
            } animation: { _ in
                .easeInOut(duration: Self.pulseDuration)
            }
        } else {
            glow
        }
    }
}

/// Hairline inner stroke that fades in from the menu bar towards the bottom edge.
struct AlertHairline: View {
    let style: NotchAlert.Style
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    var body: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: style.tint.opacity(0), location: 0),
                        .init(color: style.tint.opacity(0.15), location: 0.35),
                        .init(color: style.tint.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.25
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Accent light washing in from the icon side so the alert reads at a glance, plus one soft sheen that crosses
/// the alert as it arrives. Stays on the black fill, under the content.
/// Kept clear across the notch band: the camera housing is always hardware black, so colour beside it would
/// end in a hard edge. It fades in only below the notch.
struct AlertAmbientWash: View {
    private static let washRadiusFraction: CGFloat = 0.55
    /// How far below the notch the wash takes to reach full strength.
    private static let notchFadeHeight: CGFloat = 18
    private static let sheenWidthFraction: CGFloat = 0.35
    private static let sheenOpacity = 0.10
    private static let sheenDuration = 0.9
    private static let sheenDelay = 0.2

    let style: NotchAlert.Style
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// Height of the hardware notch band at the top; 0 on displays without a notch.
    var notchHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheenProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            ZStack {
                shape.fill(
                    RadialGradient(
                        colors: [style.tint.opacity(style.washOpacity), style.tint.opacity(0)],
                        center: UnitPoint(x: 0.08, y: 0.75),
                        startRadius: 0,
                        endRadius: proxy.size.width * Self.washRadiusFraction
                    )
                )
                shape.fill(
                    LinearGradient(
                        colors: [.clear, style.tint.opacity(style.washOpacity * 0.5)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                if !reduceMotion {
                    sheen(width: proxy.size.width).clipShape(shape)
                }
            }
            .mask { Self.belowNotchMask(height: proxy.size.height, notchHeight: notchHeight, fade: Self.notchFadeHeight) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Self.sheenDuration).delay(Self.sheenDelay)) { sheenProgress = 1 }
        }
    }

    /// Clear down to the notch's bottom edge, then a soft ramp to fully visible.
    static func belowNotchMask(height: CGFloat, notchHeight: CGFloat, fade: CGFloat) -> LinearGradient {
        let stops = belowNotchStops(height: height, notchHeight: notchHeight, fade: fade)
        return LinearGradient(
            stops: stops.map { .init(color: .black.opacity($0.opacity), location: $0.location) },
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Mask stops as unit locations: opacity 0 through the notch band, 1 once `fade` points below it.
    nonisolated static func belowNotchStops(height: CGFloat, notchHeight: CGFloat, fade: CGFloat) -> [(location: CGFloat, opacity: Double)] {
        guard height > 0, notchHeight > 0 else { return [(0, 1), (1, 1)] }
        let start = min(notchHeight / height, 1)
        let end = min((notchHeight + fade) / height, 1)
        return [(0, 0), (start, 0), (end, 1), (1, 1)]
    }

    private func sheen(width: CGFloat) -> some View {
        let sheenWidth = width * Self.sheenWidthFraction
        return LinearGradient(
            colors: [.clear, .white.opacity(Self.sheenOpacity), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: sheenWidth)
        .rotationEffect(.degrees(12))
        .offset(x: -sheenWidth + (width + sheenWidth) * sheenProgress - width / 2 + sheenWidth / 2)
        .opacity(sheenProgress >= 1 ? 0 : 1)
    }
}

/// Stacked-card edges peeking out under the alert while more alerts are queued.
struct AlertStackHint: View {
    private static let maxLayers = 2
    private static let layerInset: CGFloat = 22
    private static let layerPeek: CGFloat = 5
    private static let layerHeight: CGFloat = 24

    let queuedCount: Int
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach((0..<min(queuedCount, Self.maxLayers)).reversed(), id: \.self) { layer in
                let depth = CGFloat(layer + 1)
                UnevenRoundedRectangle(
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius
                )
                .fill(Color(white: 0.14 - 0.03 * Double(layer)))
                .overlay {
                    UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                }
                .frame(height: Self.layerHeight)
                .padding(.horizontal, Self.layerInset * depth)
                .offset(y: Self.layerPeek * depth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
