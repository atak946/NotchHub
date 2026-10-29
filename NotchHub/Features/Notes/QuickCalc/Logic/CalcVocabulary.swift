import Foundation

/// Turkish and English words for units and currencies. Lookups are case- and diacritic-insensitive
/// (`SANİYE`, `saniye` and `gün`/`gun` all match).
enum CalcVocabulary {
    /// Words between the source and target unit: "5 km to mi", "5 km in mi", "5 km -> mi".
    static let separators: Set<String> = ["to", "in", "into", "as", "->", "→", "=", "=>"]

    static func normalize(_ word: String) -> String {
        word
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func unit(for word: String) -> CalcUnit? {
        unitsByWord[normalize(word)]
    }

    /// ISO code for an alias (`tl`, `dolar`, `€`) or any three-letter code (`usd`, `jpy`).
    static func currencyCode(for word: String) -> String? {
        let normalized = normalize(word)
        if let code = currencyAliases[normalized] { return code }
        let isISOShaped = normalized.count == 3 && normalized.allSatisfy { $0.isASCII && $0.isLetter }
        return isISOShaped ? normalized.uppercased() : nil
    }

    private static let currencyAliases: [String: String] = [
        "$": "USD", "dolar": "USD", "dollar": "USD", "dollars": "USD",
        "€": "EUR", "euro": "EUR", "euros": "EUR", "avro": "EUR",
        "₺": "TRY", "tl": "TRY", "lira": "TRY",
        "£": "GBP", "sterlin": "GBP", "sterling": "GBP",
        "yen": "JPY", "¥": "JPY",
    ]

    private static let unitsByWord: [String: CalcUnit] = {
        var table: [String: CalcUnit] = [:]
        for (unit, words) in unitWords {
            for word in words {
                table[normalize(word)] = unit
            }
        }
        return table
    }()

    private static let unitWords: [CalcUnit: [String]] = [
        .meter: ["m", "metre", "meter", "meters", "metres"],
        .kilometer: ["km", "kilometre", "kilometer", "kilometers", "kilometres"],
        .centimeter: ["cm", "santimetre", "santim", "centimeter", "centimeters", "centimetre"],
        .millimeter: ["mm", "milimetre", "millimeter", "millimeters", "millimetre"],
        .mile: ["mi", "mil", "mile", "miles"],
        .foot: ["ft", "foot", "feet", "fit"],
        .inch: ["in", "inç", "inch", "inches"],
        .yard: ["yd", "yard", "yards", "yarda"],
        .nauticalMile: ["nmi"],
        .kilogram: ["kg", "kilo", "kilogram", "kilograms"],
        .gram: ["g", "gr", "gram", "grams"],
        .milligram: ["mg", "miligram", "milligram", "milligrams"],
        .pound: ["lb", "lbs", "pound", "pounds", "libre"],
        .ounce: ["oz", "ounce", "ounces", "ons"],
        .ton: ["t", "ton", "tons", "tonne", "tonnes"],
        .celsius: ["c", "°c", "celsius", "santigrat"],
        .fahrenheit: ["f", "°f", "fahrenheit"],
        .kelvin: ["k", "kelvin"],
        .millisecond: ["ms", "milisaniye", "millisecond", "milliseconds"],
        .second: ["s", "sn", "sec", "secs", "second", "seconds", "saniye"],
        .minute: ["min", "mins", "minute", "minutes", "dk", "dakika"],
        .hour: ["h", "hr", "hrs", "hour", "hours", "sa", "saat"],
        .day: ["d", "day", "days", "gün"],
        .week: ["wk", "week", "weeks", "hafta"],
        .bit: ["bit", "bits"],
        .byte: ["b", "byte", "bytes", "bayt"],
        .kilobyte: ["kb", "kilobyte", "kilobytes"],
        .megabyte: ["mb", "megabyte", "megabytes"],
        .gigabyte: ["gb", "gigabyte", "gigabytes"],
        .terabyte: ["tb", "terabyte", "terabytes"],
        .kibibyte: ["kib"],
        .mebibyte: ["mib"],
        .gibibyte: ["gib"],
        .tebibyte: ["tib"],
        .liter: ["l", "lt", "litre", "liter", "liters", "litres"],
        .milliliter: ["ml", "mililitre", "milliliter", "milliliters", "millilitre"],
        .gallon: ["gal", "gallon", "gallons", "galon"],
        .cubicMeter: ["m3", "m³", "metreküp"],
        .kilometerPerHour: ["kmh", "km/h", "kph", "km/sa"],
        .milePerHour: ["mph"],
        .meterPerSecond: ["m/s", "mps"],
        .knot: ["kn", "kt", "knot", "knots"],
        .squareMeter: ["m2", "m²", "metrekare"],
        .squareKilometer: ["km2", "km²"],
        .hectare: ["ha", "hektar", "hectare", "hectares"],
        .acre: ["acre", "acres", "akre"],
        .squareFoot: ["ft2", "ft²", "sqft"],
        .donum: ["dönüm", "dekar"],
    ]
}
