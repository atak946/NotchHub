import Foundation
import Observation

/// Turns module events (meeting reminders, finished timers, track changes) into notch alerts.
@MainActor
final class AlertRouter {
    private static let trackChangeDuration: Duration = .seconds(3)
    private static let trackChangeKey = "media.track"

    private let settings: SettingsStore
    private let services: ModuleServices
    private let alerts: NotchAlertCenter
    private let present: (NotchModule) -> Void
    private var lastTrackID: String?

    init(
        settings: SettingsStore,
        services: ModuleServices,
        alerts: NotchAlertCenter,
        present: @escaping (NotchModule) -> Void
    ) {
        self.settings = settings
        self.services = services
        self.alerts = alerts
        self.present = present
    }

    func start() {
        services.calendar.onReminder = { [weak self] event in
            self?.postMeetingReminder(event)
        }
        services.timer.onFinish = { [weak self] in
            // The timer syncs its state right after this callback; read it on the next turn.
            Task { @MainActor in self?.postTimerFinished() }
        }
        services.externalAlerts.shouldPostAlert = { [weak self] in
            self?.canPost ?? false
        }
        services.externalAlerts.onOpenModule = { [weak self] target in
            guard let module = NotchModule(rawValue: target.rawValue) else { return }
            self?.present(module)
        }
        lastTrackID = services.media.nowPlaying?.trackID
        trackNowPlaying()
    }

    private var canPost: Bool {
        settings.alertsEnabled && !settings.isPaused
    }

    // MARK: - Calendar

    private func postMeetingReminder(_ event: CalendarEvent) {
        guard canPost, settings.isEnabled(.calendar) else { return }
        let calendar = services.calendar
        let link = event.meetingLink
        let timeText = RelativeTimeFormatter.text(for: event, at: Date())

        let app = link?.provider.alertApp
        alerts.post(NotchAlert(
            module: .calendar,
            systemImage: "calendar",
            title: event.title,
            subtitle: [timeText.capitalizedFirstLetter, link?.provider.displayName]
                .compactMap { $0 }
                .joined(separator: " · "),
            style: .reminder,
            coalescingKey: "calendar.\(event.id)",
            autoDismissAfter: nil,
            actionTitle: link == nil ? "Aç" : "Katıl",
            action: { [weak self] in
                if link == nil {
                    self?.present(.calendar)
                } else {
                    calendar.join(event)
                }
            },
            appBundleID: app?.bundleID,
            appName: app?.name,
            timestampText: event.start.formatted(date: .omitted, time: .shortened)
        ))
    }

    // MARK: - Timer

    private func postTimerFinished() {
        guard canPost, settings.isEnabled(.timer) else { return }
        let timer = services.timer

        switch timer.state {
        case .running(let phase):
            alerts.post(NotchAlert(
                module: .timer,
                systemImage: phase.systemImage,
                title: "\(phase.title) başladı",
                subtitle: "Önceki aşama bitti",
                style: .success,
                coalescingKey: "timer"
            ))
        case .finished(let phase):
            let next = timer.isPomodoro ? timer.upcomingPhase : nil
            alerts.post(NotchAlert(
                module: .timer,
                systemImage: phase.systemImage,
                title: timer.isPomodoro ? "\(phase.title) bitti" : "Süre doldu",
                subtitle: next.map { "Sıradaki: \($0.title)" },
                style: .success,
                coalescingKey: "timer",
                autoDismissAfter: nil,
                actionTitle: next == nil ? "Tamam" : "\(next?.title ?? "") başlat",
                action: {
                    if next != nil {
                        timer.startNextPhase()
                    } else {
                        timer.cancel()
                    }
                }
            ))
        case .idle, .paused:
            break
        }
    }

    // MARK: - Media

    private func trackNowPlaying() {
        withObservationTracking {
            _ = services.media.nowPlaying?.trackID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleTrackChange()
                self?.trackNowPlaying()
            }
        }
    }

    private func handleTrackChange() {
        guard let nowPlaying = services.media.nowPlaying else {
            lastTrackID = nil
            return
        }
        let trackID = nowPlaying.trackID
        guard trackID != lastTrackID else { return }
        let isFirstTrack = lastTrackID == nil
        lastTrackID = trackID

        guard !isFirstTrack, nowPlaying.isPlaying, canPost,
              settings.showTrackChangeAlerts, settings.isEnabled(.media)
        else { return }

        alerts.post(NotchAlert(
            module: .media,
            systemImage: "music.note",
            title: nowPlaying.title,
            subtitle: nowPlaying.artist,
            style: .info,
            coalescingKey: Self.trackChangeKey,
            autoDismissAfter: Self.trackChangeDuration
        ))
    }
}

private extension MeetingProvider {
    /// Native app whose icon leads the reminder; browser-only providers fall back to the calendar symbol.
    var alertApp: (bundleID: String, name: String)? {
        switch self {
        case .zoom: ("us.zoom.xos", "Zoom")
        case .teams: ("com.microsoft.teams2", "Microsoft Teams")
        case .webex: ("Cisco-Systems.Spark", "Webex")
        case .meet, .other: nil
        }
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
