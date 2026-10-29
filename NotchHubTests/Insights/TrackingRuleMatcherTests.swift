import Testing
@testable import NotchHub

struct TrackingRuleMatcherTests {
    private func snapshot(bundle: String? = "com.microsoft.VSCode", title: String? = nil, path: String? = nil) -> ActivitySnapshot {
        ActivitySnapshot(bundleID: bundle, windowTitle: title, documentPath: path, idleSeconds: 0)
    }

    @Test func titleContainsIsCaseInsensitive() {
        let rules = [TrackingRule(client: "Northwind", matchType: .windowTitleContains, pattern: "NorthwindServices")]
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Program.cs — northwindservices"), rules: rules) == "Northwind")
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Other"), rules: rules) == nil)
    }

    @Test func bundleIDMustMatchExactly() {
        let rules = [TrackingRule(client: "Ops", matchType: .appBundleID, pattern: "com.microsoft.vscode")]
        #expect(TrackingRuleMatcher.client(for: snapshot(), rules: rules) == "Ops")
        #expect(TrackingRuleMatcher.client(for: snapshot(bundle: "com.microsoft.VSCodeInsiders"), rules: rules) == nil)
    }

    @Test func specificMatchTypesWinOverListOrder() {
        let rules = [
            TrackingRule(client: "AppRule", matchType: .appBundleID, pattern: "com.microsoft.VSCode"),
            TrackingRule(client: "TitleRule", matchType: .windowTitleContains, pattern: "Globex"),
            TrackingRule(client: "PathRule", matchType: .pathContains, pattern: "/clients/northwind/"),
        ]
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Globex", path: "/Users/me/clients/northwind/a.cs"), rules: rules) == "PathRule")
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Globex"), rules: rules) == "TitleRule")
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Welcome"), rules: rules) == "AppRule")
    }

    @Test func listOrderBreaksTiesWithinType() {
        let rules = [
            TrackingRule(client: "First", matchType: .windowTitleContains, pattern: "API"),
            TrackingRule(client: "Second", matchType: .windowTitleContains, pattern: "Northwind API"),
        ]
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "Northwind API"), rules: rules) == "First")
    }

    @Test func pathRuleFallsBackToTitle() {
        let rules = [TrackingRule(client: "Northwind", matchType: .pathContains, pattern: "~/src/northwind")]
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "zsh — ~/src/northwind"), rules: rules) == "Northwind")
    }

    @Test func invalidRulesAreIgnoredAndClientIsTrimmed() {
        let rules = [
            TrackingRule(client: "", matchType: .windowTitleContains, pattern: "X"),
            TrackingRule(client: "Any", matchType: .windowTitleContains, pattern: "  "),
            TrackingRule(client: " Globex ", matchType: .windowTitleContains, pattern: "X"),
        ]
        #expect(TrackingRuleMatcher.client(for: snapshot(title: "X"), rules: rules) == "Globex")
    }

    @Test func missingWindowInfoOnlyMatchesAppRules() {
        let rules = [
            TrackingRule(client: "Title", matchType: .windowTitleContains, pattern: "a"),
            TrackingRule(client: "App", matchType: .appBundleID, pattern: "com.microsoft.VSCode"),
        ]
        #expect(TrackingRuleMatcher.client(for: snapshot(), rules: rules) == "App")
    }
}
