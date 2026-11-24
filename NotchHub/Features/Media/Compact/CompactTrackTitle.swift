import SwiftUI

/// Track title in the room the artwork leaves in the collapsed left wing.
struct CompactTrackTitle: View {
    let track: NowPlaying

    /// Narrower than this only an ellipsis would show.
    static let minimumWidth: CGFloat = 36
    private static let pausedOpacity = 0.5

    var body: some View {
        Text(verbatim: track.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(track.isPlaying ? 0.9 : Self.pausedOpacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The artwork's label already reads the track.
            .accessibilityHidden(true)
    }
}

/// Full title and artist in a capsule under the notch while the collapsed media controls are in use.
/// Purely visual: the closed notch's window is click-through.
struct TrackTitlePill: View {
    let track: NowPlaying

    static let height: CGFloat = 26
    private static let maxWidth: CGFloat = 340
    private static let strokeOpacity = 0.09

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: track.title)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .layoutPriority(1)
            if !track.artist.isEmpty {
                Text(verbatim: track.artist)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background {
            Capsule()
                .fill(.black)
                .overlay { Capsule().strokeBorder(.white.opacity(Self.strokeOpacity), lineWidth: 1) }
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
        .frame(maxWidth: Self.maxWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
