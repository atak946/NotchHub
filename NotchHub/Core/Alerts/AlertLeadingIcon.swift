import SwiftUI

/// 38pt leading visual: sender avatar (with app badge), the real app icon, or a tinted symbol.
struct AlertLeadingIcon: View {
    static let size: CGFloat = 38
    private static let badgeSize: CGFloat = 17
    private static let badgeOffset: CGFloat = 3

    let alert: NotchAlert
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appIcon: NSImage? {
        guard alert.appBundleID != nil || alert.appName != nil else { return nil }
        return AppIconResolver.shared.icon(bundleID: alert.appBundleID, appName: alert.appName)
    }

    var body: some View {
        let icon = appIcon
        Group {
            if let sender = alert.sender, let initials = Monogram.initials(for: sender) {
                MonogramAvatar(name: sender, initials: initials, size: Self.size)
                    .overlay(alignment: .bottomTrailing) {
                        badge(icon)
                    }
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            } else {
                AlertSymbolBadge(systemImage: alert.systemImage, tint: alert.style.tint)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .overlay(alignment: .bottomTrailing) {
            if alert.style == .success, alert.sender == nil {
                SuccessCheckBadge(size: Self.badgeSize, animates: !reduceMotion)
                    .offset(x: Self.badgeOffset, y: Self.badgeOffset)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(alert.sender ?? alert.sourceLabel)
    }

    @ViewBuilder
    private func badge(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .offset(x: Self.badgeOffset, y: Self.badgeOffset)
        }
    }
}

/// Tinted SF Symbol in a soft gradient circle with an inner top highlight.
struct AlertSymbolBadge: View {
    /// Waits for the content's blur-in so the bounce is actually visible.
    private static let entryDelay: Duration = .milliseconds(220)

    let systemImage: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped on appear so the symbol bounces once as the alert content lands.
    @State private var hasEntered = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [tint.opacity(0.36), tint.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75
                )
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: hasEntered)
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: Self.entryDelay)
            hasEntered = true
        }
    }
}

/// Small green check that bounces in once when a success alert appears.
private struct SuccessCheckBadge: View {
    private static let entryDelay: Duration = .milliseconds(260)

    let size: CGFloat
    let animates: Bool
    @State private var isShown = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, NotchAlert.Style.success.tint)
            .background(Circle().fill(.black).padding(1))
            .symbolEffect(.bounce, options: .nonRepeating, value: isShown)
            .task {
                guard animates else { return }
                try? await Task.sleep(for: Self.entryDelay)
                isShown = true
            }
            .accessibilityHidden(true)
    }
}
