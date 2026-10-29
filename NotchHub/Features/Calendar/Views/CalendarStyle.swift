import SwiftUI

enum CalendarMetrics {
    static let cardWidth: CGFloat = 316
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 14
    static let colorBarWidth: CGFloat = 4
    static let rowCornerRadius: CGFloat = 7
    static let groupingPickerWidth: CGFloat = 96
    static let soonThreshold: TimeInterval = 5 * 60
    static let pressedScale: CGFloat = 0.96
    static let hoverOpacity: Double = 0.85
    static let animation = Animation.spring(duration: 0.22, bounce: 0.25)
}

extension CalendarColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

/// Subtle press-scale and hover feedback shared by every calendar button.
struct CalendarPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(.rect)
                .scaleEffect(configuration.isPressed ? CalendarMetrics.pressedScale : 1)
                .opacity(isHovered && !configuration.isPressed ? CalendarMetrics.hoverOpacity : 1)
                .animation(CalendarMetrics.animation, value: configuration.isPressed)
                .animation(CalendarMetrics.animation, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

/// Filled capsule button used for "Join" and permission actions.
struct CalendarProminentButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(tint.gradient, in: .capsule)
    }
}
