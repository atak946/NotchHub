import SwiftUI

/// Glyph beside the closed notch (~28 × 24 pt): remaining time inside a tiny progress ring.
struct TimerCompactView: View {
    let timer: TimerService

    private static let ringSize: CGFloat = 22
    private static let lineWidth: CGFloat = 2
    private static let fontSize: CGFloat = 7.5

    init(timer: TimerService) {
        self.timer = timer
    }

    var body: some View {
        if timer.hasCompactContent {
            let phase = timer.state.phase ?? .countdown
            ZStack {
                TimerProgressRing(progress: timer.progress, tint: phase.tint, lineWidth: Self.lineWidth)
                Text(TimerFormatter.compact(timer.remaining))
                    .font(.system(size: Self.fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Self.lineWidth + 1)
                    .opacity(timer.state.isPaused ? 0.55 : 1)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .help("\(phase.title): \(TimerFormatter.clock(timer.remaining)) kaldı")
            .accessibilityElement()
            .accessibilityLabel("\(phase.title), \(TimerFormatter.clock(timer.remaining)) kaldı")
        } else {
            EmptyView()
        }
    }
}
