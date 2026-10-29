import Foundation
import Testing
@testable import NotchHub

struct IntegrationsURLParserTests {
    @Test func parsesFullAlertURL() throws {
        let url = integrationsURL(
            "notchhub://alert?title=Deploy%20done&subtitle=prod&style=success&icon=hammer.fill"
                + "&duration=12&key=deploy&open=https://example.com/run/1"
        )
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)

        #expect(alert.title == "Deploy done")
        #expect(alert.subtitle == "prod")
        #expect(alert.style == .success)
        #expect(alert.systemImage == "hammer.fill")
        #expect(alert.autoDismissAfter == .seconds(12))
        #expect(alert.coalescingKey == "external.deploy")
        #expect(alert.openURL?.absoluteString == "https://example.com/run/1")
        #expect(alert.command == nil)
    }

    @Test(arguments: ExternalAlertStyle.allCases)
    func acceptsEveryStyle(style: ExternalAlertStyle) throws {
        let url = integrationsURL("notchhub://alert?title=x&style=\(style.rawValue.uppercased())")
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)
        #expect(alert.style == style)
        #expect(alert.systemImage == style.defaultSystemImage)
    }

    @Test func defaultsToInfoWithDefaultDuration() throws {
        let alert = try #require(ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi")).alert)
        #expect(alert.style == .info)
        #expect(alert.autoDismissAfter == NotchAlert.defaultDuration)
        #expect(alert.coalescingKey == nil)
        #expect(alert.subtitle == nil)
    }

    @Test func decodesFullyPercentEncodedValuesFromTheCLI() throws {
        let url = integrationsURL("notchhub://alert?title=%e2%9c%93%20%48%69&style=%73%75%63%63%65%73%73")
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)
        #expect(alert.title == "✓ Hi")
        #expect(alert.style == .success)
    }

    @Test func zeroDurationIsSticky() throws {
        let alert = try #require(
            ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&duration=0")).alert
        )
        #expect(alert.autoDismissAfter == nil)
    }

    @Test func fractionalDurationIsAccepted() throws {
        let alert = try #require(
            ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&duration=1.5")).alert
        )
        #expect(alert.autoDismissAfter == .milliseconds(1500))
    }

    @Test func hugeDurationIsClampedWithWarning() throws {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&duration=99999"))
        #expect(result.alert?.autoDismissAfter == .seconds(3600))
        #expect(result.warnings.contains { $0.contains("clamped") })
    }

    @Test(arguments: ["-1", "abc", "nan", "inf", ""])
    func rejectsBadDuration(value: String) {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&duration=\(value)"))
        #expect(result.error == .invalidDuration(value))
    }

    @Test func rejectsUnknownStyle() {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&style=loud"))
        #expect(result.error == .invalidStyle("loud"))
    }

    @Test(arguments: ["notchhub://alert", "notchhub://alert?title=", "notchhub://alert?title=%20%0A%09"])
    func rejectsMissingOrBlankTitle(url: String) {
        #expect(ExternalRequestParser.parse(url: integrationsURL(url)).error == .missingTitle)
    }

    @Test func rejectsOtherSchemes() {
        #expect(ExternalRequestParser.parse(url: integrationsURL("https://alert?title=x")).error == .notNotchHubURL)
    }

    @Test func rejectsUnknownAction() {
        #expect(ExternalRequestParser.parse(url: integrationsURL("notchhub://delete?title=x")).error
            == .unknownAction("delete"))
    }

    @Test func rejectsOversizedURL() {
        let long = String(repeating: "a", count: ExternalRequestParser.maxURLLength)
        #expect(ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=\(long)")).error
            == .payloadTooLarge)
    }

    @Test func ignoresUnknownParametersWithWarning() throws {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=Hi&color=red&module=timer"))
        #expect(result.alert?.title == "Hi")
        #expect(result.warnings == ["Ignored unknown parameter 'color'", "Ignored unknown parameter 'module'"])
    }

    @Test func keepsFirstOfDuplicateParameters() {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=One&title=Two"))
        #expect(result.alert?.title == "One")
        #expect(result.warnings == ["Ignored duplicate parameter 'title'"])
    }

    @Test func invalidIconFallsBackToBell() {
        for icon in ["Not A Symbol", "..", "bell..fill", "../../etc", "a%2Fb"] {
            let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=x&icon=\(icon.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"))
            #expect(result.alert?.systemImage == "bell", "icon \(icon)")
            #expect(!result.warnings.isEmpty)
        }
    }

    @Test(arguments: ["javascript:alert(1)", "ftp://host/file", "notchhub://alert?title=x", "mailto:a@b.c",
                      "https://", "file:relative/path", "x-apple.systempreferences:"])
    func dropsDisallowedOpenURLs(open: String) {
        let encoded = open.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=x&open=\(encoded)"))
        #expect(result.alert?.openURL == nil)
        #expect(result.warnings.contains { $0.contains("open URL") })
    }

    @Test func acceptsFileOpenURL() throws {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=x&open=file:///tmp/report.html"))
        #expect(result.alert?.openURL?.path == "/tmp/report.html")
    }

    @Test func namespacesAndSanitizesKey() {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?title=x&key=vpn.state%20%2F%3Bx"))
        #expect(result.alert?.coalescingKey == "external.vpn.statex")
        #expect(result.warnings.contains { $0.contains("sanitized") })
    }

    @Test func parsesOpenModule() throws {
        for target in IntegrationsOpenTarget.allCases {
            let result = try ExternalRequestParser.parse(url: integrationsURL("notchhub://open?module=\(target.rawValue)")).get()
            #expect(result.request == .open(target))
        }
    }

    @Test func rejectsUnknownModule() {
        #expect(ExternalRequestParser.parse(url: integrationsURL("notchhub://open?module=finder")).error
            == .invalidModule("finder"))
        #expect(ExternalRequestParser.parse(url: integrationsURL("notchhub://open")).error == .invalidModule(""))
    }

    @Test func commandFieldsBuildTitleStyleAndIcon() throws {
        let url = integrationsURL("notchhub://alert?command=dotnet%20build%20-c%20Release&exit=0&elapsed=72")
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)
        #expect(alert.title == "✓ dotnet build · 1dk 12sn")
        #expect(alert.style == .success)
        #expect(alert.systemImage == CommandFinishedFormatter.successSymbol)
        #expect(alert.command == ExternalCommandResult(commandLine: "dotnet build -c Release", exitCode: 0, elapsed: 72))
    }

    @Test func failedCommandIsUrgent() throws {
        let url = integrationsURL("notchhub://alert?command=npm%20test&exit=1&elapsed=45")
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)
        #expect(alert.title == "✗ npm test başarısız (çıkış 1) · 45sn")
        #expect(alert.style == .urgent)
        #expect(alert.systemImage == CommandFinishedFormatter.failureSymbol)
    }

    @Test func explicitTitleAndStyleWinOverCommand() throws {
        let url = integrationsURL("notchhub://alert?title=Tests&style=reminder&command=npm%20test&exit=1")
        let alert = try #require(ExternalRequestParser.parse(url: url).alert)
        #expect(alert.title == "Tests")
        #expect(alert.style == .reminder)
    }

    @Test(arguments: ["abc", "999", "1.5"])
    func rejectsBadExitCode(value: String) {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?command=make&exit=\(value)"))
        #expect(result.error == .invalidExitCode(value))
    }

    @Test(arguments: ["-3", "x", "1e12"])
    func rejectsBadElapsed(value: String) {
        let result = ExternalRequestParser.parse(url: integrationsURL("notchhub://alert?command=make&elapsed=\(value)"))
        #expect(result.error == .invalidElapsed(value))
    }
}

struct IntegrationsJSONParserTests {
    @Test func parsesAlertLine() throws {
        let line = #"{"title":"Backup","subtitle":"42 GB","style":"success","icon":"hammer.fill","duration":0,"key":"backup"}"#
        let alert = try #require(ExternalRequestParser.parse(jsonLine: line).alert)
        #expect(alert.title == "Backup")
        #expect(alert.subtitle == "42 GB")
        #expect(alert.style == .success)
        #expect(alert.autoDismissAfter == nil)
        #expect(alert.coalescingKey == "external.backup")
    }

    @Test func actionDefaultsToAlertAndSupportsOpen() throws {
        let open = try ExternalRequestParser.parse(jsonLine: #"{"action":"open","module":"calendar"}"#).get()
        #expect(open.request == .open(.calendar))
        #expect(ExternalRequestParser.parse(jsonLine: #"{"action":"wipe","title":"x"}"#).error == .unknownAction("wipe"))
    }

    @Test func numericCommandFields() throws {
        let line = #"{"command":"xcodebuild -scheme App test","exit":65,"elapsed":125.7,"subtitle":"in App"}"#
        let alert = try #require(ExternalRequestParser.parse(jsonLine: line).alert)
        #expect(alert.title == "✗ xcodebuild başarısız (çıkış 65) · 2dk 5sn")
        #expect(alert.subtitle == "in App")
    }

    @Test(arguments: ["", "not json", "[1,2]", "\"title\"", "{\"title\":", "null"])
    func rejectsMalformedJSON(line: String) {
        #expect(ExternalRequestParser.parse(jsonLine: line).error == .invalidJSON)
    }

    @Test func nonScalarFieldsAreIgnoredWithWarning() {
        let result = ExternalRequestParser.parse(jsonLine: #"{"title":"x","subtitle":{"nested":true},"extra":[1]}"#)
        #expect(result.alert?.subtitle == nil)
        #expect(result.warnings.count == 2)
    }

    @Test func booleanStyleIsRejected() {
        #expect(ExternalRequestParser.parse(jsonLine: #"{"title":"x","style":true}"#).error == .invalidStyle("true"))
    }

    @Test func rejectsOversizedLine() {
        let line = #"{"title":""# + String(repeating: "a", count: ExternalRequestParser.maxJSONLength) + #""}"#
        #expect(ExternalRequestParser.parse(jsonLine: line).error == .payloadTooLarge)
    }

    @Test func rejectsTooManyFields() {
        let fields = (0..<20).map { #""f\#($0)":"v""# }.joined(separator: ",")
        #expect(ExternalRequestParser.parse(jsonLine: "{\"title\":\"x\",\(fields)}").error == .payloadTooLarge)
    }

    @Test func injectionStringsAreSanitizedNotExecuted() throws {
        let line = #"{"title":"\u0000rm -rf ~; ‮exe.txt\u0007<script>alert(1)</script>","subtitle":"line1\nline2\r\n\tend"}"#
        let alert = try #require(ExternalRequestParser.parse(jsonLine: line).alert)
        #expect(alert.title == "rm -rf ~; exe.txt<script>alert(1)</script>")
        #expect(alert.subtitle == "line1 line2 end")
    }

    @Test func errorMessagesEchoSanitizedValues() {
        let result = ExternalRequestParser.parse(jsonLine: #"{"title":"x","style":"\u001b[31mred\u001b[0m"}"#)
        guard case .invalidStyle(let echoed) = result.error else {
            Issue.record("expected invalidStyle")
            return
        }
        #expect(!echoed.unicodeScalars.contains { $0.value == 0x1B })
    }
}
