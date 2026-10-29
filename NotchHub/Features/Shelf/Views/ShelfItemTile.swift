import SwiftUI

/// One tile: preview, selection highlight, name and hover quick actions.
struct ShelfItemTile: View {
    static let width: CGFloat = 78
    static let thumbnailSide: CGFloat = 54
    private static let thumbnailPadding: CGFloat = 5
    private static let footerHeight: CGFloat = 18
    private static let selectionCornerRadius: CGFloat = 12
    private static let hoverScale: CGFloat = 1.04
    private static let nameFontSize: CGFloat = 10

    let item: ShelfItem
    let isSelected: Bool
    let handlers: ShelfMouseHandlers
    let quickActions: [ShelfTileAction]

    @State private var isPreviewHovered = false
    @State private var isFooterHovered = false

    private var isHovering: Bool { isPreviewHovered || isFooterHovered }

    var body: some View {
        VStack(spacing: 4) {
            preview
            footer
        }
        .frame(width: Self.width)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .help(item.displayName)
    }

    private var preview: some View {
        ShelfThumbnailView(item: item, side: Self.thumbnailSide)
            .padding(Self.thumbnailPadding)
            .background(selectionBackground)
            .scaleEffect(isPreviewHovered ? Self.hoverScale : 1)
            .overlay(ShelfMouseArea(handlers: hoverTrackingHandlers))
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: Self.selectionCornerRadius)
            .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.35)) : AnyShapeStyle(.clear))
            .overlay {
                RoundedRectangle(cornerRadius: Self.selectionCornerRadius)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
    }

    private var footer: some View {
        ZStack {
            if isHovering {
                HStack(spacing: 2) {
                    ForEach(quickActions) { action in
                        ShelfHoverButton(action: action)
                    }
                }
                .transition(.opacity)
            } else {
                Text(item.displayName)
                    .font(.system(size: Self.nameFontSize, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.width, height: Self.footerHeight)
        .contentShape(.rect)
        .onHover { isFooterHovered = $0 }
    }

    private var hoverTrackingHandlers: ShelfMouseHandlers {
        var tracked = handlers
        let isHovered = $isPreviewHovered
        tracked.onHover = { isHovered.wrappedValue = $0 }
        return tracked
    }
}

private struct ShelfHoverButton: View {
    private static let side: CGFloat = 18
    private static let iconSize: CGFloat = 10

    let action: ShelfTileAction

    var body: some View {
        Button(action: action.perform) {
            Image(systemName: action.systemImage)
                .font(.system(size: Self.iconSize, weight: .semibold))
                .frame(width: Self.side, height: Self.side)
        }
        .buttonStyle(ShelfIconButtonStyle(isDestructive: action.isDestructive))
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

/// Small circular icon button with designed hover / pressed feedback.
struct ShelfIconButtonStyle: ButtonStyle {
    private static let pressedScale: CGFloat = 0.88
    private static let hoverScale: CGFloat = 1.08

    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, isDestructive: isDestructive)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let isDestructive: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered && isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .background(.quaternary.opacity(isHovered ? 1 : 0.6), in: .circle)
                .scaleEffect(configuration.isPressed ? ShelfIconButtonStyle.pressedScale : (isHovered ? ShelfIconButtonStyle.hoverScale : 1))
                .contentShape(.circle)
                .onHover { isHovered = $0 }
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.snappy(duration: 0.12), value: isHovered)
        }
    }
}
