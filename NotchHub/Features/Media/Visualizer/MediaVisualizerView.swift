import SwiftUI

/// Small artwork-tinted equalizer bars for the collapsed notch. The `TimelineView` only ticks while
/// playing, visible, outside Low Power Mode and with Reduce Motion off.
struct MediaVisualizerView: View {
    let isPlaying: Bool
    let tint: Color
    var barWidth: CGFloat = MediaVisualizerLayout.barWidth
    var spacing: CGFloat = MediaVisualizerLayout.barSpacing
    var power: LowPowerModeObserver = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWindowVisible = true

    /// ~30 fps is smooth for 2 pt bars without redrawing at the display's full refresh rate.
    private static let frameInterval: TimeInterval = 1.0 / 30
    private static let transitionDuration = 0.35
    private static let generator = EqualizerBarGenerator(seed: 0x4E6F_7463_6848_7562)

    private var activity: MediaVisualizerActivity {
        MediaVisualizerActivity.resolve(
            isPlaying: isPlaying,
            isVisible: isWindowVisible,
            isLowPowerMode: power.isLowPowerMode,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        let activity = activity
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: activity != .animating)) { context in
            let levels = Self.levels(for: activity, at: context.date)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: barWidth)
                        .scaleEffect(y: levels[index], anchor: .center)
                }
            }
        }
        .foregroundStyle(tint)
        .animation(reduceMotion ? nil : .easeOut(duration: Self.transitionDuration), value: activity)
        .animation(reduceMotion ? nil : .easeInOut(duration: Self.transitionDuration), value: tint)
        .background(WindowVisibilityReader { isWindowVisible = $0 })
        .accessibilityHidden(true)
    }

    private static func levels(for activity: MediaVisualizerActivity, at date: Date) -> [CGFloat] {
        let values: [Double]
        switch activity {
        case .animating: values = generator.levels(at: date.timeIntervalSinceReferenceDate)
        case .still: values = generator.staticLevels
        case .resting: values = generator.restingLevels
        }
        return values.map { CGFloat($0) }
    }
}

extension Color {
    init(_ rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
