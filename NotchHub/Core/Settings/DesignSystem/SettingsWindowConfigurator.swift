import AppKit
import SwiftUI

/// Gives the hosting Settings window a transparent, hidden title bar with full-size content,
/// a permanent dark appearance and the given title (shown in the Window menu and Mission Control).
struct SettingsWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        WindowObservingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowObservingView else { return }
        view.title = title
        view.apply()
    }

    private final class WindowObservingView: NSView {
        private static let autosaveName = "NotchHubSettingsWindow"
        /// Opening size: a share of the screen, clamped so it is roomy on a laptop but not huge on a desktop display.
        private static let screenShare: CGFloat = 0.72
        private static let minimumOpeningSize = CGSize(width: 980, height: 680)
        private static let maximumOpeningSize = CGSize(width: 1240, height: 860)

        var title = ""
        private weak var sizedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // Run after SwiftUI's own initial sizing pass, which would otherwise override ours.
            DispatchQueue.main.async { [weak self] in self?.sizeOnce() }
        }

        /// SwiftUI's Settings scene opens at its ideal size, which is cramped; size it once and remember user resizes.
        private func sizeOnce() {
            guard let window, sizedWindow !== window else { return }
            sizedWindow = window
            window.styleMask.insert(.resizable)
            if window.setFrameUsingName(Self.autosaveName) {
                window.setFrameAutosaveName(Self.autosaveName)
                return
            }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? Self.maximumOpeningSize
            let width = min(max(visible.width * Self.screenShare, Self.minimumOpeningSize.width), Self.maximumOpeningSize.width)
            let height = min(max(visible.height * Self.screenShare, Self.minimumOpeningSize.height), Self.maximumOpeningSize.height)
            window.setContentSize(CGSize(width: min(width, visible.width), height: min(height, visible.height)))
            window.center()
            window.setFrameAutosaveName(Self.autosaveName)
        }

        func apply() {
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(SettingsTheme.Palette.canvas)
            if window.title != title { window.title = title }
        }
    }
}
