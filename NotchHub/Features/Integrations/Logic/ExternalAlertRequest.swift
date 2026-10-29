import Foundation

/// Alert styles accepted from external callers (`style=` parameter).
enum ExternalAlertStyle: String, CaseIterable, Sendable {
    case info
    case reminder
    case success
    case urgent

    var alertStyle: NotchAlert.Style {
        switch self {
        case .info: .info
        case .reminder: .reminder
        case .success: .success
        case .urgent: .urgent
        }
    }

    /// Symbol used when the caller does not pass `icon=`.
    var defaultSystemImage: String {
        switch self {
        case .info: "bell"
        case .reminder: "bell.badge"
        case .success: "checkmark.circle.fill"
        case .urgent: "exclamationmark.triangle.fill"
        }
    }
}

/// Panel tabs an external caller may open with `notchhub://open?module=…`.
enum IntegrationsOpenTarget: String, CaseIterable, Sendable {
    case shelf
    case media
    case timer
    case calendar
    case status
}

/// Outcome of a shell command reported by the zsh hook or `notchhub done`.
struct ExternalCommandResult: Equatable, Sendable {
    let commandLine: String
    let exitCode: Int
    let elapsed: TimeInterval

    var succeeded: Bool { exitCode == 0 }
}

/// A validated, sanitized alert ready to be posted to the notch.
struct ExternalAlertRequest: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let style: ExternalAlertStyle
    /// Syntactically valid SF Symbol name; the service still checks it exists.
    let systemImage: String
    /// `nil` keeps the alert until dismissed (`duration=0`).
    let autoDismissAfter: Duration?
    /// Already namespaced (`external.<key>`) so callers cannot replace built-in alerts.
    let coalescingKey: String?
    /// Only http, https or file URLs.
    let openURL: URL?
    let command: ExternalCommandResult?
}

/// Every action the URL scheme and socket understand.
enum ExternalRequest: Equatable, Sendable {
    case alert(ExternalAlertRequest)
    case open(IntegrationsOpenTarget)
}

/// A parsed request plus non-fatal problems (ignored parameters, dropped values).
struct ExternalParseResult: Equatable, Sendable {
    let request: ExternalRequest
    let warnings: [String]
}

enum ExternalRequestError: Error, Equatable, Sendable {
    case notNotchHubURL
    case payloadTooLarge
    case invalidJSON
    case unknownAction(String)
    case missingTitle
    case invalidStyle(String)
    case invalidDuration(String)
    case invalidModule(String)
    case invalidExitCode(String)
    case invalidElapsed(String)

    /// Short English message returned to socket clients and logged.
    var message: String {
        switch self {
        case .notNotchHubURL: "not a notchhub:// URL"
        case .payloadTooLarge: "request too large"
        case .invalidJSON: "expected one JSON object per line"
        case .unknownAction(let action): "unknown action '\(action)' (use alert or open)"
        case .missingTitle: "title is required"
        case .invalidStyle(let value): "invalid style '\(value)' (use info, reminder, success or urgent)"
        case .invalidDuration(let value): "invalid duration '\(value)' (seconds, 0 = sticky)"
        case .invalidModule(let value): "invalid module '\(value)' (use shelf, media, timer, calendar or status)"
        case .invalidExitCode(let value): "invalid exit code '\(value)'"
        case .invalidElapsed(let value): "invalid elapsed '\(value)'"
        }
    }
}
