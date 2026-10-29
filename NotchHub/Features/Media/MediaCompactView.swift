import SwiftUI

/// Closed-notch indicator (~28 × 24 pt): tiny artwork, or equalizer bars when no artwork is available.
struct MediaCompactView: View {
    let media: MediaService

    private static let artworkSize: CGFloat = 22
    private static let artworkRadius: CGFloat = 5

    init(media: MediaService) {
        self.media = media
    }

    var body: some View {
        if let track = media.nowPlaying {
            Group {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.artworkSize, height: Self.artworkSize)
                        .clipShape(.rect(cornerRadius: Self.artworkRadius, style: .continuous))
                        .opacity(track.isPlaying ? 1 : 0.6)
                } else {
                    MediaEqualizerView(isPlaying: track.isPlaying)
                        .frame(width: 16, height: 14)
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: track.isPlaying)
            .help("\(track.title) — \(track.artist)")
            .accessibilityLabel("Şimdi çalıyor: \(track.title) - \(track.artist)")
        }
    }
}
