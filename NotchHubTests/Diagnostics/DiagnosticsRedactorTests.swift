import Foundation
import Testing
@testable import NotchHub

struct DiagnosticsRedactorTests {
    private static let home = "/Users/sample"

    @Test(arguments: [
        ("mail jane.doe+x@example.co.uk now", "mail <email> now"),
        ("a@b.io and c.d@e.org", "<email> and <email>"),
        ("no email here @ all", "no email here @ all"),
    ])
    func emails(input: String, expected: String) {
        #expect(DiagnosticsRedactor.redactEmails(input) == expected)
    }

    @Test(arguments: [
        ("GET https://api.example.com/v1/feed?token=abc&x=1 ok", "GET https://api.example.com/v1/feed?<query> ok"),
        ("webcal://cal.example.com/a.ics?key=secret", "webcal://cal.example.com/a.ics?<query>"),
        ("https://example.com/plain", "https://example.com/plain"),
    ])
    func urlQueries(input: String, expected: String) {
        #expect(DiagnosticsRedactor.redactURLQueries(input) == expected)
    }

    @Test func homePathBecomesTilde() {
        let input = "Saved /Users/sample/Library/Application Support/NotchHub/notes.json"
        #expect(DiagnosticsRedactor.redactHomePath(input, homeDirectory: Self.home)
            == "Saved ~/Library/Application Support/NotchHub/notes.json")
    }

    @Test func otherUserFoldersAreAlsoHidden() {
        #expect(DiagnosticsRedactor.redactHomePath("/Users/other/Desktop", homeDirectory: Self.home) == "~/Desktop")
    }

    @Test(arguments: [
        ("peer 192.168.1.20:443 up", "peer <ip>:443 up"),
        ("dns 2001:0db8:85a3:0000:0000:8a2e:0370:7334", "dns <ip>"),
        ("route fe80::1c2b:3aff", "route <ip>"),
        ("at 12:30:45.120 [info]", "at 12:30:45.120 [info]"),
        ("version 1.4.0 build 5", "version 1.4.0 build 5"),
    ])
    func ipAddresses(input: String, expected: String) {
        #expect(DiagnosticsRedactor.redactIPAddresses(input) == expected)
    }

    @Test(arguments: [
        ("sha 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "sha <hex>"),
        ("token ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8", "token <token>"),
        ("id 1F2E3D4C5B6A7980", "id <hex>"),
        ("short abcdef12", "short abcdef12"),
        ("NotificationMirrorSettingsSectionViewModelCoordinator", "NotificationMirrorSettingsSectionViewModelCoordinator"),
    ])
    func tokens(input: String, expected: String) {
        #expect(DiagnosticsRedactor.redactTokens(input) == expected)
    }

    @Test func fullRedactionCombinesRules() {
        let input = "user a@b.com opened /Users/sample/x.ics from https://h.example/p?k=v via 10.0.0.1"
        let output = DiagnosticsRedactor.redact(input, homeDirectory: Self.home)
        #expect(output == "user <email> opened ~/x.ics from https://h.example/p?<query> via <ip>")
    }

    @Test func redactionKeepsReportStructure() {
        let input = "NotchHub 1.4.0 (6)\nmacOS: Version 26.1 (Build 25B78)\nMac: Mac15,6"
        #expect(DiagnosticsRedactor.redact(input, homeDirectory: Self.home) == input)
    }
}
