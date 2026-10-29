import SwiftUI

enum DevOpsTileMetrics {
    static let size = CGSize(width: 140, height: 70)
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 9
    static let iconSize: CGFloat = 13
    static let hoverOpacity: Double = 0.16
    static let restOpacity: Double = 0.08
    static let pressedScale: CGFloat = 0.97
}

/// Shared tile layout: icon + title on top, a bold value and a secondary detail line.
struct DevOpsTileChrome: View {
    let systemImage: String
    let title: String
    let value: String
    let detail: String?
    let tint: Color
    let action: (() -> Void)?

    @State private var isHovered = false

    init(systemImage: String, title: String, value: String, detail: String?, tint: Color, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(DevOpsTileButtonStyle(isHovered: isHovered, tint: tint))
            } else {
                content.modifier(DevOpsTileBackground(isHovered: isHovered, isPressed: false, tint: tint))
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)\(detail.map { ", \($0)" } ?? "")")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: DevOpsTileMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(DevOpsTileMetrics.padding)
        .frame(width: DevOpsTileMetrics.size.width, height: DevOpsTileMetrics.size.height, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: DevOpsTileMetrics.cornerRadius))
    }
}

private struct DevOpsTileButtonStyle: ButtonStyle {
    let isHovered: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(DevOpsTileBackground(isHovered: isHovered, isPressed: configuration.isPressed, tint: tint))
    }
}

private struct DevOpsTileBackground: ViewModifier {
    let isHovered: Bool
    let isPressed: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: DevOpsTileMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? DevOpsTileMetrics.hoverOpacity : DevOpsTileMetrics.restOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DevOpsTileMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(isHovered ? 0.6 : 0.25), lineWidth: 1)
            )
            .scaleEffect(isPressed ? DevOpsTileMetrics.pressedScale : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}
