import SwiftUI

/// Closed-notch indicator: tiny artwork (plus the optional music visualizer), or equalizer bars when
/// no artwork is available.
struct MediaCompactView: View {
    let media: MediaService
    let visualizer: MediaVisualizerPlacement
    let tints: ArtworkTintStore

    /// Re-runs tint extraction when the artwork changes or the visualizer is switched on.
    private struct TintRequest: Hashable {
        let image: ObjectIdentifier
        let isNeeded: Bool
    }

    private static let artworkSize = MediaVisualizerLayout.artworkSize
    private static let artworkRadius: CGFloat = 5
    private static let overlayPadding: CGFloat = 2
    private static let overlayBackdropOpacity = 0.55

    init(media: MediaService, visualizer: MediaVisualizerPlacement = .hidden, tints: ArtworkTintStore = .shared) {
        self.media = media
        self.visualizer = visualizer
        self.tints = tints
    }

    var body: some View {
        if let track = media.nowPlaying {
            Group {
                if let image = media.artwork {
                    HStack(spacing: MediaVisualizerLayout.besideGap) {
                        artwork(image, isPlaying: track.isPlaying)
                            .overlay(alignment: .bottomTrailing) {
                                if visualizer == .overlay {
                                    overlayBars(image, isPlaying: track.isPlaying)
                                }
                            }
                        if visualizer == .beside {
                            MediaVisualizerView(isPlaying: track.isPlaying, tint: Color(tints.tint(for: image)))
                                .frame(width: MediaVisualizerLayout.barsWidth, height: MediaVisualizerLayout.barHeight)
                        }
                    }
                    .task(id: TintRequest(image: ObjectIdentifier(image), isNeeded: visualizer != .hidden)) {
                        guard visualizer != .hidden else { return }
                        await tints.prepare(image)
                    }
                } else if visualizer == .hidden {
                    MediaEqualizerView(isPlaying: track.isPlaying)
                        .frame(width: 16, height: 14)
                        .foregroundStyle(.white)
                } else {
                    MediaVisualizerView(isPlaying: track.isPlaying, tint: .white)
                        .frame(width: MediaVisualizerLayout.barsWidth, height: MediaVisualizerLayout.barHeight)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: track.isPlaying)
            .help("\(track.title) — \(track.artist)")
            .accessibilityLabel("Şimdi çalıyor: \(track.title) - \(track.artist)")
        }
    }

    private func artwork(_ image: NSImage, isPlaying: Bool) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.artworkSize, height: Self.artworkSize)
            .clipShape(.rect(cornerRadius: Self.artworkRadius, style: .continuous))
            .opacity(isPlaying ? 1 : 0.6)
    }

    private func overlayBars(_ image: NSImage, isPlaying: Bool) -> some View {
        MediaVisualizerView(
            isPlaying: isPlaying,
            tint: Color(tints.tint(for: image)),
            barWidth: MediaVisualizerLayout.overlayBarWidth,
            spacing: MediaVisualizerLayout.overlayBarSpacing
        )
        .frame(height: MediaVisualizerLayout.overlayBarHeight)
        .padding(Self.overlayPadding)
        .background(.black.opacity(Self.overlayBackdropOpacity), in: .rect(cornerRadius: 3, style: .continuous))
    }
}
