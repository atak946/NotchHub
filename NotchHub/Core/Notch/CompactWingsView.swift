import SwiftUI

/// Live indicators beside the hardware notch while the panel is closed:
/// left wing = now playing (plus media controls when enabled), or overflow status glyphs when no media;
/// right wing = meeting mic button, timer and status glyphs.
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
            HStack(spacing: isLeftWingFree ? CompactGlyphSplit.spacing : nil) {
                if isLeftWingFree {
                    ForEach(leftGlyphs) { $0 }
                    if split.overflow > 0, split.pillInLeftWing {
                        overflowPill(count: split.overflow)
                    }
                    Spacer(minLength: 0)
                } else {
                    mediaWing(wingWidth: wingWidth)
                }
            }
            .frame(width: wingWidth)
            .padding(.leading, 6)

            Spacer(minLength: model.geometry.notchSize.width)

            HStack(spacing: Self.micButtonSpacing) {
                if model.showsMicMuteButton {
                    // Leading edge must match NotchGeometry.micMuteButtonRect (the click hit rect).
                    MicMuteWingButton(
                        isMuted: model.services.system.micMute.isMuted,
                        isHovered: model.isMicMuteHovered
                    )
                    .padding(.leading, NotchGeometry.micMuteNotchInset)
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
                HStack(spacing: CompactGlyphSplit.spacing) {
                    ForEach(rightGlyphs) { $0 }
                    if split.overflow > 0, !split.pillInLeftWing {
                        overflowPill(count: split.overflow)
                    }
                }
                .fixedSize()
            }
            .frame(width: wingWidth)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private func mediaWing(wingWidth: CGFloat) -> some View {
        let services = model.services
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

    private static let micButtonSpacing: CGFloat = 6

    /// The left wing hosts glyphs only while nothing is playing.
    private var isLeftWingFree: Bool {
        !model.services.hasCompactMedia && !model.showsMediaControls
    }

    private func leftGlyphWidth(wingWidth: CGFloat) -> CGFloat {
        isLeftWingFree ? wingWidth : 0
    }

    private func rightGlyphWidth(wingWidth: CGFloat) -> CGFloat {
        guard model.showsMicMuteButton else { return wingWidth }
        return wingWidth - NotchGeometry.micMuteNotchInset - NotchGeometry.micMuteButtonWidth - Self.micButtonSpacing
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
