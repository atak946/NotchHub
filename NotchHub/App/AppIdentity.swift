import Foundation

/// Identifiers derived from the bundle id, so forks and local builds never hardcode an owner prefix.
enum AppIdentity {
    static let fallbackBundleID = "dev.notchhub.NotchHub"
    static let bundleID = Bundle.main.bundleIdentifier ?? fallbackBundleID
    static let logSubsystem = bundleID
}
