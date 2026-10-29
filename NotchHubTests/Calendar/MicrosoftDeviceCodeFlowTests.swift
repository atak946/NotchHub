import Foundation
import Testing
@testable import NotchHub

struct MicrosoftDeviceCodeFlowTests {
    private static let configuration = MicrosoftGraphConfiguration(clientID: "11111111-2222-3333-4444-555555555555", tenant: "organizations")
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func deviceCode(expiresIn: Int = 900, interval: Int = 5) -> CalendarTestHTTPStub {
        .json("""
        {"user_code":"ABCD-1234","device_code":"dev-code+/=","verification_uri":"https://microsoft.com/devicelogin",
         "expires_in":\(expiresIn),"interval":\(interval),"message":"To sign in, use a web browser…"}
        """)
    }

    private static func oauthError(_ code: String) -> CalendarTestHTTPStub {
        .json(#"{"error":"\#(code)","error_description":"AADSTS70016: \#(code)\r\nTrace ID: 1"}"#, status: 400)
    }

    private static let token = CalendarTestHTTPStub.json(
        #"{"token_type":"Bearer","scope":"Calendars.Read User.Read","expires_in":3600,"access_token":"access-1","refresh_token":"refresh-1"}"#
    )

    private func makeFlow(_ http: CalendarTestHTTPClient, clock: CalendarTestClock, sleeper: CalendarTestSleeper) -> MicrosoftDeviceCodeFlow {
        MicrosoftDeviceCodeFlow(configuration: Self.configuration, http: http, now: { clock.now }, sleep: sleeper.sleep)
    }

    @Test func requestsDeviceCodeWithScopes() async throws {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.deviceCode()])
        let grant = try await makeFlow(http, clock: clock, sleeper: CalendarTestSleeper()).requestDeviceCode()

        #expect(grant.prompt.userCode == "ABCD-1234")
        #expect(grant.prompt.verificationURL.absoluteString == "https://microsoft.com/devicelogin")
        #expect(grant.prompt.expiresAt == Self.start.addingTimeInterval(900))
        #expect(grant.interval == 5)
        let request = try #require(http.requests.first)
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode")
        #expect(body.contains("client_id=11111111-2222-3333-4444-555555555555"))
        #expect(body.contains("scope=Calendars.Read%20offline_access%20User.Read"))
    }

    @Test func pollsThroughPendingAndSlowDownUntilSuccess() async throws {
        let clock = CalendarTestClock(Self.start)
        let sleeper = CalendarTestSleeper(clock: clock)
        let http = CalendarTestHTTPClient(sequence: [
            Self.deviceCode(),
            Self.oauthError("authorization_pending"),
            Self.oauthError("slow_down"),
            Self.oauthError("authorization_pending"),
            Self.token,
        ])
        let flow = makeFlow(http, clock: clock, sleeper: sleeper)

        let grant = try await flow.requestDeviceCode()
        let tokens = try await flow.pollForToken(grant)

        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
        #expect(sleeper.sleeps == [.seconds(5), .seconds(5), .seconds(10), .seconds(10)])
        #expect(tokens.expiresAt == clock.now.addingTimeInterval(3600))
        let body = String(decoding: http.requests.last?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(body.contains("device_code=dev-code%2B%2F%3D"))
    }

    @Test func stopsWhenServerReportsExpiredCode() async throws {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.deviceCode(), Self.oauthError("expired_token")])
        let flow = makeFlow(http, clock: clock, sleeper: CalendarTestSleeper(clock: clock))
        let grant = try await flow.requestDeviceCode()

        await #expect(throws: MicrosoftAuthError.expired) { try await flow.pollForToken(grant) }
    }

    @Test func stopsPollingOnceTheCodeLifetimeHasPassed() async throws {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.deviceCode(expiresIn: 12), Self.oauthError("authorization_pending")])
        let flow = makeFlow(http, clock: clock, sleeper: CalendarTestSleeper(clock: clock))
        let grant = try await flow.requestDeviceCode()

        await #expect(throws: MicrosoftAuthError.expired) { try await flow.pollForToken(grant) }
        // Device code + polls at t=5 and t=10; at t=15 the code has expired and no request is sent.
        #expect(http.requests.count == 3)
    }

    @Test func reportsDeclinedSignIn() async throws {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.deviceCode(), Self.oauthError("authorization_declined")])
        let flow = makeFlow(http, clock: clock, sleeper: CalendarTestSleeper(clock: clock))
        let grant = try await flow.requestDeviceCode()

        await #expect(throws: MicrosoftAuthError.declined) { try await flow.pollForToken(grant) }
    }

    @Test func surfacesInvalidClientDescription() async {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.oauthError("invalid_client")])
        let flow = makeFlow(http, clock: clock, sleeper: CalendarTestSleeper())

        await #expect(throws: MicrosoftAuthError.invalidClient("AADSTS70016: invalid_client")) {
            try await flow.requestDeviceCode()
        }
    }

    @Test func refreshKeepsPreviousRefreshTokenWhenNotRotated() async throws {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [.json(#"{"access_token":"access-2","expires_in":"3599"}"#)])
        let tokens = try await makeFlow(http, clock: clock, sleeper: CalendarTestSleeper()).refresh("refresh-1")

        #expect(tokens == MicrosoftTokenSet(accessToken: "access-2", refreshToken: "refresh-1", expiresAt: Self.start.addingTimeInterval(3599)))
        let body = String(decoding: http.requests.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=refresh-1"))
    }

    @Test func refreshMapsInvalidGrant() async {
        let clock = CalendarTestClock(Self.start)
        let http = CalendarTestHTTPClient(sequence: [Self.oauthError("invalid_grant")])
        let flow = makeFlow(http, clock: clock, sleeper: CalendarTestSleeper())

        await #expect(throws: MicrosoftAuthError.invalidGrant) { try await flow.refresh("old") }
    }

    @Test func distrustsForeignVerificationURL() async throws {
        let clock = CalendarTestClock(Self.start)
        let stub = CalendarTestHTTPStub.json(
            #"{"user_code":"X","device_code":"d","verification_uri":"https://phish.example.com/login","expires_in":900}"#
        )
        let grant = try await makeFlow(CalendarTestHTTPClient(sequence: [stub]), clock: clock, sleeper: CalendarTestSleeper())
            .requestDeviceCode()

        #expect(grant.prompt.verificationURL.absoluteString == "https://microsoft.com/devicelogin")
        #expect(grant.interval == MicrosoftDeviceCodeFlow.defaultInterval)
    }
}
