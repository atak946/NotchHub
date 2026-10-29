import Foundation
import Testing
@testable import NotchHub

struct FileTimeLedgerStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotchHubTests-Insights-\(UUID().uuidString)", isDirectory: true)

    @Test func missingFileLoadsEmpty() throws {
        let store = FileTimeLedgerStore(directory: directory)
        #expect(try store.load() == .empty)
    }

    @Test func roundTrip() throws {
        let store = FileTimeLedgerStore(directory: directory)
        let ledger = TimeLedger.empty
            .adding(seconds: 75, client: "Northwind", appBundleID: "com.microsoft.VSCode", day: "2026-10-28")
            .adding(seconds: 30, client: "Ünlü, \"Co\"", appBundleID: nil, day: "2026-10-29")
        try store.save(ledger)
        #expect(try FileTimeLedgerStore(directory: directory).load() == ledger)
        try store.delete()
        #expect(try store.load() == .empty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func persistsOnlyAggregates() throws {
        let store = FileTimeLedgerStore(directory: directory)
        try store.save(TimeLedger.empty.adding(seconds: 15, client: "Northwind", appBundleID: "com.a", day: "2026-10-28"))
        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(json.contains("\"client\":\"Northwind\""))
        #expect(!json.lowercased().contains("title"))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func corruptFileIsSetAsideAndThrows() throws {
        let store = FileTimeLedgerStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.contains { $0.contains("corrupt") })
        try? FileManager.default.removeItem(at: directory)
    }
}
