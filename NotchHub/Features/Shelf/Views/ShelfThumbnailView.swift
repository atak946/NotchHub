import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Square preview for a shelf item: QuickLook thumbnail, image or text snippet.
struct ShelfThumbnailView: View {
    static let cornerRadius: CGFloat = 10
    private static let textPadding: CGFloat = 6
    private static let textFontSize: CGFloat = 9
    private static let textLineLimit = 5

    let item: ShelfItem
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        content
            .frame(width: side, height: side)
            .task(id: item.id) { await loadThumbnail() }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text(let string):
            Text(string)
                .font(.system(size: Self.textFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(Self.textLineLimit)
                .multilineTextAlignment(.leading)
                .padding(Self.textPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.quaternary, in: .rect(cornerRadius: Self.cornerRadius))
        case .file, .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(.quaternary)
            }
        }
    }

    private func loadThumbnail() async {
        switch item.kind {
        case .text:
            thumbnail = nil
        case .image(let data):
            thumbnail = NSImage(data: data)
        case .file(let url):
            thumbnail = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            let size = CGSize(width: side, height: side)
            if let cgImage = await Self.quickLookThumbnail(for: url, size: size, scale: displayScale) {
                thumbnail = NSImage(cgImage: cgImage, size: size)
            }
        }
    }

    private nonisolated static func quickLookThumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}
