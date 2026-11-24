import AppKit
import SwiftUI

/// Transparent overlay that only takes right clicks and ⌃-clicks; everything else reaches the view below.
struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView(action: action)
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isSecondary(event) else { return nil }
            return super.hitTest(point)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Opens on release, like the click it stands for.
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) { action() }

        private static func isSecondary(_ event: NSEvent) -> Bool {
            switch event.type {
            case .rightMouseDown, .rightMouseUp: true
            case .leftMouseDown, .leftMouseUp: event.modifierFlags.contains(.control)
            default: false
            }
        }
    }
}
