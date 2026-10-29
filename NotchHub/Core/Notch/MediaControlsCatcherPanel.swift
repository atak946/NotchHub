import AppKit

/// Small invisible window exactly over the collapsed media controls. Only this rect takes clicks, so
/// the rest of the wings keep passing clicks through to the menu bar.
final class MediaControlsCatcherPanel: NSPanel {
    private let catcherView = MediaControlsCatcherView()

    var onClick: (() -> Void)? {
        get { catcherView.onClick }
        set { catcherView.onClick = newValue }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = catcherView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MediaControlsCatcherView: NSView {
    /// Fully transparent pixels can let clicks fall through; a near-invisible fill keeps them here.
    /// The black notch panel is drawn above this window, so nothing shows.
    private static let hitFill = NSColor.black.withAlphaComponent(0.01)

    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        Self.hitFill.setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
