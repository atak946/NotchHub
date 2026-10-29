import Foundation

/// User-entered Azure app registration (public client — no secret).
struct MicrosoftGraphConfiguration: Equatable, Sendable {
    static let defaultTenant = "organizations"
    private static let authorityHost = "https://login.microsoftonline.com/"
    private static let guidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
    private static let tenantCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))

    let clientID: String
    let tenant: String

    /// Nil unless the client id is a GUID and the tenant is a GUID, domain or `organizations`/`common`/`consumers`.
    static func validated(clientID rawClientID: String, tenant rawTenant: String) -> MicrosoftGraphConfiguration? {
        let clientID = rawClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTenant = rawTenant.trimmingCharacters(in: .whitespacesAndNewlines)
        let tenant = trimmedTenant.isEmpty ? defaultTenant : trimmedTenant
        guard clientID.range(of: guidPattern, options: .regularExpression) != nil else { return nil }
        guard tenant.unicodeScalars.allSatisfy(tenantCharacters.contains) else { return nil }
        return MicrosoftGraphConfiguration(clientID: clientID, tenant: tenant)
    }

    var deviceCodeURL: URL? { URL(string: "\(Self.authorityHost)\(tenant)/oauth2/v2.0/devicecode") }
    var tokenURL: URL? { URL(string: "\(Self.authorityHost)\(tenant)/oauth2/v2.0/token") }
}

/// What the user needs to see while the device-code sign-in is pending.
struct MicrosoftDeviceCodePrompt: Equatable, Sendable {
    let userCode: String
    let verificationURL: URL
    let message: String?
    let expiresAt: Date
}

struct MicrosoftDeviceCodeGrant: Equatable, Sendable {
    let deviceCode: String
    let prompt: MicrosoftDeviceCodePrompt
    /// Polling interval in seconds as provided by the server.
    let interval: Int
}

/// OAuth tokens, persisted as JSON in the Keychain.
struct MicrosoftTokenSet: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

enum MicrosoftAuthError: Error, Equatable, LocalizedError {
    case notConfigured
    case expired
    case declined
    case invalidGrant
    case invalidClient(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Önce geçerli bir Uygulama (istemci) kimliği girin."
        case .expired: "Giriş kodunun süresi doldu. Tekrar deneyin."
        case .declined: "Giriş reddedildi."
        case .invalidGrant: "Microsoft 365 oturumu sona erdi. Tekrar giriş yapın."
        case let .invalidClient(message): "Uygulama kaydı reddedildi: \(message)"
        case let .server(message): message
        case .invalidResponse: "Microsoft'tan beklenmeyen yanıt."
        }
    }
}

/// State of the Microsoft 365 connection shown in settings.
enum MicrosoftSignInState: Equatable, Sendable {
    case signedOut
    case requestingCode
    case awaitingUser(MicrosoftDeviceCodePrompt)
    case signedIn(username: String)
}

// MARK: - Wire formats

/// Some Microsoft endpoints have historically returned numbers as strings.
struct MicrosoftFlexibleInt: Decodable, Equatable, Sendable {
    let value: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self), let number = Int(text) {
            value = number
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer")
        }
    }
}

struct MicrosoftDeviceCodeResponse: Decodable, Sendable {
    let userCode: String
    let deviceCode: String
    let verificationURI: String
    let expiresIn: MicrosoftFlexibleInt
    let interval: MicrosoftFlexibleInt?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

struct MicrosoftTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: MicrosoftFlexibleInt

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct MicrosoftOAuthErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
