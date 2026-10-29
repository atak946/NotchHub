import SwiftUI

/// Main calendar module for the expanded notch (~590 × 160 pt).
struct CalendarModuleView: View {
    private let calendar: CalendarService
    private let onOpenCameraMirror: (() -> Void)?

    init(calendar: CalendarService, onOpenCameraMirror: (() -> Void)? = nil) {
        self.calendar = calendar
        self.onOpenCameraMirror = onOpenCameraMirror
    }

    var body: some View {
        Group {
            switch calendar.authorization {
            case .authorized:
                TimelineView(.everyMinute) { context in
                    authorizedContent(at: context.date)
                }
            case .notDetermined, .denied:
                CalendarAccessView(calendar: calendar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func authorizedContent(at date: Date) -> some View {
        let cardEvent = calendar.nextEvent.flatMap { isToday($0, at: date) ? $0 : nil }
        return HStack(alignment: .top, spacing: CalendarMetrics.columnSpacing) {
            if let cardEvent {
                NextEventCard(
                    event: cardEvent,
                    date: date,
                    onJoin: { calendar.join(cardEvent) },
                    onOpenCalendar: { calendar.openCalendarApp() },
                    onOpenCameraMirror: onOpenCameraMirror
                )
            } else {
                DayClearCard(upcoming: calendar.nextEvent) { calendar.openCalendarApp() }
            }
            TodayEventList(calendar: calendar, excludedEventID: cardEvent?.id)
        }
        .animation(CalendarMetrics.animation, value: cardEvent?.id)
    }

    private func isToday(_ event: CalendarEvent, at date: Date) -> Bool {
        event.isInProgress(at: date) || Calendar.current.isDate(event.start, inSameDayAs: date)
    }
}

/// Shown when no more timed events remain today.
private struct DayClearCard: View {
    let upcoming: CalendarEvent?
    let onOpenCalendar: () -> Void

    var body: some View {
        Button(action: onOpenCalendar) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Gününüz boş")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                if let upcoming {
                    HStack(spacing: 4) {
                        Text("Sıradaki:")
                        Text(upcoming.start, format: .relative(presentation: .named).locale(.current))
                        Text("·")
                        Text(upcoming.title).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text("Bugün başka toplantı yok")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(CalendarMetrics.cardPadding)
            .frame(width: CalendarMetrics.cardWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: CalendarMetrics.cardCornerRadius))
        }
        .buttonStyle(CalendarPressableStyle())
        .help("Takvimi Aç")
    }
}
