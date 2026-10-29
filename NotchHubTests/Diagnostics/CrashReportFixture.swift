import Foundation

/// A sanitized, hand-trimmed macOS `.ips` crash report (header line + JSON body).
/// Identifiers are fake; it keeps the fields the parser must ignore so tests can prove they are dropped.
enum CrashReportFixture {
    static let incidentID = "11111111-2222-3333-4444-555555555555"
    static let otherThreadSymbol = "OtherThreadSecretSymbol"
    static let registerValue = "6987650320123"

    static var ips: String { header + "\n" + body }

    static let header = """
    {"app_name":"NotchHub","timestamp":"2026-10-29 19:27:44.00 +0300","app_version":"1.3.2","slice_uuid":"00000000-0000-0000-0000-000000000000","build_version":"5","platform":1,"bundleID":"dev.notchhub.NotchHub","share_with_app_devs":0,"is_first_party":0,"bug_type":"309","os_version":"macOS 26.6.2 (25G83)","roots_installed":0,"name":"NotchHub","incident_id":"\(incidentID)"}
    """

    static var body: String {
        """
        {
          "uptime": 1000,
          "userID": 501,
          "modelCode": "Mac15,6",
          "cpuType": "ARM-64",
          "incident": "\(incidentID)",
          "crashReporterKey": "AAAABBBBCCCCDDDD",
          "procPath": "/Users/sample/Applications/NotchHub.app/Contents/MacOS/NotchHub",
          "bundleInfo": {"CFBundleShortVersionString": "1.3.2", "CFBundleVersion": "5"},
          "exception": {"codes": "0x0000000000000001, 0x00000001a07f1510", "rawCodes": [1, 6987650320], "type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
          "faultingThread": 1,
          "threads": [
            {"id": 1, "frames": [{"imageOffset": 10, "symbol": "\(otherThreadSymbol)", "symbolLocation": 1, "imageIndex": 0}]},
            {"id": 2, "triggered": true, "threadState": {"x": [{"value": \(registerValue)}]}, "frames": \(frames)}
          ],
          "usedImages": [
            {"name": "libswiftCore.dylib", "path": "/usr/lib/swift/libswiftCore.dylib", "arch": "arm64e"},
            {"path": "/Users/sample/Applications/NotchHub.app/Contents/MacOS/NotchHub", "arch": "arm64"}
          ]
        }
        """
    }

    /// 20 frames: two symbolicated system frames, then unsymbolicated app frames.
    static var frames: String {
        let system = [
            #"{"imageOffset": 1451280, "symbol": "closure #1 in _assertionFailure(_:_:file:line:flags:)", "symbolLocation": 400, "imageIndex": 0}"#,
            #"{"imageOffset": 62588, "symbol": "Array._checkSubscript(_:wasNativeTypeChecked:)", "symbolLocation": 160, "imageIndex": 0}"#,
        ]
        let app = (0..<18).map { #"{"imageOffset": \#(4096 + $0), "imageIndex": 1}"# }
        return "[" + (system + app).joined(separator: ",") + "]"
    }
}
