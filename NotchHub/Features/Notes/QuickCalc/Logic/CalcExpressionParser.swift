import Foundation

/// Small recursive-descent evaluator for arithmetic. Pure and total: bad input throws, it never traps.
///
/// Grammar (lowest to highest precedence):
/// ```
/// expression := term (("+" | "-") term)*
/// term       := unary (("*" | "/") unary)*
/// unary      := ("+" | "-") unary | power
/// power      := postfix ("^" unary)?        // right-associative, binds tighter than unary minus
/// postfix    := primary "%"*
/// primary    := number | "(" expression ")"
/// ```
/// `a + b%` and `a - b%` follow calculator convention (b percent of a); elsewhere `b%` is `b / 100`.
struct CalcExpressionParser: Sendable {
    static let maximumDepth = 64

    let decimalSeparator: Character

    init(decimalSeparator: Character = ".") {
        self.decimalSeparator = decimalSeparator
    }

    init(locale: Locale) {
        self.init(decimalSeparator: locale.decimalSeparator?.first ?? ".")
    }

    func evaluate(_ text: String) throws(QuickCalcError) -> Double {
        let tokens = try CalcTokenizer.tokenize(text, decimalSeparator: decimalSeparator)
        guard !tokens.isEmpty else { throw .unexpectedEnd }
        var cursor = Cursor(tokens: tokens)
        let value = try cursor.expression(depth: 0).value
        if let extra = cursor.peek {
            throw extra == .rightParen ? .unmatchedClosingParenthesis : .unexpectedToken
        }
        guard value.isFinite else { throw .invalidResult }
        return value
    }
}

enum CalcToken: Equatable, Sendable {
    case number(Double)
    case plus, minus, times, divide, power, percent
    case leftParen, rightParen
}

enum CalcTokenizer {
    private static let numberCharacters: Set<Character> = [".", ","]
    private static let symbols: [Character: CalcToken] = [
        "+": .plus, "-": .minus, "−": .minus, "–": .minus,
        "*": .times, "×": .times, "·": .times,
        "/": .divide, "÷": .divide, ":": .divide,
        "^": .power, "%": .percent, "(": .leftParen, ")": .rightParen,
    ]

    static func tokenize(_ text: String, decimalSeparator: Character) throws(QuickCalcError) -> [CalcToken] {
        var tokens: [CalcToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if isNumberCharacter(character) {
                let end = text[index...].firstIndex { !isNumberCharacter($0) } ?? text.endIndex
                let raw = String(text[index..<end])
                guard let value = CalcNumberLiteral.parse(raw, decimalSeparator: decimalSeparator) else {
                    throw .invalidNumber(raw)
                }
                tokens.append(.number(value))
                index = end
            } else if let symbol = symbols[character] {
                tokens.append(symbol)
                index = text.index(after: index)
            } else {
                throw .unexpectedCharacter(character)
            }
        }
        return tokens
    }

    private static func isNumberCharacter(_ character: Character) -> Bool {
        (character.isASCII && character.isNumber) || numberCharacters.contains(character)
    }
}

/// One parsed operand; `isPercent` marks a bare `b%` so `a + b%` can apply it to `a`.
private struct Operand {
    var value: Double
    var isPercent = false
}

private struct Cursor {
    let tokens: [CalcToken]
    var position = 0

    var peek: CalcToken? {
        position < tokens.count ? tokens[position] : nil
    }

    mutating func advance() -> CalcToken? {
        defer { position += 1 }
        return peek
    }

    mutating func expression(depth: Int) throws(QuickCalcError) -> Operand {
        var result = try term(depth: depth)
        while let token = peek, token == .plus || token == .minus {
            position += 1
            let rhs = try term(depth: depth)
            let delta = rhs.isPercent ? result.value * rhs.value : rhs.value
            result = Operand(value: token == .plus ? result.value + delta : result.value - delta)
        }
        return result
    }

    mutating func term(depth: Int) throws(QuickCalcError) -> Operand {
        var result = try unary(depth: depth)
        while let token = peek, token == .times || token == .divide {
            position += 1
            let rhs = try unary(depth: depth)
            if token == .times {
                result = Operand(value: result.value * rhs.value)
            } else {
                guard rhs.value != 0 else { throw .divisionByZero }
                result = Operand(value: result.value / rhs.value)
            }
        }
        return result
    }

    mutating func unary(depth: Int) throws(QuickCalcError) -> Operand {
        guard depth < CalcExpressionParser.maximumDepth else { throw .tooDeeplyNested }
        switch peek {
        case .minus:
            position += 1
            let operand = try unary(depth: depth + 1)
            return Operand(value: -operand.value, isPercent: operand.isPercent)
        case .plus:
            position += 1
            return try unary(depth: depth + 1)
        default:
            return try power(depth: depth)
        }
    }

    mutating func power(depth: Int) throws(QuickCalcError) -> Operand {
        let base = try postfix(depth: depth)
        guard peek == .power else { return base }
        position += 1
        let exponent = try unary(depth: depth + 1)
        let value = Foundation.pow(base.value, exponent.value)
        guard value.isFinite else { throw .invalidResult }
        return Operand(value: value)
    }

    mutating func postfix(depth: Int) throws(QuickCalcError) -> Operand {
        var operand = try primary(depth: depth)
        while peek == .percent {
            position += 1
            operand = Operand(value: operand.value / 100, isPercent: true)
        }
        return operand
    }

    mutating func primary(depth: Int) throws(QuickCalcError) -> Operand {
        guard let token = advance() else { throw .unexpectedEnd }
        switch token {
        case .number(let value):
            return Operand(value: value)
        case .leftParen:
            let inner = try expression(depth: depth + 1)
            guard advance() == .rightParen else { throw .missingClosingParenthesis }
            return Operand(value: inner.value)
        case .rightParen:
            throw .unmatchedClosingParenthesis
        default:
            throw .unexpectedToken
        }
    }
}
