import AppKit
import Foundation
import OSLog

/// Reads this process's own unified-log entries; abstracted so the reporter is testable.
protocol DiagnosticsLogReading: Sendable {
    func recentLines(since date: Date, limit: Int) async throws -> [String]
}

/// `OSLogStore` scoped to the current process and filtered to `AppIdentity.logSubsystem`.
struct OSLogDiagnosticsReader: DiagnosticsLogReading {
    let subsystem: String

    init(subsystem: String = AppIdentity.logSubsystem) {
        self.subsystem = subsystem
    }

    func recentLines(since date: Date, limit: Int) async throws -> [String] {
        let subsystem = subsystem
        // Enumerating the store is synchronous and can take a while; keep it off the main actor.
        return try await Task.detached(priority: .utility) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: date)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            var lines: [String] = []
            for entry in try store.getEntries(at: position, matching: predicate) {
                guard let log = entry as? OSLogEntryLog else { continue }
                let time = formatter.string(from: log.date)
                lines.append("\(time) [\(Self.label(for: log.level))] [\(log.category)] \(log.composedMessage)")
                if lines.count > limit * 2 {
                    lines.removeFirst(lines.count - limit)
                }
            }
            return Array(lines.suffix(limit))
        }.value
    }

    static func label(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "default"
        @unknown default: "default"
        }
    }
}

/// Gathers app, OS and hardware facts that identify no person.
@MainActor
enum DiagnosticsSystemInfo {
    static let unknown = "unknown"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? unknown
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? unknown
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// `hw.model`, e.g. `Mac15,6`.
    static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return unknown }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return unknown }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static var displays: [DiagnosticsDisplay] {
        NSScreen.screens.map { screen in
            DiagnosticsDisplay(
                isBuiltIn: screen.isBuiltIn,
                hasNotch: screen.safeAreaInsets.top > 0,
                width: Int(screen.frame.width),
                height: Int(screen.frame.height)
            )
        }
    }

    /// Info.plist `NHIssueURL`, filled from the `NH_ISSUE_URL` build setting.
    static var issueURLSetting: String? {
        Bundle.main.object(forInfoDictionaryKey: DiagnosticsIssueURL.infoPlistKey) as? String
    }
}
