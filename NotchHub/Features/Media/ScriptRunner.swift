import AppKit
import Foundation

/// Result of one AppleScript run: its text coercion (if any) and the raw descriptor bytes.
struct ScriptOutput: Equatable, Sendable {
    let text: String?
    let data: Data

    init(text: String?, data: Data = Data()) {
        self.text = text
        self.data = data
    }
}

enum ScriptError: Error, Equatable, Sendable {
    case compileFailed(String)
    case executionFailed(code: Int, message: String)
    /// The user denied (or has not yet granted) Automation access for the target app.
    case notPermitted
    /// The target app quit between the running check and the script.
    case applicationNotRunning

    static let notPermittedCode = -1743
    static let applicationNotRunningCode = -600

    static func from(code: Int, message: String) -> ScriptError {
        switch code {
        case notPermittedCode: .notPermitted
        case applicationNotRunningCode: .applicationNotRunning
        default: .executionFailed(code: code, message: message)
        }
    }
}

/// Executes AppleScript source. Abstracted so providers can be tested without real players.
protocol ScriptRunner: Sendable {
    func run(_ source: String) async throws -> ScriptOutput
}

/// Runs NSAppleScript on one dedicated serial queue: NSAppleScript is not thread-safe and must stay off the main actor.
actor AppleScriptRunner: ScriptRunner {
    static let shared = AppleScriptRunner()

    private static let unknownErrorCode = -1
    private let queue = DispatchSerialQueue(label: "\(AppIdentity.bundleID).applescript", qos: .userInitiated)
    private var compiledScripts: [String: NSAppleScript] = [:]

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    func run(_ source: String) throws -> ScriptOutput {
        let script = try compiledScript(for: source)
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw Self.error(from: errorInfo, compiling: false)
        }
        return ScriptOutput(text: descriptor.stringValue, data: descriptor.data)
    }

    private func compiledScript(for source: String) throws -> NSAppleScript {
        if let cached = compiledScripts[source] {
            return cached
        }
        guard let script = NSAppleScript(source: source) else {
            throw ScriptError.compileFailed("Invalid script source")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            throw Self.error(from: errorInfo, compiling: true)
        }
        compiledScripts[source] = script
        return script
    }

    private static func error(from info: NSDictionary?, compiling: Bool) -> ScriptError {
        let code = info?[NSAppleScript.errorNumber] as? Int ?? unknownErrorCode
        let message = info?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        if compiling, code != ScriptError.notPermittedCode {
            return .compileFailed(message)
        }
        return ScriptError.from(code: code, message: message)
    }
}

/// Answers whether an app is running without ever launching it.
protocol RunningApplicationChecking: Sendable {
    func isRunning(bundleIdentifier: String) async -> Bool
}

struct WorkspaceRunningApplicationChecker: RunningApplicationChecking {
    func isRunning(bundleIdentifier: String) async -> Bool {
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains { !$0.isTerminated }
        }
    }
}

/// Downloads remote artwork bytes.
protocol ArtworkDownloading: Sendable {
    func download(_ url: URL) async throws -> Data
}

struct URLSessionArtworkDownloader: ArtworkDownloading {
    enum DownloadError: Error, Equatable {
        case insecureURL
        case badStatus(Int)
    }

    private static let okStatus = 200..<300
    private static let timeout: TimeInterval = 10

    func download(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw DownloadError.insecureURL }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !Self.okStatus.contains(http.statusCode) {
            throw DownloadError.badStatus(http.statusCode)
        }
        return data
    }
}
