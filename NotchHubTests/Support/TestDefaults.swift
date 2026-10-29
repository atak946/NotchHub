import CoreFoundation
import Foundation
import os

/// Creates isolated `UserDefaults` suites for tests and cleans up their plists.
///
/// Every suite name gets the `NotchHubTests.Suites.` prefix. Suites created in a run are
/// removed by an `atexit` handler; because background writers can recreate a plist after
/// that handler runs, the first use in the next run also deletes stale prefixed plists.
enum TestDefaults {
    static let prefix = "NotchHubTests.Suites."
    private static let staleAge: TimeInterval = 10 * 60
    private static let recordedNames = OSAllocatedUnfairLock<[String]>(initialState: [])

    private static let bootstrap: Void = {
        removeStalePlists()
        atexit {
            TestDefaults.removeRecordedSuites()
        }
    }()

    /// A fresh, empty suite whose name is `prefix + base`.
    static func suite(named base: String) -> UserDefaults {
        makeSuite(base).defaults
    }

    /// A fresh, empty suite plus its full (prefixed) name, for code that takes a domain name.
    static func makeSuite(_ base: String) -> (name: String, defaults: UserDefaults) {
        _ = bootstrap
        let name = prefix + base
        recordedNames.withLock { names in
            names.append(name)
        }
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Could not create UserDefaults suite \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }

    private static var preferencesDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library", directoryHint: .isDirectory)
        return library.appending(path: "Preferences", directoryHint: .isDirectory)
    }

    private static func removeStalePlists() {
        let manager = FileManager.default
        let directory = preferencesDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-staleAge)
        for entry in entries {
            let fileName = entry.lastPathComponent
            guard fileName.hasPrefix(prefix), fileName.hasSuffix(".plist") else { continue }
            let values = try? entry.resourceValues(forKeys: Set(keys))
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    private static func removeRecordedSuites() {
        let names = recordedNames.withLock { $0 }
        let manager = FileManager.default
        let directory = preferencesDirectory
        for name in names {
            // Flush pending writes first, then unlink. Deliberately no removePersistentDomain here:
            // cfprefsd persists that removal asynchronously and recreates an empty plist after the
            // unlink (observed on macOS 26), whereas sync-then-unlink leaves nothing behind.
            CFPreferencesAppSynchronize(name as CFString)
            for suffix in [".plist", ".plist.lockfile", ".lockfile"] {
                let file = directory.appending(path: name + suffix, directoryHint: .notDirectory)
                try? manager.removeItem(at: file)
            }
        }
    }
}
