import AppKit
import SwiftUI

/// One clipboard tile: text snippet or image thumbnail, relative time, hover actions.
struct ClipboardEntryTile: View {
    private static let width: CGFloat = ShelfItemTile.width
    private static let side: CGFloat = ShelfItemTile.thumbnailSide
    private static let padding: CGFloat = 5
    private static let footerHeight: CGFloat = 18
    private static let cornerRadius: CGFloat = 12
    private static let hoverScale: CGFloat = 1.04
    private static let footerFontSize: CGFloat = 10
    private static let textFontSize: CGFloat = 9
    private static let textLineLimit = 5

    let entry: ClipboardEntry
    let imageURL: URL?
    let timeText: String
    let isCopied: Bool
    let handlers: ShelfMouseHandlers
    let actions: [ShelfTileAction]

    @State private var isPreviewHovered = false
    @State private var isFooterHovered = false
    @State private var thumbnail: NSImage?

    private var isHovering: Bool { isPreviewHovered || isFooterHovered }

    var body: some View {
        VStack(spacing: 4) {
            preview
            footer
        }
        .frame(width: Self.width)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .animation(.snappy(duration: 0.18), value: isCopied)
        .help(entry.previewText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isImage ? "Görsel, \(timeText)" : "\(entry.previewText), \(timeText)")
    }

    private var preview: some View {
        content
            .frame(width: Self.side, height: Self.side)
            .padding(Self.padding)
            .background(highlight)
            .scaleEffect(isPreviewHovered ? Self.hoverScale : 1)
            .overlay(ShelfMouseArea(handlers: hoverTrackingHandlers))
            .task(id: entry.id) { loadThumbnail() }
    }

    @ViewBuilder
    private var content: some View {
        if let text = entry.text {
            Text(text)
                .font(.system(size: Self.textFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(Self.textLineLimit)
                .multilineTextAlignment(.leading)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.quaternary, in: .rect(cornerRadius: ShelfThumbnailView.cornerRadius))
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: ShelfThumbnailView.cornerRadius)
                .fill(.quaternary)
        }
    }

    private var highlight: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(isCopied ? AnyShapeStyle(Color.green.opacity(0.25)) : AnyShapeStyle(.clear))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(isCopied ? Color.green : .clear, lineWidth: 1.5)
            }
    }

    private var footer: some View {
        ZStack {
            if isHovering {
                HStack(spacing: 2) {
                    ForEach(actions) { action in
                        Button(action: action.perform) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(ShelfIconButtonStyle(isDestructive: action.isDestructive))
                        .help(action.title)
                        .accessibilityLabel(action.title)
                    }
                }
                .transition(.opacity)
            } else {
                Label(isCopied ? "Kopyalandı" : timeText, systemImage: isCopied ? "checkmark" : (entry.isImage ? "photo" : "text.alignleft"))
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: Self.footerFontSize, weight: .medium).monospacedDigit())
                    .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
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

    private func loadThumbnail() {
        guard entry.isImage, let imageURL else { return }
        thumbnail = NSImage(contentsOf: imageURL)
    }
}
