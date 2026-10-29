import Foundation
import Synchronization
@testable import NotchHub

/// In-memory `CalendarSecretStore` (stands in for the Keychain).
final class CalendarTestSecretStore: CalendarSecretStore {
    private let storage = Mutex<[String: String]>([:])

    var all: [String: String] { storage.withLock { $0 } }

    func secret(for key: String) -> String? { storage.withLock { $0[key] } }

    func setSecret(_ value: String, for key: String) throws {
        storage.withLock { $0[key] = value }
    }

    func removeSecret(for key: String) {
        storage.withLock { $0[key] = nil }
    }
}

struct CalendarTestHTTPStub: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]

    static func json(_ text: String, status: Int = 200) -> CalendarTestHTTPStub {
        CalendarTestHTTPStub(status: status, body: Data(text.utf8), headers: ["Content-Type": "application/json"])
    }

    static func text(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> CalendarTestHTTPStub {
        CalendarTestHTTPStub(status: status, body: Data(text.utf8), headers: headers)
    }
}

enum CalendarTestHTTPError: Error {
    case badResponse
}

/// Records requests and answers them with a responder closure.
final class CalendarTestHTTPClient: CalendarHTTPClient {
    typealias Responder = @Sendable (URLRequest) -> CalendarTestHTTPStub

    private let recorded = Mutex<[URLRequest]>([])
    private let responder: Responder

    init(responder: @escaping Responder) {
        self.responder = responder
    }

    /// Serves `stubs` in order (the last one repeats).
    convenience init(sequence stubs: [CalendarTestHTTPStub]) {
        let index = Mutex(0)
        self.init { _ in
            index.withLock { current in
                let stub = stubs[min(current, stubs.count - 1)]
                current += 1
                return stub
            }
        }
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let stub = responder(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)
        else { throw CalendarTestHTTPError.badResponse }
        return (stub.body, response)
    }
}

/// Records requested sleeps and advances a test clock instead of waiting.
final class CalendarTestSleeper: Sendable {
    private let recorded = Mutex<[Duration]>([])
    private let clock: CalendarTestClock?

    init(clock: CalendarTestClock? = nil) {
        self.clock = clock
    }

    var sleeps: [Duration] { recorded.withLock { $0 } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            recorded.withLock { $0.append(duration) }
            clock?.advance(by: TimeInterval(duration.components.seconds))
        }
    }
}

enum CalendarICSFixtures {
    static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    /// Wraps VEVENT lines in a VCALENDAR with CRLF line endings.
    static func calendar(_ body: [String], name: String? = "Work") -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Microsoft Corporation//Outlook 16.0 MIMEDIR//EN"]
        if let name { lines.append("X-WR-CALNAME:\(name)") }
        lines += body
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func event(_ properties: [String]) -> [String] {
        ["BEGIN:VEVENT"] + properties + ["END:VEVENT"]
    }

    static let context = CalendarSourceContext(
        idPrefix: "ics.test",
        calendarID: "ics.calendar.test",
        calendarTitle: "Work",
        color: .fallback,
        account: CalendarAccount(id: "ics.account.test", title: "Work", kind: .outlook)
    )

    static let march = DateInterval(start: utc("2026-03-01T00:00:00Z"), end: utc("2026-04-01T00:00:00Z"))

    static func expand(_ text: String, window: DateInterval = march) -> [CalendarEvent] {
        ICSEventExpander.events(in: ICSParser.parse(text), window: window, context: context)
            .sorted { $0.start < $1.start }
    }
}
