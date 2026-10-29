import SwiftUI

/// Elevation of a glass container.
enum GlassSurfaceLevel {
    /// Flush grouping, e.g. the sidebar panel.
    case inset
    /// Default card on the backdrop.
    case raised
}

private struct GlassSurfaceModifier: ViewModifier {
    private static let shadowRadius: CGFloat = 6
    private static let shadowOpacity = 0.28

    let level: GlassSurfaceLevel
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(SettingsTheme.Palette.solidSurface)
                } else {
                    switch level {
                    case .inset:
                        shape.fill(Color.white.opacity(0.035))
                    case .raised:
                        ZStack {
                            shape.fill(SettingsTheme.Palette.glass)
                            shape.fill(Color.white.opacity(0.04))
                        }
                    }
                }
            }
            .overlay(shape.strokeBorder(edgeLight, lineWidth: 1).allowsHitTesting(false))
            // Kept small on purpose: SwiftUI renders shadows on the CPU and cost grows with the radius.
            .shadow(color: .black.opacity(level == .raised ? Self.shadowOpacity : 0), radius: Self.shadowRadius, y: 3)
    }

    /// Light catching the top edge of the glass, fading towards the bottom.
    private var edgeLight: LinearGradient {
        let top = level == .raised ? 0.16 : 0.08
        return LinearGradient(colors: [.white.opacity(top), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
    }
}

private enum GlowLimits {
    static let maxRadius: CGFloat = 6
}

extension View {
    /// Wraps the view in a frosted glass card. Apply padding before calling.
    func glassSurface(_ level: GlassSurfaceLevel = .raised, radius: CGFloat = SettingsTheme.Radius.l) -> some View {
        modifier(GlassSurfaceModifier(level: level, radius: radius))
    }

    /// Soft colored halo; the radius is capped because shadows are blurred on the CPU.
    func glassGlow(_ color: Color, radius: CGFloat = 8, opacity: Double = 0.55) -> some View {
        shadow(color: color.opacity(opacity), radius: min(radius, GlowLimits.maxRadius))
    }
}

/// Hairline divider between rows inside a glass card.
struct GlassDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(SettingsTheme.Palette.hairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// Glossy rounded square with a white glyph on a tinted gradient.
struct GlassIconTile: View {
    let symbol: String
    var tint: Color = SettingsTheme.Palette.brand
    var size: CGFloat = 22
    var glows = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: size, height: size)
            .background(shape.fill(SettingsTheme.gradient(for: tint)))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: tint.opacity(glows ? 0.6 : 0.25), radius: glows ? 5 : 2, y: 1)
            .accessibilityHidden(true)
    }
}
