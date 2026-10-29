import AppKit

/// Invisible window over the collapsed notch: catches drags from other apps (Finder drags don't reach
/// global mouse monitors reliably) and clicks, so the panel can open as a drop target.
final class DropCatcherPanel: NSPanel {
    private let catcherView = DropCatcherView()

    var onDragEnter: (() -> Void)? {
        get { catcherView.onDragEnter }
        set { catcherView.onDragEnter = newValue }
    }

    var onClick: (() -> Void)? {
        get { catcherView.onClick }
        set { catcherView.onClick = newValue }
    }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
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

private final class DropCatcherView: NSView {
    var onDragEnter: (() -> Void)?
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
