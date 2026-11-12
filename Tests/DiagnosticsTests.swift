import XCTest

/// 导出诊断：剔除敏感键、文件名、崩溃报告挑选、日志截断。
final class DiagnosticsTests: XCTestCase {
    func testSensitiveKeysAreDropped() {
        let domain: [String: Any] = [
            "pro.licenseUnlocked": true,
            "proLicenseKey": "ABCD-1234",
            "apiKey": "sk-123",
            "githubToken": "ghp_x",
            "userEmail": "a@b.com",
            "Password": "hunter2",
            "clientSecret": "s",
            "activationCode": "XYZ",
            "onboarding.seen": true,
            "AppleLanguages": ["zh-Hans"],
            "NSWindow Frame Settings": "0 0 800 600",
        ]
        let clean = Diagnostics.sanitizedDefaults(domain)
        XCTAssertEqual(Set(clean.keys), ["onboarding.seen", "AppleLanguages", "NSWindow Frame Settings"])
    }

    func testSensitiveMatchIsCaseInsensitive() {
        XCTAssertTrue(Diagnostics.isSensitive("LICENSE"))
        XCTAssertTrue(Diagnostics.isSensitive("hotKeyCombo"))
        XCTAssertTrue(Diagnostics.isSensitive("promoCode"))
        XCTAssertFalse(Diagnostics.isSensitive("onboarding.seen"))
        XCTAssertFalse(Diagnostics.isSensitive("checkForUpdates"))
    }

    func testNestedValuesAreCleanedToo() {
        let domain: [String: Any] = [
            "settings": ["token": "t", "size": 2, "inner": ["password": "p", "ok": 1]],
            "list": [["secret": "s", "name": "a"]],
            "contact": "write to me at someone@example.com",
        ]
        let clean = Diagnostics.sanitizedDefaults(domain)
        let settings = clean["settings"] as? [String: Any]
        XCTAssertEqual(settings.map { Set($0.keys) }, ["size", "inner"])
        XCTAssertEqual((settings?["inner"] as? [String: Any]).map { Set($0.keys) }, ["ok"])
        let list = clean["list"] as? [[String: Any]]
        XCTAssertEqual(list?.first.map { Set($0.keys) }, ["name"])
        XCTAssertEqual(clean["contact"] as? String, Diagnostics.redacted)
    }

    func testFileName() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 11
        parts.hour = 22
        parts.minute = 52
        parts.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(Diagnostics.fileName(date: date, english: false, timeZone: zone),
                       "Dockling-诊断-20261111-2252.zip")
        XCTAssertEqual(Diagnostics.fileName(date: date, english: true, timeZone: zone),
                       "Dockling-Diagnostics-20261111-2252.zip")
    }

    func testCrashReportsPickNewestOwnIpsFiles() {
        let now = Date()
        var files: [(name: String, modified: Date)] = (0..<14).map { i in
            ("Dockling-2026-11-\(i).ips", now.addingTimeInterval(Double(-i) * 60))
        }
        files.append(("Safari-2026.ips", now))
        files.append(("Dockling-2026.diag", now))
        files.append(("dockling-lower.ips", now.addingTimeInterval(30)))
        let picked = Diagnostics.crashReports(files, processNames: ["Dockling", ""])
        XCTAssertEqual(picked.count, Diagnostics.crashLimit)
        XCTAssertEqual(picked.first, "dockling-lower.ips")
        XCTAssertFalse(picked.contains("Safari-2026.ips"))
        XCTAssertFalse(picked.contains("Dockling-2026.diag"))
    }

    func testLogKeepsNewestLines() {
        let lines = (0..<6000).map(String.init)
        let trimmed = Diagnostics.trimmedLog(lines)
        XCTAssertEqual(trimmed.count, Diagnostics.logLineLimit)
        XCTAssertEqual(trimmed.last, "5999")
        XCTAssertEqual(Diagnostics.trimmedLog(["a"]), ["a"])
    }

    func testInfoText() {
        let text = Diagnostics.infoText([("App", [("Version", "0.7.0")]), ("Pro", [("Active", "no")])])
        XCTAssertEqual(text, "[App]\nVersion: 0.7.0\n\n[Pro]\nActive: no\n")
    }
}
