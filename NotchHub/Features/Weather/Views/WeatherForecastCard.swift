import SwiftUI

/// Small forecast card: place, current condition and the next hours.
struct WeatherForecastCard: View {
    let snapshot: WeatherSnapshot
    let now: Date

    private static let columnWidth: CGFloat = 38
    private static let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            hourlyRow
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.black.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: snapshot.placeName ?? String(localized: "Bilinmeyen konum"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(verbatim: snapshot.condition.title(isDay: snapshot.isDay))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var hourlyRow: some View {
        HStack(spacing: 4) {
            ForEach(snapshot.upcomingHours(from: now, limit: WeatherService.hourlyCount)) { hour in
                VStack(spacing: 5) {
                    Text(hour.time, format: .dateTime.hour())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: hour.condition.symbolName(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13))
                        .frame(height: 16)
                        .help(hour.condition.title(isDay: hour.isDay))
                    Text(verbatim: WeatherTemperatureFormatter.compact(celsius: hour.temperature))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(width: Self.columnWidth)
            }
        }
    }
}
