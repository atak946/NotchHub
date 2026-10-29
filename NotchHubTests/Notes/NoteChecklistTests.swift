import Testing
@testable import NotchHub

struct NoteChecklistTests {
    @Test func parseRecognisesCheckedAndUncheckedLines() {
        let lines = NoteChecklist.parse("Title\n[ ] open\n[x] done\n  [X] indented\n[] not an item\n[ ]no space")

        #expect(lines.map(\.kind) == [
            .text,
            .checklist(isChecked: false),
            .checklist(isChecked: true),
            .checklist(isChecked: true),
            .text,
            .text,
        ])
        #expect(lines.map(\.text) == ["Title", "open", "done", "indented", "[] not an item", "[ ]no space"])
        #expect(lines.map(\.id) == Array(0..<6))
    }

    @Test func toggleFlipsOnlyTheTargetLine() {
        let body = "[ ] a\n[x] b"
        #expect(NoteChecklist.toggle(lineAt: 0, in: body) == "[x] a\n[x] b")
        #expect(NoteChecklist.toggle(lineAt: 1, in: body) == "[ ] a\n[ ] b")
    }

    @Test func togglePreservesIndentationAndNormalisesUppercase() {
        #expect(NoteChecklist.toggle(lineAt: 0, in: "\t[X] item") == "\t[ ] item")
        #expect(NoteChecklist.toggle(lineAt: 0, in: "  [ ] item") == "  [x] item")
    }

    @Test func toggleIgnoresTextLinesAndOutOfRange() {
        let body = "plain\n[ ] a\n"
        #expect(NoteChecklist.toggle(lineAt: 0, in: body) == body)
        #expect(NoteChecklist.toggle(lineAt: 9, in: body) == body)
        #expect(NoteChecklist.toggle(lineAt: -1, in: body) == body)
    }

    @Test func toggleTwiceRestoresBody() {
        let body = "x\n[ ] task\ny"
        #expect(NoteChecklist.toggle(lineAt: 1, in: NoteChecklist.toggle(lineAt: 1, in: body)) == body)
    }

    @Test func hasChecklistDetectsItems() {
        #expect(NoteChecklist.hasChecklist("a\n[ ] b"))
        #expect(!NoteChecklist.hasChecklist("a\nb"))
    }
}
