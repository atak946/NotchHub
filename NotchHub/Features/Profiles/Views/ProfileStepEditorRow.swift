import SwiftUI

/// One step in the editor: type icon, value field (text / folder picker / timeout), reorder and delete controls.
struct ProfileStepEditorRow: View {
    @Binding var step: ProfileStep
    let issue: ProfileStepIssue?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: step.action.kind.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(step.action.kind.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Toggle("Hata olsa da devam et", isOn: $step.continueOnFailure)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                controls
            }
            valueEditor
            if let issue {
                Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .help("Yukarı taşı")
            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .help("Aşağı taşı")
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .help("Adımı kaldır")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var valueEditor: some View {
        switch step.action {
        case let .openApp(bundleID):
            TextField("Bundle ID", text: textBinding(bundleID) { .openApp(bundleID: $0) }, prompt: Text("com.devolutions.remotedesktopmanager"))
                .labelsHidden()
        case let .openURL(url):
            TextField("URL", text: textBinding(url) { .openURL($0) }, prompt: Text("https://… or rdm://…"))
                .labelsHidden()
        case let .waitForVPN(timeout):
            Stepper(value: timeoutBinding(timeout), in: ProfileStepValidator.vpnTimeoutRange, step: 15) {
                Text("Zaman aşımı \(timeout) sn").monospacedDigit()
            }
        case .openInVSCode, .dockerComposeUp, .dockerComposeStop, .openTerminal:
            folderEditor(path: step.action.folderPath ?? "")
        }
    }

    private func folderEditor(path: String) -> some View {
        HStack {
            TextField("Klasör", text: Binding(
                get: { path },
                set: { step.action = step.action.withFolderPath($0) }
            ), prompt: Text("/Users/…/Workspace/Client"))
            .labelsHidden()
            Button("Seç…") {
                if let picked = ProfilesFolderPicker.pick(startingAt: path.isEmpty ? ProfilesStore.defaultWorkspaceRoot : path) {
                    step.action = step.action.withFolderPath(picked)
                }
            }
        }
    }

    private func textBinding(_ value: String, make: @escaping (String) -> ProfileAction) -> Binding<String> {
        Binding(get: { value }, set: { step.action = make($0) })
    }

    private func timeoutBinding(_ value: Int) -> Binding<Int> {
        Binding(get: { value }, set: { step.action = .waitForVPN(timeoutSeconds: $0) })
    }
}
