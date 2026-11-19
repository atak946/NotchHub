import SwiftUI

/// Previous / play-pause / next in the collapsed right wing, revealed while the pointer is over them.
/// Play-pause is a disc in the artwork's tint; the skip buttons stay quiet glyphs until hovered.
/// Purely visual: clicks arrive through `MediaControlsCatcherPanel`, so the hit rects come from
/// `NotchGeometry`, not from here.
struct CompactMediaControlsView: View {
    let isPlaying: Bool
    let isRevealed: Bool
    let hovered: MediaControlAction?
    let presses: [MediaControlAction: Int]
    let artwork: NSImage?
    var tints: ArtworkTintStore = .shared

    private enum Style {
        static let skipSymbolSize: CGFloat = 9.5
        static let playSymbolSize: CGFloat = 8.5
        static let discSize: CGFloat = 19
        static let hoverRingSize: CGFloat = 20
        static let skipRestingOpacity = 0.72
        static let hoverFillOpacity = 0.16
        static let revealOffset: CGFloat = -8
        static let revealStagger = 0.035
        static let reveal = Animation.spring(response: 0.32, dampingFraction: 0.72)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = discTint
        HStack(spacing: 0) {
            ForEach(MediaControlAction.allCases) { action in
                button(for: action, tint: tint)
                    .opacity(isRevealed ? 1 : 0)
                    .scaleEffect(isRevealed ? 1 : 0.6)
                    .offset(x: isRevealed || reduceMotion ? 0 : Style.revealOffset)
                    .animation(revealAnimation(for: action), value: isRevealed)
            }
        }
        .frame(width: NotchGeometry.mediaControlsWidth, height: NotchGeometry.mediaControlsBoxHeight)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .task(id: artwork.map(ObjectIdentifier.init)) {
            if let artwork { await tints.prepare(artwork) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(!isRevealed)
    }

    @ViewBuilder
    private func button(for action: MediaControlAction, tint: Color) -> some View {
        let isHovered = hovered == action
        Group {
            if action == .playPause {
                playPauseDisc(isHovered: isHovered, tint: tint)
            } else {
                skipGlyph(for: action, isHovered: isHovered)
            }
        }
        .symbolEffect(.bounce, value: presses[action, default: 0])
        .frame(width: NotchGeometry.mediaControlButtonWidth, height: NotchGeometry.mediaControlsBoxHeight)
        .accessibilityLabel(action.title(isPlaying: isPlaying))
    }

    private func playPauseDisc(isHovered: Bool, tint: Color) -> some View {
        Image(systemName: MediaControlAction.playPause.systemImage(isPlaying: isPlaying))
            .font(.system(size: Style.playSymbolSize, weight: .black))
            .foregroundStyle(.black.opacity(0.82))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Style.discSize, height: Style.discSize)
            .background(tint.gradient, in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: tint.opacity(isHovered ? 0.7 : 0.35), radius: isHovered ? 5 : 3)
            .scaleEffect(isHovered ? 1.08 : 1)
    }

    private func skipGlyph(for action: MediaControlAction, isHovered: Bool) -> some View {
        Image(systemName: action.systemImage(isPlaying: isPlaying))
            .font(.system(size: Style.skipSymbolSize, weight: .bold))
            .opacity(isHovered ? 1 : Style.skipRestingOpacity)
            .frame(width: Style.hoverRingSize, height: Style.hoverRingSize)
            .background(.white.opacity(isHovered ? Style.hoverFillOpacity : 0), in: .circle)
    }

    /// The artwork tint, lifted toward white so the black glyph on it always reads.
    private var discTint: Color {
        let tint = tints.tint(for: artwork)
        return Color(tint).mix(with: .white, by: 0.25)
    }

    private func revealAnimation(for action: MediaControlAction) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        let index = isRevealed ? action.rawValue : MediaControlAction.allCases.count - 1 - action.rawValue
        return Style.reveal.delay(Double(index) * Style.revealStagger)
    }
}
