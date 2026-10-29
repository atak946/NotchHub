import Foundation

/// An app the privacy indicator attributes microphone use to.
struct CaptureApp: Equatable, Sendable, Identifiable {
    let bundleID: String?
    let name: String

    var id: String { bundleID ?? name }
}

/// Maps raw CoreAudio input processes to user-facing apps (helpers folded into their parent app).
enum PrivacyAppMapper {
    /// WebKit capture runs in shared `com.apple.WebKit.*` processes; attribute it to Safari when it runs.
    private static let webKitPrefix = "com.apple.WebKit"
    private static let safariBundleID = "com.apple.Safari"

    static func apps(
        from processes: [AudioInputProcess],
        runningApps: [SystemRunningApp],
        ownBundleID: String?
    ) -> [CaptureApp] {
        var seen = Set<String>()
        var result: [CaptureApp] = []
        for process in processes {
            guard let app = resolve(process, runningApps: runningApps) else { continue }
            if let ownBundleID, app.bundleID == ownBundleID || process.bundleID == ownBundleID { continue }
            guard seen.insert(app.id).inserted else { continue }
            result.append(app)
        }
        return result
    }

    static func resolve(_ process: AudioInputProcess, runningApps: [SystemRunningApp]) -> CaptureApp? {
        if let bundleID = process.bundleID, let owner = owningApp(of: bundleID, in: runningApps) {
            return owner
        }
        guard let name = trimmed(process.name) else { return nil }
        return CaptureApp(bundleID: process.bundleID, name: name)
    }

    /// The running app whose bundle id equals `bundleID` or is its longest dotted prefix.
    private static func owningApp(of bundleID: String, in runningApps: [SystemRunningApp]) -> CaptureApp? {
        let target = bundleID.hasPrefix(webKitPrefix) ? safariBundleID : bundleID
        var best: CaptureApp?
        var bestLength = 0
        for app in runningApps {
            guard let candidate = app.bundleIdentifier, let name = trimmed(app.name) else { continue }
            let matches = target == candidate || target.hasPrefix(candidate + ".")
            if matches, candidate.count > bestLength {
                best = CaptureApp(bundleID: candidate, name: name)
                bestLength = candidate.count
            }
        }
        return best
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Which dot the collapsed notch shows. Like macOS, camera (green) wins over microphone (orange).
enum PrivacyIndicatorKind: Equatable, Sendable {
    case camera
    case microphone

    static func current(isMicrophoneInUse: Bool, isCameraInUse: Bool) -> PrivacyIndicatorKind? {
        if isCameraInUse { return .camera }
        return isMicrophoneInUse ? .microphone : nil
    }
}

/// User-facing descriptions for the privacy indicator tooltip and the Status tile.
enum PrivacyIndicatorText {
    /// "Zoom mikrofonu kullanıyor", or nil when no app could be identified.
    static func microphone(apps: [CaptureApp]) -> String? {
        guard let first = apps.first else { return nil }
        let others = apps.count - 1
        if others == 0 {
            return String(localized: "\(first.name) mikrofonu kullanıyor")
        }
        return String(localized: "\(first.name) ve \(others) uygulama daha mikrofonu kullanıyor")
    }

    /// Tooltip lines for the compact dot; camera has no public per-app API, so it stays generic.
    static func help(isMicrophoneInUse: Bool, isCameraInUse: Bool, microphoneApps: [CaptureApp]) -> String {
        var lines: [String] = []
        if isMicrophoneInUse {
            lines.append(microphone(apps: microphoneApps) ?? String(localized: "Mikrofon kullanımda"))
        }
        if isCameraInUse {
            lines.append(String(localized: "Kamera kullanımda"))
        }
        return lines.joined(separator: "\n")
    }
}
