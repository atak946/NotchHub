import SwiftUI

/// Design tokens of the Settings window. Direction: "dark glass": a deep, softly drifting color
/// backdrop, frosted cards with lit edges, glowing violet → pink accents and tight SF Pro Display
/// titles. The window is always dark.
enum SettingsTheme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Horizontal padding inside a card row.
        static let rowHorizontal: CGFloat = 14
        /// Vertical padding inside a card row.
        static let rowVertical: CGFloat = 9
        /// Height of the transparent title bar the content runs under.
        static let titleBar: CGFloat = 28
    }

    enum Radius {
        static let s: CGFloat = 7
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        static let xl: CGFloat = 18
    }

    enum Motion {
        static let hover = Animation.easeOut(duration: 0.16)
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let selection = Animation.spring(response: 0.32, dampingFraction: 0.86)
    }

    enum Palette {
        /// Base of the backdrop behind every glass surface.
        static let canvas = Color(red: 0.035, green: 0.035, blue: 0.075)
        /// Opaque card fill used when Reduce Transparency is on.
        static let solidSurface = Color(red: 0.11, green: 0.105, blue: 0.16)

        static let brand = Color(red: 0.52, green: 0.38, blue: 1.0)
        static let brandSecondary = Color(red: 0.96, green: 0.36, blue: 0.74)
        static let brandTertiary = Color(red: 0.26, green: 0.78, blue: 1.0)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.4)

        static let hairline = Color.white.opacity(0.08)
        static let hoverFill = Color.white.opacity(0.06)
        static let pressedFill = Color.white.opacity(0.11)
        static let controlFill = Color.white.opacity(0.12)
        /// Frosted-glass tint used instead of live materials: the backdrop is already a soft blur,
        /// so a translucent fill looks the same without per-frame backdrop blurring.
        static let glass = Color(red: 0.62, green: 0.58, blue: 0.86).opacity(0.10)
    }

    enum Typography {
        static let pageTitle = Font.system(size: 26, weight: .bold)
        static let pageSubtitle = Font.system(size: 12.5)
        static let sectionTitle = Font.system(size: 12, weight: .semibold)
        static let sidebarGroup = Font.system(size: 10.5, weight: .bold)
        static let row = Font.system(size: 13)
        /// SF Pro Display looks best slightly tightened at display sizes.
        static let displayTracking: CGFloat = -0.6
    }

    /// Violet → pink signature gradient for selection, switches and highlights.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [Palette.brand, Palette.brandSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Title text: bright white fading slightly downwards.
    static var textGradient: LinearGradient {
        LinearGradient(colors: [.white, .white.opacity(0.74)], startPoint: .top, endPoint: .bottom)
    }

    /// Top-lit gradient for a tint, used by icon tiles.
    static func gradient(for tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(0.78), tint], startPoint: .top, endPoint: .bottom)
    }
}
