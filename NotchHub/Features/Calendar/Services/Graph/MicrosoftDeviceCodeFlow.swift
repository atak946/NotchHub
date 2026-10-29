import Foundation

/// OAuth 2.0 device authorization grant (RFC 8628) against the Microsoft identity platform, plus token refresh.
struct MicrosoftDeviceCodeFlow: Sendable {
    static let scopes = "Calendars.Read offline_access User.Read"
    static let deviceCodeGrantType = "urn:ietf:params:oauth:grant-type:device_code"
    static let defaultInterval = 5
    static let slowDownIncrement = 5
    static let verificationFallbackURL = URL(string: "https://microsoft.com/devicelogin")
    private static let trustedVerificationHostSuffixes = ["microsoft.com", "microsoftonline.com"]

    private enum ErrorCode {
        static let pending = "authorization_pending"
        static let slowDown = "slow_down"
        static let expired: Set<String> = ["expired_token", "code_expired"]
        static let declined: Set<String> = ["authorization_declined", "access_denied"]
        static let invalidGrant = "invalid_grant"
        static let invalidClient: Set<String> = ["invalid_client", "unauthorized_client"]
    }

    let configuration: MicrosoftGraphConfiguration
    let http: any CalendarHTTPClient
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void

    func requestDeviceCode() async throws -> MicrosoftDeviceCodeGrant {
        guard let url = configuration.deviceCodeURL else { throw MicrosoftAuthError.notConfigured }
        let (data, response) = try await post(url, fields: [("client_id", configuration.clientID), ("scope", Self.scopes)])
        guard (200..<300).contains(response.statusCode) else { throw Self.error(from: data) }
        guard let decoded = try? JSONDecoder().decode(MicrosoftDeviceCodeResponse.self, from: data) else {
            throw MicrosoftAuthError.invalidResponse
        }
        let prompt = MicrosoftDeviceCodePrompt(
            userCode: decoded.userCode,
            verificationURL: Self.verificationURL(decoded.verificationURI),
            message: decoded.message,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expiresIn.value))
        )
        return MicrosoftDeviceCodeGrant(
            deviceCode: decoded.deviceCode,
            prompt: prompt,
            interval: max(1, decoded.interval?.value ?? Self.defaultInterval)
        )
    }

    /// Polls with the server-provided interval (growing on `slow_down`) until the user finishes or the code expires.
    func pollForToken(_ grant: MicrosoftDeviceCodeGrant) async throws -> MicrosoftTokenSet {
        guard let url = configuration.tokenURL else { throw MicrosoftAuthError.notConfigured }
        var interval = grant.interval
        while true {
            try await sleep(.seconds(interval))
            guard now() < grant.prompt.expiresAt else { throw MicrosoftAuthError.expired }
            let (data, response) = try await post(url, fields: [
                ("grant_type", Self.deviceCodeGrantType),
                ("client_id", configuration.clientID),
                ("device_code", grant.deviceCode),
            ])
            if (200..<300).contains(response.statusCode) {
                return try tokenSet(from: data, previousRefreshToken: nil)
            }
            let code = (try? JSONDecoder().decode(MicrosoftOAuthErrorResponse.self, from: data))?.error
            switch code {
            case ErrorCode.pending:
                continue
            case ErrorCode.slowDown:
                interval += Self.slowDownIncrement
            default:
                throw Self.error(from: data)
            }
        }
    }

    func refresh(_ refreshToken: String) async throws -> MicrosoftTokenSet {
        guard let url = configuration.tokenURL else { throw MicrosoftAuthError.notConfigured }
        let (data, response) = try await post(url, fields: [
            ("grant_type", "refresh_token"),
            ("client_id", configuration.clientID),
            ("refresh_token", refreshToken),
            ("scope", Self.scopes),
        ])
        guard (200..<300).contains(response.statusCode) else { throw Self.error(from: data) }
        return try tokenSet(from: data, previousRefreshToken: refreshToken)
    }

    // MARK: - Private

    private func post(_ url: URL, fields: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = CalendarFormEncoding.encode(fields)
        return try await http.data(for: request)
    }

    private func tokenSet(from data: Data, previousRefreshToken: String?) throws -> MicrosoftTokenSet {
        guard let decoded = try? JSONDecoder().decode(MicrosoftTokenResponse.self, from: data) else {
            throw MicrosoftAuthError.invalidResponse
        }
        return MicrosoftTokenSet(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? previousRefreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expiresIn.value))
        )
    }

    static func error(from data: Data) -> MicrosoftAuthError {
        guard let decoded = try? JSONDecoder().decode(MicrosoftOAuthErrorResponse.self, from: data) else {
            return .invalidResponse
        }
        let description = Self.firstLine(decoded.errorDescription) ?? decoded.error
        switch decoded.error {
        case let code where ErrorCode.expired.contains(code): return .expired
        case let code where ErrorCode.declined.contains(code): return .declined
        case ErrorCode.invalidGrant: return .invalidGrant
        case let code where ErrorCode.invalidClient.contains(code): return .invalidClient(description)
        default: return .server(description)
        }
    }

    /// Only Microsoft-owned https pages are opened; anything else falls back to microsoft.com/devicelogin.
    private static func verificationURL(_ text: String) -> URL {
        let fallback = verificationFallbackURL ?? URL(fileURLWithPath: "/")
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else {
            return fallback
        }
        let trusted = trustedVerificationHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        return trusted ? url : fallback
    }

    /// AAD descriptions look like "AADSTS7000218: The request body must contain…\r\nTrace ID: …".
    private static func firstLine(_ text: String?) -> String? {
        text?.split(whereSeparator: \.isNewline).first.map(String.init)
    }
}
