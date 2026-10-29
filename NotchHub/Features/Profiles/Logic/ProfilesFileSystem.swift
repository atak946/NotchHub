import Foundation

enum ProfilesItemKind: Sendable, Equatable {
    case missing
    case file
    case directory
}

/// Minimal read-only file system surface so validation, scanning and CLI resolution are testable.
protocol ProfilesFileSystem: Sendable {
    func itemKind(atPath path: String) -> ProfilesItemKind
    func isExecutableFile(atPath path: String) -> Bool
    /// Entry names (not paths). Empty when unreadable.
    func contentsOfDirectory(atPath path: String) -> [String]
}

struct LiveProfilesFileSystem: ProfilesFileSystem {
    func itemKind(atPath path: String) -> ProfilesItemKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .missing }
        return isDirectory.boolValue ? .directory : .file
    }

    func isExecutableFile(atPath path: String) -> Bool {
        itemKind(atPath: path) == .file && FileManager.default.isExecutableFile(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }
}
