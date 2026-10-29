import Foundation

/// Decides whether the first-run wizard should appear on launch.
enum OnboardingPolicy {
    /// Bump when the wizard gains content every existing user should see once.
    static let currentVersion = 1

    /// `nil` means the wizard was never completed (first launch or a pre-1.4 install).
    static func shouldShow(storedVersion: Int?, currentVersion: Int = currentVersion) -> Bool {
        guard let storedVersion else { return true }
        return storedVersion < currentVersion
    }
}

/// Persists the last wizard version the user finished or dismissed.
@MainActor
final class OnboardingStateStore {
    static let completedVersionKey = "onboarding.completedVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedVersion: Int? {
        defaults.object(forKey: Self.completedVersionKey) as? Int
    }

    var shouldShowOnLaunch: Bool {
        OnboardingPolicy.shouldShow(storedVersion: completedVersion)
    }

    func markCompleted(version: Int = OnboardingPolicy.currentVersion) {
        let stored = completedVersion ?? 0
        defaults.set(max(stored, version), forKey: Self.completedVersionKey)
    }
}
