import SwiftUI

/// Slim level HUD laid into the black notch: icon in the left wing, value in the right, bar just below the notch.
struct NotchHUDView: View {
    struct Layout: Equatable {
        let notchHeight: CGFloat
        let notchWidth: CGFloat
        /// Horizontal inset of the wing content from the HUD edges.
        let sideInset: CGFloat
    }

    private static let iconSize: CGFloat = 13
    private static let barHeight: CGFloat = 4
    private static let barBottomInset: CGFloat = 6
    private static let barSideInset: CGFloat = 4
    private static let levelAnimation = Animation.spring(response: 0.25, dampingFraction: 0.85)

    let reading: HUDReading
    let layout: Layout

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: HUDLevel.systemImage(of: reading))
                    .font(.system(size: Self.iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: layout.notchWidth)

                Text(HUDLevel.valueText(of: reading))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: layout.notchHeight)
            .padding(.horizontal, layout.sideInset)

            Spacer(minLength: 0)

            if let level = HUDLevel.displayedLevel(of: reading) {
                LevelBar(level: level, tint: tint)
                    .frame(width: layout.notchWidth - Self.barSideInset * 2, height: Self.barHeight)
                    .padding(.bottom, Self.barBottomInset)
            }
        }
        .animation(Self.levelAnimation, value: reading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HUDLevel.title(of: reading.kind)) \(HUDLevel.valueText(of: reading))")
    }

    private var tint: Color {
        if reading.kind == .volume, reading.isMuted { return .white.opacity(0.4) }
        return .white
    }
}

private struct LevelBar: View {
    let level: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.18))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .scaleEffect(x: max(level, 0.001), y: 1, anchor: .leading)
            }
            .clipShape(.capsule)
    }
}
