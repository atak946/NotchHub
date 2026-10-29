import SwiftUI

/// Sheet editing a draft copy of a profile; the original is only replaced on Save.
struct ProfileEditorView: View {
    static let minWidth: CGFloat = 560
    static let minHeight: CGFloat = 520

    @State private var draft: ClientProfile
    let validator: ProfileStepValidator
    let onSave: (ClientProfile) -> Void
    let onCancel: () -> Void

    init(
        profile: ClientProfile,
        validator: ProfileStepValidator,
        onSave: @escaping (ClientProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: profile)
        self.validator = validator
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Profil") {
                    TextField("Ad", text: $draft.name, prompt: Text("Müşteri adı"))
                    colorPicker
                }
                ProfileStepListSection(title: "Etkinleştirme adımları", steps: $draft.steps, validator: validator)
                ProfileStepListSection(title: "Devre dışı bırakma adımları (isteğe bağlı)", steps: $draft.deactivateSteps, validator: validator)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text(issueSummary)
                    .font(.caption)
                    .foregroundStyle(issueCount == 0 ? Color.secondary : Color.orange)
                Spacer()
                Button("İptal", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
    }

    private var colorPicker: some View {
        LabeledContent("Renk") {
            HStack(spacing: 6) {
                ForEach(ProfileColor.allCases) { color in
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: draft.color == color ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel(color.title)
                }
            }
        }
    }

    private var issueCount: Int {
        (draft.steps + draft.deactivateSteps).count { validator.validate($0.action) != nil }
    }

    private var issueSummary: String {
        issueCount == 0 ? "Tüm adımlar geçerli" : "\(issueCount) adım dikkat gerektiriyor (kaydetmeye yine de izin var)"
    }
}

/// Editable, reorderable list of steps.
private struct ProfileStepListSection: View {
    let title: String
    @Binding var steps: [ProfileStep]
    let validator: ProfileStepValidator

    var body: some View {
        Section(title) {
            ForEach($steps) { $step in
                let index = steps.firstIndex { $0.id == step.id } ?? 0
                ProfileStepEditorRow(
                    step: $step,
                    issue: validator.validate(step.action),
                    canMoveUp: index > 0,
                    canMoveDown: index < steps.count - 1,
                    onMoveUp: { move(step.id, by: -1) },
                    onMoveDown: { move(step.id, by: 1) },
                    onDelete: { remove(step.id) }
                )
            }
            Menu("Adım Ekle", systemImage: "plus") {
                ForEach(ProfileActionKind.allCases) { kind in
                    Button(kind.title, systemImage: kind.systemImage) {
                        steps = steps + [ProfileStep(action: kind.template)]
                    }
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        steps = steps.filter { $0.id != id }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        var reordered = steps
        reordered.swapAt(index, target)
        steps = reordered
    }
}
