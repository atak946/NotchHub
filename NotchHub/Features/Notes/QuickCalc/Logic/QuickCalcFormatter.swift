import Foundation

/// Locale-aware text for results: a grouped display string and an ungrouped copy string.
struct QuickCalcFormatter {
    private static let displayFractionDigits = 6
    private static let copyFractionDigits = 10
    private static let currencyFractionDigits = 2
    private static let smallCurrencyFractionDigits = 4
    private static let scientificUpperBound = 1e15
    private static let scientificLowerBound = 1e-6

    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// "37,5", "3,106856 mi", "3.412,50 TRY".
    func display(_ value: QuickCalcValue) -> String {
        switch value {
        case .number(let amount):
            return number(amount, maxFractionDigits: Self.displayFractionDigits, grouped: true)
        case .measurement(let amount, let unit):
            let formatter = MeasurementFormatter()
            formatter.locale = locale
            formatter.unitOptions = .providedUnit
            formatter.unitStyle = .medium
            formatter.numberFormatter = numberFormatter(
                for: amount,
                maxFractionDigits: Self.displayFractionDigits,
                grouped: true
            )
            return formatter.string(from: Measurement(value: amount, unit: unit.dimension))
        case .currency(let amount, let code, _):
            return currencyAmount(amount, grouped: true) + " " + code
        }
    }

    /// What Enter puts on the clipboard: the bare number in the user's locale, without grouping.
    func copyText(_ value: QuickCalcValue) -> String {
        switch value {
        case .currency(let amount, _, _):
            currencyAmount(amount, grouped: false)
        default:
            number(value.amount, maxFractionDigits: Self.copyFractionDigits, grouped: false)
        }
    }

    // MARK: - Numbers

    private func currencyAmount(_ amount: Double, grouped: Bool) -> String {
        let digits = abs(amount) < 1 ? Self.smallCurrencyFractionDigits : Self.currencyFractionDigits
        let formatter = numberFormatter(for: amount, maxFractionDigits: digits, grouped: grouped)
        formatter.minimumFractionDigits = Self.currencyFractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    private func number(_ amount: Double, maxFractionDigits: Int, grouped: Bool) -> String {
        let formatter = numberFormatter(for: amount, maxFractionDigits: maxFractionDigits, grouped: grouped)
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    private func numberFormatter(for amount: Double, maxFractionDigits: Int, grouped: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        let magnitude = abs(amount)
        let isExtreme = magnitude >= Self.scientificUpperBound
            || (magnitude > 0 && magnitude < Self.scientificLowerBound)
        if isExtreme {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = Self.displayFractionDigits
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = maxFractionDigits
            formatter.usesGroupingSeparator = grouped
        }
        return formatter
    }
}
