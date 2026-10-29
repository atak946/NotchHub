import Testing
@testable import NotchHub

struct TimeCSVExporterTests {
    @Test func headerAndSortedRowsWithCRLF() {
        let csv = TimeCSVExporter.csv(for: [
            TimeLedgerEntry(day: "2026-10-28", client: "Globex", appBundleID: "com.b", seconds: 90),
            TimeLedgerEntry(day: "2026-10-27", client: "Northwind", appBundleID: "com.a", seconds: 3600),
        ])
        #expect(csv == "Tarih,Müşteri,Uygulama,Dakika\r\n2026-10-27,Northwind,com.a,60.0\r\n2026-10-28,Globex,com.b,1.5\r\n")
    }

    @Test func emptyExportHasHeaderOnly() {
        #expect(TimeCSVExporter.csv(for: []) == "Tarih,Müşteri,Uygulama,Dakika\r\n")
    }

    @Test(arguments: [
        ("plain", "plain"),
        ("Acme, Inc", "\"Acme, Inc\""),
        ("The \"Big\" One", "\"The \"\"Big\"\" One\""),
        ("line\nbreak", "\"line\nbreak\""),
        ("=SUM(A1)", "'=SUM(A1)"),
        ("+1", "'+1"),
        ("-x,y", "\"'-x,y\""),
        ("@cmd", "'@cmd"),
        ("", ""),
    ])
    func escapesFields(raw: String, expected: String) {
        #expect(TimeCSVExporter.escape(raw) == expected)
    }

    @Test func minutesUseDotDecimal() {
        #expect(TimeCSVExporter.minutes(45) == "0.8")
        #expect(TimeCSVExporter.minutes(0) == "0.0")
    }
}
