import Foundation

/// A named client context ("Acme"): an ordered list of steps that sets up the work environment.
struct ClientProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var color: ProfileColor
    var steps: [ProfileStep]
    /// Optional teardown run by "Deactivate" (e.g. `docker compose stop`).
    var deactivateSteps: [ProfileStep]

    init(
        id: UUID = UUID(),
        name: String,
        color: ProfileColor = .blue,
        steps: [ProfileStep] = [],
        deactivateSteps: [ProfileStep] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.steps = steps
        self.deactivateSteps = deactivateSteps
    }

    /// Name shown in the UI; never empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Adsız profil") : trimmed
    }
}

/// Fixed palette so profiles stay readable on the black notch background.
enum ProfileColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: String(localized: "Mavi")
        case .purple: String(localized: "Mor")
        case .pink: String(localized: "Pembe")
        case .red: String(localized: "Kırmızı")
        case .orange: String(localized: "Turuncu")
        case .yellow: String(localized: "Sarı")
        case .green: String(localized: "Yeşil")
        case .teal: String(localized: "Turkuaz")
        case .gray: String(localized: "Gri")
        }
    }
}

/// One step of a profile. `continueOnFailure` lets non-critical steps fail without aborting the run.
struct ProfileStep: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var action: ProfileAction
    var continueOnFailure: Bool

    init(id: UUID = UUID(), action: ProfileAction, continueOnFailure: Bool = false) {
        self.id = id
        self.action = action
        self.continueOnFailure = continueOnFailure
    }
}

enum ProfileAction: Codable, Hashable, Sendable {
    /// Launch or activate an app by bundle identifier.
    case openApp(bundleID: String)
    /// Open an http(s) URL or an allow-listed app URL scheme (e.g. `rdm://`).
    case openURL(String)
    /// Open a folder in VS Code.
    case openInVSCode(path: String)
    /// `docker compose up -d` in a folder.
    case dockerComposeUp(path: String)
    /// `docker compose stop` in a folder (typical deactivate step).
    case dockerComposeStop(path: String)
    /// Open the configured terminal app at a folder.
    case openTerminal(path: String)
    /// Wait until a VPN tunnel is up; opens the VPN client and prompts the user if it is not.
    case waitForVPN(timeoutSeconds: Int)

    static let defaultVPNTimeoutSeconds = 90

    var kind: ProfileActionKind {
        switch self {
        case .openApp: .openApp
        case .openURL: .openURL
        case .openInVSCode: .openInVSCode
        case .dockerComposeUp: .dockerComposeUp
        case .dockerComposeStop: .dockerComposeStop
        case .openTerminal: .openTerminal
        case .waitForVPN: .waitForVPN
        }
    }

    /// Folder the action works on, if any.
    var folderPath: String? {
        switch self {
        case let .openInVSCode(path), let .dockerComposeUp(path), let .dockerComposeStop(path), let .openTerminal(path):
            path
        case .openApp, .openURL, .waitForVPN:
            nil
        }
    }

    /// Returns a copy with the folder replaced (no-op for actions without a folder).
    func withFolderPath(_ path: String) -> ProfileAction {
        switch self {
        case .openInVSCode: .openInVSCode(path: path)
        case .dockerComposeUp: .dockerComposeUp(path: path)
        case .dockerComposeStop: .dockerComposeStop(path: path)
        case .openTerminal: .openTerminal(path: path)
        case .openApp, .openURL, .waitForVPN: self
        }
    }

    /// Short human description, e.g. "compose up · api".
    var summary: String {
        switch self {
        case let .openApp(bundleID): String(localized: "\(bundleID) aç")
        case let .openURL(url): String(localized: "\(url) aç")
        case let .openInVSCode(path): "VS Code · \(Self.folderName(path))"
        case let .dockerComposeUp(path): "compose up · \(Self.folderName(path))"
        case let .dockerComposeStop(path): "compose stop · \(Self.folderName(path))"
        case let .openTerminal(path): "Terminal · \(Self.folderName(path))"
        case let .waitForVPN(timeout): String(localized: "VPN bekle (\(timeout) sn)")
        }
    }

    private static func folderName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "–" : name
    }
}

enum ProfileActionKind: String, CaseIterable, Identifiable, Sendable {
    case openApp, openURL, openInVSCode, dockerComposeUp, dockerComposeStop, openTerminal, waitForVPN

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openApp: String(localized: "Uygulama aç")
        case .openURL: String(localized: "URL aç")
        case .openInVSCode: String(localized: "Klasörü VS Code'da aç")
        case .dockerComposeUp: "docker compose up -d"
        case .dockerComposeStop: "docker compose stop"
        case .openTerminal: String(localized: "Terminali klasörde aç")
        case .waitForVPN: String(localized: "VPN bekle")
        }
    }

    var systemImage: String {
        switch self {
        case .openApp: "app.badge"
        case .openURL: "link"
        case .openInVSCode: "chevron.left.forwardslash.chevron.right"
        case .dockerComposeUp: "shippingbox"
        case .dockerComposeStop: "stop.circle"
        case .openTerminal: "terminal"
        case .waitForVPN: "lock.shield"
        }
    }

    /// Empty template used when the user adds a step in the editor.
    var template: ProfileAction {
        switch self {
        case .openApp: .openApp(bundleID: "")
        case .openURL: .openURL("https://")
        case .openInVSCode: .openInVSCode(path: "")
        case .dockerComposeUp: .dockerComposeUp(path: "")
        case .dockerComposeStop: .dockerComposeStop(path: "")
        case .openTerminal: .openTerminal(path: "")
        case .waitForVPN: .waitForVPN(timeoutSeconds: ProfileAction.defaultVPNTimeoutSeconds)
        }
    }
}
