import SwiftUI

/// Draggable progress bar with elapsed / remaining labels. Seeks once the drag ends.
struct MediaProgressBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var isHovered = false

    private static let trackHeight: CGFloat = 4
    private static let activeTrackHeight: CGFloat = 7
    private static let hitHeight: CGFloat = 14

    private var isSeekable: Bool { duration > 0 }

    private var displayedPosition: TimeInterval {
        dragFraction.map { PlaybackMath.position(forFraction: $0, duration: duration) } ?? position
    }

    var body: some View {
        VStack(spacing: 3) {
            bar
            HStack {
                Text(MediaTimeFormatter.string(from: displayedPosition))
                Spacer()
                Text(MediaTimeFormatter.remainingString(position: displayedPosition, duration: duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let fraction = dragFraction ?? PlaybackMath.progress(position: position, duration: duration)
            let isActive = isHovered || dragFraction != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.primary.opacity(isActive ? 1 : 0.8))
                    .frame(width: max(proxy.size.width * fraction, 0))
            }
            .frame(height: isActive ? Self.activeTrackHeight : Self.trackHeight)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(dragGesture(width: proxy.size.width), isEnabled: isSeekable)
            .onHover { isHovered = $0 && isSeekable }
            .animation(.easeOut(duration: 0.15), value: isActive)
        }
        .frame(height: Self.hitHeight)
        .accessibilityElement()
        .accessibilityLabel("Oynatma konumu")
        .accessibilityValue(MediaTimeFormatter.string(from: displayedPosition))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragFraction = Self.fraction(at: value.location.x, width: width)
            }
            .onEnded { value in
                let fraction = Self.fraction(at: value.location.x, width: width)
                onSeek(PlaybackMath.position(forFraction: fraction, duration: duration))
                dragFraction = nil
            }
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}
