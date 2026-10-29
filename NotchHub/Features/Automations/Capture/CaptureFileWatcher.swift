import CoreServices
import Foundation
import OSLog

/// Delivers file-level events for a set of folders on the main actor.
@MainActor
protocol CaptureFileWatching: AnyObject {
    /// Returns `false` when the stream could not be created or started.
    func start(paths: [String], handler: @escaping @MainActor ([CaptureFileEvent]) -> Void) -> Bool
    func stop()
}

/// `FSEventStream` with `kFSEventStreamCreateFlagFileEvents`, scheduled on the main queue.
@MainActor
final class FSEventsCaptureWatcher: CaptureFileWatching {
    static let latency: CFTimeInterval = 0.3

    /// Retained by the stream context; forwards callbacks to the handler.
    @MainActor
    private final class Box {
        let handler: @MainActor ([CaptureFileEvent]) -> Void

        init(handler: @escaping @MainActor ([CaptureFileEvent]) -> Void) {
            self.handler = handler
        }
    }

    private var stream: FSEventStreamRef?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CaptureCatcher")

    func start(paths: [String], handler: @escaping @MainActor ([CaptureFileEvent]) -> Void) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        let box = Box(handler: handler)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<AnyObject>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            Unmanaged.passUnretained(box).release()
            logger.error("FSEventStreamCreate failed")
            return false
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            logger.error("FSEventStreamStart failed")
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
        let events = (0..<min(count, pathArray.count)).map { index in
            CaptureFileEvent(path: pathArray[index], flags: FSEventsCaptureWatcher.flags(from: flags[index]))
        }
        // The stream is scheduled on the main queue.
        MainActor.assumeIsolated {
            box.handler(events)
        }
    }

    nonisolated static func flags(from raw: FSEventStreamEventFlags) -> CaptureFileEvent.Flags {
        let mapping: [(Int, CaptureFileEvent.Flags)] = [
            (kFSEventStreamEventFlagItemCreated, .created),
            (kFSEventStreamEventFlagItemRemoved, .removed),
            (kFSEventStreamEventFlagItemRenamed, .renamed),
            (kFSEventStreamEventFlagItemModified, .modified),
            (kFSEventStreamEventFlagItemIsFile, .isFile),
            (kFSEventStreamEventFlagItemIsDir, .isDirectory),
        ]
        return mapping.reduce(into: []) { result, pair in
            if raw & UInt32(pair.0) != 0 { result.insert(pair.1) }
        }
    }
}
