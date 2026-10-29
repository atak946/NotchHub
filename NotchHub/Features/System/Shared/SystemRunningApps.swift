import AppKit
import Observation

/// A running application, reduced to what the System monitors need.
struct SystemRunningApp: Equatable, Sendable {
    let bundleIdentifier: String?
    let name: String?
}

/// Observable list of running applications, refreshed on launch/terminate notifications.
@MainActor
@Observable
final class SystemRunningApps {
    typealias Source = @MainActor () -> [SystemRunningApp]

    private(set) var apps: [SystemRunningApp] = []

    @ObservationIgnored private let source: Source
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(source: @escaping Source = SystemRunningApps.workspaceApps) {
        self.source = source
    }

    var isRunning: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
    }

    func reload() {
        let updated = source()
        if updated != apps {
            apps = updated
        }
    }

    static func workspaceApps() -> [SystemRunningApp] {
        NSWorkspace.shared.runningApplications.map {
            SystemRunningApp(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName)
        }
    }
}

/// A desktop meeting client whose presence (together with an active microphone) means "in a meeting".
struct MeetingApp: Hashable, Sendable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

/// Known meeting clients. Browsers are deliberately excluded: they are almost always running,
/// so counting them would make every microphone use look like a meeting.
enum MeetingAppCatalog {
    static let known: [MeetingApp] = [
        MeetingApp(bundleIdentifier: "us.zoom.xos", name: "Zoom"),
        MeetingApp(bundleIdentifier: "com.microsoft.teams2", name: "Teams"),
        MeetingApp(bundleIdentifier: "com.microsoft.teams", name: "Teams"),
        MeetingApp(bundleIdentifier: "Cisco-Systems.Spark", name: "Webex"),
        MeetingApp(bundleIdentifier: "com.webex.meetingmanager", name: "Webex"),
        MeetingApp(bundleIdentifier: "com.apple.FaceTime", name: "FaceTime"),
    ]

    static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.operasoftware.Opera",
    ]

    /// Meeting clients among `apps`, in catalog order.
    static func running(in apps: [SystemRunningApp]) -> [MeetingApp] {
        let ids = Set(apps.compactMap(\.bundleIdentifier)).subtracting(browserBundleIdentifiers)
        return known.filter { ids.contains($0.bundleIdentifier) }
    }
}
