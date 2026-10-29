import SwiftUI

/// Compact weather beside the header clock: condition symbol, current temperature and today's high / low.
/// A click shows the next hours in a card drawn inside the panel (a real popover window would sit outside
/// the notch panel, and moving the pointer onto it would close the notch).
struct WeatherHeaderView: View {
    let weather: WeatherService

    @State private var isForecastShown = false
    @State private var isHovered = false

    private static let cardOffset: CGFloat = 6

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let snapshot = weather.displaySnapshot(at: context.date) {
                button(for: snapshot)
                    .overlay(alignment: .bottomTrailing) {
                        if isForecastShown {
                            WeatherForecastCard(snapshot: snapshot, now: context.date)
                                .fixedSize()
                                // Hangs the card's top edge below the button.
                                .alignmentGuide(.bottom) { $0[.top] }
                                .offset(y: Self.cardOffset)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                                .onTapGesture { toggleForecast() }
                        }
                    }
            }
        }
    }

    private func button(for snapshot: WeatherSnapshot) -> some View {
        Button(action: toggleForecast) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.condition.symbolName(isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                Text(verbatim: WeatherTemperatureFormatter.compact(celsius: snapshot.temperature))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(verbatim: highLowText(snapshot))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if isHovered || isForecastShown {
                    RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(snapshot.condition.title(isDay: snapshot.isDay))
        .accessibilityLabel(accessibilityText(snapshot))
    }

    private func toggleForecast() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isForecastShown.toggle()
        }
    }

    private func highLowText(_ snapshot: WeatherSnapshot) -> String {
        "↑" + WeatherTemperatureFormatter.compact(celsius: snapshot.high)
            + " ↓" + WeatherTemperatureFormatter.compact(celsius: snapshot.low)
    }

    private func accessibilityText(_ snapshot: WeatherSnapshot) -> String {
        let condition = snapshot.condition.title(isDay: snapshot.isDay)
        let current = WeatherTemperatureFormatter.full(celsius: snapshot.temperature)
        let high = WeatherTemperatureFormatter.full(celsius: snapshot.high)
        let low = WeatherTemperatureFormatter.full(celsius: snapshot.low)
        return String(localized: "\(condition), \(current), en yüksek \(high), en düşük \(low)")
    }
}
