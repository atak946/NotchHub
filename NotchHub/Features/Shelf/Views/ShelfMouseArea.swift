import AppKit
import SwiftUI

enum ShelfKeyCommand: Sendable {
    case quickLook
    case delete
}

/// Callbacks the AppKit mouse area reports to the SwiftUI tile.
struct ShelfMouseHandlers {
    var onPress: @MainActor (_ toggling: Bool) -> Void
    var onRelease: @MainActor (_ toggling: Bool, _ didDrag: Bool) -> Void
    var onDoubleClick: @MainActor () -> Void
    var dragItems: @MainActor () -> [ShelfItem]
    var onDragActive: @MainActor (Bool) -> Void
    var onHover: @MainActor (Bool) -> Void
    var onKey: @MainActor (ShelfKeyCommand) -> Void
    var menu: @MainActor () -> NSMenu?
}

/// AppKit-backed hit area: Finder-style selection, multi-item drag out, keys and context menu.
struct ShelfMouseArea: NSViewRepresentable {
    let handlers: ShelfMouseHandlers

    func makeNSView(context: Context) -> ShelfMouseAreaView {
        let view = ShelfMouseAreaView()
        view.handlers = handlers
        return view
    }

    func updateNSView(_ nsView: ShelfMouseAreaView, context: Context) {
        nsView.handlers = handlers
    }
}

final class ShelfMouseAreaView: NSView, NSDraggingSource {
    private static let dragThreshold: CGFloat = 4
    private static let dragImageSide: CGFloat = 48
    private static let dragStackOffset: CGFloat = 6
    private static let spaceKeyCode: UInt16 = 49
    private static let deleteKeyCodes: Set<UInt16> = [51, 117]

    var handlers: ShelfMouseHandlers?
    private var mouseDownEvent: NSEvent?
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        handlers?.onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        handlers?.onHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didDrag = false
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            handlers?.onDoubleClick()
            return
        }
        handlers?.onPress(Self.isToggling(event))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard event.clickCount < 2 else { return }
        handlers?.onRelease(Self.isToggling(event), didDrag)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, !didDrag else { return }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) >= Self.dragThreshold else { return }
        guard let items = handlers?.dragItems(), !items.isEmpty else { return }
        didDrag = true
        handlers?.onDragActive(true)
        beginDraggingSession(with: draggingItems(for: items), event: mouseDownEvent, source: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let menu = handlers?.menu() else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.spaceKeyCode {
            handlers?.onKey(.quickLook)
        } else if Self.deleteKeyCodes.contains(event.keyCode) {
            handlers?.onKey(.delete)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        handlers?.onDragActive(false)
    }

    // MARK: - Private

    private static func isToggling(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
    }

    private func draggingItems(for items: [ShelfItem]) -> [NSDraggingItem] {
        let side = Self.dragImageSide
        let origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        return items.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: ShelfStore.pasteboardWriter(for: item))
            let offset = CGFloat(index) * Self.dragStackOffset
            let frame = CGRect(x: origin.x + offset, y: origin.y - offset, width: side, height: side)
            draggingItem.setDraggingFrame(frame, contents: Self.dragImage(for: item))
            return draggingItem
        }
    }

    private static func dragImage(for item: ShelfItem) -> NSImage? {
        switch item.kind {
        case .file(let url):
            NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        case .image(let data):
            NSImage(data: data)
        case .text:
            NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Metin")
        }
    }
}

/// `NSMenuItem` that runs a closure.
@MainActor
final class ShelfMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, systemImage: String, isEnabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
