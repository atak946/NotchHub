import Foundation
import Observation
import OSLog

/// Runs client profiles one at a time and reports progress through the notch alert queue.
@MainActor
@Observable
final class ProfilesService {
    enum RunKind: Equatable, Sendable {
        case activate
        case deactivate
    }

    struct RunState: Equatable, Sendable {
        let profileID: UUID
        let kind: RunKind
        var stepIndex: Int
        var stepCount: Int
        var stepSummary: String

        var progressText: String { "\(min(stepIndex + 1, stepCount))/\(stepCount)" }
    }

    static let successAlertDuration: Duration = .seconds(5)
    static let progressAlertDuration: Duration = .seconds(4)

    let store: ProfilesStore
    private(set) var runState: RunState?
    private(set) var lastReports: [UUID: ProfileRunReport] = [:]
    private(set) var suggestions: [ProfilesWorkspaceSuggestion] = []
    private(set) var isScanning = false

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let runner: ProfileRunner
    @ObservationIgnored private let scanner: ProfilesWorkspaceScanner
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Profiles")

    init(
        store: ProfilesStore,
        alerts: NotchAlertCenter,
        executor: (any ProfileStepExecuting)? = nil,
        validator: ProfileStepValidator = ProfileStepValidator(),
        scanner: ProfilesWorkspaceScanner = ProfilesWorkspaceScanner()
    ) {
        self.store = store
        self.alerts = alerts
        self.scanner = scanner
        let resolvedExecutor = executor ?? LiveProfileStepExecutor(configuration: { [store] in store.executorConfiguration })
        runner = ProfileRunner(executor: resolvedExecutor, validator: validator)
    }

    var isRunning: Bool { runState != nil }

    func isRunning(_ profileID: UUID) -> Bool {
        runState?.profileID == profileID
    }

    // MARK: - Running

    /// Starts a profile. Ignored while another run is in progress (cancel it first).
    @discardableResult
    func activate(_ profileID: UUID) -> Task<Void, Never>? {
        start(profileID, kind: .activate)
    }

    @discardableResult
    func deactivate(_ profileID: UUID) -> Task<Void, Never>? {
        start(profileID, kind: .deactivate)
    }

    func cancel() {
        runTask?.cancel()
    }

    func stop() {
        cancel()
    }

    private func start(_ profileID: UUID, kind: RunKind) -> Task<Void, Never>? {
        guard runTask == nil, let profile = store.profile(id: profileID) else { return nil }
        let steps = kind == .activate ? profile.steps : profile.deactivateSteps
        guard !steps.isEmpty else {
            finishWithoutSteps(profile, kind: kind)
            return nil
        }
        runState = RunState(profileID: profileID, kind: kind, stepIndex: 0, stepCount: steps.count, stepSummary: steps[0].action.summary)
        postProgress(profile, kind: kind, stepCount: steps.count)

        let task = Task { [weak self] in
            guard let self else { return }
            let report = await runner.run(
                steps,
                prompt: { [weak self] prompt in self?.postPrompt(prompt, profile: profile) },
                onEvent: { [weak self] event in self?.handle(event) }
            )
            finish(profile, kind: kind, report: report)
        }
        runTask = task
        return task
    }

    private func handle(_ event: ProfileRunEvent) {
        guard case let .stepStarted(index, total, summary) = event, var state = runState else { return }
        state.stepIndex = index
        state.stepCount = total
        state.stepSummary = summary
        runState = state
    }

    private func finish(_ profile: ClientProfile, kind: RunKind, report: ProfileRunReport) {
        runTask = nil
        runState = nil
        lastReports = lastReports.merging([profile.id: report]) { _, new in new }
        switch (kind, report.outcome) {
        case (.activate, .succeeded), (.activate, .succeededWithWarnings):
            store.activeProfileID = profile.id
        case (.deactivate, .succeeded), (.deactivate, .succeededWithWarnings):
            if store.activeProfileID == profile.id { store.activeProfileID = nil }
        case (_, .failed), (_, .cancelled):
            break
        }
        logger.info("Profile run finished: \(String(describing: report.outcome), privacy: .public)")
        postResult(profile, kind: kind, report: report)
    }

    private func finishWithoutSteps(_ profile: ClientProfile, kind: RunKind) {
        let report = ProfileRunReport(results: [], outcome: .succeeded)
        finish(profile, kind: kind, report: report)
    }

    // MARK: - Suggestions

    /// Scans the workspace root off the main actor; hides folders already used by a profile.
    func scanWorkspace() async {
        guard !isScanning else { return }
        isScanning = true
        let root = store.workspaceRoot
        let scanner = self.scanner
        let found = await Task.detached(priority: .utility) { scanner.scan(root: root) }.value
        let used = store.usedFolderPaths
        suggestions = found.filter { !used.contains($0.path) }
        isScanning = false
    }

    @discardableResult
    func createProfile(from suggestion: ProfilesWorkspaceSuggestion) -> ClientProfile {
        let colors = ProfileColor.allCases
        let color = colors[store.profiles.count % colors.count]
        let profile = suggestion.makeProfile(color: color)
        store.save(profile)
        suggestions = suggestions.filter { $0.id != suggestion.id }
        return profile
    }

    // MARK: - Alerts

    static func alertKey(for profileID: UUID) -> String {
        "profiles.run.\(profileID.uuidString)"
    }

    private func postProgress(_ profile: ClientProfile, kind: RunKind, stepCount: Int) {
        let verb = kind == .activate ? "başlatılıyor" : "devre dışı bırakılıyor"
        post(NotchAlert(
            module: .status,
            systemImage: "briefcase",
            title: "\(profile.displayName) \(verb)",
            subtitle: "\(stepCount) adım",
            style: .info,
            coalescingKey: Self.alertKey(for: profile.id),
            autoDismissAfter: Self.progressAlertDuration
        ))
    }

    private func postPrompt(_ prompt: ProfilePrompt, profile: ClientProfile) {
        post(NotchAlert(
            module: .status,
            systemImage: prompt.systemImage,
            title: prompt.title,
            subtitle: "\(profile.displayName) · \(prompt.subtitle)",
            style: .reminder,
            coalescingKey: Self.alertKey(for: profile.id),
            autoDismissAfter: nil,
            actionTitle: "Çalışmayı iptal et",
            action: { [weak self] in self?.cancel() }
        ))
    }

    private func postResult(_ profile: ClientProfile, kind: RunKind, report: ProfileRunReport) {
        let name = profile.displayName
        let alert: NotchAlert
        switch report.outcome {
        case .succeeded, .succeededWithWarnings:
            let warning = report.outcome == .succeededWithWarnings ? " (uyarılarla)" : ""
            alert = NotchAlert(
                module: .status,
                systemImage: "checkmark.circle",
                title: kind == .activate ? "\(name) hazır\(warning)" : "\(name) devre dışı\(warning)",
                subtitle: report.firstFailure.map { "\($0.summary): \(Self.message(of: $0.status))" },
                style: .success,
                coalescingKey: Self.alertKey(for: profile.id),
                autoDismissAfter: Self.successAlertDuration
            )
        case .failed:
            let failure = report.firstFailure
            alert = NotchAlert(
                module: .status,
                systemImage: "exclamationmark.triangle",
                title: "\(name) başarısız",
                subtitle: failure.map { "\($0.summary): \(Self.message(of: $0.status))" },
                style: .urgent,
                coalescingKey: Self.alertKey(for: profile.id),
                autoDismissAfter: nil,
                actionTitle: "Yeniden dene",
                action: { [weak self] in
                    _ = kind == .activate ? self?.activate(profile.id) : self?.deactivate(profile.id)
                }
            )
        case .cancelled:
            alert = NotchAlert(
                module: .status,
                systemImage: "xmark.circle",
                title: "\(name) iptal edildi",
                style: .info,
                coalescingKey: Self.alertKey(for: profile.id)
            )
        }
        post(alert)
    }

    private func post(_ alert: NotchAlert) {
        guard store.alertsEnabled else { return }
        alerts.post(alert)
    }

    static func message(of status: ProfileStepStatus) -> String {
        switch status {
        case let .succeeded(detail): detail ?? "Bitti"
        case let .failed(message): message
        case .skipped: "Atlandı"
        case .cancelled: "İptal edildi"
        }
    }
}
