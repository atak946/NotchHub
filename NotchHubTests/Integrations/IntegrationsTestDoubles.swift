import Foundation
@testable import NotchHub

@MainActor
final class IntegrationsFakeSystem: IntegrationsSystem {
    var knownSymbols: Set<String> = ["bell", "hammer.fill", "checkmark.circle.fill", "xmark.octagon.fill",
                                     "checkmark.seal.fill", "exclamationmark.triangle.fill"]
    var bundledZshHookPath: String?
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []
    private(set) var copiedTexts: [String] = []

    func symbolExists(_ name: String) -> Bool { knownSymbols.contains(name) }
    func open(_ url: URL) { openedURLs.append(url) }
    func revealInFinder(_ url: URL) { revealedURLs.append(url) }
    func copyToPasteboard(_ text: String) { copiedTexts.append(text) }
}

final class IntegrationsFakeSocketServer: IntegrationsSocketServing, @unchecked Sendable {
    private let lock = NSLock()
    private var _startedPaths: [String] = []
    private var _stopCount = 0

    var startedPaths: [String] { lock.withLock { _startedPaths } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func start(
        path: String,
        onState: @escaping @Sendable (IntegrationsSocketState) -> Void,
        onLine: @escaping @MainActor @Sendable (String) -> String
    ) {
        lock.withLock { _startedPaths.append(path) }
    }

    func stop() {
        lock.withLock { _stopCount += 1 }
    }
}

@MainActor
final class IntegrationsTestClock {
    var now: Date

    init(_ now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

func makeIntegrationsTestDefaults() -> UserDefaults {
    TestDefaults.suite(named: "IntegrationsTests.\(UUID().uuidString)")
}

var integrationsUTCCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}

extension ExternalParseResult {
    var alert: ExternalAlertRequest? {
        if case .alert(let request) = request { return request }
        return nil
    }
}

extension Result where Success == ExternalParseResult, Failure == ExternalRequestError {
    var alert: ExternalAlertRequest? { (try? get())?.alert }
    var warnings: [String] { (try? get())?.warnings ?? [] }
    var error: ExternalRequestError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

func integrationsURL(_ string: String) -> URL {
    guard let url = URL(string: string) else { fatalError("Bad test URL \(string)") }
    return url
}
