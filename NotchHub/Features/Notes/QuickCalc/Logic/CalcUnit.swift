import Foundation

/// Physical quantity a unit measures; only units of the same kind convert into each other.
enum CalcUnitKind: Sendable {
    case length, mass, temperature, duration, data, volume, speed, area
}

/// Every unit the quick calculator understands. `dimension` builds the Foundation unit on demand,
/// which keeps this type `Sendable` without sharing `Dimension` instances.
enum CalcUnit: String, CaseIterable, Sendable {
    case meter, kilometer, centimeter, millimeter, mile, foot, inch, yard, nauticalMile
    case kilogram, gram, milligram, pound, ounce, ton
    case celsius, fahrenheit, kelvin
    case millisecond, second, minute, hour, day, week
    case bit, byte, kilobyte, megabyte, gigabyte, terabyte, kibibyte, mebibyte, gibibyte, tebibyte
    case liter, milliliter, gallon, cubicMeter
    case kilometerPerHour, milePerHour, meterPerSecond, knot
    case squareMeter, squareKilometer, hectare, acre, squareFoot, donum

    private static let secondsPerDay = 86_400.0
    private static let secondsPerWeek = 604_800.0
    private static let squareMetersPerDonum = 1_000.0

    var kind: CalcUnitKind {
        switch self {
        case .meter, .kilometer, .centimeter, .millimeter, .mile, .foot, .inch, .yard, .nauticalMile: .length
        case .kilogram, .gram, .milligram, .pound, .ounce, .ton: .mass
        case .celsius, .fahrenheit, .kelvin: .temperature
        case .millisecond, .second, .minute, .hour, .day, .week: .duration
        case .bit, .byte, .kilobyte, .megabyte, .gigabyte, .terabyte,
             .kibibyte, .mebibyte, .gibibyte, .tebibyte: .data
        case .liter, .milliliter, .gallon, .cubicMeter: .volume
        case .kilometerPerHour, .milePerHour, .meterPerSecond, .knot: .speed
        case .squareMeter, .squareKilometer, .hectare, .acre, .squareFoot, .donum: .area
        }
    }

    var dimension: Dimension {
        lengthMassOrTemperature ?? durationOrData ?? volumeSpeedOrArea
    }

    /// Converts `value` from this unit to `target`; nil when the kinds differ.
    func convert(_ value: Double, to target: CalcUnit) -> Double? {
        guard kind == target.kind else { return nil }
        let base = dimension.converter.baseUnitValue(fromValue: value)
        return target.dimension.converter.value(fromBaseUnitValue: base)
    }

    // Split into three switches so each stays short.
    private var lengthMassOrTemperature: Dimension? {
        switch self {
        case .meter: UnitLength.meters
        case .kilometer: UnitLength.kilometers
        case .centimeter: UnitLength.centimeters
        case .millimeter: UnitLength.millimeters
        case .mile: UnitLength.miles
        case .foot: UnitLength.feet
        case .inch: UnitLength.inches
        case .yard: UnitLength.yards
        case .nauticalMile: UnitLength.nauticalMiles
        case .kilogram: UnitMass.kilograms
        case .gram: UnitMass.grams
        case .milligram: UnitMass.milligrams
        case .pound: UnitMass.pounds
        case .ounce: UnitMass.ounces
        case .ton: UnitMass.metricTons
        case .celsius: UnitTemperature.celsius
        case .fahrenheit: UnitTemperature.fahrenheit
        case .kelvin: UnitTemperature.kelvin
        default: nil
        }
    }

    private var durationOrData: Dimension? {
        switch self {
        case .millisecond: UnitDuration.milliseconds
        case .second: UnitDuration.seconds
        case .minute: UnitDuration.minutes
        case .hour: UnitDuration.hours
        case .day: Self.customDuration(String(localized: "gün"), seconds: Self.secondsPerDay)
        case .week: Self.customDuration(String(localized: "hafta"), seconds: Self.secondsPerWeek)
        case .bit: UnitInformationStorage.bits
        case .byte: UnitInformationStorage.bytes
        case .kilobyte: UnitInformationStorage.kilobytes
        case .megabyte: UnitInformationStorage.megabytes
        case .gigabyte: UnitInformationStorage.gigabytes
        case .terabyte: UnitInformationStorage.terabytes
        case .kibibyte: UnitInformationStorage.kibibytes
        case .mebibyte: UnitInformationStorage.mebibytes
        case .gibibyte: UnitInformationStorage.gibibytes
        case .tebibyte: UnitInformationStorage.tebibytes
        default: nil
        }
    }

    private var volumeSpeedOrArea: Dimension {
        switch self {
        case .liter: UnitVolume.liters
        case .milliliter: UnitVolume.milliliters
        case .gallon: UnitVolume.gallons
        case .cubicMeter: UnitVolume.cubicMeters
        case .kilometerPerHour: UnitSpeed.kilometersPerHour
        case .milePerHour: UnitSpeed.milesPerHour
        case .meterPerSecond: UnitSpeed.metersPerSecond
        case .knot: UnitSpeed.knots
        case .squareMeter: UnitArea.squareMeters
        case .squareKilometer: UnitArea.squareKilometers
        case .hectare: UnitArea.hectares
        case .acre: UnitArea.acres
        case .squareFoot: UnitArea.squareFeet
        case .donum:
            UnitArea(symbol: String(localized: "dönüm"), converter: UnitConverterLinear(coefficient: Self.squareMetersPerDonum))
        // Reached only for units handled by the two switches above.
        default: UnitVolume.liters
        }
    }

    private static func customDuration(_ symbol: String, seconds: Double) -> UnitDuration {
        UnitDuration(symbol: symbol, converter: UnitConverterLinear(coefficient: seconds))
    }
}
