import Foundation

/// The privacy-safe subset of a macOS `.ips` crash report: no other threads, registers,
/// image paths, user paths, device identifiers or incident id.
struct CrashReport: Equatable, Sendable {
    struct Frame: Equatable, Sendable {
        /// Image basename, e.g. `libswiftCore.dylib`.
        let image: String
        let symbol: String?
        /// Offset into `symbol` when symbolicated, otherwise into the image.
        let offset: Int
    }

    let appVersion: String
    let appBuild: String
    let osVersion: String
    let cpuType: String
    let exceptionType: String
    let exceptionSignal: String?
    let exceptionCodes: String?
    let crashedThread: Int
    let frames: [Frame]
}

enum CrashReportParseError: Error, Equatable {
    case missingHeader
    case invalidJSON
    case notACrash
}

/// Parses the two-part `.ips` format: a one-line JSON header followed by a JSON body.
enum CrashReportParser {
    static let maxFrames = 15
    static let unknown = "unknown"

    static func parse(_ text: String) throws -> CrashReport {
        guard let newline = text.firstIndex(of: "\n") else { throw CrashReportParseError.missingHeader }
        let header = try object(from: String(text[..<newline]))
        let body = try object(from: String(text[text.index(after: newline)...]))
        guard let exception = body["exception"] as? [String: Any],
              let exceptionType = exception["type"] as? String
        else { throw CrashReportParseError.notACrash }

        let crashedThread = body["faultingThread"] as? Int ?? 0
        return CrashReport(
            appVersion: string(header["app_version"]) ?? bundleValue(body, "CFBundleShortVersionString") ?? unknown,
            appBuild: string(header["build_version"]) ?? bundleValue(body, "CFBundleVersion") ?? unknown,
            osVersion: string(header["os_version"]) ?? unknown,
            cpuType: string(body["cpuType"]) ?? unknown,
            exceptionType: exceptionType,
            exceptionSignal: string(exception["signal"]),
            exceptionCodes: string(exception["codes"]),
            crashedThread: crashedThread,
            frames: frames(in: body, thread: crashedThread)
        )
    }

    private static func frames(in body: [String: Any], thread index: Int) -> [CrashReport.Frame] {
        guard let threads = body["threads"] as? [[String: Any]],
              threads.indices.contains(index),
              let rawFrames = threads[index]["frames"] as? [[String: Any]]
        else { return [] }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        return rawFrames.prefix(maxFrames).map { frame in
            let symbol = string(frame["symbol"])
            let offset = symbol == nil ? frame["imageOffset"] as? Int : frame["symbolLocation"] as? Int
            return CrashReport.Frame(
                image: imageName(images, frame["imageIndex"] as? Int),
                symbol: symbol,
                offset: offset ?? 0
            )
        }
    }

    /// Only the basename: full image paths can reveal the user's folders.
    private static func imageName(_ images: [[String: Any]], _ index: Int?) -> String {
        guard let index, images.indices.contains(index) else { return "???" }
        if let name = string(images[index]["name"]) { return basename(name) }
        if let path = string(images[index]["path"]) { return basename(path) }
        return "???"
    }

    static func basename(_ path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.isEmpty ? "???" : last
    }

    private static func bundleValue(_ body: [String: Any], _ key: String) -> String? {
        (body["bundleInfo"] as? [String: Any]).flatMap { string($0[key]) }
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func object(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any]
        else { throw CrashReportParseError.invalidJSON }
        return object
    }
}

/// Renders a `CrashReport` as a sanitized GitHub issue body that stays under `maxBodyLength`.
enum CrashReportFormatter {
    static let maxBodyLength = 6000
    static var issueTitle: String { String(localized: "Çökme: ") }
    static var attachInstruction: String {
        String(localized: "NotchHub beklenmedik şekilde kapandı. Tam çökme raporunu (.ips) bu sayfaya sürükleyerek elle ekleyebilirsin.")
    }

    /// The summary block (frames last, so URL-length trimming drops frames first).
    static func summary(_ report: CrashReport, homeDirectory: String, maxLength: Int = maxBodyLength) -> String {
        let headerLines = header(report)
        let frameLines = report.frames.enumerated().map { index, frame in line(index, frame) }
        var kept = frameLines
        while !kept.isEmpty, render(headerLines, kept, dropped: frameLines.count - kept.count, home: homeDirectory).count > maxLength {
            kept.removeLast()
        }
        return render(headerLines, kept, dropped: frameLines.count - kept.count, home: homeDirectory)
    }

    private static func header(_ report: CrashReport) -> [String] {
        let exception = [report.exceptionType, report.exceptionSignal.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
        return [
            "NotchHub \(report.appVersion) (\(report.appBuild))",
            "macOS: \(report.osVersion)",
            "CPU: \(report.cpuType)",
            "Exception: \(exception)",
            "Codes: \(report.exceptionCodes ?? CrashReportParser.unknown)",
            "Crashed thread: \(report.crashedThread)",
        ]
    }

    static func line(_ index: Int, _ frame: CrashReport.Frame) -> String {
        let location = frame.symbol ?? "0x" + String(frame.offset, radix: 16)
        let offset = frame.symbol == nil ? "" : " + \(frame.offset)"
        return "\(index)  \(frame.image)  \(location)\(offset)"
    }

    private static func render(_ header: [String], _ frames: [String], dropped: Int, home: String) -> String {
        let trailer = dropped > 0 ? ["… (\(dropped) more frames truncated)"] : []
        let text = (header + ["Frames:"] + frames + trailer).joined(separator: "\n")
        return DiagnosticsRedactor.redact(text, homeDirectory: home)
    }
}
