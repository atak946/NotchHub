import Foundation
import OSLog

/// Persistence boundary for the time ledger.
protocol TimeLedgerStoring: Sendable {
    func load() throws -> TimeLedger
    func save(_ ledger: TimeLedger) throws
    func delete() throws
}

/// JSON file under Application Support/NotchHub/Insights.
struct FileTimeLedgerStore: TimeLedgerStoring {
    static let fileName = "time-ledger.json"
    static let directoryPermissions = 0o700

    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    static func makeDefault() -> FileTimeLedgerStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileTimeLedgerStore(directory: base.appendingPathComponent("NotchHub/Insights", isDirectory: true))
    }

    func load() throws -> TimeLedger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(TimeLedger.self, from: data)
        } catch {
            quarantineCorruptFile()
            throw error
        }
    }

    func save(_ ledger: TimeLedger) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Keeps an unreadable file aside instead of silently overwriting the user's history.
    private func quarantineCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
