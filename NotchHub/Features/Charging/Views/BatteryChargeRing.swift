import SwiftUI

/// Leading visual of power alerts: a ring that fills to the battery level with a spring, the bolt
/// (or battery) symbol in the middle, and a soft breathing glow while charging. Static with Reduce Motion.
struct BatteryChargeRing: View {
    private static let lineWidth: CGFloat = 3.5
    private static let symbolSize: CGFloat = 15
    /// The fill starts after the alert content has blurred in.
    private static let fillDelay: Duration = .milliseconds(180)
    private static let fillAnimation = Animation.spring(response: 0.9, dampingFraction: 0.82)
    private static let glowAnimation = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    /// A sliver of ring stays visible at 0 % so the shape still reads.
    private static let minimumTrim = 0.02
    private static let startLevelFraction = 0.35

    let glyph: AlertBatteryGlyph
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel: Double?
    @State private var isGlowing = false

    var body: some View {
        let level = shownLevel ?? (reduceMotion ? glyph.level : glyph.level * Self.startLevelFraction)
        ZStack {
            Circle()
                .fill(tint.opacity(isGlowing ? 0.26 : 0.14))
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: Self.lineWidth)
                .padding(Self.lineWidth / 2)
            Circle()
                .trim(from: 0, to: max(level, Self.minimumTrim))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(Self.lineWidth / 2)
                .shadow(color: tint.opacity(0.6), radius: isGlowing ? 4 : 1.5)
            Image(systemName: glyph.systemImage)
                .font(.system(size: Self.symbolSize, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: shownLevel != nil)
        }
        .task(id: glyph) { await animateIn() }
        .accessibilityHidden(true)
    }

    private func animateIn() async {
        guard !reduceMotion else {
            shownLevel = glyph.level
            return
        }
        do {
            try await Task.sleep(for: Self.fillDelay)
        } catch {
            return
        }
        withAnimation(Self.fillAnimation) { shownLevel = glyph.level }
        guard glyph.state == .charging else { return }
        withAnimation(Self.glowAnimation) { isGlowing = true }
    }
}
