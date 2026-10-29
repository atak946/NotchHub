import Foundation

/// Pure helpers that turn untrusted external strings into safe display values.
enum ExternalAlertSanitizer {
    static let maxTitleLength = 80
    static let maxSubtitleLength = 160
    static let maxKeyLength = 64
    static let maxSymbolLength = 64
    static let maxOpenURLLength = 2048
    static let maxCommandLength = 512
    static let fallbackSymbol = "bell"
    static let keyNamespace = "external."
    static let allowedOpenSchemes: Set<String> = ["http", "https", "file"]

    private static let ellipsis = "…"
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    private static let keyCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    )

    /// Strips control / format characters (bidi overrides, NUL, zero-width spaces), folds line breaks
    /// into spaces, collapses whitespace and truncates to `maxLength` characters. Returns `nil` when empty.
    static func displayText(_ raw: String, maxLength: Int) -> String? {
        let scalars = raw.unicodeScalars.compactMap(cleanScalar)
        let cleaned = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        return truncated(cleaned, to: maxLength)
    }

    /// `true` for dotted lowercase SF Symbol names such as `hammer.circle.fill`.
    static func isPlausibleSymbolName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maxSymbolLength else { return false }
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            }
        }
    }

    /// Keeps `[A-Za-z0-9._-]`, prefixes `external.`. Returns `nil` when nothing usable remains.
    static func coalescingKey(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { keyCharacters.contains($0) }
        let key = String(String.UnicodeScalarView(kept)).prefix(maxKeyLength)
        return key.isEmpty ? nil : keyNamespace + key
    }

    /// Accepts absolute http(s) URLs with a host and absolute file URLs; anything else is `nil`.
    static func openURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxOpenURLLength,
              !trimmed.unicodeScalars.contains(where: isControl),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              allowedOpenSchemes.contains(scheme)
        else { return nil }

        if scheme == "file" {
            return url.path.hasPrefix("/") ? url : nil
        }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func truncated(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let keep = max(maxLength - ellipsis.count, 0)
        return String(text.prefix(keep)).trimmingCharacters(in: .whitespaces) + ellipsis
    }

    // MARK: - Private

    private static func cleanScalar(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        if scalar == zeroWidthJoiner { return scalar }
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            return scalar.properties.isWhitespace ? " " : nil
        case .format, .surrogate, .privateUse, .unassigned:
            return nil
        default:
            return scalar
        }
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
    }
}
