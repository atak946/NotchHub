import SwiftUI

extension TimerPhase {
    /// Semantic accent: focus is warm, breaks are cool, a plain countdown uses the app tint.
    var tint: Color {
        switch self {
        case .countdown: .accentColor
        case .work: .orange
        case .shortBreak: .mint
        case .longBreak: .cyan
        }
    }
}

/// Circular progress ring with a faint track.
struct TimerProgressRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// Row of Pomodoro session dots; filled dots are completed work sessions.
struct TimerSessionDots: View {
    let completed: Int
    let total: Int
    let tint: Color

    private static let dotSize: CGFloat = 6
    private static let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(total) odak oturumundan \(completed) tanesi tamamlandı")
    }
}

/// Round icon button with hover/press feedback.
struct TimerControlButton: View {
    let systemImage: String
    let help: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(TimerPressableStyle(isProminent: isProminent))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Shared pressable style: subtle fill that brightens on hover and shrinks on press.
struct TimerPressableStyle: ButtonStyle {
    var isProminent = false
    var shape: AnyShape = AnyShape(Circle())

    func makeBody(configuration: Configuration) -> some View {
        TimerPressableBody(configuration: configuration, isProminent: isProminent, shape: shape)
    }
}

private struct TimerPressableBody: View {
    let configuration: ButtonStyleConfiguration
    let isProminent: Bool
    let shape: AnyShape
    @State private var isHovered = false

    private var fillOpacity: Double {
        let base = isProminent ? 0.22 : 0.10
        return isHovered ? base + 0.08 : base
    }

    var body: some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(shape.fill(.primary.opacity(fillOpacity)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Horizontal shake whenever `trigger` changes; use with `TimerService.finishCount`.
    func timerFinishShake(trigger: Int) -> some View {
        modifier(TimerShakeModifier(trigger: trigger))
    }
}

/// Damped horizontal shake driven by a keyframe track (transform-only, no layout work).
struct TimerShakeModifier: ViewModifier {
    static let offsets: [CGFloat] = [-6, 6, -5, 5, -3, 3, 0]
    static let stepDuration: TimeInterval = 0.06

    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                for offset in TimerShakeModifier.offsets {
                    LinearKeyframe(offset, duration: TimerShakeModifier.stepDuration)
                }
            }
        }
    }
}
