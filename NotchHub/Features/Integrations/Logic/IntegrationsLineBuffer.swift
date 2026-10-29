import Foundation

/// Splits a byte stream into newline-delimited lines with a hard per-line size cap.
struct IntegrationsLineBuffer: Sendable {
    struct OverflowError: Error, Equatable {}

    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")

    let maxLineBytes: Int
    private var pending = Data()

    init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    /// Appends bytes and returns every completed, non-blank line.
    mutating func append(_ data: Data) -> Result<[String], OverflowError> {
        pending.append(data)
        var lines: [String] = []
        while let newlineIndex = pending.firstIndex(of: Self.newline) {
            let lineData = pending[pending.startIndex..<newlineIndex]
            pending = Data(pending[pending.index(after: newlineIndex)...])
            guard lineData.count <= maxLineBytes else { return .failure(OverflowError()) }
            if let line = Self.decode(lineData) { lines.append(line) }
        }
        guard pending.count <= maxLineBytes else { return .failure(OverflowError()) }
        return .success(lines)
    }

    /// Remaining unterminated text once the peer closed its side.
    mutating func flush() -> String? {
        defer { pending = Data() }
        return Self.decode(pending)
    }

    private static func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.last == carriageReturn { bytes = bytes.dropLast() }
        let line = String(decoding: bytes, as: UTF8.self)
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : line
    }
}
