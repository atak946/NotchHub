import Foundation

/// One line of a note body as shown in the read-only preview.
struct NoteLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case checklist(isChecked: Bool)
    }

    /// Zero-based line number in the body; also the identity used for toggling.
    let id: Int
    let kind: Kind
    /// Line text without the checkbox marker (and without leading indentation for checklist lines).
    let text: String
}

/// Pure parsing and toggling of "[ ] " / "[x] " checklist lines.
enum NoteChecklist {
    static let uncheckedMarker = "[ ] "
    static let checkedMarker = "[x] "
    private static let checkedMarkerUpper = "[X] "
    private static let lineSeparator = "\n"

    static func parse(_ body: String) -> [NoteLine] {
        lines(of: body).enumerated().map { index, line in
            guard let marker = marker(in: line) else {
                return NoteLine(id: index, kind: .text, text: line)
            }
            let content = String(line.dropFirst(marker.indent.count + marker.prefix.count))
            return NoteLine(id: index, kind: .checklist(isChecked: marker.isChecked), text: content)
        }
    }

    /// Flips the checkbox on `lineIndex`, keeping indentation and text. Non-checklist lines are left alone.
    static func toggle(lineAt lineIndex: Int, in body: String) -> String {
        var lines = lines(of: body)
        guard lines.indices.contains(lineIndex), let marker = marker(in: lines[lineIndex]) else { return body }
        let line = lines[lineIndex]
        let content = line.dropFirst(marker.indent.count + marker.prefix.count)
        let newPrefix = marker.isChecked ? uncheckedMarker : checkedMarker
        lines[lineIndex] = marker.indent + newPrefix + content
        return lines.joined(separator: lineSeparator)
    }

    static func hasChecklist(_ body: String) -> Bool {
        lines(of: body).contains { marker(in: $0) != nil }
    }

    // MARK: - Private

    private struct Marker {
        let indent: String
        let prefix: String
        let isChecked: Bool
    }

    private static func lines(of body: String) -> [String] {
        body.components(separatedBy: lineSeparator)
    }

    private static func marker(in line: String) -> Marker? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        if rest.hasPrefix(uncheckedMarker) {
            return Marker(indent: indent, prefix: uncheckedMarker, isChecked: false)
        }
        for checked in [checkedMarker, checkedMarkerUpper] where rest.hasPrefix(checked) {
            return Marker(indent: indent, prefix: checked, isChecked: true)
        }
        return nil
    }
}
