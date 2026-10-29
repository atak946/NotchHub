import SwiftUI

/// A dark, wallpaper-like desktop with a slim menu bar; the notch content hangs from the top centre.
struct DemoDesktop<Content: View>: View {
    static var menuBarHeight: CGFloat { DemoStage.geometry.notchSize.height }

    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            DemoWallpaper()
            DemoMenuBar()
                .frame(height: Self.menuBarHeight)
            content
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

/// Deep navy base with soft violet, magenta and teal light, like a macOS dark wallpaper.
struct DemoWallpaper: View {
    private struct Glow {
        let color: Color
        let center: UnitPoint
        let radius: CGFloat
    }

    private static let base = LinearGradient(
        colors: [Color(red: 0.05, green: 0.05, blue: 0.13), Color(red: 0.09, green: 0.06, blue: 0.18)],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let glows = [
        Glow(color: Color(red: 0.47, green: 0.27, blue: 0.95), center: UnitPoint(x: 0.18, y: 0.95), radius: 0.75),
        Glow(color: Color(red: 0.93, green: 0.30, blue: 0.62), center: UnitPoint(x: 0.85, y: 1.05), radius: 0.6),
        Glow(color: Color(red: 0.16, green: 0.62, blue: 0.80), center: UnitPoint(x: 0.62, y: 0.15), radius: 0.45),
    ]

    var body: some View {
        GeometryReader { proxy in
            let extent = max(proxy.size.width, proxy.size.height)
            ZStack {
                Self.base
                ForEach(Self.glows.indices, id: \.self) { index in
                    let glow = Self.glows[index]
                    RadialGradient(
                        colors: [glow.color.opacity(0.55), glow.color.opacity(0)],
                        center: glow.center,
                        startRadius: 0,
                        endRadius: extent * glow.radius
                    )
                }
            }
        }
    }
}

/// Generic menu bar: an Apple logo on the left, status glyphs on the right; no real app or clock data.
struct DemoMenuBar: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Image(systemName: "switch.2")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.22))
    }
}

/// The real notch root view on the demo desktop.
struct DemoNotchScene: View {
    let stage: DemoStage
    let size: CGSize

    var body: some View {
        DemoDesktop(size: size) {
            NotchRootView(model: stage.model, alerts: stage.alerts, displayID: 0)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
    }
}

/// The Settings window content (sidebar and one page) as a floating window over the demo wallpaper.
struct DemoSettingsScene: View {
    static let windowSize = CGSize(width: 1000, height: 680)
    static let size = CGSize(width: 1080, height: 760)
    private static let sidebarWidth: CGFloat = 236
    private static let cornerRadius: CGFloat = 14

    let stage: DemoStage
    let category: SettingsCategory
    let query: String

    var body: some View {
        ZStack {
            DemoWallpaper()
            window
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var window: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: .constant(category), query: .constant(query))
                .frame(width: Self.sidebarWidth)
            SettingsDetailView(
                category: category,
                settings: stage.settings,
                language: stage.language,
                services: stage.services,
                updater: stage.updater
            )
        }
        // The real backdrop's film grain would bloat every PNG; a smooth wallpaper keeps the glow.
        .background { DemoWallpaper().overlay(Color.black.opacity(0.35)) }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}
