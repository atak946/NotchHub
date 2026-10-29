import AppKit
import ApplicationServices
import Observation
import OSLog

/// OS boundary for the Accessibility (AX) trust check, injectable for tests.
protocol AccessibilityTrustChecking: Sendable {
    /// `prompt == true` lets macOS show its "grant access" dialog; never pass it implicitly.
    func isTrusted(prompt: Bool) -> Bool
    @MainActor func openSystemSettings()
}

struct SystemAccessibilityTrust: AccessibilityTrustChecking {
    /// Raw value of `kAXTrustedCheckOptionPrompt`; the imported global is a mutable C var Swift 6 rejects.
    static let promptOptionKey = "AXTrustedCheckOptionPrompt"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    func isTrusted(prompt: Bool) -> Bool {
        let options = [Self.promptOptionKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func openSystemSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Shared, observable Accessibility trust state for every Insights service.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool

    @ObservationIgnored private let checker: any AccessibilityTrustChecking
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    /// Reads the current state silently; never prompts.
    init(checker: any AccessibilityTrustChecking = SystemAccessibilityTrust()) {
        self.checker = checker
        isTrusted = checker.isTrusted(prompt: false)
    }

    /// Re-reads trust without prompting. Cheap enough to call before every AX poll.
    @discardableResult
    func refresh() -> Bool {
        let trusted = checker.isTrusted(prompt: false)
        if trusted != isTrusted {
            logger.info("Accessibility trust changed: \(trusted, privacy: .public)")
            isTrusted = trusted
        }
        return trusted
    }

    /// Explicit user action: shows the system prompt and opens Privacy & Security › Accessibility.
    func requestAccess() {
        let trusted = checker.isTrusted(prompt: true)
        if !trusted {
            checker.openSystemSettings()
        }
        refresh()
    }
}
