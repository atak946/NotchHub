import CoreGraphics

/// What the collapsed-notch equalizer bars do right now.
enum MediaVisualizerActivity: Equatable, Sendable {
    /// Live pseudo-random motion (the only state that keeps a `TimelineView` ticking).
    case animating
    /// Fixed staggered bars: Reduce Motion, Low Power Mode or nobody can see the notch.
    case still
    /// Paused: every bar shrinks to the resting level.
    case resting

    static func resolve(isPlaying: Bool, isVisible: Bool, isLowPowerMode: Bool, reduceMotion: Bool) -> Self {
        guard isPlaying else { return .resting }
        if reduceMotion || isLowPowerMode || !isVisible { return .still }
        return .animating
    }
}

/// Where the bars go in the left wing without changing the wing widths.
enum MediaVisualizerPlacement: Equatable, Sendable {
    case hidden
    /// Next to the artwork.
    case beside
    /// A small badge on the artwork's corner, when the media controls leave no room beside it.
    case overlay
}

/// Pure layout rules for the collapsed music visualizer.
enum MediaVisualizerLayout {
    static let artworkSize: CGFloat = 22
    static let barCount = EqualizerBarGenerator.defaultBarCount
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 1.5
    static let barHeight: CGFloat = 14
    static let besideGap: CGFloat = 4
    static let overlayBarWidth: CGFloat = 1.5
    static let overlayBarSpacing: CGFloat = 1
    static let overlayBarHeight: CGFloat = 8

    static var barsWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * barSpacing
    }

    /// Room the visualizer needs beside the artwork.
    static var besideWidth: CGFloat { besideGap + barsWidth }

    static func placement(isEnabled: Bool, wingWidth: CGFloat, showsMediaControls: Bool) -> MediaVisualizerPlacement {
        guard isEnabled, wingWidth > 0 else { return .hidden }
        var reserved = artworkSize
        if showsMediaControls {
            reserved += NotchGeometry.mediaControlsWidth + NotchGeometry.mediaControlsNotchInset
        }
        return wingWidth - reserved >= besideWidth ? .beside : .overlay
    }
}
