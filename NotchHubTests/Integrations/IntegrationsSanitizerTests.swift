import Foundation
import Testing
@testable import NotchHub

struct IntegrationsSanitizerTests {
    @Test func truncatesLongTitlesWithEllipsis() throws {
        let text = try #require(ExternalAlertSanitizer.displayText(String(repeating: "x", count: 200), maxLength: 80))
        #expect(text.count == 80)
        #expect(text.hasSuffix("…"))
    }

    @Test func keepsShortTextAndEmoji() {
        #expect(ExternalAlertSanitizer.displayText("  Build 👨‍💻 done  ", maxLength: 80) == "Build 👨‍💻 done")
    }

    @Test func stripsBidiZeroWidthAndControls() {
        let raw = "a\u{202E}b\u{200B}c\u{0000}d\u{2028}e\u{FEFF}"
        #expect(ExternalAlertSanitizer.displayText(raw, maxLength: 80) == "abcd e")
    }

    @Test func blankBecomesNil() {
        #expect(ExternalAlertSanitizer.displayText(" \n\t\u{200B} ", maxLength: 80) == nil)
    }

    @Test(arguments: ["bell", "hammer.fill", "1.circle", "person.2.wave.2.fill"])
    func plausibleSymbols(name: String) {
        #expect(ExternalAlertSanitizer.isPlausibleSymbolName(name))
    }

    @Test(arguments: ["", "Bell", "bell fill", ".bell", "bell.", "bell/../x", "a\u{0}", String(repeating: "a", count: 65)])
    func implausibleSymbols(name: String) {
        #expect(!ExternalAlertSanitizer.isPlausibleSymbolName(name))
    }

    @Test func keyIsLimitedAndNamespaced() throws {
        let key = try #require(ExternalAlertSanitizer.coalescingKey(String(repeating: "k", count: 100)))
        #expect(key == "external." + String(repeating: "k", count: 64))
        #expect(ExternalAlertSanitizer.coalescingKey("💥 ;") == nil)
    }

    @Test func openURLRules() {
        #expect(ExternalAlertSanitizer.openURL("https://example.com") != nil)
        #expect(ExternalAlertSanitizer.openURL("HTTP://example.com/a?b=c") != nil)
        #expect(ExternalAlertSanitizer.openURL("file:///Users/me/report.pdf") != nil)
        #expect(ExternalAlertSanitizer.openURL("https://exa\u{0}mple.com") == nil)
        #expect(ExternalAlertSanitizer.openURL("https://" + String(repeating: "a", count: 2100) + ".com") == nil)
        #expect(ExternalAlertSanitizer.openURL("javascript:alert(1)") == nil)
        #expect(ExternalAlertSanitizer.openURL("") == nil)
    }
}
