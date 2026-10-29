import SwiftUI

/// Soft accent glow spilling out under the notch; urgent alerts breathe gently.
struct AlertGlow: View {
    private static let blurRadius: CGFloat = 12
    private static let verticalOffset: CGFloat = 6
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
                        .init(color: style.tint.opacity(0.08), location: 0.4),
                        .init(color: style.tint.opacity(0.5), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
