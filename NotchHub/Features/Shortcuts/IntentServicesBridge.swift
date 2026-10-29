import Foundation
import OSLog

/// A profile as Shortcuts sees it.
struct IntentProfile: Equatable, Sendable {
    let id: UUID
    let name: String
}

/// The app capabilities App Intents may use. `LiveIntentRoutes` adapts the real services; tests use fakes.
@MainActor
protocol IntentRouting: AnyObject {
    func isModuleEnabled(_ module: NotchModule) -> Bool
    /// `false` while notch alerts are turned off or paused.
    var canPostAlerts: Bool { get }
    var profiles: [IntentProfile] { get }
    func startTimer(duration: TimeInterval)
    func addNote(text: String)
    /// Returns `false` when another profile run is still in progress.
    func runProfile(id: UUID) -> Bool
    func postAlert(title: String, message: String?, style: NotchAlert.Style)
    func open(_ module: NotchModule)
    func toggle(_ module: NotchModule)
    /// A default input device exists and the mute controller is running.
    var isMicMuteAvailable: Bool { get }
    /// Toggles the system microphone mute; returns the new muted state.
    func toggleMicMute() -> Bool
}

/// Input limits shared by the intents and the bridge (mirrors `TimerService.customMinutesRange`).
enum IntentLimits {
    static let timerMinutes = 1...180
}

/// Errors Shortcuts shows to the user.
enum IntentBridgeError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notReady
    case moduleDisabled(NotchModule)
    case invalidDuration
    case emptyText
    case emptyTitle
    case profileNotFound
    case profileBusy
    case alertsUnavailable
    case micUnavailable

    var errorDescription: String? {
        String(localized: localizedStringResource)
    }

    /// Localized from the catalog; Shortcuts resolves it in the user's language.
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "NotchHub henüz hazır değil. Birkaç saniye sonra yeniden dene."
        case .moduleDisabled(let module): "\(module.title) modülü kapalı. Ayarlar'dan açabilirsin."
        case .invalidDuration:
            "Süre \(IntentLimits.timerMinutes.lowerBound) ile \(IntentLimits.timerMinutes.upperBound) dakika arasında olmalı."
        case .emptyText: "Not metni boş olamaz."
        case .emptyTitle: "Uyarı başlığı boş olamaz."
        case .profileNotFound: "Profil bulunamadı."
        case .profileBusy: "Başka bir profil hâlâ çalışıyor."
        case .alertsUnavailable: "Çentik uyarıları kapalı ya da duraklatılmış."
        case .micUnavailable: "Susturulabilecek bir mikrofon bulunamadı."
        }
    }
}

/// Single entry point for App Intents: validates input and routes to the in-process services.
/// AppDelegate calls `configure(_:)` once the services exist; until then intents wait briefly, then fail.
@MainActor
final class IntentServicesBridge {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    static let shared = IntentServicesBridge()
    static let readinessTimeout: Duration = .seconds(3)
    static let readinessPollInterval: Duration = .milliseconds(100)

    private(set) var routes: (any IntentRouting)?
    private let sleep: Sleeper
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Shortcuts")

    init(routes: (any IntentRouting)? = nil, sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.routes = routes
        self.sleep = sleep
    }

    var isReady: Bool { routes != nil }

    func configure(_ routes: any IntentRouting) {
        self.routes = routes
    }

    // MARK: - Commands

    func startTimer(minutes: Int) async throws {
        let routes = try await readyRoutes()
        try requireEnabled(.timer, in: routes)
        guard IntentLimits.timerMinutes.contains(minutes) else { throw IntentBridgeError.invalidDuration }
        routes.startTimer(duration: TimeInterval(minutes) * Self.secondsPerMinute)
        logger.info("Shortcut started a \(minutes) min timer")
    }

    func addNote(text: String) async throws {
        let routes = try await readyRoutes()
        try requireEnabled(.notes, in: routes)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IntentBridgeError.emptyText }
        routes.addNote(text: trimmed)
        logger.info("Shortcut added a note")
    }

    func profiles() async throws -> [IntentProfile] {
        try await readyRoutes().profiles
    }

    func runProfile(id: UUID) async throws -> IntentProfile {
        let routes = try await readyRoutes()
        guard let profile = routes.profiles.first(where: { $0.id == id }) else { throw IntentBridgeError.profileNotFound }
        guard routes.runProfile(id: id) else { throw IntentBridgeError.profileBusy }
        logger.info("Shortcut started a profile run")
        return profile
    }

    func showAlert(title: String, message: String?, style: NotchAlert.Style) async throws {
        let routes = try await readyRoutes()
        guard routes.canPostAlerts else { throw IntentBridgeError.alertsUnavailable }
        guard let cleanTitle = ExternalAlertSanitizer.displayText(title, maxLength: ExternalAlertSanitizer.maxTitleLength) else {
            throw IntentBridgeError.emptyTitle
        }
        let cleanMessage = message.flatMap {
            ExternalAlertSanitizer.displayText($0, maxLength: ExternalAlertSanitizer.maxSubtitleLength)
        }
        routes.postAlert(title: cleanTitle, message: cleanMessage, style: style)
    }

    func open(_ module: NotchModule) async throws {
        let routes = try await readyRoutes()
        try requireEnabled(module, in: routes)
        routes.open(module)
    }

    func toggle(_ module: NotchModule) async throws {
        let routes = try await readyRoutes()
        try requireEnabled(module, in: routes)
        routes.toggle(module)
    }

    /// Returns `true` when the microphone is muted afterwards.
    func toggleMicMute() async throws -> Bool {
        let routes = try await readyRoutes()
        guard routes.isMicMuteAvailable else { throw IntentBridgeError.micUnavailable }
        return routes.toggleMicMute()
    }

    // MARK: - Private

    private static let secondsPerMinute: TimeInterval = 60

    /// Waits up to `readinessTimeout` for `configure(_:)` (the app may have just been launched by Shortcuts).
    private func readyRoutes() async throws -> any IntentRouting {
        if let routes { return routes }
        let attempts = Int(Self.readinessTimeout / Self.readinessPollInterval)
        for _ in 0..<attempts {
            do {
                try await sleep(Self.readinessPollInterval)
            } catch {
                break
            }
            if let routes { return routes }
        }
        logger.error("Shortcut ran before the app finished launching")
        throw IntentBridgeError.notReady
    }

    private func requireEnabled(_ module: NotchModule, in routes: any IntentRouting) throws {
        guard routes.isModuleEnabled(module) else { throw IntentBridgeError.moduleDisabled(module) }
    }
}
