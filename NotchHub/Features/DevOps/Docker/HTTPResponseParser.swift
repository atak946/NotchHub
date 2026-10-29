import Foundation

/// Status line and headers of an HTTP/1.1 response. Header names are lowercased.
struct HTTPResponseHead: Equatable, Sendable {
    let statusCode: Int
    let reason: String
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Incremental output of `HTTPResponseParser`.
enum HTTPResponseEvent: Equatable, Sendable {
    case head(HTTPResponseHead)
    /// A slice of the decoded body (chunk framing removed). May arrive in many pieces.
    case body(Data)
    case end
}

enum HTTPParseError: Error, Equatable, Sendable {
    case invalidStatusLine
    case invalidHeader
    case headerTooLarge
    case invalidContentLength
    case unsupportedTransferEncoding
    case invalidChunkSize
    case invalidChunkTerminator
    case lineTooLong
    case unexpectedEndOfStream
    case dataAfterEnd
}

/// Minimal, incremental HTTP/1.1 response parser for a single response per connection.
///
/// Supports `Content-Length`, `Transfer-Encoding: chunked` (with extensions and trailers)
/// and read-until-close bodies. Input may be split at any byte boundary.
struct HTTPResponseParser: Sendable {
    static let maxHeaderBytes = 64 * 1024
    static let maxLineBytes = 4 * 1024

    private enum State: Equatable, Sendable {
        case head
        case fixedBody(remaining: Int)
        case chunkSize
        case chunkData(remaining: Int)
        case chunkDataTerminator
        case trailers
        case untilClose
        case done
    }

    private static let crlf: [UInt8] = [0x0D, 0x0A]
    private static let headerTerminator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]

    private var state: State = .head
    private var buffer: [UInt8] = []

    private(set) var head: HTTPResponseHead?

    var isComplete: Bool { state == .done }

    init() {}

    /// Feeds received bytes and returns everything that could be decoded so far.
    mutating func feed(_ data: Data) throws -> [HTTPResponseEvent] {
        if state == .done {
            if data.isEmpty { return [] }
            throw HTTPParseError.dataAfterEnd
        }
        buffer.append(contentsOf: data)
        var events: [HTTPResponseEvent] = []
        while try step(into: &events) {}
        return events
    }

    /// Signals that the peer closed the connection.
    mutating func finish() throws -> [HTTPResponseEvent] {
        switch state {
        case .done:
            return []
        case .untilClose:
            state = .done
            return [.end]
        default:
            throw HTTPParseError.unexpectedEndOfStream
        }
    }

    // MARK: - State machine

    /// Advances one step; returns `false` when more input is needed.
    private mutating func step(into events: inout [HTTPResponseEvent]) throws -> Bool {
        switch state {
        case .head:
            return try parseHead(into: &events)
        case .fixedBody(let remaining):
            return consumeBody(remaining: remaining, into: &events) { left in
                left == 0 ? .done : .fixedBody(remaining: left)
            }
        case .chunkSize:
            return try parseChunkSize(into: &events)
        case .chunkData(let remaining):
            return consumeBody(remaining: remaining, into: &events) { left in
                left == 0 ? .chunkDataTerminator : .chunkData(remaining: left)
            }
        case .chunkDataTerminator:
            guard buffer.count >= 2 else { return false }
            guard Array(buffer.prefix(2)) == Self.crlf else { throw HTTPParseError.invalidChunkTerminator }
            buffer.removeFirst(2)
            state = .chunkSize
            return true
        case .trailers:
            return try parseTrailerLine(into: &events)
        case .untilClose:
            guard !buffer.isEmpty else { return false }
            events.append(.body(Data(buffer)))
            buffer.removeAll(keepingCapacity: true)
            return false
        case .done:
            guard buffer.isEmpty else { throw HTTPParseError.dataAfterEnd }
            return false
        }
    }

    private mutating func consumeBody(
        remaining: Int,
        into events: inout [HTTPResponseEvent],
        next: (Int) -> State
    ) -> Bool {
        guard !buffer.isEmpty else { return false }
        let take = min(remaining, buffer.count)
        events.append(.body(Data(buffer.prefix(take))))
        buffer.removeFirst(take)
        let newState = next(remaining - take)
        state = newState
        if newState == .done {
            events.append(.end)
        }
        return newState != .done || !buffer.isEmpty
    }

    private mutating func parseHead(into events: inout [HTTPResponseEvent]) throws -> Bool {
        guard let range = Self.firstRange(of: Self.headerTerminator, in: buffer) else {
            if buffer.count > Self.maxHeaderBytes { throw HTTPParseError.headerTooLarge }
            return false
        }
        guard range.lowerBound <= Self.maxHeaderBytes else { throw HTTPParseError.headerTooLarge }
        let headBytes = Array(buffer[..<range.lowerBound])
        buffer.removeFirst(range.upperBound)
        let parsed = try Self.parseHead(headBytes)

        // Interim 1xx responses (except 101) precede the real one.
        if (100..<200).contains(parsed.statusCode), parsed.statusCode != 101 {
            return true
        }
        head = parsed
        events.append(.head(parsed))
        state = try Self.bodyState(for: parsed)
        if state == .done {
            events.append(.end)
        }
        return true
    }

    private mutating func parseChunkSize(into events: inout [HTTPResponseEvent]) throws -> Bool {
        guard let line = try takeLine() else { return false }
        let sizeText = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !sizeText.isEmpty, sizeText.count <= 16, let size = Int(sizeText, radix: 16), size >= 0 else {
            throw HTTPParseError.invalidChunkSize
        }
        state = size == 0 ? .trailers : .chunkData(remaining: size)
        return true
    }

    private mutating func parseTrailerLine(into events: inout [HTTPResponseEvent]) throws -> Bool {
        guard let line = try takeLine() else { return false }
        if line.isEmpty {
            state = .done
            events.append(.end)
        }
        return true
    }

    /// Removes and returns one CRLF-terminated line (without the terminator).
    private mutating func takeLine() throws -> String? {
        guard let range = Self.firstRange(of: Self.crlf, in: buffer) else {
            if buffer.count > Self.maxLineBytes { throw HTTPParseError.lineTooLong }
            return nil
        }
        let lineBytes = buffer[..<range.lowerBound]
        guard lineBytes.count <= Self.maxLineBytes else { throw HTTPParseError.lineTooLong }
        let line = String(decoding: lineBytes, as: UTF8.self)
        buffer.removeFirst(range.upperBound)
        return line
    }

    // MARK: - Pure helpers

    private static func parseHead(_ bytes: [UInt8]) throws -> HTTPResponseHead {
        let text = String(decoding: bytes, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw HTTPParseError.invalidStatusLine }
        let statusLine = lines.removeFirst()
        let (code, reason) = try parseStatusLine(statusLine)

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw HTTPParseError.invalidHeader }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(" ") else { throw HTTPParseError.invalidHeader }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }
        return HTTPResponseHead(statusCode: code, reason: reason, headers: headers)
    }

    private static func parseStatusLine(_ line: String) throws -> (Int, String) {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              parts[0].hasPrefix("HTTP/1."),
              parts[1].count == 3,
              let code = Int(parts[1]),
              (100...599).contains(code)
        else {
            throw HTTPParseError.invalidStatusLine
        }
        let reason = parts.count == 3 ? String(parts[2]) : ""
        return (code, reason)
    }

    private static func bodyState(for head: HTTPResponseHead) throws -> State {
        if head.statusCode == 204 || head.statusCode == 304 {
            return .done
        }
        if let encoding = head.header("transfer-encoding") {
            let codings = encoding.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard codings.last == "chunked" else { throw HTTPParseError.unsupportedTransferEncoding }
            guard codings.count == 1 else { throw HTTPParseError.unsupportedTransferEncoding }
            return .chunkSize
        }
        if let lengthText = head.header("content-length") {
            let values = Set(lengthText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            guard values.count == 1, let first = values.first, let length = Int(first), length >= 0 else {
                throw HTTPParseError.invalidContentLength
            }
            return length == 0 ? .done : .fixedBody(remaining: length)
        }
        return .untilClose
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Range<Int>? {
        guard haystack.count >= needle.count else { return nil }
        let lastStart = haystack.count - needle.count
        var index = 0
        while index <= lastStart {
            if haystack[index] == needle[0], Array(haystack[index..<(index + needle.count)]) == needle {
                return index..<(index + needle.count)
            }
            index += 1
        }
        return nil
    }
}

/// Splits a byte stream into newline-delimited records (Docker's `/events` emits one JSON object per line).
struct NewlineDelimitedSplitter: Sendable {
    static let maxRecordBytes = 1024 * 1024

    private var pending: [UInt8] = []

    init() {}

    mutating func append(_ data: Data) throws -> [Data] {
        pending.append(contentsOf: data)
        var records: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let record = pending[..<newline].filter { $0 != 0x0D }
            pending.removeFirst(newline + 1)
            if !record.allSatisfy(Self.isWhitespace) {
                records.append(Data(record))
            }
        }
        if pending.count > Self.maxRecordBytes {
            pending.removeAll()
            throw HTTPParseError.lineTooLong
        }
        return records
    }

    /// Returns a trailing record without newline, if any (call at end of stream).
    mutating func flush() -> Data? {
        defer { pending.removeAll() }
        guard !pending.allSatisfy(Self.isWhitespace) else { return nil }
        return Data(pending)
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
