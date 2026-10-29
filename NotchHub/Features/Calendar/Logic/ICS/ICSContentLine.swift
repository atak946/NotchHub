import Foundation

/// One unfolded iCalendar content line: `NAME;PARAM=value;PARAM="quoted":VALUE` (RFC 5545 §3.1).
struct ICSContentLine: Equatable, Sendable {
    /// Upper-cased property name.
    let name: String
    /// Upper-cased parameter names → unquoted values.
    let parameters: [String: String]
    let value: String

    func parameter(_ name: String) -> String? {
        parameters[name.uppercased()]
    }
}

enum ICSContentLineReader {
    private static let quote: Character = "\""

    /// Splits text into logical lines, joining folded continuation lines (CRLF/LF followed by space or tab).
    static func unfoldedLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = rawLine.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1].append(contentsOf: rawLine.dropFirst())
            } else {
                lines.append(String(rawLine))
            }
        }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func lines(in text: String) -> [ICSContentLine] {
        unfoldedLines(text).compactMap(parse)
    }

    static func parse(_ line: String) -> ICSContentLine? {
        guard let colon = firstIndex(of: ":", in: line) else { return nil }
        let head = line[line.startIndex..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = split(head, on: ";")
        guard let rawName = parts.first, !rawName.isEmpty else { return nil }

        var parameters: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[part.startIndex..<equals].uppercased()
            let rawValue = part[part.index(after: equals)...]
            parameters[key] = rawValue.replacingOccurrences(of: String(quote), with: "")
        }
        return ICSContentLine(name: rawName.uppercased(), parameters: parameters, value: value)
    }

    /// Reverses TEXT escaping: `\n`, `\N`, `\,`, `\;`, `\\`.
    static func unescapeText(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var isEscaping = false
        for character in value {
            if isEscaping {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Private

    private static func firstIndex(of separator: Character, in text: String) -> String.Index? {
        var isQuoted = false
        for index in text.indices {
            let character = text[index]
            if character == quote {
                isQuoted.toggle()
            } else if character == separator, !isQuoted {
                return index
            }
        }
        return nil
    }

    private static func split(_ text: Substring, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var isQuoted = false
        for character in text {
            if character == quote {
                isQuoted.toggle()
                current.append(character)
            } else if character == separator, !isQuoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }
}
