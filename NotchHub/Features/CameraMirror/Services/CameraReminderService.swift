import Foundation
import Observation
import OSLog

/// Posts "Kamerayı kontrol et" a few minutes before a video meeting. The alert never starts the camera;
/// only its action button opens the mirror.
@MainActor
@Observable
final class CameraReminderService {
    static let enabledKey = "cameraMirror.reminderEnabled"
    static let leadTimeKey = "cameraMirror.reminderLeadTime"
    static let alertDuration: Duration = .seconds(30)
    /// Fired events are remembered this long past their start, then pruned.
    private static let firedRetention: TimeInterval = 24 * 60 * 60
    private static let fireSlack: TimeInterval = 0.25

    /// "Toplantı öncesi kamera hatırlatması" (default on).
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            reschedule()
        }
    }

    /// One of `CameraReminderPolicy.leadTimeOptions`.
    var leadTime: TimeInterval {
        didSet {
            defaults.set(leadTime, forKey: Self.leadTimeKey)
            reschedule()
        }
    }

    /// Set by the integrator: whether a notch alert may be posted right now.
    @ObservationIgnored var canPost: @MainActor () -> Bool = { true }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let events: @MainActor () -> [CalendarEvent]
    @ObservationIgnored private let onCheckCamera: @MainActor () -> Void
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: NotchAlertCenter.Sleeper
    @ObservationIgnored private var firedEvents: [String: Date] = [:]
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CameraMirror")

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping NotchAlertCenter.Sleeper = { try await Task.sleep(for: $0) },
        events: @escaping @MainActor () -> [CalendarEvent],
        onCheckCamera: @escaping @MainActor () -> Void
    ) {
        self.alerts = alerts
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.events = events
        self.onCheckCamera = onCheckCamera
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let storedLead = defaults.object(forKey: Self.leadTimeKey) as? Double
        leadTime = storedLead.flatMap { CameraReminderPolicy.leadTimeOptions.contains($0) ? $0 : nil }
            ?? CameraReminderPolicy.defaultLeadTime
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reschedule()
    }

    func stop() {
        isStarted = false
        fireTask?.cancel()
        fireTask = nil
    }

    /// Fires due reminders and arms a timer for the next one. Call when the calendar changes.
    func reschedule() {
        fireTask?.cancel()
        fireTask = nil
        guard isStarted, isEnabled else { return }
        let date = now()
        fireDue(at: date)
        let fired = Set(firedEvents.keys)
        guard let next = CameraReminderPolicy.nextFireDate(in: events(), at: date, leadTime: leadTime, alreadyFired: fired)
        else { return }
        let delay = next.timeIntervalSince(date) + Self.fireSlack
        let sleep = self.sleep
        fireTask = Task { [weak self] in
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reschedule()
        }
    }

    private func fireDue(at date: Date) {
        firedEvents = firedEvents.filter { date.timeIntervalSince($0.value) < Self.firedRetention }
        let due = CameraReminderPolicy.dueEvents(
            in: events(),
            at: date,
            leadTime: leadTime,
            alreadyFired: Set(firedEvents.keys)
        )
        for event in due {
            firedEvents[event.id] = event.start
            guard canPost() else { continue }
            logger.info("Camera check reminder for upcoming video meeting")
            post(for: event)
        }
    }

    private func post(for event: CalendarEvent) {
        let provider = event.meetingLink?.provider
        let onCheckCamera = self.onCheckCamera
        alerts.post(NotchAlert(
            module: .calendar,
            systemImage: "video.fill",
            title: "Toplantı yaklaşıyor",
            subtitle: [event.title, provider?.displayName].compactMap { $0 }.joined(separator: " · "),
            style: .info,
            coalescingKey: "cameraMirror.\(event.id)",
            autoDismissAfter: Self.alertDuration,
            actionTitle: "Kamerayı kontrol et",
            action: { onCheckCamera() },
            appName: "Kamera",
            timestampText: event.start.formatted(date: .omitted, time: .shortened)
        ))
    }
}
