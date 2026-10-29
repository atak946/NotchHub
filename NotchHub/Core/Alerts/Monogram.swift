import Foundation

/// sRGB colour pair for a monogram gradient; kept free of SwiftUI so it can be unit tested.
struct MonogramGradient: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    let top: RGB
    let bottom: RGB
}

/// Initials and a deterministic colour for a person-like sender name.
enum Monogram {
    static let maxInitials = 2

    /// Muted, saturated pairs that read well on the black notch.
    static let palette: [MonogramGradient] = [
        gradient((0.98, 0.55, 0.36), (0.86, 0.28, 0.33)),
        gradient((0.99, 0.76, 0.33), (0.93, 0.48, 0.20)),
        gradient((0.45, 0.86, 0.58), (0.16, 0.62, 0.48)),
        gradient((0.38, 0.78, 0.98), (0.20, 0.47, 0.92)),
        gradient((0.63, 0.56, 0.99), (0.40, 0.31, 0.86)),
        gradient((0.96, 0.52, 0.80), (0.74, 0.27, 0.66)),
        gradient((0.50, 0.86, 0.88), (0.18, 0.56, 0.68)),
        gradient((0.78, 0.80, 0.86), (0.48, 0.51, 0.60)),
    ]

    /// First letter of the first and last word ("Ayşe Nur Kaya" → "AK"); `nil` when the name has no letters.
    static func initials(for name: String) -> String? {
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" || $0 == "_" })
            .compactMap { word in word.first(where: \.isLetter) }
        guard let first = words.first else { return nil }
        let letters = words.count > 1 ? [first, words[words.count - 1]] : [first]
        return String(letters.prefix(maxInitials)).uppercased()
    }

    static func gradient(for name: String) -> MonogramGradient {
        palette[paletteIndex(for: name, count: palette.count)]
    }

    /// FNV-1a over the normalised name: stable across launches, unlike `hashValue`.
    static func paletteIndex(for name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let normalised = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalised.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    private static func gradient(
        _ top: (Double, Double, Double),
        _ bottom: (Double, Double, Double)
    ) -> MonogramGradient {
        MonogramGradient(
            top: .init(red: top.0, green: top.1, blue: top.2),
            bottom: .init(red: bottom.0, green: bottom.1, blue: bottom.2)
        )
    }
}
