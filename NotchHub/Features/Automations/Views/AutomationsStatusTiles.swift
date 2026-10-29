import SwiftUI

/// Both automation tiles for the Status grid (a `Group`, so each tile is its own grid cell).
struct AutomationsStatusTiles: View {
    let automations: Automations

    init(automations: Automations) {
        self.automations = automations
    }

    var body: some View {
        Group {
            FocusGuardStatusTile(service: automations.focusGuard)
            CaptureCatcherStatusTile(service: automations.captureCatcher)
        }
    }
}

/// Focus Guard state and today's distraction count. Click toggles the guard.
struct FocusGuardStatusTile: View {
    let service: FocusGuardService

    var body: some View {
        AutomationsTile(
            systemImage: "brain.head.profile",
            title: String(localized: "Odak Koruma"),
            detail: detail,
            tint: tint,
            help: service.isEnabled ? String(localized: "Odak Koruma'yı kapat") : String(localized: "Odak Koruma'yı aç")
        ) {
            service.isEnabled.toggle()
        }
    }

    private var detail: String {
        guard service.isEnabled else { return String(localized: "Kapalı") }
        let count = service.distractionsToday
        let today = count == 1
            ? String(localized: "Bugün 1 dikkat dağınıklığı")
            : String(localized: "Bugün \(count) dikkat dağınıklığı")
        return service.isGuarding ? String(localized: "Korunuyor · \(today)") : today
    }

    private var tint: Color {
        guard service.isEnabled else { return .secondary }
        if service.isGuarding { return service.distractionsToday > 0 ? .orange : .green }
        return .blue
    }
}

/// Last captured screenshot/download. Click adds it to the shelf.
struct CaptureCatcherStatusTile: View {
    let service: CaptureCatcherService

    var body: some View {
        AutomationsTile(
            systemImage: service.lastBatch?.systemImage ?? "camera.viewfinder",
            title: String(localized: "Yakalananlar"),
            detail: detail,
            tint: tint,
            help: service.canShelveLastBatch
                ? String(localized: "Rafa ekle")
                : String(localized: "Ekran görüntüleri ve indirilenler")
        ) {
            service.shelveLastBatch()
        }
        .disabled(!service.canShelveLastBatch)
    }

    private var detail: String {
        guard service.isEnabled else { return String(localized: "Kapalı") }
        guard service.isWatching else { return String(localized: "İzlenmiyor") }
        guard let batch = service.lastBatch else { return String(localized: "İzleniyor") }
        return service.canShelveLastBatch ? batch.subtitle : String(localized: "\(batch.subtitle) · Rafta")
    }

    private var tint: Color {
        guard service.isEnabled else { return .secondary }
        guard service.isWatching else { return .orange }
        return service.canShelveLastBatch ? .blue : .green
    }
}

/// Shared ~140 × 70 pt tile chrome.
struct AutomationsTile: View {
    static let size = CGSize(width: 140, height: 70)

    let systemImage: String
    let title: String
    let detail: String
    let tint: Color
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(8)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isHovered ? 0.24 : 0.14))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}
