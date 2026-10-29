import Foundation

/// Formats Celsius values in the unit the locale's measurement system prefers (°F for the US system).
enum WeatherTemperatureFormatter {
    static func unit(for locale: Locale) -> UnitTemperature {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// Rounded value in the locale's unit; never "-0".
    static func roundedValue(celsius: Double, locale: Locale) -> Double {
        let converted = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit(for: locale)).value
        let rounded = converted.rounded()
        return rounded == 0 ? 0 : rounded
    }

    /// Full form with the unit, e.g. "22 °C" or "72°F".
    static func full(celsius: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let measurement = Measurement(value: roundedValue(celsius: celsius, locale: locale), unit: unit(for: locale))
        return measurement.formatted(
            .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    /// Compact form for tight layouts, e.g. "22°".
    static func compact(celsius: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let value = roundedValue(celsius: celsius, locale: locale)
        return value.formatted(.number.precision(.fractionLength(0)).locale(locale)) + "°"
    }
}
