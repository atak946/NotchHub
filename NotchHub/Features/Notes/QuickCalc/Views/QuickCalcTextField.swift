import AppKit
import SwiftUI

/// Single-line `NSTextField` for the calculator. Like `NoteTextEditor`, a click makes the non-activating
/// panel key and focus changes are reported so the panel's keyboard-focus hold applies; Enter submits.
struct QuickCalcTextField: NSViewRepresentable {
    static let fontSize: CGFloat = 16

    @Binding var text: String
    let placeholder: String
    /// Take focus once when the field appears (the user just picked the segment or a history entry).
    let focusOnAppear: Bool
    let onFocusChange: @MainActor (Bool) -> Void
    let onFocusTaken: @MainActor () -> Void
    let onSubmit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> QuickCalcNSTextField {
        let field = QuickCalcNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.font = .monospacedDigitSystemFont(ofSize: Self.fontSize, weight: .medium)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        apply(to: field)
        return field
    }

    func updateNSView(_ field: QuickCalcNSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        apply(to: field)
        if field.stringValue != text {
            field.stringValue = text
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        if focusOnAppear, field.window != nil {
            Task { @MainActor in field.takeFocus() }
        }
    }

    static func dismantleNSView(_ field: QuickCalcNSTextField, coordinator: Coordinator) {
        field.reportFocus(false)
    }

    private func apply(to field: QuickCalcNSTextField) {
        field.onFocusChange = onFocusChange
        field.onFocusTaken = onFocusTaken
        field.wantsFocusOnAttach = focusOnAppear
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: @MainActor () -> Void

        init(text: Binding<String>, onSubmit: @escaping @MainActor () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            onSubmit()
            return true
        }
    }
}

/// Text field that takes the first click, makes its window key and reports editing focus.
final class QuickCalcNSTextField: NSTextField {
    var onFocusChange: (@MainActor (Bool) -> Void)?
    var onFocusTaken: (@MainActor () -> Void)?
    var wantsFocusOnAttach = false
    private var isReportedFocused = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { reportFocus(true) }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        reportFocus(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            reportFocus(false)
        } else if wantsFocusOnAttach {
            // Deferred: focusing inside the view-update pass would mutate observed state mid-update.
            Task { @MainActor [weak self] in self?.takeFocus() }
        }
    }

    /// Makes the panel key and puts the caret at the end of the text.
    func takeFocus() {
        guard let window else { return }
        wantsFocusOnAttach = false
        window.makeKey()
        if currentEditor() == nil {
            window.makeFirstResponder(self)
        }
        currentEditor()?.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
        let handler = onFocusTaken
        Task { @MainActor in handler?() }
    }

    func reportFocus(_ isFocused: Bool) {
        guard isFocused != isReportedFocused else { return }
        isReportedFocused = isFocused
        onFocusChange?(isFocused)
    }
}
