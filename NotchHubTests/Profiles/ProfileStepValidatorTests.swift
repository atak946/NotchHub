import Foundation
import Testing
@testable import NotchHub

struct ProfileStepValidatorTests {
    private let fileSystem = ProfilesFakeFileSystem(
        directories: ["/w/acme", "/w/plain"],
        files: ["/w/acme/docker-compose.yml", "/w/file.txt"]
    )

    private var validator: ProfileStepValidator { ProfileStepValidator(fileSystem: fileSystem) }

    @Test func acceptsWellFormedBundleID() {
        #expect(validator.validate(.openApp(bundleID: "com.philandro.anydesk")) == nil)
    }

    @Test(arguments: ["", "  ", "noDots", "com.evil;rm", ".leading", "trailing."])
    func rejectsMalformedBundleIDs(_ bundleID: String) {
        #expect(validator.validate(.openApp(bundleID: bundleID)) != nil)
    }

    @Test(arguments: ["https://portal.acme.com/login", "http://10.0.0.5:8080", "rdm://open?DataSource=x", "anydesk:123456789"])
    func acceptsAllowListedURLs(_ url: String) {
        #expect(validator.validate(.openURL(url)) == nil)
    }

    @Test func rejectsDisallowedSchemes() {
        #expect(validator.validate(.openURL("file:///etc/passwd")) == .schemeNotAllowed("file"))
        #expect(validator.validate(.openURL("javascript:alert(1)")) == .schemeNotAllowed("javascript"))
    }

    @Test func rejectsWebURLWithoutHostAndGarbage() {
        #expect(validator.validate(.openURL("https://")) == .missingHost)
        #expect(validator.validate(.openURL("not a url")) == .invalidURL("not a url"))
    }

    @Test func folderStepsRequireExistingAbsoluteDirectory() {
        #expect(validator.validate(.openInVSCode(path: "/w/plain")) == nil)
        #expect(validator.validate(.openTerminal(path: "")) == .emptyPath)
        #expect(validator.validate(.openTerminal(path: "w/plain")) == .relativePath("w/plain"))
        #expect(validator.validate(.openTerminal(path: "/w/missing")) == .folderMissing("/w/missing"))
        #expect(validator.validate(.openTerminal(path: "/w/file.txt")) == .notAFolder("/w/file.txt"))
    }

    @Test func folderPathIsStandardized() {
        #expect(validator.validate(.openInVSCode(path: "/w/plain/../acme/")) == nil)
    }

    @Test func composeStepsNeedComposeFile() {
        #expect(validator.validate(.dockerComposeUp(path: "/w/acme")) == nil)
        #expect(validator.validate(.dockerComposeStop(path: "/w/plain")) == .composeFileMissing("/w/plain"))
    }

    @Test func vpnTimeoutMustBeInRange() {
        #expect(validator.validate(.waitForVPN(timeoutSeconds: 60)) == nil)
        #expect(validator.validate(.waitForVPN(timeoutSeconds: 1)) == .timeoutOutOfRange(1))
        #expect(validator.validate(.waitForVPN(timeoutSeconds: 10_000)) == .timeoutOutOfRange(10_000))
    }

    @Test func templatesForFolderStepsAreInvalidUntilFilled() {
        for kind in ProfileActionKind.allCases {
            let issue = validator.validate(kind.template)
            switch kind {
            case .waitForVPN: #expect(issue == nil)
            default: #expect(issue != nil)
            }
        }
    }
}
