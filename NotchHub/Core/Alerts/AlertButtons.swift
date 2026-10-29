import SwiftUI

/// Dark, material-like capsule with an accent hairline; presses squash slightly like a haptic tap.
struct AlertActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        AlertActionLabel(configuration: configuration, tint: tint)
    }
}

private struct AlertActionLabel: View {
    private static let pressedScale: CGFloat = 0.92

    let configuration: ButtonStyleConfiguration
    let tint: Color
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.white.opacity(isPressed ? 0.20 : (isHovered ? 0.16 : 0.10)))
                    .overlay {
                        Capsule().fill(tint.opacity(isHovered ? 0.22 : 0.14))
                    }
                    .overlay {
                        Capsule().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.22), tint.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        )
                    }
            }
            .contentShape(.capsule)
            .scaleEffect(isPressed && !reduceMotion ? Self.pressedScale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Quiet close glyph that gains a circle on hover.
struct AlertCloseButton: View {
    private static let size: CGFloat = 22

    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.45))
                .frame(width: Self.size, height: Self.size)
                .background(.white.opacity(isHovered ? 0.12 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Kapat")
        .accessibilityLabel("Kapat")
    }
}
