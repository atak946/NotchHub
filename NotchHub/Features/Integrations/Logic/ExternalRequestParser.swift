import Foundation

/// Parses and validates `notchhub://` URLs and newline-delimited JSON socket requests.
///
/// URL: `notchhub://alert?title=…&subtitle=…&style=info|reminder|success|urgent&icon=<SF Symbol>`
/// `&duration=<sec|0=sticky>&key=<coalescing>&open=<url>` (+ `command`, `exit`, `elapsed` for finished commands)
/// and `notchhub://open?module=shelf|media|timer|calendar|status`.
/// JSON: `{"action":"alert","title":"…",…}` with the same field names (`action` defaults to `alert`).
enum ExternalRequestParser {
    static let scheme = "notchhub"
    static let maxURLLength = 4096
    static let maxJSONLength = 8192
    static let maxFieldCount = 16
    static let defaultDuration: Duration = NotchAlert.defaultDuration
    static let maxDurationSeconds: Double = 3600
    static let maxElapsedSeconds: Double = 60 * 60 * 24 * 30
    static let exitCodeRange = -255...255

    private static let maxReportedNameLength = 32

    enum Action: String, Sendable {
        case alert
        case open
    }

    enum Field: String, CaseIterable, Sendable {
        case action, title, subtitle, style, icon, duration, key, open, module, command, exit, elapsed
    }

    typealias Outcome = Result<ExternalParseResult, ExternalRequestError>

    static func parse(url: URL) -> Outcome {
        guard url.scheme?.lowercased() == scheme else { return .failure(.notNotchHubURL) }
        guard url.absoluteString.count <= maxURLLength else { return .failure(.payloadTooLarge) }
        let actionName = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var warnings: [String] = []
        var fields: [String: String] = [:]
        for item in items {
            if fields[item.name] != nil {
                warnings.append("Ignored duplicate parameter '\(reportable(item.name))'")
                continue
            }
            fields[item.name] = item.value ?? ""
        }
        return parse(actionName: actionName, fields: fields, warnings: warnings)
    }

    static func parse(jsonLine: String) -> Outcome {
        guard jsonLine.utf8.count <= maxJSONLength else { return .failure(.payloadTooLarge) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(jsonLine.utf8)),
              let dictionary = object as? [String: Any]
        else { return .failure(.invalidJSON) }

        var warnings: [String] = []
        var fields: [String: String] = [:]
        for (name, value) in dictionary {
            guard let text = scalarText(value) else {
                warnings.append("Ignored non-scalar field '\(reportable(name))'")
                continue
            }
            fields[name] = text
        }
        let actionName = (fields.removeValue(forKey: Field.action.rawValue) ?? Action.alert.rawValue).lowercased()
        return parse(actionName: actionName, fields: fields, warnings: warnings)
    }

    // MARK: - Shared validation

    private static func parse(actionName: String, fields: [String: String], warnings: [String]) -> Outcome {
        guard let action = Action(rawValue: actionName) else {
            return .failure(.unknownAction(reportable(actionName)))
        }
        guard fields.count <= maxFieldCount else { return .failure(.payloadTooLarge) }

        var warnings = warnings
        let allowed = allowedFields(for: action)
        for name in fields.keys.sorted() where !allowed.contains(name) {
            warnings.append("Ignored unknown parameter '\(reportable(name))'")
        }
        let known = fields.filter { allowed.contains($0.key) }

        switch action {
        case .open:
            return parseOpen(known).map { ExternalParseResult(request: .open($0), warnings: warnings) }
        case .alert:
            return parseAlert(known, warnings: &warnings).map {
                ExternalParseResult(request: .alert($0), warnings: warnings)
            }
        }
    }

    private static func allowedFields(for action: Action) -> Set<String> {
        switch action {
        case .open: [Field.module.rawValue]
        case .alert: Set(Field.allCases.map(\.rawValue)).subtracting([Field.action.rawValue, Field.module.rawValue])
        }
    }

    private static func parseOpen(_ fields: [String: String]) -> Result<IntegrationsOpenTarget, ExternalRequestError> {
        let raw = fields[Field.module.rawValue] ?? ""
        guard let target = IntegrationsOpenTarget(rawValue: raw.lowercased()) else {
            return .failure(.invalidModule(reportable(raw)))
        }
        return .success(target)
    }

    private static func parseAlert(
        _ fields: [String: String],
        warnings: inout [String]
    ) -> Result<ExternalAlertRequest, ExternalRequestError> {
        let command: ExternalCommandResult?
        switch parseCommand(fields) {
        case .success(let value): command = value
        case .failure(let error): return .failure(error)
        }

        let style: ExternalAlertStyle
        if let rawStyle = fields[Field.style.rawValue] {
            guard let parsed = ExternalAlertStyle(rawValue: rawStyle.lowercased()) else {
                return .failure(.invalidStyle(reportable(rawStyle)))
            }
            style = parsed
        } else {
            style = command.map(CommandFinishedFormatter.style(for:)) ?? .info
        }

        let explicitTitle = fields[Field.title.rawValue].flatMap {
            ExternalAlertSanitizer.displayText($0, maxLength: ExternalAlertSanitizer.maxTitleLength)
        }
        guard let title = explicitTitle ?? command.map(CommandFinishedFormatter.title(for:)) else {
            return .failure(.missingTitle)
        }

        let duration: Duration?
        switch parseDuration(fields[Field.duration.rawValue], warnings: &warnings) {
        case .success(let value): duration = value
        case .failure(let error): return .failure(error)
        }

        return .success(ExternalAlertRequest(
            title: title,
            subtitle: fields[Field.subtitle.rawValue].flatMap {
                ExternalAlertSanitizer.displayText($0, maxLength: ExternalAlertSanitizer.maxSubtitleLength)
            },
            style: style,
            systemImage: symbol(fields[Field.icon.rawValue], style: style, command: command, warnings: &warnings),
            autoDismissAfter: duration,
            coalescingKey: key(fields[Field.key.rawValue], warnings: &warnings),
            openURL: openURL(fields[Field.open.rawValue], warnings: &warnings),
            command: command
        ))
    }

    private static func parseCommand(_ fields: [String: String]) -> Result<ExternalCommandResult?, ExternalRequestError> {
        let rawCommand = fields[Field.command.rawValue]
        let rawExit = fields[Field.exit.rawValue]
        guard rawCommand != nil || rawExit != nil else { return .success(nil) }

        var exitCode = 0
        if let rawExit {
            guard let value = Int(rawExit.trimmingCharacters(in: .whitespaces)), exitCodeRange.contains(value) else {
                return .failure(.invalidExitCode(reportable(rawExit)))
            }
            exitCode = value
        }

        var elapsed: TimeInterval = 0
        if let rawElapsed = fields[Field.elapsed.rawValue] {
            guard let value = Double(rawElapsed.trimmingCharacters(in: .whitespaces)), value.isFinite,
                  value >= 0, value <= maxElapsedSeconds
            else { return .failure(.invalidElapsed(reportable(rawElapsed))) }
            elapsed = value
        }

        let commandLine = rawCommand.flatMap {
            ExternalAlertSanitizer.displayText($0, maxLength: ExternalAlertSanitizer.maxCommandLength)
        } ?? ""
        return .success(ExternalCommandResult(commandLine: commandLine, exitCode: exitCode, elapsed: elapsed))
    }

    private static func parseDuration(
        _ raw: String?,
        warnings: inout [String]
    ) -> Result<Duration?, ExternalRequestError> {
        guard let raw else { return .success(defaultDuration) }
        guard let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 else {
            return .failure(.invalidDuration(reportable(raw)))
        }
        if seconds == 0 { return .success(nil) }
        if seconds > maxDurationSeconds {
            warnings.append("Duration clamped to \(Int(maxDurationSeconds))s")
            return .success(.seconds(maxDurationSeconds))
        }
        return .success(.milliseconds(Int64((seconds * 1000).rounded())))
    }

    private static func symbol(
        _ raw: String?,
        style: ExternalAlertStyle,
        command: ExternalCommandResult?,
        warnings: inout [String]
    ) -> String {
        guard let raw else {
            return command.map(CommandFinishedFormatter.systemImage(for:)) ?? style.defaultSystemImage
        }
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard ExternalAlertSanitizer.isPlausibleSymbolName(name) else {
            warnings.append("Invalid icon '\(reportable(raw))', using '\(ExternalAlertSanitizer.fallbackSymbol)'")
            return ExternalAlertSanitizer.fallbackSymbol
        }
        return name
    }

    private static func key(_ raw: String?, warnings: inout [String]) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let key = ExternalAlertSanitizer.coalescingKey(raw) else {
            warnings.append("Ignored invalid key")
            return nil
        }
        if key != ExternalAlertSanitizer.keyNamespace + raw {
            warnings.append("Key sanitized to '\(key.dropFirst(ExternalAlertSanitizer.keyNamespace.count))'")
        }
        return key
    }

    private static func openURL(_ raw: String?, warnings: inout [String]) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let url = ExternalAlertSanitizer.openURL(raw) else {
            warnings.append("Ignored open URL (only http, https and file URLs are allowed)")
            return nil
        }
        return url
    }

    /// JSON strings, numbers and booleans become text; arrays, objects and null are rejected.
    private static func scalarText(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return nil
    }

    /// Echo-safe version of untrusted text for warnings and errors.
    private static func reportable(_ text: String) -> String {
        ExternalAlertSanitizer.displayText(text, maxLength: maxReportedNameLength) ?? ""
    }
}
