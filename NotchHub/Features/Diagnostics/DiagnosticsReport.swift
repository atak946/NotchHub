import Foundation

/// One connected display, without names or serials.
struct DiagnosticsDisplay: Equatable, Sendable {
    let isBuiltIn: Bool
    let hasNotch: Bool
    let width: Int
    let height: Int
}

/// Everything collected for one report; formatting and redaction stay pure.
struct DiagnosticsSnapshot: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let modelIdentifier: String
    let displays: [DiagnosticsDisplay]
    let enabledModules: [String]
    let permissions: [DiagnosticsPermissionLine]
    let logLines: [String]
    let generatedAt: Date
}

struct DiagnosticsPermissionLine: Equatable, Sendable {
    let name: String
    let status: String
}

/// Plain-text rendering of a snapshot: the full report for the clipboard, a short summary for the URL.
enum DiagnosticsReportFormatter {
    static let maxLogLines = 200
    static let noLogsLine = "(no log entries in the last hour)"

    static func summary(_ snapshot: DiagnosticsSnapshot) -> String {
        let displays = snapshot.displays.enumerated().map { index, display in
            "  - Display \(index + 1): \(display.width)x\(display.height)"
                + (display.isBuiltIn ? ", built-in" : ", external")
                + (display.hasNotch ? ", notch" : ", no notch")
        }
        let modules = snapshot.enabledModules.isEmpty ? "none" : snapshot.enabledModules.joined(separator: ", ")
        let permissions = snapshot.permissions.map { "  - \($0.name): \($0.status)" }
        return ([
            "NotchHub \(snapshot.appVersion) (\(snapshot.appBuild))",
            "macOS: \(snapshot.osVersion)",
            "Mac: \(snapshot.modelIdentifier)",
            "Displays: \(snapshot.displays.count)",
        ] + displays + [
            "Modules: \(modules)",
            "Permissions:",
        ] + permissions).joined(separator: "\n")
    }

    static func fullReport(_ snapshot: DiagnosticsSnapshot) -> String {
        let generated = ISO8601DateFormatter().string(from: snapshot.generatedAt)
        let logs = snapshot.logLines.suffix(maxLogLines)
        return ([
            "=== NotchHub diagnostics ===",
            "Generated: \(generated)",
            "",
            summary(snapshot),
            "",
            "=== Log (last hour, newest last, \(logs.count) lines) ===",
        ] + (logs.isEmpty ? [noLogsLine] : Array(logs))).joined(separator: "\n")
    }
}
