import AppKit

/// OS side effects used by `ExternalAlertService`, behind a protocol for tests.
@MainActor
protocol IntegrationsSystem: AnyObject {
    func symbolExists(_ name: String) -> Bool
    func open(_ url: URL)
    func revealInFinder(_ url: URL)
    func copyToPasteboard(_ text: String)
    /// Path of the bundled zsh hook, if the app ships it as a resource.
    var bundledZshHookPath: String? { get }
}

@MainActor
final class LiveIntegrationsSystem: IntegrationsSystem {
    private static let zshHookResource = "notchhub"
    private static let zshHookExtension = "zsh"

    init() {}

    func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    var bundledZshHookPath: String? {
        Bundle.main.path(forResource: Self.zshHookResource, ofType: Self.zshHookExtension)
    }
}
