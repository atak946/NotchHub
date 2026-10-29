import AppKit
import Foundation
import OSLog

struct ProfilesExecutorConfiguration: Sendable {
    var terminalBundleID: String
    /// `nil` when no VPN client is chosen or installed.
    var vpnAppBundleID: String?
}

/// Performs profile steps with NSWorkspace and `Process` (argument arrays only, no shell).
@MainActor
final class LiveProfileStepExecutor: ProfileStepExecuting {
    static let vscodeBundleID = "com.microsoft.VSCode"
    static let composeTimeout: Duration = .seconds(600)
    static let codeCLITimeout: Duration = .seconds(30)
    static let vpnPollInterval: Duration = .seconds(2)

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let processRunner: any ProfilesProcessRunning
    private let validator: ProfileStepValidator
    private let configuration: @MainActor () -> ProfilesExecutorConfiguration
    private let isVPNUp: @MainActor () -> Bool
    private let sleep: Sleeper
    private let workspace = NSWorkspace.shared
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Profiles")

    init(
        configuration: @escaping @MainActor () -> ProfilesExecutorConfiguration,
        processRunner: any ProfilesProcessRunning = LiveProfilesProcessRunner(),
        validator: ProfileStepValidator = ProfileStepValidator(),
        isVPNUp: @escaping @MainActor () -> Bool = { ProfilesVPNDetector.isTunnelUp(ProfilesVPNDetector.currentAddresses()) },
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.configuration = configuration
        self.processRunner = processRunner
        self.validator = validator
        self.isVPNUp = isVPNUp
        self.sleep = sleep
    }

    func execute(_ action: ProfileAction, prompt: @escaping @MainActor (ProfilePrompt) -> Void) async throws -> String? {
        switch action {
        case let .openApp(bundleID):
            try await openApp(bundleID: bundleID)
        case let .openURL(string):
            try await openURL(try validator.validateURL(string).get())
        case let .openInVSCode(path):
            try await openInVSCode(try validator.validateFolder(path).get())
        case let .dockerComposeUp(path):
            try await compose(["compose", "up", "-d"], in: try validator.validateComposeFolder(path).get())
        case let .dockerComposeStop(path):
            try await compose(["compose", "stop"], in: try validator.validateComposeFolder(path).get())
        case let .openTerminal(path):
            try await openTerminal(at: try validator.validateFolder(path).get())
        case let .waitForVPN(timeout):
            try await waitForVPN(timeoutSeconds: timeout, prompt: prompt)
        }
    }

    // MARK: - Apps & URLs

    private func applicationURL(for bundleID: String) throws -> URL {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ProfileStepFailure(message: "\(bundleID) uygulaması yüklü değil")
        }
        return url
    }

    private func openApp(bundleID: String) async throws -> String? {
        let appURL = try applicationURL(for: bundleID)
        do {
            try await workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw ProfileStepFailure(message: "\(appURL.lastPathComponent) açılamadı: \(error.localizedDescription)")
        }
        return appURL.deletingPathExtension().lastPathComponent
    }

    private func openURL(_ url: URL) async throws -> String? {
        guard let handler = workspace.urlForApplication(toOpen: url) else {
            throw ProfileStepFailure(message: "No app handles \(url.scheme ?? "this") URLs")
        }
        do {
            try await workspace.open([url], withApplicationAt: handler, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw ProfileStepFailure(message: "URL açılamadı: \(error.localizedDescription)")
        }
        return handler.deletingPathExtension().lastPathComponent
    }

    // MARK: - Folders

    private func openInVSCode(_ folder: URL) async throws -> String? {
        let bundlePaths = workspace.urlsForApplications(withBundleIdentifier: Self.vscodeBundleID)
            .map { $0.path(percentEncoded: false) }
        let resolver = ProfilesCLIResolver(vscodeBundlePaths: bundlePaths + ProfilesCLIResolver.defaultVSCodeBundlePaths)
        if let code = resolver.resolveCode() {
            do {
                let result = try await processRunner.run(
                    executable: code,
                    arguments: [folder.path(percentEncoded: false)],
                    workingDirectory: nil,
                    environment: childEnvironment(path: resolver.childProcessPath(including: code)),
                    timeout: Self.codeCLITimeout
                )
                if result.exitCode == 0 { return "code CLI" }
                logger.error("code CLI exited with \(result.exitCode, privacy: .public)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("code CLI failed: \(String(describing: error), privacy: .public)")
            }
        }
        let appURL = try applicationURL(for: Self.vscodeBundleID)
        try await open(folder, with: appURL)
        return "Visual Studio Code"
    }

    private func openTerminal(at folder: URL) async throws -> String? {
        let appURL = try applicationURL(for: configuration().terminalBundleID)
        try await open(folder, with: appURL)
        return appURL.deletingPathExtension().lastPathComponent
    }

    private func open(_ folder: URL, with appURL: URL) async throws {
        do {
            try await workspace.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw ProfileStepFailure(message: "Klasör \(appURL.lastPathComponent) ile açılamadı: \(error.localizedDescription)")
        }
    }

    // MARK: - Docker

    private func compose(_ arguments: [String], in folder: URL) async throws -> String? {
        let resolver = ProfilesCLIResolver()
        guard let docker = resolver.resolveDocker() else {
            throw ProfileStepFailure(message: "docker CLI bulunamadı (Docker Desktop veya OrbStack)")
        }
        let result = try await processRunner.run(
            executable: docker,
            arguments: arguments,
            workingDirectory: folder,
            environment: childEnvironment(path: resolver.childProcessPath(including: docker)),
            timeout: Self.composeTimeout
        )
        guard result.exitCode == 0 else {
            let lastLine = result.outputTail
                .split(whereSeparator: \.isNewline)
                .last.map(String.init) ?? "çıkış kodu \(result.exitCode)"
            throw ProfileStepFailure(message: "docker \(arguments.joined(separator: " ")) failed: \(lastLine)")
        }
        return folder.lastPathComponent
    }

    private func childEnvironment(path: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        return environment
    }

    // MARK: - VPN

    private func waitForVPN(timeoutSeconds: Int, prompt: @escaping @MainActor (ProfilePrompt) -> Void) async throws -> String? {
        if isVPNUp() { return "zaten bağlı" }

        let vpnBundleID = configuration().vpnAppBundleID
        if let vpnBundleID, let appURL = workspace.urlForApplication(withBundleIdentifier: vpnBundleID) {
            do {
                _ = try await workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                logger.error("Could not open VPN app: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.error("VPN app \(vpnBundleID ?? "none", privacy: .public) not found")
        }
        prompt(ProfilePrompt(
            title: "VPN'e bağlanın",
            subtitle: "Tünel için en fazla \(timeoutSeconds) sn bekleniyor",
            systemImage: "lock.shield"
        ))

        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            try await sleep(Self.vpnPollInterval)
            try Task.checkCancellation()
            if isVPNUp() { return "bağlandı" }
        }
        throw ProfileStepFailure(message: "\(timeoutSeconds) sn sonra VPN bağlı değil")
    }
}
