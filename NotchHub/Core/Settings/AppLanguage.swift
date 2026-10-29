import Foundation
import Observation

/// The app's UI language. Turkish and English show their native names, untranslated,
/// so a user can always find their own language.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    /// Value written to `AppleLanguages`; `nil` means follow the system.
    var languageCode: String? {
        self == .system ? nil : rawValue
    }

    /// Maps a stored language identifier ("en", "en-GB") to a supported language; unknown codes follow the system.
    init(languageIdentifier: String) {
        let base = languageIdentifier.split(separator: "-").first.map(String.init) ?? languageIdentifier
        self = Self.allCases.first { $0.languageCode == base.lowercased() } ?? .system
    }
}

/// Reads and writes the app-domain `AppleLanguages` override. A change applies after a relaunch.
struct AppLanguageStore {
    static let defaultsKey = "AppleLanguages"

    private let defaults: UserDefaults
    /// The persistent domain `defaults` writes to; reading it directly skips the global (system) value.
    private let domainName: String

    init(defaults: UserDefaults = .standard, domainName: String = AppIdentity.bundleID) {
        self.defaults = defaults
        self.domainName = domainName
    }

    var current: AppLanguage {
        let domain = defaults.persistentDomain(forName: domainName)
        guard let codes = domain?[Self.defaultsKey] as? [String], let first = codes.first else {
            return .system
        }
        return AppLanguage(languageIdentifier: first)
    }

    func select(_ language: AppLanguage) {
        if let code = language.languageCode {
            defaults.set([code], forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}

/// Settings state for the language picker. Created once at launch, so `launchLanguage` is what is running.
@MainActor
@Observable
final class AppLanguageSettings {
    let launchLanguage: AppLanguage
    @ObservationIgnored private let store: AppLanguageStore

    var selection: AppLanguage {
        didSet { store.select(selection) }
    }

    /// The choice differs from the running language and only takes effect after a relaunch.
    var needsRelaunch: Bool {
        selection != launchLanguage
    }

    init(store: AppLanguageStore = AppLanguageStore()) {
        self.store = store
        let current = store.current
        launchLanguage = current
        selection = current
    }
}
