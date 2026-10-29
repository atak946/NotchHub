import Foundation

/// Builds "✓ dotnet build · 1m 12s" / "✗ npm test failed (exit 1) · 45s" from a raw shell command line.
enum CommandFinishedFormatter {
    static let maxNameLength = 40
    static let fallbackName = String(localized: "Komut")
    static let successSymbol = "checkmark.circle.fill"
    static let failureSymbol = "xmark.octagon.fill"

    /// Prefix words that only wrap the real command (`sudo make` → `make`).
    static let wrapperCommands: Set<String> = [
        "sudo", "env", "time", "nice", "nohup", "command", "builtin", "exec", "noglob", "nocorrect",
        "caffeinate", "doas", "xcrun", "arch",
    ]
    /// Subcommands that are followed by the meaningful word (`npm run build`).
    static let passthroughSubcommands: Set<String> = ["run", "exec", "x", "dlx"]

    private static let separators: Set<String> = ["|", "||", "&&", ";", "&", "|&"]
    private static let subcommandCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_-"
    )
    private static let maxSubcommandLength = 24

    static func title(for result: ExternalCommandResult) -> String {
        let name = commandName(from: result.commandLine)
        let duration = IntegrationsDurationFormatter.text(for: result.elapsed)
        if result.succeeded {
            return "✓ \(name) · \(duration)"
        }
        return String(localized: "✗ \(name) başarısız (çıkış \(result.exitCode)) · \(duration)")
    }

    static func style(for result: ExternalCommandResult) -> ExternalAlertStyle {
        result.succeeded ? .success : .urgent
    }

    static func systemImage(for result: ExternalCommandResult) -> String {
        result.succeeded ? successSymbol : failureSymbol
    }

    /// Executable basename plus its first subcommand word, skipping env assignments and wrappers.
    /// `FOO=1 sudo /usr/local/bin/npm run test -- --watch` → `npm run test`.
    static func commandName(from commandLine: String) -> String {
        let words = firstSegment(of: tokens(in: commandLine))
        guard let executableIndex = executableIndex(in: words) else { return fallbackName }

        var parts = [basename(words[executableIndex])]
        var index = executableIndex + 1
        while index < words.count, parts.count < 3, isSubcommand(words[index]) {
            parts.append(words[index])
            guard passthroughSubcommands.contains(words[index]) else { break }
            index += 1
        }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? fallbackName : ExternalAlertSanitizer.truncated(name, to: maxNameLength)
    }

    // MARK: - Private

    private static func executableIndex(in words: [String]) -> Int? {
        var index = 0
        var afterWrapper = false
        while index < words.count {
            let word = words[index]
            if isAssignment(word) || (afterWrapper && word.hasPrefix("-")) {
                index += 1
                continue
            }
            if wrapperCommands.contains(basename(word)) {
                afterWrapper = true
                index += 1
                continue
            }
            return basename(word).isEmpty ? nil : index
        }
        return nil
    }

    /// Whitespace split honouring simple single/double quotes; separators become their own tokens.
    private static func tokens(in commandLine: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }

        for character in commandLine {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                flush()
            } else if character == ";" || character == "|" || character == "&" {
                flush()
                tokens.append(String(character))
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
    }

    private static func firstSegment(of tokens: [String]) -> [String] {
        Array(tokens.prefix { !separators.contains($0) })
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func isSubcommand(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first, CharacterSet.letters.contains(first),
              word.count <= maxSubcommandLength
        else { return false }
        return word.unicodeScalars.allSatisfy { subcommandCharacters.contains($0) }
    }

    private static func basename(_ word: String) -> String {
        let name = word.split(separator: "/").last.map(String.init) ?? ""
        return ExternalAlertSanitizer.displayText(name, maxLength: maxNameLength) ?? ""
    }
}
