import Foundation
@testable import NotchHub

/// Manually advanced clock shared with services under test.
final class AutomationsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

@MainActor
final class AutomationsFakeWorkspace: FocusWorkspace {
    private(set) var handler: (@MainActor (FocusActivation) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var activatedPIDs: [pid_t] = []
    var frontmostApp: FocusActivation?
    var activationSucceeds = true

    var isObserving: Bool { handler != nil }

    func startObserving(_ handler: @escaping @MainActor (FocusActivation) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stopObserving() {
        stopCount += 1
        handler = nil
    }

    func activate(processID: pid_t) -> Bool {
        activatedPIDs.append(processID)
        return activationSucceeds
    }

    func send(_ activation: FocusActivation) {
        handler?(activation)
    }
}

@MainActor
final class AutomationsFakeWatcher: CaptureFileWatching {
    private(set) var handler: (@MainActor ([CaptureFileEvent]) -> Void)?
    private(set) var startedPaths: [[String]] = []
    private(set) var stopCount = 0
    var startSucceeds = true

    func start(paths: [String], handler: @escaping @MainActor ([CaptureFileEvent]) -> Void) -> Bool {
        startedPaths.append(paths)
        self.handler = startSucceeds ? handler : nil
        return startSucceeds
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func send(_ events: [CaptureFileEvent]) {
        handler?(events)
    }
}

/// In-memory file system for the classifier.
final class AutomationsFakeProbe: CaptureFileProbing, @unchecked Sendable {
    private var files: [String: CaptureFileInfo] = [:]

    func put(_ path: String, size: Int64, created: Date?, isRegularFile: Bool = true) {
        files[path] = CaptureFileInfo(isRegularFile: isRegularFile, size: size, creationDate: created)
    }

    func remove(_ path: String) {
        files[path] = nil
    }

    func rename(_ from: String, to: String) {
        files[to] = files[from]
        files[from] = nil
    }

    func info(atPath path: String) -> CaptureFileInfo? {
        files[path]
    }

    func exists(atPath path: String) -> Bool {
        files[path] != nil
    }
}

struct AutomationsFakePreferences: CapturePreferencesReading {
    var values: [String: String] = [:]

    func string(forKey key: String, domain: String) -> String? {
        values["\(domain)/\(key)"]
    }
}

enum AutomationsPaths {
    static let home = "/Users/tester"
    static let desktop = "/Users/tester/Desktop"
    static let downloads = "/Users/tester/Downloads"
    static let shots = "/Users/tester/Pictures/Shots"

    static let existingFolders: Set<String> = [desktop, downloads, shots, "/Users/tester/Pictures/Shottr"]

    static func resolver(_ preferences: AutomationsFakePreferences = AutomationsFakePreferences()) -> CaptureFolderResolver {
        CaptureFolderResolver(
            preferences: preferences,
            homeDirectory: URL(filePath: home, directoryHint: .isDirectory),
            isDirectory: { existingFolders.contains($0) }
        )
    }
}

extension CaptureFileEvent {
    static func created(_ path: String) -> CaptureFileEvent {
        CaptureFileEvent(path: path, flags: [.created, .isFile])
    }

    static func renamed(_ path: String) -> CaptureFileEvent {
        CaptureFileEvent(path: path, flags: [.renamed, .isFile])
    }

    static func modified(_ path: String) -> CaptureFileEvent {
        CaptureFileEvent(path: path, flags: [.modified, .isFile])
    }

    static func removed(_ path: String) -> CaptureFileEvent {
        CaptureFileEvent(path: path, flags: [.removed, .isFile])
    }
}

func makeAutomationsTestDefaults() -> UserDefaults {
    let (suiteName, defaults) = TestDefaults.makeSuite("Automations.\(UUID().uuidString)")
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

let automationsNeverSleep: CaptureCatcherService.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
