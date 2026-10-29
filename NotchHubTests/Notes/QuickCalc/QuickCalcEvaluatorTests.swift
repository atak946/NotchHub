import Foundation
import Testing
@testable import NotchHub

struct QuickCalcEvaluatorTests {
    private let turkish = QuickCalcEvaluator(decimalSeparator: ",")
    private let english = QuickCalcEvaluator(decimalSeparator: ".")
    private static let rateDate = Date(timeIntervalSince1970: 1_761_696_000)
    private let rates = CurrencyRates(
        base: "USD",
        rates: ["USD": 1, "TRY": 40, "EUR": 0.8, "GBP": 0.75],
        updatedAt: QuickCalcEvaluatorTests.rateDate,
        fetchedAt: QuickCalcEvaluatorTests.rateDate
    )

    private func measurement(_ input: String, _ evaluator: QuickCalcEvaluator? = nil) -> (Double, CalcUnit)? {
        guard case .value(.measurement(let amount, let unit)) = (evaluator ?? english).evaluate(input, rates: nil) else {
            return nil
        }
        return (amount, unit)
    }

    private func isClose(_ lhs: Double?, _ rhs: Double, tolerance: Double = 1e-6) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance * max(1, abs(rhs))
    }

    // MARK: - Arithmetic

    @Test func emptyAndWhitespaceInputIsEmpty() {
        #expect(turkish.evaluate("", rates: nil) == .empty)
        #expect(turkish.evaluate("   ", rates: nil) == .empty)
    }

    @Test func plainArithmeticUsesLocaleDecimals() {
        #expect(turkish.evaluate("12,5*3", rates: nil) == .value(.number(37.5)))
        #expect(english.evaluate("12.5*3", rates: nil) == .value(.number(37.5)))
    }

    @Test func arithmeticErrorsSurfaceAsFailures() {
        #expect(english.evaluate("1/0", rates: nil) == .failure(.divisionByZero))
        #expect(english.evaluate("(1+", rates: nil) == .failure(.unexpectedEnd))
    }

    // MARK: - Units

    @Test(arguments: [
        ("5 km to mi", 3.106855961, CalcUnit.mile),
        ("5 km mil", 3.106855961, .mile),
        ("5 km in mi", 3.106855961, .mile),
        ("5km->mi", 3.106855961, .mile),
        ("5 km → mi", 3.106855961, .mile),
        ("100 f c", 37.777777778, .celsius),
        ("100f c", 37.777777778, .celsius),
        ("0 °C °F", 32, .fahrenheit),
        ("0 c k", 273.15, .kelvin),
        ("3 gb mb", 3000, .megabyte),
        ("1 gib mib", 1024, .mebibyte),
        ("2 saat dakika", 120, .minute),
        ("1 gün saat", 24, .hour),
        ("1 hafta gün", 7, .day),
        ("90 sn dk", 1.5, .minute),
        ("2 in cm", 5.08, .centimeter),
        ("1 kg lb", 2.204622622, .pound),
        ("1 l ml", 1000, .milliliter),
        ("100 km/h m/s", 27.777777778, .meterPerSecond),
        ("1 dönüm m2", 1000, .squareMeter),
        ("(2+3) km m", 5000, .meter),
        ("2 SAAT DAKİKA", 120, .minute),
    ])
    func convertsUnits(input: String, expected: Double, unit: CalcUnit) {
        let result = measurement(input)
        #expect(result?.1 == unit)
        #expect(isClose(result?.0, expected))
    }

    @Test func unitConversionWithTurkishDecimals() {
        let result = measurement("1,5 saat dakika", turkish)
        #expect(result?.1 == .minute)
        #expect(isClose(result?.0, 90))
    }

    @Test func inchIsTheSourceWhenOnlyTwoWordsFollow() {
        let result = measurement("1 in in cm")
        #expect(result?.1 == .centimeter)
        #expect(isClose(result?.0, 2.54))
    }

    @Test func unitErrors() {
        #expect(english.evaluate("5 km kg", rates: nil) == .failure(.incompatibleUnits))
        #expect(english.evaluate("5 km", rates: nil) == .failure(.missingTargetUnit))
        #expect(english.evaluate("5 km to", rates: nil) == .failure(.missingTargetUnit))
        #expect(english.evaluate("5 km florp", rates: nil) == .failure(.unknownUnit("florp")))
        #expect(english.evaluate("5 km usd", rates: rates) == .failure(.incompatibleUnits))
        #expect(english.evaluate("5 km to mi to m", rates: nil) == .failure(.unknownUnit("km to mi to m")))
    }

    @Test func splitSeparatesExpressionFromUnitTail() {
        #expect(QuickCalcEvaluator.split("(2+3) km to mi") == ("(2+3) ", "km to mi"))
        #expect(QuickCalcEvaluator.split("1+2") == ("1+2", ""))
        #expect(QuickCalcEvaluator.split("100 $ tl") == ("100 ", "$ tl"))
    }

    // MARK: - Currency

    private func currency(_ input: String, _ evaluator: QuickCalcEvaluator? = nil) -> (Double, String, Date)? {
        guard case .value(.currency(let amount, let code, let date)) = (evaluator ?? english).evaluate(input, rates: rates) else {
            return nil
        }
        return (amount, code, date)
    }

    @Test(arguments: [
        ("100 usd try", 4000.0, "TRY"),
        ("50 eur tl", 2500, "TRY"),
        ("100 dolar avro", 80, "EUR"),
        ("100 $ to ₺", 4000, "TRY"),
        ("75 GBP USD", 100, "USD"),
        ("40 lira -> dollar", 1, "USD"),
        ("1 sterlin €", 0.8 / 0.75, "EUR"),
    ])
    func convertsCurrencyWithInjectedRates(input: String, expected: Double, code: String) {
        let result = currency(input)
        #expect(result?.1 == code)
        #expect(result?.2 == Self.rateDate)
        #expect(isClose(result?.0, expected))
    }

    @Test func currencyArithmeticAndTurkishDecimals() {
        let result = currency("2*12,5 usd tl", turkish)
        #expect(result?.1 == "TRY")
        #expect(isClose(result?.0, 1000))
    }

    @Test func currencyWithoutRatesAsksForThem() {
        #expect(english.evaluate("100 usd try", rates: nil) == .needsRates)
    }

    @Test func unknownCurrencyCodes() {
        #expect(english.evaluate("100 xyz try", rates: rates) == .failure(.unknownCurrency("XYZ")))
        #expect(english.evaluate("100 usd xyz", rates: rates) == .failure(.unknownCurrency("XYZ")))
        #expect(english.evaluate("100 usd lirasi", rates: rates) == .failure(.unknownUnit("lirasi")))
    }
}
