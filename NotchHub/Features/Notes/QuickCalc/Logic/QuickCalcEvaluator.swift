import Foundation

/// A successful evaluation.
enum QuickCalcValue: Equatable, Sendable {
    case number(Double)
    case measurement(Double, unit: CalcUnit)
    case currency(Double, code: String, rateDate: Date)

    var amount: Double {
        switch self {
        case .number(let value), .measurement(let value, _), .currency(let value, _, _): value
        }
    }
}

enum QuickCalcOutcome: Equatable, Sendable {
    case empty
    case value(QuickCalcValue)
    /// The input is a currency conversion but no rates are loaded yet.
    case needsRates
    case failure(QuickCalcError)
}

/// Turns one line of input into a result: arithmetic, then an optional "<unit> [to] <unit>" tail.
/// Pure: the caller supplies the locale and the current rates.
struct QuickCalcEvaluator: Sendable {
    /// Characters that start the conversion tail (`5 km mi`, `100 $ tl`).
    private static let tailStarters: Set<Character> = ["°", "$", "€", "₺", "£", "¥"]

    let parser: CalcExpressionParser

    init(locale: Locale) {
        parser = CalcExpressionParser(locale: locale)
    }

    init(decimalSeparator: Character) {
        parser = CalcExpressionParser(decimalSeparator: decimalSeparator)
    }

    func evaluate(_ input: String, rates: CurrencyRates?) -> QuickCalcOutcome {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let (expression, tail) = Self.split(trimmed)
        do {
            let amount = try parser.evaluate(expression)
            guard !tail.isEmpty else { return .value(.number(amount)) }
            let (source, target) = try Self.conversionWords(tail)
            return try convert(amount, from: source, to: target, rates: rates)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Conversion

    private func convert(
        _ amount: Double,
        from source: String,
        to target: String,
        rates: CurrencyRates?
    ) throws(QuickCalcError) -> QuickCalcOutcome {
        let sourceUnit = CalcVocabulary.unit(for: source)
        let targetUnit = CalcVocabulary.unit(for: target)
        if let sourceUnit, let targetUnit {
            guard let converted = sourceUnit.convert(amount, to: targetUnit) else { throw .incompatibleUnits }
            guard converted.isFinite else { throw .invalidResult }
            return .value(.measurement(converted, unit: targetUnit))
        }
        if sourceUnit != nil || targetUnit != nil {
            // One side is a unit: the other is either a currency (mismatch) or unknown.
            let other = sourceUnit == nil ? source : target
            throw CalcVocabulary.currencyCode(for: other) == nil ? .unknownUnit(other) : .incompatibleUnits
        }
        guard let sourceCode = CalcVocabulary.currencyCode(for: source) else { throw .unknownUnit(source) }
        guard let targetCode = CalcVocabulary.currencyCode(for: target) else { throw .unknownUnit(target) }
        guard let rates else { return .needsRates }
        guard rates.rate(for: sourceCode) != nil else { throw .unknownCurrency(sourceCode) }
        guard let converted = rates.convert(amount, from: sourceCode, to: targetCode) else {
            throw .unknownCurrency(targetCode)
        }
        guard converted.isFinite else { throw .invalidResult }
        return .value(.currency(converted, code: targetCode, rateDate: rates.updatedAt))
    }

    // MARK: - Splitting

    /// Splits at the first letter or unit/currency symbol: "(2+3) km to mi" → ("(2+3) ", "km to mi").
    static func split(_ input: String) -> (expression: String, tail: String) {
        guard let start = input.firstIndex(where: { $0.isLetter || tailStarters.contains($0) }) else {
            return (input, "")
        }
        let tail = input[start...].trimmingCharacters(in: .whitespaces)
        return (String(input[..<start]), tail)
    }

    /// "km mi", "km to mi", "km->mi", "in in cm" → (source, target).
    static func conversionWords(_ tail: String) throws(QuickCalcError) -> (String, String) {
        let spaced = tail
            .replacingOccurrences(of: "->", with: " -> ")
            .replacingOccurrences(of: "→", with: " → ")
            .replacingOccurrences(of: "=>", with: " => ")
        let words = spaced.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.count {
        case 0, 1:
            throw .missingTargetUnit
        case 2:
            guard !CalcVocabulary.separators.contains(CalcVocabulary.normalize(words[1])) || words[1] == "in" else {
                throw .missingTargetUnit
            }
            return (words[0], words[1])
        case 3 where CalcVocabulary.separators.contains(CalcVocabulary.normalize(words[1])):
            return (words[0], words[2])
        default:
            throw .unknownUnit(words.joined(separator: " "))
        }
    }
}
