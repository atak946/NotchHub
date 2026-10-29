import AppKit
import SwiftUI

/// Icon button with designed hover / press feedback for the media panel.
struct MediaIconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = 15
    var diameter: CGFloat = 30
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(.quaternary.opacity(isHovered ? 1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressScaleButtonStyle())
        .foregroundStyle(.primary)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    private static let pressedScale: CGFloat = 0.86
    private static let pressedOpacity = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Rounded artwork with a placeholder glyph when no image is available.
struct MediaArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: image.map(ObjectIdentifier.init))
    }
}

/// Animated equalizer bars; static when paused or when Reduce Motion is on.
struct MediaEqualizerView: View {
    let isPlaying: Bool
    var barCount = 4
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let restingScale: CGFloat = 0.25
    private static let frequencies: [Double] = [5.1, 7.3, 4.2, 6.4, 5.7]

    var body: some View {
        TimelineView(.animation(paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .frame(width: barWidth)
                        .scaleEffect(y: scale(for: index, at: context.date), anchor: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func scale(for index: Int, at date: Date) -> CGFloat {
        guard isPlaying, !reduceMotion else { return Self.restingScale + 0.15 * CGFloat(index % 2) }
        let frequency = Self.frequencies[index % Self.frequencies.count]
        let wave = sin(date.timeIntervalSinceReferenceDate * frequency + Double(index))
        return Self.restingScale + (1 - Self.restingScale) * CGFloat((wave + 1) / 2)
    }
}

/// Opens a player app explicitly at the user's request.
enum MediaAppLauncher {
    @MainActor
    static func isInstalled(_ source: MediaSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil
    }

    @MainActor
    static func open(_ source: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
