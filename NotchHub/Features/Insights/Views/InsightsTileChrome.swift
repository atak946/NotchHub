import SwiftUI

/// Shared 140 × 70 pt tile surface with a tinted hover state.
struct InsightsTileChrome<Content: View>: View {
    static var size: CGSize { CGSize(width: 140, height: 70) }
    private static var cornerRadius: CGFloat { 12 }
    private static var padding: CGFloat { 9 }

    let tint: Color
    let help: String
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            content()
                .padding(Self.padding)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(tint.opacity(isHovered ? 0.24 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(isHovered ? 0.55 : 0.2), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(help)
    }
}
