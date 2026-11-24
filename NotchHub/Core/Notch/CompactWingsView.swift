import SwiftUI

/// Live indicators beside the hardware notch while the panel is closed:
/// left wing = now playing artwork, plus the track title or overflow status glyphs in the room it leaves;
/// right wing = meeting mic button, timer and status glyphs; the media controls replace the glyphs
/// while the pointer is over them.
///
/// The wings keep their width (wider would cover menu bar extras). Glyphs that do not fit move to an
/// empty left wing, and the rest fold into a "+N" pill (see `CompactGlyphSplit`).
struct CompactWingsView: View {
    let model: NotchViewModel

    /// Natural width of each status glyph, keyed by subview id; filled by the hidden measuring row.
    @State private var glyphWidths: [AnyHashable: CGFloat] = [:]

    var body: some View {
        let wingWidth = model.wingWidth
        if wingWidth > 0 {
            Group(subviews: statusGlyphs(model.services)) { glyphs in
                wings(glyphs: glyphs, wingWidth: wingWidth)
                    .background { measuringRow(glyphs) }
            }
            .frame(height: model.geometry.notchSize.height)
            .environment(\.colorScheme, .dark)
        }
    }

    private func wings(glyphs: SubviewsCollection, wingWidth: CGFloat) -> some View {
        let split = CompactGlyphSplit.split(
            widths: glyphs.map { glyphWidths[AnyHashable($0.id)] },
            rightWidth: rightGlyphWidth(wingWidth: wingWidth),
            leftWidth: leftGlyphWidth(wingWidth: wingWidth)
        )
        let rightGlyphs = glyphs.prefix(split.right)
        let leftGlyphs = glyphs.dropFirst(split.right).prefix(split.left)
        return HStack(spacing: 0) {
            HStack(spacing: CompactGlyphSplit.spacing) {
                if hasLeftMedia {
                    MediaCompactView(media: model.services.media, visualizer: visualizerPlacement(wingWidth: wingWidth))
                }
                if let track = compactTitleTrack(split: split, wingWidth: wingWidth) {
                    CompactTrackTitle(track: track)
                } else {
                    Spacer(minLength: 0)
                }
                ForEach(leftGlyphs) { $0 }
                if split.overflow > 0, split.pillInLeftWing {
                    overflowPill(count: split.overflow)
                }
            }
            .frame(width: wingWidth)
            .padding(.leading, 6)

            Spacer(minLength: model.geometry.notchSize.width)

            HStack(spacing: NotchGeometry.mediaControlsMicGap) {
                if model.showsMicMuteButton {
                    // Leading edge must match NotchGeometry.micMuteButtonRect (the click hit rect).
                    MicMuteWingButton(
                        isMuted: model.services.system.micMute.isMuted,
                        isHovered: model.isMicMuteHovered
                    )
                    .padding(.leading, NotchGeometry.micMuteNotchInset)
                    .transition(.opacity)
                }
                ZStack(alignment: .leading) {
                    HStack(spacing: CompactGlyphSplit.spacing) {
                        Spacer(minLength: 0)
                        ForEach(rightGlyphs) { $0 }
                        if split.overflow > 0, !split.pillInLeftWing {
                            overflowPill(count: split.overflow)
                        }
                    }
                    .opacity(isControlsRevealed ? 0 : 1)
                    .blur(radius: isControlsRevealed ? 3 : 0)
                    .animation(.easeOut(duration: 0.18), value: isControlsRevealed)
                    if model.showsMediaControls {
                        // Leading edge must match NotchGeometry.mediaControlsRect (the click hit rects).
                        CompactMediaControlsView(
                            isPlaying: model.services.media.nowPlaying?.isPlaying ?? false,
                            isRevealed: isControlsRevealed,
                            hovered: model.hoveredMediaControl,
                            presses: model.mediaControlPresses,
                            artwork: model.services.media.artwork
                        )
                        .padding(.leading, model.showsMicMuteButton ? 0 : NotchGeometry.mediaControlsNotchInset)
                    }
                }
            }
            .frame(width: wingWidth)
            .padding(.trailing, 6)
        }
    }

    private var hasLeftMedia: Bool { model.services.hasCompactMedia }

    /// The track to name in the left wing; status glyphs that overflow there come first.
    private func compactTitleTrack(split: CompactGlyphSplit.Result, wingWidth: CGFloat) -> NowPlaying? {
        let isWingFree = split.left == 0 && !(split.overflow > 0 && split.pillInLeftWing)
        guard hasLeftMedia, isWingFree, leftGlyphWidth(wingWidth: wingWidth) >= CompactTrackTitle.minimumWidth else {
            return nil
        }
        return model.services.media.nowPlaying
    }

    private func visualizerPlacement(wingWidth: CGFloat) -> MediaVisualizerPlacement {
        MediaVisualizerLayout.placement(isEnabled: model.settings.showsMediaVisualizer, wingWidth: wingWidth)
    }

    private func overflowPill(count: Int) -> some View {
        CompactOverflowPill(count: count)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frame in
                model.overflowPillFrame = frame
            })
            .onDisappear { model.overflowPillFrame = nil }
    }

    /// Lays every glyph out at its natural size, invisibly, to feed `CompactGlyphSplit`.
    private func measuringRow(_ glyphs: SubviewsCollection) -> some View {
        HStack(spacing: 0) {
            ForEach(glyphs) { glyph in
                glyph
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width in
                        glyphWidths[AnyHashable(glyph.id)] = width
                    })
            }
        }
        .fixedSize()
        .hidden()
        .allowsHitTesting(false)
    }

    /// Room for glyphs in the left wing: all of it with no media, otherwise what the artwork leaves.
    private func leftGlyphWidth(wingWidth: CGFloat) -> CGFloat {
        guard hasLeftMedia else { return wingWidth }
        let occupied = MediaVisualizerLayout.occupiedWidth(for: visualizerPlacement(wingWidth: wingWidth))
        return max(wingWidth - occupied - CompactGlyphSplit.spacing, 0)
    }

    /// Room for glyphs in the right wing after the mic button (the controls only cover them on hover).
    private func rightGlyphWidth(wingWidth: CGFloat) -> CGFloat {
        guard model.showsMicMuteButton else { return wingWidth }
        return wingWidth - NotchGeometry.micMuteNotchInset - NotchGeometry.micMuteButtonWidth
            - NotchGeometry.mediaControlsMicGap
    }

    private var isControlsRevealed: Bool {
        model.showsMediaControls && model.isMediaControlsRevealed
    }

    /// Status glyphs in priority order, one subview each.
    @ViewBuilder
    private func statusGlyphs(_ services: ModuleServices) -> some View {
        if services.hasCompactTimer {
            TimerCompactView(timer: services.timer)
        }
        if services.hasCompactIndicators {
            StatusCompactIndicators(services: services)
        }
    }
}

/// "+N" for glyphs that did not fit beside the notch; hovering or clicking it opens the Status panel.
private struct CompactOverflowPill: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 1)
            .frame(width: CompactGlyphSplit.pillWidth)
            .background(.white.opacity(0.14), in: .capsule)
            .help("\(count) gösterge daha")
            .accessibilityLabel("\(count) gösterge daha")
    }
}
