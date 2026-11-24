import AppKit
import SwiftUI

/// Small panel that drops below the chevron. Closes on Esc or a click elsewhere.
@MainActor
final class MenuBarContainerPanel: NSPanel {
    private static let gap: CGFloat = 4
    private static let screenMargin: CGFloat = 8

    var onClose: (() -> Void)?

    private var outsideClickMonitor: Any?
    private var ignoredClickArea = CGRect.zero

    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    /// Hangs below `anchor` (the chevron), kept inside the screen that holds it.
    func show(below anchor: CGRect, on screen: NSScreen) {
        ignoredClickArea = anchor
        reposition(below: anchor, on: screen)
        makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeUnlessOnAnchor() }
        }
    }

    func reposition(below anchor: CGRect, on screen: NSScreen) {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        let bounds = screen.frame.insetBy(dx: Self.screenMargin, dy: 0)
        let x = min(max(anchor.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        setFrame(CGRect(x: x, y: anchor.minY - Self.gap - size.height, width: size.width, height: size.height), display: true)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func dismiss() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        guard isVisible else { return }
        orderOut(nil)
        onClose?()
    }

    /// A click on the chevron toggles the panel itself.
    private func closeUnlessOnAnchor() {
        guard !ignoredClickArea.contains(NSEvent.mouseLocation) else { return }
        dismiss()
    }
}
