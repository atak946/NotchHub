import SwiftUI

/// Shared ~140 × 70 pt tile used by every System feature on the Status tab.
struct SystemStatusTileView: View {
    static let size = CGSize(width: 140, height: 70)

    private static let cornerRadius: CGFloat = 14
    private static let iconSize: CGFloat = 24

    let systemImage: String
    let title: String
    let value: String
    let detail: String?
    let tint: Color
    let help: String
    let action: (@MainActor () -> Void)?

    @State private var isHovered = false

    init(
        systemImage: String,
        title: String,
        value: String,
        detail: String? = nil,
        tint: Color,
        help: String = "",
        action: (@MainActor () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .background(tint.opacity(0.2), in: .circle)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(tint.opacity(isHovered ? 0.2 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(isHovered ? 0.5 : 0.22), lineWidth: 1)
        )
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .scaleEffect(isHovered && action != nil ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Small filled dot for compact indicators (≤ 14 × 14 pt).
struct SystemIndicatorDot: View {
    static let frameSize: CGFloat = 14

    let systemImage: String
    let tint: Color
    let help: String

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: Self.frameSize - 2, height: Self.frameSize - 2)
        .frame(width: Self.frameSize, height: Self.frameSize)
        .help(help)
        .accessibilityLabel(help)
    }
}
