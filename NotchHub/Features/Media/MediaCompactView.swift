import SwiftUI

/// Closed-notch indicator: tiny artwork (plus the optional music visualizer), or equalizer bars when
/// no artwork is available.
struct MediaCompactView: View {
    let media: MediaService
    let visualizer: MediaVisualizerPlacement
    let tints: ArtworkTintStore

    private static let artworkSize = MediaVisualizerLayout.artworkSize
    private static let artworkRadius: CGFloat = 6
    private static let pausedSaturation = 0.25
    private static let pausedScale: CGFloat = 0.9
    private static let glowOpacity = 0.55
    private static let glowRadius: CGFloat = 5
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
                        artwork(image, isPlaying: track.isPlaying, tint: Color(tints.tint(for: image)))
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
                    .task(id: ObjectIdentifier(image)) {
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

    /// Rounded cover with a hairline rim and a soft glow in its own color while playing;
    /// paused it shrinks, desaturates and shows a small pause glyph.
    private func artwork(_ image: NSImage, isPlaying: Bool, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.artworkRadius, style: .continuous)
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.artworkSize, height: Self.artworkSize)
            .saturation(isPlaying ? 1 : Self.pausedSaturation)
            .overlay {
                if !isPlaying {
                    ZStack {
                        Color.black.opacity(0.4)
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: tint.opacity(isPlaying ? Self.glowOpacity : 0), radius: Self.glowRadius)
            .scaleEffect(isPlaying ? 1 : Self.pausedScale)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPlaying)
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
