import Foundation
import Observation

/// Pre-meeting camera check: the notch mirror plus the reminder that offers it before video meetings.
@MainActor
final class CameraMirror {
    let service: CameraMirrorService
    let reminder: CameraReminderService

    private let calendar: CalendarService
    private var isTracking = false

    init(alerts: NotchAlertCenter, calendar: CalendarService, service: CameraMirrorService = CameraMirrorService()) {
        self.calendar = calendar
        self.service = service
        reminder = CameraReminderService(
            alerts: alerts,
            events: { [calendar] in
                calendar.todayEvents + [calendar.nextEvent].compactMap { $0 }
            },
            onCheckCamera: { [service] in service.open() }
        )
    }

    func start() {
        reminder.start()
        guard !isTracking else { return }
        isTracking = true
        trackCalendar()
    }

    func stop() {
        isTracking = false
        reminder.stop()
        service.close()
    }

    private func trackCalendar() {
        withObservationTracking {
            _ = calendar.nextEvent
            _ = calendar.todayEvents
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isTracking else { return }
                self.reminder.reschedule()
                self.trackCalendar()
            }
        }
    }
}

extension CameraMirror {
    /// Production wiring: reminders follow the alert settings and the calendar module toggle.
    static func live(settings: SettingsStore, alerts: NotchAlertCenter, calendar: CalendarService) -> CameraMirror {
        let mirror = CameraMirror(alerts: alerts, calendar: calendar)
        mirror.reminder.canPost = { [weak settings] in
            guard let settings else { return false }
            return settings.alertsEnabled && !settings.isPaused && settings.isEnabled(.calendar)
        }
        return mirror
    }
}
