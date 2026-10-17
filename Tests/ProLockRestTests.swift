import XCTest

/// 补齐的 Pro 锁：快速开关的 Pro 工具、AI 刘海对话、充电上限，以及试用到期提醒。
final class ProLockRestTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 快速开关

    func testProToolsLockedOnlyWhenNotUnlocked() {
        for tool in QuickToggle.allCases {
            let isPro = ProFeatures.proTools.contains(tool)
            XCTAssertEqual(ProLicenseGate.isToolLocked(tool, unlocked: false), isPro, "\(tool)")
            XCTAssertFalse(ProLicenseGate.isToolLocked(tool, unlocked: true), "\(tool)")
            XCTAssertEqual(ProLicenseGate.canUseTool(tool, isOn: false, unlocked: false), !isPro, "\(tool)")
            XCTAssertTrue(ProLicenseGate.canUseTool(tool, isOn: false, unlocked: true), "\(tool)")
        }
    }

    func testTheFiveProToolsAreTheOnesLocked() {
        let locked = Set(QuickToggle.allCases.filter { ProLicenseGate.isToolLocked($0, unlocked: false) })
        XCTAssertEqual(locked, [.textCapture, .qrCode, .presentation, .keyboardLock, .lowPower])
    }

    func testAToolLeftOnCanStillBeTurnedOff() {
        // 试用中打开的演示模式，到期后还能点一下关掉。
        XCTAssertTrue(ProLicenseGate.canUseTool(.presentation, isOn: true, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseTool(.keyboardLock, isOn: true, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseTool(.lowPower, isOn: true, unlocked: false))
        // 一次性动作没有“开着”的说法。
        XCTAssertFalse(ProLicenseGate.canUseTool(.textCapture, isOn: true, unlocked: false))
        XCTAssertFalse(ProLicenseGate.canUseTool(.qrCode, isOn: true, unlocked: false))
    }

    func testSettingsCheckboxForProToolNeedsUnlock() {
        let key = QuickToggle.key
        XCTAssertFalse(ProLicenseGate.canEnableListChoice(key: key, value: "textCapture", unlocked: false))
        XCTAssertTrue(ProLicenseGate.canEnableListChoice(key: key, value: "textCapture", unlocked: true))
        XCTAssertTrue(ProLicenseGate.canEnableListChoice(key: key, value: "darkMode", unlocked: false))
        XCTAssertTrue(ProLicenseGate.canEnableListChoice(key: "metrics", value: "textCapture", unlocked: false))
    }

    // MARK: AI 刘海对话

    func testAINotchNeedsUnlock() {
        XCTAssertFalse(ProLicenseGate.canOpenAINotch(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canOpenAINotch(unlocked: true))
        XCTAssertFalse(ProLicenseGate.canUse(.aiNotch, unlocked: false))
    }

    // MARK: 充电上限

    func testChargeLimitStopsWhenLockedAndComesBack() {
        let wanted = ChargeLimitConfig(enabled: true, limit: 80, buffer: 5)
        let locked = ProLicenseGate.chargeLimitConfig(wanted, unlocked: false)
        XCTAssertFalse(locked.enabled)
        XCTAssertFalse(locked.isActive)
        XCTAssertEqual(locked.limit, 80, "上限和缓冲保留")
        XCTAssertEqual(locked.buffer, 5)
        // 锁着时助手不暂停充电，哪怕已经到了上限、之前正暂停着。
        XCTAssertFalse(ChargeLimitPolicy.shouldInhibit(percent: 95, config: locked, currentlyInhibited: true))
        let unlocked = ProLicenseGate.chargeLimitConfig(wanted, unlocked: true)
        XCTAssertEqual(unlocked, wanted)
        XCTAssertTrue(ChargeLimitPolicy.shouldInhibit(percent: 95, config: unlocked, currentlyInhibited: false))
    }

    func testChargeLimitOffStaysOff() {
        let off = ChargeLimitConfig(enabled: false, limit: 70, buffer: 3)
        XCTAssertFalse(ProLicenseGate.chargeLimitConfig(off, unlocked: true).enabled)
        XCTAssertFalse(ProLicenseGate.chargeLimitConfig(off, unlocked: false).enabled)
    }

    // MARK: 试用到期提醒

    func testNoReminderEarlyInTrial() {
        for days in 2...7 {
            XCTAssertNil(ProTrialReminder.due(state: .trial(daysLeft: days), supporter: false, shown: []), "\(days)")
        }
        XCTAssertNil(ProTrialReminder.due(state: .free, supporter: false, shown: []))
        XCTAssertNil(ProTrialReminder.due(state: .pro, supporter: false, shown: []))
    }

    func testLastDayRemindsOnce() {
        XCTAssertEqual(ProTrialReminder.due(state: .trial(daysLeft: 1), supporter: false, shown: []), .lastDay)
        let shown = ProTrialReminder.marking(.lastDay, in: [])
        XCTAssertNil(ProTrialReminder.due(state: .trial(daysLeft: 1), supporter: false, shown: shown))
    }

    func testExpiredRemindsOnceEvenAfterLastDay() {
        let afterLastDay = ProTrialReminder.marking(.lastDay, in: [])
        XCTAssertEqual(ProTrialReminder.due(state: .expiredTrial, supporter: false, shown: afterLastDay), .expired)
        let shown = ProTrialReminder.marking(.expired, in: afterLastDay)
        XCTAssertNil(ProTrialReminder.due(state: .expiredTrial, supporter: false, shown: shown))
    }

    func testSkippedLastDayOnlyShowsExpired() {
        // 最后一天没开码头，直接到期：只弹到期那条，之后也不补“剩 1 天”。
        XCTAssertEqual(ProTrialReminder.due(state: .expiredTrial, supporter: false, shown: []), .expired)
        let shown = ProTrialReminder.marking(.expired, in: [])
        XCTAssertEqual(shown, [.lastDay, .expired])
        XCTAssertNil(ProTrialReminder.due(state: .trial(daysLeft: 1), supporter: false, shown: shown))
    }

    func testSupporterAndActivatedNeverReminded() {
        XCTAssertNil(ProTrialReminder.due(state: .trial(daysLeft: 1), supporter: true, shown: []))
        XCTAssertNil(ProTrialReminder.due(state: .expiredTrial, supporter: true, shown: []))
        XCTAssertNil(ProTrialReminder.due(state: .pro, supporter: false, shown: []))
    }

    func testRemindersFollowTheTrialClock() {
        let snapshot = ProLicenseSnapshot(trialStart: now)
        func due(after days: Double, shown: Set<ProTrialReminder> = []) -> ProTrialReminder? {
            ProTrialReminder.due(state: ProLicenseLogic.state(snapshot, now: now + day * days),
                                 supporter: false, shown: shown)
        }
        XCTAssertNil(due(after: 0))
        XCTAssertNil(due(after: 5.9))
        XCTAssertEqual(due(after: 6), .lastDay)
        XCTAssertEqual(due(after: 6.99), .lastDay)
        XCTAssertEqual(due(after: 7), .expired)
        XCTAssertEqual(due(after: 30), .expired)
        // 激活后就算试用早过了也不提醒。
        let activated = ProLicenseSnapshot(licenseKey: "k", instanceID: "i", lastValidated: now + day * 8, trialStart: now)
        XCTAssertNil(ProTrialReminder.due(state: ProLicenseLogic.state(activated, now: now + day * 8),
                                          supporter: false, shown: []))
    }

    func testShownRoundTripsThroughDefaults() {
        let shown: Set<ProTrialReminder> = [.expired, .lastDay]
        XCTAssertEqual(ProTrialReminder.encode(shown), ["expired", "lastDay"])
        XCTAssertEqual(ProTrialReminder.decode(["lastDay", "bogus"]), [.lastDay])
        XCTAssertEqual(ProTrialReminder.decode(ProTrialReminder.encode(shown)), shown)
    }

    func testReminderTextMentionsBuyingOrCode() {
        XCTAssertTrue(ProTrialReminder.expired.message.contains("兑换码"))
        XCTAssertTrue(ProTrialReminder.lastDay.message.contains("兑换码"))
        XCTAssertTrue(ProTrialReminder.expired.actionTitle.contains("兑换码"))
        XCTAssertFalse(ProTrialReminder.lastDay.title.isEmpty)
    }
}
