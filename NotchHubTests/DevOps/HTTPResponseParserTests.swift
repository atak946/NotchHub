import Foundation
import Testing
@testable import NotchHub

struct HTTPResponseParserTests {
    private func body(of events: [HTTPResponseEvent]) -> String {
        events.reduce(into: "") { text, event in
            if case .body(let data) = event { text += String(decoding: data, as: UTF8.self) }
        }
    }

    private func parseAll(_ raw: String, splitEvery size: Int? = nil) throws -> [HTTPResponseEvent] {
        var parser = HTTPResponseParser()
        let bytes = Array(raw.utf8)
        var events: [HTTPResponseEvent] = []
        let step = size ?? bytes.count
        var index = 0
        while index < bytes.count {
            let end = min(index + step, bytes.count)
            events += try parser.feed(Data(bytes[index..<end]))
            index = end
        }
        events += try parser.finish()
        return events
    }

    @Test func parsesContentLengthResponse() throws {
        let events = try parseAll("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n[]")

        guard case .head(let head) = events.first else {
            Issue.record("missing head")
            return
        }
        #expect(head.statusCode == 200)
        #expect(head.reason == "OK")
        #expect(head.header("Content-Type") == "application/json")
        #expect(body(of: events) == "[]")
        #expect(events.last == .end)
    }

    @Test func parsesChunkedResponseWithExtensionsAndTrailers() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "4;ext=1\r\nWiki\r\n5\r\npedia\r\nE\r\n in\r\n\r\nchunks.\r\n0\r\nX-Trailer: yes\r\n\r\n"
        let events = try parseAll(raw)

        #expect(body(of: events) == "Wikipedia in\r\n\r\nchunks.")
        #expect(events.last == .end)
        #expect(events.filter { $0 == .end }.count == 1)
    }

    @Test func handlesBytewiseSplitPackets() throws {
        let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\nA\r\n0123456789\r\n0\r\n\r\n"
        let fixed = "HTTP/1.1 201 Created\r\nContent-Length: 5\r\n\r\nhello"

        for size in [1, 2, 3, 7] {
            #expect(try body(of: parseAll(chunked, splitEvery: size)) == "abc0123456789")
            #expect(try body(of: parseAll(fixed, splitEvery: size)) == "hello")
        }
    }

    @Test func streamsChunksBeforeResponseEnds() throws {
        var parser = HTTPResponseParser()
        let first = try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6\r\n{\"a\":1"))

        #expect(body(of: first) == "{\"a\":1")
        #expect(!first.contains(.end))
        #expect(!parser.isComplete)

        let second = try parser.feed(devOpsData("\r\n"))
        #expect(second.isEmpty)
    }

    @Test func readsUntilCloseWithoutFraming() throws {
        let events = try parseAll("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nstream body")
        #expect(body(of: events) == "stream body")
        #expect(events.last == .end)
    }

    @Test func noContentHasEmptyBody() throws {
        var parser = HTTPResponseParser()
        let events = try parser.feed(devOpsData("HTTP/1.1 204 No Content\r\n\r\n"))
        #expect(events.count == 2)
        #expect(events.last == .end)
        #expect(parser.isComplete)
    }

    @Test func skipsInterimContinueResponse() throws {
        let events = try parseAll("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx")
        guard case .head(let head) = events.first else {
            Issue.record("missing head")
            return
        }
        #expect(head.statusCode == 200)
        #expect(body(of: events) == "x")
    }

    @Test func rejectsMalformedStatusLine() {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidStatusLine) {
            try parser.feed(devOpsData("HTTP/1.1 OK\r\n\r\n"))
        }
        var other = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidStatusLine) {
            try other.feed(devOpsData("SSH-2.0-OpenSSH\r\n\r\n"))
        }
    }

    @Test func rejectsMalformedHeader() {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidHeader) {
            try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nNoColonHere\r\n\r\n"))
        }
    }

    @Test func rejectsInvalidContentLength() {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidContentLength) {
            try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n"))
        }
        var conflicting = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidContentLength) {
            try conflicting.feed(devOpsData("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n"))
        }
    }

    @Test func rejectsInvalidChunkSizeAndTerminator() {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidChunkSize) {
            try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n"))
        }
        var terminator = HTTPResponseParser()
        #expect(throws: HTTPParseError.invalidChunkTerminator) {
            try terminator.feed(devOpsData("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nabXX"))
        }
    }

    @Test func rejectsUnsupportedTransferEncoding() {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.unsupportedTransferEncoding) {
            try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n"))
        }
    }

    @Test func rejectsTruncatedBodyAtEndOfStream() throws {
        var parser = HTTPResponseParser()
        _ = try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc"))
        #expect(throws: HTTPParseError.unexpectedEndOfStream) {
            try parser.finish()
        }
    }

    @Test func rejectsOversizedHeader() {
        var parser = HTTPResponseParser()
        let huge = "HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: HTTPResponseParser.maxHeaderBytes + 1)
        #expect(throws: HTTPParseError.headerTooLarge) {
            try parser.feed(devOpsData(huge))
        }
    }

    @Test func rejectsDataAfterCompleteResponse() throws {
        var parser = HTTPResponseParser()
        #expect(throws: HTTPParseError.dataAfterEnd) {
            try parser.feed(devOpsData("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nxEXTRA"))
        }
    }

    @Test func newlineSplitterReassemblesRecordsAcrossChunks() throws {
        var splitter = NewlineDelimitedSplitter()

        #expect(try splitter.append(devOpsData("{\"a\":")).isEmpty)
        let records = try splitter.append(devOpsData("1}\n\r\n{\"b\":2}\n{\"c\"")).map { String(decoding: $0, as: UTF8.self) }

        #expect(records == ["{\"a\":1}", "{\"b\":2}"])
        #expect(splitter.flush().map { String(decoding: $0, as: UTF8.self) } == "{\"c\"")
        #expect(splitter.flush() == nil)
    }
}
