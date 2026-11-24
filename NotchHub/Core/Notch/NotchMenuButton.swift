import SwiftUI

/// Gear at the end of the panel header; opens the app menu (settings, pause, quit…).
struct NotchMenuButton: View {
    /// Receives the button's frame in the hosting view's coordinates, where the menu hangs from.
    let onOpen: (CGRect) -> Void

    @State private var frame = CGRect.zero
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen(frame)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6))
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frame = $0 })
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("NotchHub menüsü")
        .accessibilityLabel("NotchHub menüsü")
    }
}
