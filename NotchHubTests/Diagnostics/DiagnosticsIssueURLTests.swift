import Foundation
import Testing
@testable import NotchHub

struct DiagnosticsIssueURLTests {
    @Test(arguments: [
        ("owner/repo", "https://github.com/owner/repo/issues/new"),
        ("  owner/repo.swift \n", "https://github.com/owner/repo.swift/issues/new"),
        ("https://github.com/owner/repo", "https://github.com/owner/repo/issues/new"),
        ("https://github.com/owner/repo/", "https://github.com/owner/repo/issues/new"),
        ("https://github.com/owner/repo/issues/new", "https://github.com/owner/repo/issues/new"),
    ])
    func baseURL(configured: String, expected: String) {
        #expect(DiagnosticsIssueURL.baseURL(from: configured)?.absoluteString == expected)
    }

    @Test(arguments: [nil, "", "   ", "$(NH_ISSUE_URL)", "http://github.com/o/r", "javascript:alert(1)", "owner", "https://x.com/o/r?a=1"])
    func rejectedBaseURL(configured: String?) {
        #expect(DiagnosticsIssueURL.baseURL(from: configured) == nil)
    }

    @Test func encodesTitleAndBodyStrictly() throws {
        let base = try #require(DiagnosticsIssueURL.baseURL(from: "o/r"))
        let url = try #require(DiagnosticsIssueURL.make(base: base, title: "a+b & c", summary: "x=1"))
        let string = url.absoluteString
        #expect(string.hasPrefix("https://github.com/o/r/issues/new?title=a%2Bb%20%26%20c&body="))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = components.queryItems?.first { $0.name == "body" }?.value
        #expect(body?.contains(DiagnosticsIssueURL.pasteInstruction) == true)
        #expect(body?.contains("x=1") == true)
    }

    @Test func longSummaryIsTrimmedUnderTheCap() throws {
        let base = try #require(DiagnosticsIssueURL.baseURL(from: "o/r"))
        let summary = (1...800).map { "line \($0) çğüşöı padding padding" }.joined(separator: "\n")

        let url = try #require(DiagnosticsIssueURL.make(base: base, summary: summary))

        #expect(url.absoluteString.utf8.count <= DiagnosticsIssueURL.maxLength)
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        #expect(body?.contains("line 1 ") == true)
        #expect(body?.contains("line 800") == false)
        #expect(body?.contains(DiagnosticsIssueURL.truncationMarker) == true)
    }

    @Test func shortSummaryIsKeptWhole() throws {
        let base = try #require(DiagnosticsIssueURL.baseURL(from: "o/r"))
        let url = try #require(DiagnosticsIssueURL.make(base: base, summary: "a\nb"))
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        #expect(body == DiagnosticsIssueURL.body(summary: "a\nb"))
    }

    @Test func hugeTitleFallsBackToInstructionOnly() throws {
        let base = try #require(DiagnosticsIssueURL.baseURL(from: "o/r"))
        let url = try #require(DiagnosticsIssueURL.make(base: base, title: String(repeating: "x", count: 10_000), summary: "s"))
        #expect(url.absoluteString.utf8.count <= DiagnosticsIssueURL.maxLength)
    }
}
