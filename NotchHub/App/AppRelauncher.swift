import AppKit
import OSLog

/// Restarts the app. LSUIElement apps cannot be reopened by the system on demand, so a detached
/// shell waits for this process to exit and then opens a fresh instance of the bundle.
enum AppRelauncher {
    static let shellPath = "/bin/sh"
    /// The bundle path arrives as `$0`, so it is never parsed as shell syntax.
    static let script = "sleep 1; /usr/bin/open -n \"$0\""

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Relaunch")

    static func arguments(bundlePath: String) -> [String] {
        ["-c", script, bundlePath]
    }

    /// Returns `false` (and keeps running) when the helper cannot start.
    @MainActor
    @discardableResult
    static func relaunch(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: shellPath)
        process.arguments = arguments(bundlePath: bundleURL.path(percentEncoded: false))
        do {
            try process.run()
        } catch {
            logger.error("Relaunch helper failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
