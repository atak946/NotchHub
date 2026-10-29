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
                    Spacer(minLength: 0)
                    if services.hasCompactTimer {
                        TimerCompactView(timer: services.timer)
                    }
                    if services.hasCompactIndicators {
                        StatusCompactIndicators(services: services)
                    }
                }
                .frame(width: wingWidth)
                .padding(.trailing, 6)
            }
            .frame(height: model.geometry.notchSize.height)
            .environment(\.colorScheme, .dark)
        }
    }
}
