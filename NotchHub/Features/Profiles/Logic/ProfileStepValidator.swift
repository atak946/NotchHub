import Foundation

enum ProfileStepIssue: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyBundleID
    case invalidBundleID(String)
    case invalidURL(String)
    case schemeNotAllowed(String)
    case missingHost
    case emptyPath
    case relativePath(String)
    case folderMissing(String)
    case notAFolder(String)
    case composeFileMissing(String)
    case timeoutOutOfRange(Int)

    var description: String {
        switch self {
        case .emptyBundleID: String(localized: "Bundle kimliği boş")
        case let .invalidBundleID(value): String(localized: "“\(value)” geçerli bir bundle kimliği değil")
        case let .invalidURL(value): String(localized: "“\(value)” geçerli bir URL değil")
        case let .schemeNotAllowed(scheme): String(localized: "“\(scheme)” URL şemasına izin verilmiyor")
        case .missingHost: String(localized: "Web URL'sinde ana makine yok")
        case .emptyPath: String(localized: "Klasör seçilmedi")
        case let .relativePath(path): String(localized: "“\(path)” mutlak bir yol değil")
        case let .folderMissing(path): String(localized: "Klasör yok: \(path)")
        case let .notAFolder(path): String(localized: "Klasör değil: \(path)")
        case let .composeFileMissing(path): String(localized: "\(path) içinde compose dosyası yok")
        case let .timeoutOutOfRange(value): String(localized: "VPN zaman aşımı \(value) sn aralık dışında")
        }
    }
}

/// Pure validation of a step before it runs. Never touches anything but the injected file system.
struct ProfileStepValidator: Sendable {
    static let webSchemes: Set<String> = ["http", "https"]
    /// App URL schemes a profile may open. `file`, `javascript`, `data` etc. are deliberately absent.
    static let appSchemes: Set<String> = [
        "rdm", "anydesk", "vscode", "rdp", "ssh", "vnc", "msteams", "zoommtg", "slack", "teams",
    ]
    static let allowedSchemes = webSchemes.union(appSchemes)
    static let composeFileNames = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]
    static let vpnTimeoutRange = 5...600
    static let maxURLLength = 2048

    private static let bundleIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    )

    let fileSystem: any ProfilesFileSystem

    init(fileSystem: any ProfilesFileSystem = LiveProfilesFileSystem()) {
        self.fileSystem = fileSystem
    }

    func validate(_ action: ProfileAction) -> ProfileStepIssue? {
        switch action {
        case let .openApp(bundleID):
            validateBundleID(bundleID)
        case let .openURL(string):
            validateURL(string).profilesFailure
        case let .openInVSCode(path), let .openTerminal(path):
            validateFolder(path).profilesFailure
        case let .dockerComposeUp(path), let .dockerComposeStop(path):
            validateComposeFolder(path).profilesFailure
        case let .waitForVPN(timeout):
            Self.vpnTimeoutRange.contains(timeout) ? nil : .timeoutOutOfRange(timeout)
        }
    }

    func validateBundleID(_ bundleID: String) -> ProfileStepIssue? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .emptyBundleID }
        let isWellFormed = trimmed.unicodeScalars.allSatisfy { Self.bundleIDCharacters.contains($0) }
            && trimmed.contains(".")
            && !trimmed.hasPrefix(".")
            && !trimmed.hasSuffix(".")
        return isWellFormed ? nil : .invalidBundleID(trimmed)
    }

    func validateURL(_ string: String) -> Result<URL, ProfileStepIssue> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxURLLength,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), !scheme.isEmpty
        else { return .failure(.invalidURL(trimmed)) }
        guard Self.allowedSchemes.contains(scheme) else { return .failure(.schemeNotAllowed(scheme)) }
        if Self.webSchemes.contains(scheme), (url.host() ?? "").isEmpty {
            return .failure(.missingHost)
        }
        return .success(url)
    }

    func validateFolder(_ path: String) -> Result<URL, ProfileStepIssue> {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyPath) }
        guard trimmed.hasPrefix("/") else { return .failure(.relativePath(trimmed)) }
        let standardized = (trimmed as NSString).standardizingPath
        switch fileSystem.itemKind(atPath: standardized) {
        case .missing: return .failure(.folderMissing(standardized))
        case .file: return .failure(.notAFolder(standardized))
        case .directory: return .success(URL(filePath: standardized, directoryHint: .isDirectory))
        }
    }

    func validateComposeFolder(_ path: String) -> Result<URL, ProfileStepIssue> {
        validateFolder(path).flatMap { folder in
            let folderPath = (folder.path(percentEncoded: false) as NSString).standardizingPath
            return hasComposeFile(in: folderPath) ? .success(folder) : .failure(.composeFileMissing(folderPath))
        }
    }

    func hasComposeFile(in folderPath: String) -> Bool {
        Self.composeFileNames.contains { name in
            fileSystem.itemKind(atPath: (folderPath as NSString).appendingPathComponent(name)) == .file
        }
    }
}

extension Result {
    var profilesFailure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
