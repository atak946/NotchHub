import Foundation
import Testing
@testable import NotchHub

@MainActor
struct MicrosoftGraphSourceTests {
    private typealias F = CalendarICSFixtures
    nonisolated private static let clientID = "11111111-2222-3333-4444-555555555555"
    nonisolated private static let now = F.utc("2026-03-10T08:00:00Z")

    nonisolated private static let deviceCode = CalendarTestHTTPStub.json(
        #"{"user_code":"ABCD-1234","device_code":"dev","verification_uri":"https://microsoft.com/devicelogin","expires_in":900,"interval":5}"#
    )
    nonisolated private static let me = CalendarTestHTTPStub.json(#"{"displayName":"Jane","userPrincipalName":"jane@contoso.com","mail":null}"#)
    nonisolated private static let page = CalendarTestHTTPStub.json("""
    {"value":[{"id":"e1","subject":"Planning","isAllDay":false,"isCancelled":false,
      "start":{"dateTime":"2026-03-10T09:00:00.0000000","timeZone":"UTC"},
      "end":{"dateTime":"2026-03-10T10:00:00.0000000","timeZone":"UTC"},
      "location":{"displayName":"https://zoom.us/j/123456789"}}]}
    """)

    nonisolated private static func token(_ access: String) -> CalendarTestHTTPStub {
        .json(#"{"access_token":"\#(access)","refresh_token":"refresh-\#(access)","expires_in":3600}"#)
    }

    private struct Harness {
        let source: MicrosoftGraphSource
        let secrets: CalendarTestSecretStore
        let defaults: UserDefaults
        let http: CalendarTestHTTPClient
    }

    private func makeHarness(
        signedInAs username: String? = nil,
        tokens: MicrosoftTokenSet? = nil,
        responder: @escaping CalendarTestHTTPClient.Responder
    ) throws -> Harness {
        let defaults = CalendarFixtures.makeDefaults()
        defaults.set(Self.clientID, forKey: MicrosoftGraphSource.Keys.clientID)
        if let username { defaults.set(username, forKey: MicrosoftGraphSource.Keys.username) }
        let secrets = CalendarTestSecretStore()
        if let tokens {
            let json = String(decoding: try JSONEncoder().encode(tokens), as: UTF8.self)
            try secrets.setSecret(json, for: MicrosoftGraphSource.tokenSecretKey)
        }
        let http = CalendarTestHTTPClient(responder: responder)
        let source = MicrosoftGraphSource(defaults: defaults, secrets: secrets, http: http, now: { Self.now }, sleep: { _ in })
        return Harness(source: source, secrets: secrets, defaults: defaults, http: http)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            await Task.yield()
        }
    }

    nonisolated private static func route(_ request: URLRequest, token: CalendarTestHTTPStub = token("access-1")) -> CalendarTestHTTPStub {
        let path = request.url?.path() ?? ""
        if path.hasSuffix("/devicecode") { return deviceCode }
        if path.hasSuffix("/token") { return token }
        if path.hasSuffix("/calendarView") { return page }
        if path.hasSuffix("/me") { return me }
        return .json("{}", status: 404)
    }

    private var window: (Date, Date) {
        (F.utc("2026-03-10T00:00:00Z"), F.utc("2026-03-11T00:00:00Z"))
    }

    @Test func deviceCodeSignInStoresTokensInKeychainAndSyncs() async throws {
        let harness = try makeHarness { Self.route($0) }
        let source = harness.source
        #expect(source.authorization == .notDetermined)

        source.signIn()
        await waitUntil { source.lastSync != nil }

        #expect(source.state == .signedIn(username: "jane@contoso.com"))
        #expect(source.authorization == .authorized)
        let events = try source.events(from: window.0, to: window.1)
        #expect(events.map(\.title) == ["Planning"])
        #expect(events.first?.meetingLink?.provider == .zoom)
        #expect(events.first?.account.kind == .outlook)
        #expect(source.accounts().first?.title == "jane@contoso.com")
        #expect(harness.secrets.secret(for: MicrosoftGraphSource.tokenSecretKey)?.contains("access-1") == true)
        let defaultsDump = harness.defaults.dictionaryRepresentation().values.map { "\($0)" }.joined()
        #expect(!defaultsDump.contains("access-1"))
        #expect(!defaultsDump.contains("refresh-access-1"))
    }

    @Test func signInWithoutValidClientIDShowsStatus() throws {
        let harness = try makeHarness { Self.route($0) }
        harness.source.clientID = "nope"

        harness.source.signIn()

        #expect(harness.source.state == .signedOut)
        #expect(harness.source.statusMessage == MicrosoftAuthError.notConfigured.localizedDescription)
        #expect(harness.http.requests.isEmpty)
    }

    @Test func refreshesExpiredAccessTokenBeforeFetching() async throws {
        let expired = MicrosoftTokenSet(accessToken: "old", refreshToken: "refresh-old", expiresAt: Self.now.addingTimeInterval(-10))
        let harness = try makeHarness(signedInAs: "jane@contoso.com", tokens: expired) { Self.route($0, token: Self.token("new")) }

        await harness.source.refreshNow()

        let graphRequest = harness.http.requests.first { $0.url?.host() == "graph.microsoft.com" }
        #expect(graphRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer new")
        #expect(harness.secrets.secret(for: MicrosoftGraphSource.tokenSecretKey)?.contains("refresh-new") == true)
        #expect(try harness.source.events(from: window.0, to: window.1).count == 1)
    }

    @Test func invalidGrantSignsOutWithStatusMessage() async throws {
        let valid = MicrosoftTokenSet(accessToken: "a", refreshToken: "r", expiresAt: Self.now.addingTimeInterval(3600))
        let harness = try makeHarness(signedInAs: "jane@contoso.com", tokens: valid) { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("/calendarView") { return .json("{}", status: 401) }
            if path.hasSuffix("/token") { return .json(#"{"error":"invalid_grant","error_description":"AADSTS700082: expired"}"#, status: 400) }
            return .json("{}", status: 404)
        }

        await harness.source.refreshNow()

        #expect(harness.source.state == .signedOut)
        #expect(harness.source.authorization == .notDetermined)
        #expect(harness.source.statusMessage == MicrosoftAuthError.invalidGrant.localizedDescription)
        #expect(harness.secrets.all.isEmpty)
        #expect(harness.defaults.string(forKey: MicrosoftGraphSource.Keys.username) == nil)
    }

    @Test func networkFailureKeepsSessionAndReportsStatus() async throws {
        let valid = MicrosoftTokenSet(accessToken: "a", refreshToken: "r", expiresAt: Self.now.addingTimeInterval(3600))
        let harness = try makeHarness(signedInAs: "jane@contoso.com", tokens: valid) { _ in .json("{}", status: 503) }

        await harness.source.refreshNow()

        #expect(harness.source.isSignedIn)
        #expect(harness.source.statusMessage?.hasPrefix("Eşitleme başarısız") == true)
        #expect(throws: (any Error).self) { try harness.source.events(from: window.0, to: window.1) }
    }

    @Test func cancelSignInReturnsToSignedOut() async throws {
        let harness = try makeHarness { Self.route($0) }
        harness.source.signIn()
        #expect(harness.source.state == .requestingCode)

        harness.source.cancelSignIn()

        #expect(harness.source.state == .signedOut)
    }
}
