import XCTest

/// 钥匙串只读一次：读结果归类、内存缓存、Pro 授权合并成一个项、旧项迁移和写入判断。
final class KeychainCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 读结果归类

    func testClassifyStatuses() {
        XCTAssertEqual(KeychainRead.classify(status: 0, data: Data("abc".utf8)), .found("abc"))
        XCTAssertEqual(KeychainRead.classify(status: -25300, data: nil), .missing)
        // errSecAuthFailed（点了拒绝）、errSecInteractionNotAllowed、errSecUserCanceled
        XCTAssertEqual(KeychainRead.classify(status: -25293, data: nil), .failed(-25293))
        XCTAssertEqual(KeychainRead.classify(status: -25308, data: nil), .failed(-25308))
        XCTAssertEqual(KeychainRead.classify(status: -128, data: nil), .failed(-128))
        // 成功但没有数据或不是文字，当失败处理，不当成没有（不能据此重置试用）。
        XCTAssertEqual(KeychainRead.classify(status: 0, data: nil), .failed(0))
        XCTAssertEqual(KeychainRead.classify(status: 0, data: Data([0xFF, 0xFE])), .failed(0))
    }

    func testReadFlags() {
        XCTAssertEqual(KeychainRead.found("x").value, "x")
        XCTAssertNil(KeychainRead.missing.value)
        XCTAssertNil(KeychainRead.failed(-25293).value)
        XCTAssertTrue(KeychainRead.failed(-25293).isFailed)
        XCTAssertFalse(KeychainRead.missing.isFailed)
        XCTAssertTrue(KeychainRead.found("x").exists)
        XCTAssertTrue(KeychainRead.failed(-25293).exists)
        XCTAssertFalse(KeychainRead.missing.exists)
    }

    // MARK: 内存缓存

    func testCacheReadsKeychainOnlyOnce() {
        var cache = KeychainReadCache()
        var calls = 0
        for _ in 0..<5 {
            XCTAssertEqual(cache.read("token") { calls += 1; return .found("t") }, .found("t"))
        }
        XCTAssertEqual(calls, 1)
    }

    func testCacheRemembersDenialAndDoesNotAskAgain() {
        var cache = KeychainReadCache()
        var calls = 0
        for _ in 0..<3 {
            XCTAssertEqual(cache.read("token") { calls += 1; return .failed(-25293) }, .failed(-25293))
        }
        XCTAssertEqual(calls, 1)
    }

    func testLockedKeychainIsNotRememberedAndIsReadAgain() {
        // errSecInteractionNotAllowed：钥匙串锁着、系统没弹框，不是用户拒绝。
        XCTAssertTrue(KeychainRead.failed(-25308).isTransient)
        XCTAssertFalse(KeychainRead.failed(-25293).isTransient)
        XCTAssertFalse(KeychainRead.failed(-128).isTransient)
        XCTAssertFalse(KeychainRead.missing.isTransient)
        XCTAssertFalse(KeychainRead.found("x").isTransient)
        var cache = KeychainReadCache()
        var calls = 0
        XCTAssertEqual(cache.read("token") { calls += 1; return .failed(-25308) }, .failed(-25308))
        XCTAssertNil(cache.cached("token"), "锁着时读不到不记住")
        // 解锁后再用到：重新读一次，读到了就记住。
        XCTAssertEqual(cache.read("token") { calls += 1; return .found("t") }, .found("t"))
        XCTAssertEqual(cache.read("token") { calls += 1; return .found("other") }, .found("t"))
        XCTAssertEqual(calls, 2)
    }

    func testCacheKeepsNamesApart() {
        var cache = KeychainReadCache()
        XCTAssertEqual(cache.read("a") { .found("1") }, .found("1"))
        XCTAssertEqual(cache.read("b") { .missing }, .missing)
        XCTAssertEqual(cache.cached("a"), .found("1"))
        XCTAssertEqual(cache.cached("b"), .missing)
        XCTAssertNil(cache.cached("c"))
    }

    func testCacheWriteAndDelete() {
        var cache = KeychainReadCache()
        XCTAssertTrue(cache.needsWrite("k1", for: "openai"))
        cache.wrote("k1", for: "openai", succeeded: true)
        XCTAssertFalse(cache.needsWrite("k1", for: "openai"))
        XCTAssertTrue(cache.needsWrite("k2", for: "openai"))
        // 写失败不动原来的结果。
        cache.wrote("k2", for: "openai", succeeded: false)
        XCTAssertEqual(cache.cached("openai"), .found("k1"))
        // 写成功会覆盖之前记住的拒绝，之后直接用新值，不再读钥匙串。
        _ = cache.read("gh") { .failed(-25293) }
        cache.wrote("tok", for: "gh", succeeded: true)
        var calls = 0
        XCTAssertEqual(cache.read("gh") { calls += 1; return .missing }, .found("tok"))
        XCTAssertEqual(calls, 0)
        cache.deleted("gh")
        XCTAssertEqual(cache.cached("gh"), .missing)
        XCTAssertTrue(cache.needsWrite("tok", for: "gh"))
    }

    // MARK: 合并项

    func testRecordRoundTrip() {
        let snapshot = ProLicenseSnapshot(licenseKey: "ABCD-1234", instanceID: "inst_1",
                                          lastValidated: now, trialStart: now - 86_400 * 3)
        let text = ProLicenseRecord.encode(snapshot)
        XCTAssertEqual(ProLicenseRecord.decode(text), snapshot)
        XCTAssertFalse(text.contains("\n"))
    }

    func testRecordRoundTripEmptyAndFractionalDates() {
        XCTAssertEqual(ProLicenseRecord.decode(ProLicenseRecord.encode(ProLicenseSnapshot())), ProLicenseSnapshot())
        let odd = ProLicenseSnapshot(trialStart: Date(timeIntervalSince1970: 1_761_446_400.123456))
        XCTAssertEqual(ProLicenseRecord.decode(ProLicenseRecord.encode(odd)), odd)
    }

    func testRecordRejectsGarbage() {
        XCTAssertNil(ProLicenseRecord.decode(""))
        XCTAssertNil(ProLicenseRecord.decode("not json"))
        XCTAssertNil(ProLicenseRecord.decode("[1,2]"))
    }

    func testRecordTreatsEmptyStringsAsMissing() {
        let snapshot = ProLicenseRecord.decode(#"{"version":1,"licenseKey":"","instanceID":""}"#)
        XCTAssertEqual(snapshot, ProLicenseSnapshot())
    }

    // MARK: 读取和迁移

    func testRecordFoundSkipsLegacy() {
        let stored = ProLicenseSnapshot(trialStart: now)
        var legacyCalls = 0
        let load = ProLicenseStorePlan.load(record: .found(ProLicenseRecord.encode(stored))) {
            legacyCalls += 1
            return [:]
        }
        XCTAssertEqual(legacyCalls, 0)
        XCTAssertEqual(load, ProLicenseLoad(snapshot: stored, trusted: true, writeRecord: false, deleteLegacy: false))
    }

    func testFreshInstallWritesNothing() {
        let load = ProLicenseStorePlan.load(record: .missing) { Self.legacy([:]) }
        XCTAssertEqual(load, ProLicenseLoad(snapshot: ProLicenseSnapshot(), trusted: true, writeRecord: false, deleteLegacy: false))
        XCTAssertTrue(ProLicenseStorePlan.canStartTrial(load.snapshot, trusted: load.trusted))
    }

    func testMigratesAllFourLegacyItems() {
        let load = ProLicenseStorePlan.load(record: .missing) {
            Self.legacy([.licenseKey: "KEY", .instanceID: "inst",
                         .lastValidated: String(now.timeIntervalSince1970),
                         .trialStart: String((now - 86_400).timeIntervalSince1970)])
        }
        XCTAssertEqual(load.snapshot, ProLicenseSnapshot(licenseKey: "KEY", instanceID: "inst",
                                                         lastValidated: now, trialStart: now - 86_400))
        XCTAssertTrue(load.trusted)
        XCTAssertTrue(load.writeRecord)
        XCTAssertTrue(load.deleteLegacy)
    }

    func testMigratesTrialOnly() {
        let load = ProLicenseStorePlan.load(record: .missing) {
            Self.legacy([.trialStart: String(now.timeIntervalSince1970)])
        }
        XCTAssertEqual(load.snapshot, ProLicenseSnapshot(trialStart: now))
        XCTAssertTrue(load.writeRecord)
        XCTAssertFalse(ProLicenseStorePlan.canStartTrial(load.snapshot, trusted: load.trusted))
    }

    func testDeniedLegacyReadKeepsLegacyAndBlocksTrialReset() {
        var reads = Self.legacy([.licenseKey: "KEY", .instanceID: "inst"])
        reads[.trialStart] = .failed(-25293)
        let load = ProLicenseStorePlan.load(record: .missing) { reads }
        XCTAssertFalse(load.trusted)
        XCTAssertFalse(load.writeRecord, "读不全时不写新项，否则下次不再读旧项，读不到的那项就丢了")
        XCTAssertFalse(load.deleteLegacy)
        // 读到的部分照用：许可证还在。
        XCTAssertEqual(load.snapshot.licenseKey, "KEY")
        XCTAssertEqual(load.snapshot.instanceID, "inst")
        // 读不到试用开始时间，不能开始新试用。
        XCTAssertFalse(ProLicenseStorePlan.canStartTrial(ProLicenseSnapshot(), trusted: load.trusted))
    }

    func testDeniedRecordReadIsUntrustedAndTouchesNothing() {
        var legacyCalls = 0
        let load = ProLicenseStorePlan.load(record: .failed(-25293)) {
            legacyCalls += 1
            return [:]
        }
        XCTAssertEqual(legacyCalls, 0)
        XCTAssertEqual(load, ProLicenseLoad(snapshot: ProLicenseSnapshot(), trusted: false, writeRecord: false, deleteLegacy: false))
        XCTAssertFalse(ProLicenseStorePlan.canStartTrial(load.snapshot, trusted: load.trusted))
    }

    func testLockedRecordIsRetriedLaterButDenialIsNot() {
        let locked = ProLicenseStorePlan.load(record: .failed(-25308)) { [:] }
        XCTAssertFalse(locked.trusted)
        XCTAssertTrue(locked.retryLater, "钥匙串锁着：下次算状态时再读，不能整次运行都当未激活")
        XCTAssertFalse(ProLicenseStorePlan.canStartTrial(locked.snapshot, trusted: locked.trusted))
        let denied = ProLicenseStorePlan.load(record: .failed(-25293)) { [:] }
        XCTAssertFalse(denied.retryLater, "点了拒绝的这次运行不再问")
    }

    func testLockedLegacyIsRetriedOnlyWhenNothingWasRead() {
        var allLocked: [ProLicenseLegacyField: KeychainRead] = [:]
        for field in ProLicenseLegacyField.allCases { allLocked[field] = .failed(-25308) }
        allLocked[.lastValidated] = .missing
        let locked = ProLicenseStorePlan.load(record: .missing) { allLocked }
        XCTAssertFalse(locked.trusted)
        XCTAssertFalse(locked.writeRecord)
        XCTAssertFalse(locked.deleteLegacy)
        XCTAssertTrue(locked.retryLater)
        // 有一项读出来了（可能是用户点「允许」放行的），重读会再弹：不重试。
        var mixed = allLocked
        mixed[.licenseKey] = .found("KEY")
        XCTAssertFalse(ProLicenseStorePlan.load(record: .missing) { mixed }.retryLater)
        // 有一项是拒绝：不重试。
        var denied = allLocked
        denied[.trialStart] = .failed(-25293)
        XCTAssertFalse(ProLicenseStorePlan.load(record: .missing) { denied }.retryLater)
    }

    func testCorruptRecordFallsBackToLegacy() {
        let load = ProLicenseStorePlan.load(record: .found("garbage")) {
            Self.legacy([.trialStart: String(now.timeIntervalSince1970)])
        }
        XCTAssertEqual(load.snapshot, ProLicenseSnapshot(trialStart: now))
        XCTAssertTrue(load.writeRecord)
    }

    func testLegacyBadNumbersAreIgnored() {
        let load = ProLicenseStorePlan.load(record: .missing) {
            Self.legacy([.licenseKey: "KEY", .lastValidated: "yesterday"])
        }
        XCTAssertEqual(load.snapshot, ProLicenseSnapshot(licenseKey: "KEY"))
        XCTAssertTrue(load.writeRecord)
    }

    // MARK: 写入判断

    func testNeedsWriteOnlyWhenChanged() {
        let a = ProLicenseSnapshot(licenseKey: "K", instanceID: "I", lastValidated: now)
        XCTAssertFalse(ProLicenseStorePlan.needsWrite(current: a, next: a))
        var b = a
        b.lastValidated = now + 1
        XCTAssertTrue(ProLicenseStorePlan.needsWrite(current: a, next: b))
        // 清空一个本来就没有的值不写。
        var c = ProLicenseSnapshot()
        c.instanceID = nil
        XCTAssertFalse(ProLicenseStorePlan.needsWrite(current: ProLicenseSnapshot(), next: c))
    }

    func testPreparedKeepsTrustedValues() {
        let snapshot = ProLicenseSnapshot(licenseKey: "K", instanceID: "I", lastValidated: now)
        XCTAssertEqual(ProLicenseStorePlan.prepared(snapshot, trusted: true), snapshot)
    }

    func testPreparedMarksTrialUsedWhenUntrusted() {
        let activated = ProLicenseSnapshot(licenseKey: "K", instanceID: "I", lastValidated: now)
        let safe = ProLicenseStorePlan.prepared(activated, trusted: false)
        XCTAssertEqual(safe.trialStart, ProLicenseStorePlan.consumedTrialStart)
        XCTAssertEqual(ProLicenseLogic.state(safe, now: now), .pro)
        // 之后解绑，试用不会重新开始。
        var unlinked = safe
        unlinked.licenseKey = nil
        unlinked.instanceID = nil
        XCTAssertEqual(ProLicenseLogic.state(unlinked, now: now), .expiredTrial)
        XCTAssertFalse(ProLicenseLogic.canStartTrial(unlinked))
        // 已知的试用时间不动。
        let known = ProLicenseSnapshot(trialStart: now)
        XCTAssertEqual(ProLicenseStorePlan.prepared(known, trusted: false), known)
    }

    func testLegacyFieldNamesMatchOldAccounts() {
        XCTAssertEqual(ProLicenseLegacyField.allCases.map(\.rawValue),
                       ["licenseKey", "instanceID", "lastValidated", "trialStart"])
    }

    private static func legacy(_ values: [ProLicenseLegacyField: String]) -> [ProLicenseLegacyField: KeychainRead] {
        var reads: [ProLicenseLegacyField: KeychainRead] = [:]
        for field in ProLicenseLegacyField.allCases {
            reads[field] = values[field].map(KeychainRead.found) ?? .missing
        }
        return reads
    }
}
