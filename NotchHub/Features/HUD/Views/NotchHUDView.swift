import SwiftUI

/// Level HUD as a floating capsule under the notch: icon, bar and value in one row, like an island.
struct NotchHUDView: View {
    struct Layout: Equatable {
        /// Size of the capsule.
        let pillSize: CGSize
    }

    /// Set while the HUD can be dragged; without it the whole view is click-through.
    struct Interaction {
        let isDragging: Bool
        /// The level under the pointer, on every drag update.
        let onDrag: (Double) -> Void
        let onDragEnded: () -> Void
    }

    private static let iconSize: CGFloat = 13
    private static let iconWidth: CGFloat = 18
    private static let valueWidth: CGFloat = 36
    private static let barHeight: CGFloat = 5
    private static let horizontalPadding: CGFloat = 14
    private static let spacing: CGFloat = 10
    private static let batteryFontSize: CGFloat = 9
    private static let batterySpacing: CGFloat = 3
    private static let batteryOpacity = 0.6
    private static let mutedOpacity = 0.4
    private static let strokeOpacity = 0.09
    private static let shadowRadius: CGFloat = 10
    private static let levelAnimation = Animation.spring(response: 0.25, dampingFraction: 0.85)
    private static let tintAnimation = Animation.easeInOut(duration: 0.35)

    let reading: HUDReading
    let layout: Layout
    /// The bar colour (artwork tint while a track plays); muted volume ignores it.
    var accent: RGBColor = .white
    /// Bumped each time the level lands on an end of the bar; plays the bounce and glow.
    var edgeHits = 0
    var interaction: Interaction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.spacing) {
            leadingIcon
                .allowsHitTesting(false)

            if let level = HUDLevel.displayedLevel(of: reading) {
                bar(level: level)
            } else {
                Text(HUDLevel.title(of: reading.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(HUDLevel.valueText(of: reading))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(minWidth: Self.valueWidth, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: layout.pillSize.width, height: layout.pillSize.height)
        .background { capsule }
        .animation(interaction?.isDragging == true ? nil : Self.levelAnimation, value: reading)
        .animation(reduceMotion ? nil : Self.tintAnimation, value: accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var capsule: some View {
        Capsule()
            .fill(.black)
            .overlay { Capsule().strokeBorder(.white.opacity(Self.strokeOpacity), lineWidth: 1) }
            .shadow(color: .black.opacity(0.45), radius: Self.shadowRadius, y: 4)
    }

    private var leadingIcon: some View {
        HStack(spacing: Self.batterySpacing) {
            Image(systemName: HUDLevel.systemImage(of: reading), variableValue: HUDLevel.symbolVariableValue(of: reading))
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.iconWidth)

            if reading.kind == .volume, let battery = reading.output?.batteryPercent {
                Text((Double(battery) / 100).formatted(.percent))
                    .font(.system(size: Self.batteryFontSize, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(Self.batteryOpacity))
                    .lineLimit(1)
            }
        }
    }

    /// The bar fills the space between icon and value; its full-height row takes the drag.
    private func bar(level: Double) -> some View {
        GeometryReader { proxy in
            let barWidth = proxy.size.width
            LevelBar(level: level, tint: tint, edge: HUDLevel.edge(of: reading), edgeHits: edgeHits)
                .frame(width: barWidth, height: Self.barHeight)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(dragGesture(barWidth: barWidth))
                .allowsHitTesting(interaction != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func dragGesture(barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                interaction?.onDrag(HUDInteractionMath.level(atX: value.location.x, barWidth: barWidth, inset: 0))
            }
            .onEnded { _ in interaction?.onDragEnded() }
    }

    private var tint: Color {
        if reading.kind == .volume, reading.isMuted { return .white.opacity(Self.mutedOpacity) }
        return Color(accent)
    }

    private var accessibilityText: String {
        var parts = ["\(HUDLevel.title(of: reading.kind)) \(HUDLevel.valueText(of: reading))"]
        if let output = reading.output {
            parts.append(output.name)
            if let battery = output.batteryPercent {
                parts.append(HeadphoneBatteryFormatter.Part(kind: .main, level: battery).text)
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// Track plus fill; at either end it overshoots a few points and glows once per `edgeHits` bump.
private struct LevelBar: View {
    private struct Bounce {
        var offset: CGFloat = 0
        var glow: Double = 0
    }

    private static let overshoot: CGFloat = 3
    private static let rebound: CGFloat = -1
    private static let glowRadius: CGFloat = 5
    private static let glowPeak = 0.7

    let level: Double
    let tint: Color
    let edge: HUDLevelEdge?
    let edgeHits: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The animator's content closure is not main-actor isolated; read view state up front.
        // Reduce Motion keeps the glow but drops the movement.
        let offsetScale = reduceMotion ? 0 : direction
        let glowTint = tint
        let glowRadius = Self.glowRadius
        return Capsule()
            .fill(.white.opacity(0.18))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .scaleEffect(x: max(level, 0.001), y: 1, anchor: .leading)
            }
            .clipShape(.capsule)
            .keyframeAnimator(initialValue: Bounce(), trigger: edgeHits) { bar, bounce in
                bar
                    .offset(x: bounce.offset * offsetScale)
                    .background {
                        Capsule()
                            .fill(glowTint)
                            .blur(radius: glowRadius)
                            .opacity(bounce.glow)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    SpringKeyframe(Self.overshoot, duration: 0.12, spring: .snappy)
                    SpringKeyframe(Self.rebound, duration: 0.12)
                    SpringKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.glow) {
                    CubicKeyframe(Self.glowPeak, duration: 0.12)
                    CubicKeyframe(0, duration: 0.5)
                }
            }
    }

    /// Pushes past the right end when full, past the left end when empty.
    private var direction: CGFloat {
        edge == .empty ? -1 : 1
    }
}
