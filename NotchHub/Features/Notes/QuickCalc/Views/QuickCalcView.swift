import SwiftUI

/// "Hesap" face of the Notes module: input and live result on the left, the last five copies on the right.
struct QuickCalcView: View {
    private static let feedbackDuration: Duration = .seconds(1.2)
    private static let historyWidth: CGFloat = 220
    private static let resultFontSize: CGFloat = 22

    let service: QuickCalcService
    /// Feeds the panel's keyboard-focus hold (shared with the note editor).
    let onFocusChange: @MainActor (Bool) -> Void

    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: NotesStyle.columnSpacing) {
            calculator
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
                .opacity(0.4)
            QuickCalcHistoryList(service: service)
                .frame(width: Self.historyWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
        .task(id: service.input) { await service.refreshRatesIfNeeded() }
        .onDisappear { feedbackTask?.cancel() }
    }

    private var calculator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                NotesModePicker(selection: service.modeBinding)
                Spacer(minLength: 4)
                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.system(size: NotesStyle.captionFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            inputBox
            result
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.15), value: feedback)
    }

    private var inputBox: some View {
        QuickCalcTextField(
            text: Binding(get: { service.input }, set: { service.input = $0 }),
            placeholder: String(localized: "12,5*3 · 5 km mil · 100 usd tl"),
            focusOnAppear: service.wantsFocus,
            onFocusChange: onFocusChange,
            onFocusTaken: { service.wantsFocus = false },
            onSubmit: submit
        )
        .frame(height: 24)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: NotesStyle.cornerRadius))
    }

    @ViewBuilder
    private var result: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch service.outcome {
            case .empty:
                caption("Yazdıkça sonuç burada görünür. Enter sonucu kopyalar.")
            case .value(let value):
                Text(service.formatter.display(value))
                    .font(.system(size: Self.resultFontSize, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .contentTransition(.numericText())
                if case .currency(_, _, let rateDate) = value {
                    caption("Kur tarihi: \(rateDate.formatted(date: .abbreviated, time: .shortened))")
                }
            case .needsRates:
                caption(service.rateStore.status == .failed ? "Kurlar alınamadı" : "Kurlar yükleniyor…")
            case .failure(let error):
                Text(error.message)
                    .font(.system(size: NotesStyle.captionFontSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .animation(.snappy(duration: 0.15), value: service.outcome)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: NotesStyle.captionFontSize))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private func submit() {
        guard service.commit() else { return }
        feedbackTask?.cancel()
        feedback = String(localized: "Kopyalandı")
        feedbackTask = Task {
            try? await Task.sleep(for: Self.feedbackDuration)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }
}

/// Last five copied calculations; a click puts the expression back into the field.
private struct QuickCalcHistoryList: View {
    let service: QuickCalcService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Geçmiş", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: NotesStyle.headerFontSize, weight: .semibold))
                Spacer(minLength: 0)
                if !service.history.isEmpty {
                    NotesCapsuleButton(title: "Geçmişi temizle", systemImage: "trash", showsTitle: false) {
                        service.clearHistory()
                    }
                }
            }
            if service.history.isEmpty {
                Text("Enter ile kopyaladığın son 5 hesap burada durur.")
                    .font(.system(size: NotesStyle.captionFontSize))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.history) { entry in
                    QuickCalcHistoryRow(entry: entry) { service.reuse(entry) }
                }
            }
        }
    }
}

private struct QuickCalcHistoryRow: View {
    let entry: QuickCalcHistoryEntry
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(entry.expression)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(entry.result)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .font(.system(size: NotesStyle.rowTitleFontSize).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(isHovered ? 0.6 : 0), in: .rect(cornerRadius: NotesStyle.rowCornerRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(NotesStyle.hoverAnimation, value: isHovered)
        .help("Hesabı yeniden kullan")
    }
}
