import AppKit
import ApplicationServices
import CoreGraphics

/// Focused window details read through Accessibility.
struct FocusedWindowInfo: Equatable, Sendable {
    let title: String?
    let documentPath: String?
}

/// OS boundary for activity sampling.
protocol ActivityProbing: Sendable {
    @MainActor func frontmostBundleID() -> String?
    /// Seconds since the last keyboard/mouse input in this login session.
    func idleSeconds() -> TimeInterval
    /// Requires Accessibility trust; returns `nil` without it.
    func focusedWindow() -> FocusedWindowInfo?
}

struct SystemActivityProbe: ActivityProbing {
    static let messagingTimeout: Float = 0.25
    /// `kCGAnyInputEventType` (~0). Measured on macOS 26: `.null` returns time since login-ish values
    /// (days), so it must not be used; `.mouseMoved` is only a last-resort fallback.
    static let anyInputEventType = CGEventType(rawValue: ~0) ?? .mouseMoved

    @MainActor
    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEventType)
    }

    func focusedWindow() -> FocusedWindowInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        guard let app = AXAttributes.element(of: systemWide, kAXFocusedApplicationAttribute),
              let window = AXAttributes.element(of: app, kAXFocusedWindowAttribute)
        else { return nil }
        let title = AXAttributes.string(of: window, kAXTitleAttribute)
        let document = AXAttributes.string(of: window, kAXDocumentAttribute)
        return FocusedWindowInfo(title: title, documentPath: document.map(Self.path(fromDocument:)))
    }

    /// `AXDocument` is usually a file URL string; plain paths are passed through.
    static func path(fromDocument document: String) -> String {
        guard let url = URL(string: document), url.isFileURL else { return document }
        return url.path
    }
}
