import Foundation
import Testing
@testable import NotchHub

struct MeetingLinkParserTests {
    private func parseNotes(_ notes: String) -> MeetingLink? {
        MeetingLinkParser.parse(url: nil, location: nil, notes: notes)
    }

    @Test(arguments: [
        ("https://us02web.zoom.us/j/81234567890?pwd=abc", MeetingProvider.zoom),
        ("https://zoom.us/j/123456789", .zoom),
        ("zoommtg://zoom.us/join?confno=123", .zoom),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d", .teams),
        ("https://teams.live.com/meet/9876543210", .teams),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://acme.webex.com/meet/jane", .webex),
        ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
        ("https://meet.jit.si/MyRoom", .other),
    ])
    func detectsProviders(link: String, provider: MeetingProvider) {
        let result = parseNotes("Join here: \(link)\nThanks")
        #expect(result?.provider == provider)
        #expect(result?.url.absoluteString == link)
    }

    @Test func unwrapsOutlookSafelinks() {
        let notes = "Click <https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F555%3Fpwd%3Dx&data=05%7C01&reserved=0>"
        let result = parseNotes(notes)
        #expect(result?.provider == .zoom)
        #expect(result?.url.absoluteString == "https://zoom.us/j/555?pwd=x")
    }

    @Test func ignoresSafelinkToNonMeetingURL() {
        let notes = "<https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Fdoc&data=1>"
        #expect(parseNotes(notes) == nil)
    }

    @Test func stripsAngleBracketsAndTrailingPunctuation() {
        #expect(parseNotes("<https://meet.google.com/abc-defg-hij>")?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(parseNotes("(see https://zoom.us/j/42).")?.url.absoluteString == "https://zoom.us/j/42")
        #expect(parseNotes("Link: https://zoom.us/j/42, thanks!")?.url.absoluteString == "https://zoom.us/j/42")
    }

    @Test func acceptsSchemelessKnownHosts() {
        let result = MeetingLinkParser.parse(url: nil, location: "acme.zoom.us/j/777", notes: nil)
        #expect(result?.provider == .zoom)
        #expect(result?.url.absoluteString == "https://acme.zoom.us/j/777")
    }

    @Test func prefersEventURLThenLocationThenNotes() throws {
        let url = try #require(URL(string: "https://meet.google.com/aaa-bbbb-ccc"))
        let location = "https://zoom.us/j/1"
        let notes = "https://teams.live.com/meet/2"

        #expect(MeetingLinkParser.parse(url: url, location: location, notes: notes)?.provider == .meet)
        #expect(MeetingLinkParser.parse(url: nil, location: location, notes: notes)?.provider == .zoom)
        #expect(MeetingLinkParser.parse(url: nil, location: "Room 4", notes: notes)?.provider == .teams)
    }

    @Test func skipsNonMeetingEventURL() throws {
        let url = try #require(URL(string: "https://intranet.example.com/agenda"))
        #expect(MeetingLinkParser.parse(url: url, location: nil, notes: "https://zoom.us/j/9")?.provider == .zoom)
    }

    @Test func picksFirstMeetingLinkInText() {
        let notes = "Agenda: https://docs.example.com/x\nJoin: https://teams.microsoft.com/l/meetup-join/abc\nBackup: https://zoom.us/j/1"
        #expect(parseNotes(notes)?.provider == .teams)
    }

    @Test(arguments: [
        "",
        "Conference room B",
        "https://",
        "zoom.us",
        "https://zoom.us/pricing",
        "https://meet.google.com/",
        "https://teams.microsoft.com/",
        "https://www.example.com/j/123",
        "mailto:someone@zoom.us",
        "<<>>,.;:",
        "http://\u{0}garbage zoom",
    ])
    func returnsNilWithoutMeetingLink(text: String) {
        #expect(MeetingLinkParser.parse(url: nil, location: text, notes: text) == nil)
    }

    @Test func returnsNilForAllNilInputs() {
        #expect(MeetingLinkParser.parse(url: nil, location: nil, notes: nil) == nil)
    }

    @Test func convertsZoomLinkToAppURL() throws {
        let link = MeetingLink(provider: .zoom, url: try #require(URL(string: "https://acme.zoom.us/j/123456?pwd=s3cr3t")))

        let appURL = MeetingLinkParser.launchURL(for: link, isZoomAppInstalled: true)
        #expect(appURL.absoluteString == "zoommtg://acme.zoom.us/join?action=join&confno=123456&pwd=s3cr3t")
        #expect(MeetingLinkParser.launchURL(for: link, isZoomAppInstalled: false) == link.url)
    }

    @Test func keepsBrowserURLForNonJoinZoomAndOtherProviders() throws {
        let personal = MeetingLink(provider: .zoom, url: try #require(URL(string: "https://zoom.us/my/jane")))
        let meet = MeetingLink(provider: .meet, url: try #require(URL(string: "https://meet.google.com/abc-defg-hij")))

        #expect(MeetingLinkParser.launchURL(for: personal, isZoomAppInstalled: true) == personal.url)
        #expect(MeetingLinkParser.launchURL(for: meet, isZoomAppInstalled: true) == meet.url)
    }
}
