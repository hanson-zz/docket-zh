import XCTest

/// 充电上限的实际状态：开关是意图，胶囊和说明要看助手和授权。
final class ChargeLimitEffectTests: XCTestCase {
    private let on = ChargeLimitConfig(enabled: true, limit: 80, buffer: 5)
    private let off = ChargeLimitConfig(enabled: false, limit: 80, buffer: 5)
    private let now = Date(timeIntervalSince1970: 10_000)

    private func status(supported: Bool = true, version: Int = ChargeHelperFiles.helperVersion,
                        age: TimeInterval = 5) -> ChargeHelperStatus {
        ChargeHelperStatus(version: version, supported: supported, key: supported ? "CHTE" : nil,
                           inhibited: false, percent: 80, pluggedIn: true,
                           updated: now.addingTimeInterval(-age))
    }

    func testHelperStateFromFilesAndStatus() {
        XCTAssertEqual(ChargeHelperState.resolve(installed: false, status: nil, now: now), .notInstalled)
        XCTAssertEqual(ChargeHelperState.resolve(installed: true, status: nil, now: now), .starting)
        // 状态文件太旧：装了但没在跑。
        XCTAssertEqual(ChargeHelperState.resolve(installed: true, status: status(age: 300), now: now), .starting)
        XCTAssertEqual(ChargeHelperState.resolve(installed: false, status: status(age: 300), now: now), .notInstalled)
        // 助手在按时写状态，哪怕看不到安装文件也算在跑。
        XCTAssertEqual(ChargeHelperState.resolve(installed: false, status: status(), now: now), .running)
        XCTAssertEqual(ChargeHelperState.resolve(installed: true, status: status(supported: false), now: now),
                       .unsupported)
        XCTAssertEqual(ChargeHelperState.resolve(installed: true, status: status(version: 0), now: now),
                       .needsUpdate)
    }

    func testEffectiveOnlyWhenRunningUnlockedAndOn() {
        XCTAssertEqual(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .running), .effective)
        XCTAssertTrue(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .running).isEffective)
        XCTAssertFalse(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .running).needsAttention)
    }

    func testSwitchOnButChipCannotControlChargingIsNotEffective() {
        // 截图里的情况：开关开着，芯片接口找不到。
        let effect = ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .unsupported)
        XCTAssertEqual(effect, .unsupported(enabled: true))
        XCTAssertFalse(effect.isEffective)
        XCTAssertTrue(effect.needsAttention)
        XCTAssertEqual(effect.badge?.text, "未生效")
        XCTAssertEqual(effect.badge?.tone, .warning)
        XCTAssertEqual(effect.notice, "当前设备无法控制充电，设置的上限尚未生效。")
        // 关着也要告诉用户这台 Mac 不支持。
        let idle = ChargeLimitEffect.resolve(config: off, unlocked: true, helper: .unsupported)
        XCTAssertEqual(idle, .unsupported(enabled: false))
        XCTAssertEqual(idle.badge?.text, "不支持")
    }

    func testOnButNotYetEffective() {
        XCTAssertEqual(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .starting), .pending(.starting))
        XCTAssertEqual(ChargeLimitEffect.resolve(config: on, unlocked: false, helper: .running), .pending(.locked))
        XCTAssertEqual(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .notInstalled),
                       .needsHelper(update: false))
        XCTAssertEqual(ChargeLimitEffect.resolve(config: on, unlocked: true, helper: .needsUpdate),
                       .needsHelper(update: true))
        for helper: ChargeHelperState in [.starting, .notInstalled, .needsUpdate] {
            let effect = ChargeLimitEffect.resolve(config: on, unlocked: true, helper: helper)
            XCTAssertTrue(effect.needsAttention, "\(helper)")
            XCTAssertNotNil(effect.notice, "\(helper)")
            XCTAssertEqual(effect.badge?.tone, .warning, "\(helper)")
        }
    }

    func testOffOrNoLimitShowsNoBadge() {
        for helper: ChargeHelperState in [.notInstalled, .starting, .needsUpdate, .running] {
            XCTAssertEqual(ChargeLimitEffect.resolve(config: off, unlocked: true, helper: helper), .off)
        }
        let hundred = ChargeLimitConfig(enabled: true, limit: 100, buffer: 5)
        XCTAssertEqual(ChargeLimitEffect.resolve(config: hundred, unlocked: true, helper: .running), .off)
        XCTAssertNil(ChargeLimitEffect.off.badge)
        XCTAssertNil(ChargeLimitEffect.off.notice)
        XCTAssertNil(ChargeLimitEffect.effective.notice)
        XCTAssertEqual(ChargeLimitEffect.effective.badge?.tone, .good)
    }

    func testCompatibilityNoteMentionsTheHelper() {
        XCTAssertTrue(ChargeLimitEffect.compatibilityNote.contains("充电助手"))
    }
}
