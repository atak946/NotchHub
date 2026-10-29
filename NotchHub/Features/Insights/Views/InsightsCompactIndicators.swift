import SwiftUI

/// Closed-notch unread indicator: real icons of the busiest apps (max two, overlapped) with red count
/// badges and "+N" for more, within ~40 × 18 pt.
struct InsightsCompactIndicators: View {
    let insights: Insights

    private static let iconOverlap: CGFloat = -6
    private static let height: CGFloat = 18
    private static let overflowFontSize: CGFloat = 8

    init(insights: Insights) {
        self.insights = insights
    }

    var body: some View {
        let summary = CompactUnreadSummary(counts: insights.unread.counts)
        if insights.hasCompactIndicator, !summary.isEmpty {
            HStack(spacing: 2) {
                HStack(spacing: Self.iconOverlap) {
                    ForEach(summary.shown) { item in
                        UnreadAppBadgeIcon(item: item)
                    }
                }
                if summary.overflow > 0 {
                    Text("+\(summary.overflow)")
                        .font(.system(size: Self.overflowFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize()
                }
            }
            .frame(height: Self.height)
            .help(summary.tooltip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Okunmamış mesajlar: \(summary.tooltip)")
        } else {
            EmptyView()
        }
    }
}

/// One 16 pt app icon with a system-style red count badge on its top-right corner.
struct UnreadAppBadgeIcon: View {
    let item: UnreadAppCount

    private static let iconSize: CGFloat = 16
    private static let badgeHeight: CGFloat = 9
    private static let badgeFontSize: CGFloat = 7
    private static let badgeOffset = CGSize(width: 3, height: -2)

    var body: some View {
        icon
            .frame(width: Self.iconSize, height: Self.iconSize)
            .overlay(alignment: .topTrailing) {
                Text(CompactUnreadSummary.badgeText(for: item.count))
                    .font(.system(size: Self.badgeFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .frame(minWidth: Self.badgeHeight, minHeight: Self.badgeHeight)
                    .background(Capsule().fill(Color.red))
                    .offset(Self.badgeOffset)
            }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIconCache.shared.icon(forApp: item.app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.blue)
        }
    }
}
