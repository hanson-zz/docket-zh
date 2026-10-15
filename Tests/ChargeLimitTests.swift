import XCTest

/// 充电上限：什么时候暂停、什么时候恢复，以及装助手的脚本。
final class ChargeLimitTests: XCTestCase {
    private let on = ChargeLimitConfig(enabled: true, limit: 80, buffer: 5)

    func testPausesAtTheLimitAndResumesBelowTheBuffer() {
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 70, config: on, currentlyInhibited: false))
        XCTAssertTrue(ChargeLimitPolicy.shouldInhibit(percent: 80, config: on, currentlyInhibited: false))
        XCTAssertTrue(ChargeLimitPolicy.shouldInhibit(percent: 93, config: on, currentlyInhibited: false))
        // 缓冲区里保持原状，不来回开关。
        XCTAssertTrue(ChargeLimitPolicy.shouldInhibit(percent: 77, config: on, currentlyInhibited: true))
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 77, config: on, currentlyInhibited: false))
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 75, config: on, currentlyInhibited: true))
    }

    func testOffOrFullOrUnknownNeverPauses() {
        var off = on
        off.enabled = false
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 99, config: off, currentlyInhibited: true))
        let full = ChargeLimitConfig(enabled: true, limit: 100, buffer: 5)
        XCTAssertFalse(full.isActive)
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 100, config: full, currentlyInhibited: true))
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: nil, config: on, currentlyInhibited: true))
    }

    func testHandEditedValuesAreClamped() {
        let wild = ChargeLimitConfig(enabled: true, limit: 12, buffer: 40).clamped
        XCTAssertEqual(wild.limit, 50)
        XCTAssertEqual(wild.buffer, 10)
        XCTAssertEqual(ChargeLimitConfig(enabled: true, limit: 83, buffer: 1).clamped,
                       ChargeLimitConfig(enabled: true, limit: 80, buffer: 2))
        XCTAssertEqual(ChargeLimitConfig.default.limit, 80)
        XCTAssertFalse(ChargeLimitConfig.default.enabled)
    }

    func testConfigAndStatusRoundTrip() throws {
        let data = try ChargeHelperFiles.encoder().encode(on)
        XCTAssertEqual(try ChargeHelperFiles.decoder().decode(ChargeLimitConfig.self, from: data), on)
        let status = ChargeHelperStatus(version: 1, supported: true, key: "CHTE", inhibited: true,
                                        percent: 80, pluggedIn: true, updated: Date(timeIntervalSince1970: 1000))
        let back = try ChargeHelperFiles.decoder().decode(
            ChargeHelperStatus.self, from: ChargeHelperFiles.encoder().encode(status))
        XCTAssertEqual(back, status)
        XCTAssertTrue(status.isFresh(now: Date(timeIntervalSince1970: 1060)))
        XCTAssertFalse(status.isFresh(now: Date(timeIntervalSince1970: 1200)))
    }

    func testScriptsQuotePathsWithSpacesAndQuotes() {
        XCTAssertEqual(ChargeHelperFiles.shellQuoted("a b"), "'a b'")
        XCTAssertEqual(ChargeHelperFiles.shellQuoted("it's"), "'it'\\''s'")
        let script = ChargeHelperFiles.installScript(helper: "/Applications/My Apps/Dockling.app/Contents/MacOS/dockling-charge-helper",
                                                     plist: "/tmp/x.plist", user: "han")
        XCTAssertTrue(script.contains("'/Applications/My Apps/Dockling.app/Contents/MacOS/dockling-charge-helper'"))
        XCTAssertTrue(script.contains("launchctl bootstrap system"))
        XCTAssertTrue(script.hasPrefix("set -e"))
        XCTAssertTrue(ChargeHelperFiles.uninstallScript().contains("--reset"))
        XCTAssertEqual(ChargeHelperFiles.appleScriptQuoted("say \"hi\" \\"), "say \\\"hi\\\" \\\\")
    }

    func testLaunchdPlistNamesTheInstalledHelper() {
        let plist = ChargeHelperFiles.launchdPlist()
        XCTAssertTrue(plist.contains("<string>\(ChargeHelperFiles.installedPath)</string>"))
        XCTAssertTrue(plist.contains("<string>\(ChargeHelperFiles.label)</string>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
    }
}
