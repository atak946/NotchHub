import Foundation
import Testing
@testable import NotchHub

struct CalcExpressionParserTests {
    private let dot = CalcExpressionParser(decimalSeparator: ".")
    private let comma = CalcExpressionParser(decimalSeparator: ",")

    private func value(_ text: String, _ parser: CalcExpressionParser? = nil) throws -> Double {
        try (parser ?? dot).evaluate(text)
    }

    @Test(arguments: [
        ("1+2*3", 7.0),
        ("(1+2)*3", 9.0),
        ("10-4-3", 3.0),
        ("100/10/5", 2.0),
        ("2^3^2", 512.0),
        ("2*3^2", 18.0),
        ("-2^2", -4.0),
        ("(-2)^2", 4.0),
        ("2^-1", 0.5),
        ("--3", 3.0),
        ("+5", 5.0),
        ("3*-2", -6.0),
        (" 1 +  2 ", 3.0),
        ("((((4))))", 4.0),
        ("8 ÷ 2 × 3", 12.0),
        ("8:4", 2.0),
        ("5 − 7", -2.0),
    ])
    func respectsPrecedenceAndAssociativity(input: String, expected: Double) throws {
        #expect(try value(input) == expected)
    }

    @Test func percentFollowsCalculatorConvention() throws {
        #expect(try value("50%") == 0.5)
        #expect(try value("200+10%") == 220)
        #expect(try value("200-10%") == 180)
        #expect(try value("200*10%") == 20)
        #expect(try value("(100+50)%") == 1.5)
    }

    @Test func turkishDecimalComma() throws {
        #expect(try value("12,5*3", comma) == 37.5)
        #expect(try value("0,1+0,2", comma) == 0.1 + 0.2)
        #expect(try value("1.234,5+0,5", comma) == 1235)
        #expect(try value("1.500*2", comma) == 3000)
        #expect(try value("1.5*2", comma) == 3)
    }

    @Test func englishDecimalDot() throws {
        #expect(try value("12.5*3") == 37.5)
        #expect(try value("1,500*2") == 3000)
        #expect(try value("1,234.5") == 1234.5)
        #expect(try value("12,5") == 12.5)
        #expect(try value(".5+.5") == 1)
    }

    @Test(arguments: [
        ("", QuickCalcError.unexpectedEnd),
        ("1+", .unexpectedEnd),
        ("*2", .unexpectedToken),
        ("(1+2", .missingClosingParenthesis),
        ("1+2)", .unmatchedClosingParenthesis),
        (")", .unmatchedClosingParenthesis),
        ("1/0", .divisionByZero),
        ("1/(2-2)", .divisionByZero),
        ("2(3)", .unexpectedToken),
        ("1 2", .unexpectedToken),
        ("1.2.3,4", .invalidNumber("1.2.3,4")),
        ("1,2,3", .invalidNumber("1,2,3")),
        ("2 & 3", .unexpectedCharacter("&")),
        ("(-8)^0,5", .invalidResult),
        ("10^400", .invalidResult),
    ])
    func reportsErrors(input: String, expected: QuickCalcError) {
        let parser = input.contains("^0,5") ? comma : dot
        #expect(throws: expected) { try parser.evaluate(input) }
    }

    @Test func deepNestingFailsWithoutCrashing() {
        let deep = String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)
        #expect(throws: QuickCalcError.tooDeeplyNested) { try dot.evaluate(deep) }
        let minuses = String(repeating: "-", count: 500) + "1"
        #expect(throws: QuickCalcError.tooDeeplyNested) { try dot.evaluate(minuses) }
    }

    @Test func localeInitialiserUsesItsDecimalSeparator() throws {
        let turkish = CalcExpressionParser(locale: Locale(identifier: "tr_TR"))
        let english = CalcExpressionParser(locale: Locale(identifier: "en_US"))
        #expect(try turkish.evaluate("2,5*2") == 5)
        #expect(try english.evaluate("2.5*2") == 5)
    }
}

struct CalcNumberLiteralTests {
    @Test(arguments: [
        ("42", ",", 42.0),
        ("12,5", ",", 12.5),
        ("1.500", ",", 1500.0),
        ("1.5", ",", 1.5),
        ("0.500", ",", 0.5),
        ("1.234.567", ",", 1_234_567.0),
        ("1.234.567,89", ",", 1_234_567.89),
        ("1,500", ".", 1500.0),
        ("1,5", ".", 1.5),
        ("1,234,567.5", ".", 1_234_567.5),
        ("5.", ".", 5.0),
        (",5", ",", 0.5),
    ])
    func parsesLiterals(raw: String, separator: String, expected: Double) {
        #expect(CalcNumberLiteral.parse(raw, decimalSeparator: Character(separator)) == expected)
    }

    @Test(arguments: [".", ",", "1.2.3,4", "1,2.3", "12.34.567", "1.2,3", "1a"])
    func rejectsMalformedLiterals(raw: String) {
        #expect(CalcNumberLiteral.parse(raw, decimalSeparator: ",") == nil)
    }
}
