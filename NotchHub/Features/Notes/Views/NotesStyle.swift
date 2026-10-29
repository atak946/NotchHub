import SwiftUI

/// Shared metrics for the notes module.
enum NotesStyle {
    static let listWidth: CGFloat = 196
    static let columnSpacing: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 8
    static let headerFontSize: CGFloat = 12
    static let rowTitleFontSize: CGFloat = 11.5
    static let captionFontSize: CGFloat = 10
    static let buttonFontSize: CGFloat = 11
    static let hoverAnimation = Animation.snappy(duration: 0.12)
}

/// Capsule header button matching the shelf's header buttons.
struct NotesCapsuleButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    var showsTitle = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showsTitle {
                    Label(title, systemImage: systemImage)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .font(.system(size: NotesStyle.buttonFontSize, weight: .medium))
            .padding(.horizontal, showsTitle ? 8 : 6)
            .padding(.vertical, 3)
            .background(background, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? (isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)) : AnyShapeStyle(.tertiary))
        .scaleEffect(isHovered && isEnabled ? 1.04 : 1)
        .onHover { isHovered = $0 }
        .animation(NotesStyle.hoverAnimation, value: isHovered)
        .help(title)
        .accessibilityLabel(title)
    }

    private var background: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(Color.accentColor.opacity(isHovered ? 1 : 0.85))
        }
        return AnyShapeStyle(.quaternary.opacity(isHovered ? 1 : 0.5))
    }
}
