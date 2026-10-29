import SwiftUI

/// Read-only rendering of a note where "[ ] " / "[x] " lines become tappable checkboxes.
struct NoteChecklistPreview: View {
    let text: String
    let onToggle: (Int) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(NoteChecklist.parse(text)) { line in
                    row(for: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func row(for line: NoteLine) -> some View {
        switch line.kind {
        case .text:
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: NoteTextEditor.fontSize))
                .textSelection(.enabled)
        case .checklist(let isChecked):
            Button {
                onToggle(line.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    Text(line.text)
                        .strikethrough(isChecked)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: NoteTextEditor.fontSize))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChecked ? .isSelected : [])
        }
    }
}
