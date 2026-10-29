import SwiftUI

/// Previous / play-pause / next box shown in the collapsed left wing. Purely visual: clicks arrive
/// through `MediaControlsCatcherPanel`, so the hit rects come from `NotchGeometry`, not from here.
struct CompactMediaControlsView: View {
    let isPlaying: Bool
    let hovered: MediaControlAction?
    let presses: [MediaControlAction: Int]

    private static let symbolSize: CGFloat = 11
    private static let restingOpacity = 0.8
    private static let hoverFillOpacity = 0.18
    private static let boxFillOpacity = 0.08

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MediaControlAction.allCases) { action in
                button(for: action)
            }
        }
        .frame(width: NotchGeometry.mediaControlsWidth, height: NotchGeometry.mediaControlsBoxHeight)
        .background(.white.opacity(Self.boxFillOpacity), in: .capsule)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .allowsHitTesting(false)
    }

    private func button(for action: MediaControlAction) -> some View {
        let isHovered = hovered == action
        return Image(systemName: action.systemImage(isPlaying: isPlaying))
            .font(.system(size: Self.symbolSize, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: presses[action, default: 0])
            .opacity(isHovered ? 1 : Self.restingOpacity)
            .frame(width: NotchGeometry.mediaControlButtonWidth, height: NotchGeometry.mediaControlsBoxHeight)
            .background(.white.opacity(isHovered ? Self.hoverFillOpacity : 0), in: .capsule)
            .accessibilityLabel(action.title(isPlaying: isPlaying))
    }
}
