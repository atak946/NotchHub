import SwiftUI

/// Left column: the next (or in-progress) meeting with a big Join button.
struct NextEventCard: View {
    let event: CalendarEvent
    let date: Date
    let onJoin: () -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(event.calendarColor.color)
                .frame(width: CalendarMetrics.colorBarWidth)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RelativeTimePill(event: event, date: date)
                    Spacer(minLength: 0)
                    openCalendarButton
                }
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                detailLine
                Spacer(minLength: 0)
                joinRow
            }
        }
        .padding(CalendarMetrics.cardPadding)
        .frame(width: CalendarMetrics.cardWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: CalendarMetrics.cardCornerRadius))
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            Text((event.start..<event.end).formatted(.interval.hour().minute()))
                .monospacedDigit()
            if let location = event.location, event.meetingLink == nil || !location.contains("://") {
                Text("·")
                Text(location)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var joinRow: some View {
        if let link = event.meetingLink {
            Button(action: onJoin) {
                CalendarProminentButtonLabel(
                    title: "\(link.provider.displayName) Toplantısına Katıl",
                    systemImage: link.provider.systemImage,
                    tint: link.provider.tint.color
                )
            }
            .buttonStyle(CalendarPressableStyle())
            .help("\(link.provider.displayName) toplantısını aç")
        } else {
            Label(event.account.displayTitle, systemImage: event.account.kind.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var openCalendarButton: some View {
        Button(action: onOpenCalendar) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(CalendarPressableStyle())
        .help("Takvimi Aç")
    }
}

private struct RelativeTimePill: View {
    let event: CalendarEvent
    let date: Date

    var body: some View {
        Text(RelativeTimeFormatter.text(for: event, at: date))
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .contentTransition(.numericText())
    }

    private var tint: Color {
        if event.isInProgress(at: date) { return .green }
        if event.start.timeIntervalSince(date) <= CalendarMetrics.soonThreshold { return .orange }
        return .secondary
    }
}
