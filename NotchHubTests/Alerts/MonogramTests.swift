import Testing
@testable import NotchHub

struct MonogramTests {
    @Test(arguments: [
        ("Ayşe Kaya", "AK"),
        ("ayşe nur kaya", "AK"),
        ("Deniz", "D"),
        ("  İlker  Öztürk ", "İÖ"),
        ("john.doe", "JD"),
        ("😀 Deniz", "D"),
    ])
    func derivesInitials(name: String, expected: String) {
        #expect(Monogram.initials(for: name) == expected)
    }

    @Test(arguments: ["", "   ", "+90 555 123 45 67", "😀"])
    func returnsNilWithoutLetters(name: String) {
        #expect(Monogram.initials(for: name) == nil)
    }

    @Test func colourIsDeterministicAndCaseInsensitive() {
        let first = Monogram.gradient(for: "Ayşe Kaya")

        #expect(Monogram.gradient(for: "Ayşe Kaya") == first)
        #expect(Monogram.gradient(for: "  ayşe kaya ") == first)
    }

    @Test func paletteIndexStaysInRange() {
        let names = ["A", "Bora", "Cem Yılmaz", "Deniz", "Ece", "Fatih Terim", "Gül", "Hakan"]
        let indices = names.map { Monogram.paletteIndex(for: $0, count: Monogram.palette.count) }

        #expect(indices.allSatisfy { (0..<Monogram.palette.count).contains($0) })
        #expect(Set(indices).count > 1)
    }

    @Test func paletteIndexHandlesEmptyPalette() {
        #expect(Monogram.paletteIndex(for: "Ayşe", count: 0) == 0)
    }
}
