import SwiftUI

/// Expanded panel: module tabs and clock in the row beside the notch, the active module below.
struct NotchContentView: View {
    let model: NotchViewModel

    private static let notchClearance: CGFloat = 16
    private static let headerSpacing: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.headerSpacing) {
            header
                .frame(height: model.geometry.notchSize.height)
            moduleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            ModuleTabBar(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.notchSize.width + Self.notchClearance)
            HeaderClock()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        let services = model.services
        switch model.activeModule {
        case .shelf:
            ShelfModuleView(store: services.shelf)
        case .media:
            MediaModuleView(media: services.media, audio: services.audio)
        case .timer:
            TimerModuleView(timer: services.timer)
        case .calendar:
            CalendarModuleView(calendar: services.calendar)
        case .notes:
            NotesModuleView(store: services.notes, shelf: services.shelf)
        case .status:
            StatusModuleView(services: services)
        case nil:
            Text("Ayarlar'dan bir modül etkinleştir")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ModuleTabBar: View {
    let model: NotchViewModel
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.enabledModules.enumerated()), id: \.element) { index, module in
                ModuleTab(
                    module: module,
                    isSelected: model.activeModule == module,
                    namespace: selection
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.select(module)
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

private struct ModuleTab: View {
    let module: NotchModule
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: module.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 30, height: 26)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary.opacity(0.5))
                    }
                }
                .scaleEffect(isHovered && !isSelected ? 1.06 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(module.title)
    }
}

private struct HeaderClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .foregroundStyle(.secondary)
                Text(context.date, format: .dateTime.hour().minute())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }
}
