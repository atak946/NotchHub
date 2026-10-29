import AppKit
import SwiftUI

/// Plain-text `NSTextView` wrapper. Clicking it makes the (non-activating) notch panel key so typing works,
/// and focus changes are reported so the panel can stay open while the user types.
struct NoteTextEditor: NSViewRepresentable {
    static let fontSize: CGFloat = 12
    private static let inset = CGSize(width: 4, height: 6)

    @Binding var text: String
    let onFocusChange: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NoteNSTextView()
        textView.configure(fontSize: Self.fontSize, inset: Self.inset)
        textView.string = text
        textView.delegate = context.coordinator
        textView.onFocusChange = onFocusChange
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NoteNSTextView else { return }
        textView.onFocusChange = onFocusChange
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = Self.clamped(selection, to: (text as NSString).length)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? NoteNSTextView)?.reportFocus(false)
    }

    private static func clamped(_ ranges: [NSValue], to length: Int) -> [NSValue] {
        let clamped = ranges.map { value -> NSValue in
            let range = value.rangeValue
            let location = min(range.location, length)
            return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
        }
        return clamped.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : clamped
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Text view that takes the first click, makes its window key and reports first-responder changes.
final class NoteNSTextView: NSTextView {
    var onFocusChange: (@MainActor (Bool) -> Void)?
    private var isReportedFocused = false

    func configure(fontSize: CGFloat, inset: CGSize) {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = .systemFont(ofSize: fontSize)
        textColor = .labelColor
        insertionPointColor = .labelColor
        textContainerInset = inset
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { reportFocus(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { reportFocus(false) }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reportFocus(false) }
    }

    func reportFocus(_ isFocused: Bool) {
        guard isFocused != isReportedFocused else { return }
        isReportedFocused = isFocused
        onFocusChange?(isFocused)
    }
}
