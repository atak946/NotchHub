import SwiftUI

/// Live indicators beside the hardware notch while the panel is closed:
/// left wing = now playing (plus media controls when enabled),
/// right wing = meeting mic button, timer and status glyphs.
struct CompactWingsView: View {
    let model: NotchViewModel

    var body: some View {
        let wingWidth = model.wingWidth
        let services = model.services
        if wingWidth > 0 {
            HStack(spacing: 0) {
                HStack {
                    if services.hasCompactMedia {
                        MediaCompactView(media: services.media, visualizer: MediaVisualizerLayout.placement(
                            isEnabled: model.settings.showsMediaVisualizer,
                            wingWidth: wingWidth,
                            showsMediaControls: model.showsMediaControls
                        ))
                    }
                    Spacer(minLength: 0)
                    if model.showsMediaControls {
                        // Trailing edge must match NotchGeometry.mediaControlsRect (the click hit rects).
                        CompactMediaControlsView(
                            isPlaying: services.media.nowPlaying?.isPlaying ?? false,
                            hovered: model.hoveredMediaControl,
                            presses: model.mediaControlPresses
                        )
                        .padding(.trailing, NotchGeometry.mediaControlsNotchInset)
                        .transition(.opacity)
                    }
                }
                .frame(width: wingWidth)
                .padding(.leading, 6)

                Spacer(minLength: model.geometry.notchSize.width)

                HStack(spacing: 6) {
                    if model.showsMicMuteButton {
                        // Leading edge must match NotchGeometry.micMuteButtonRect (the click hit rect).
                        MicMuteWingButton(isMuted: services.system.micMute.isMuted, isHovered: model.isMicMuteHovered)
                            .padding(.leading, NotchGeometry.micMuteNotchInset)
                            .transition(.opacity)
                    }
                    // The wing keeps its width (wider would cover menu bar extras): glyphs that do not
                    // fit fold into a "+N" pill, dropping the lowest priority (last) ones first.
                    Group(subviews: trailingGlyphs(services)) { glyphs in
                        CompactGlyphRow(glyphs: glyphs)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: wingWidth)
                .padding(.trailing, 6)
            }
            .frame(height: model.geometry.notchSize.height)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Right wing glyphs in priority order, one subview each.
    @ViewBuilder
    private func trailingGlyphs(_ services: ModuleServices) -> some View {
        if services.hasCompactTimer {
            TimerCompactView(timer: services.timer)
        }
        if services.hasCompactIndicators {
            StatusCompactIndicators(services: services)
        }
    }
}

/// Shows as many glyphs as fit in the offered width and folds the rest into a "+N" pill.
struct CompactGlyphRow: View {
    static let spacing: CGFloat = 4

    let glyphs: SubviewsCollection

    var body: some View {
        // Candidates from "all glyphs" down to "only the pill"; ViewThatFits picks the first that fits.
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: glyphs.count, through: 0, by: -1)), id: \.self) { shown in
                HStack(spacing: Self.spacing) {
                    ForEach(glyphs.prefix(shown)) { $0 }
                    if shown < glyphs.count {
                        CompactOverflowPill(count: glyphs.count - shown)
                    }
                }
                .fixedSize()
            }
        }
    }
}

/// "+N" for glyphs that did not fit beside the notch; the panel lists them all.
private struct CompactOverflowPill: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.white.opacity(0.14), in: .capsule)
            .fixedSize()
            .help("\(count) gösterge daha")
            .accessibilityLabel("\(count) gösterge daha")
    }
}
