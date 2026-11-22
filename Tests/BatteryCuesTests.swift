import XCTest

/// 电池卡片和面板的小熊猫、蓝牙配件轻提示、底部「更新于」、电量低提醒防反复。
final class BatteryCuesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: 小熊猫常态

    func testLowPandaOnlyBelowTwentyOnBattery() {
        XCTAssertEqual(BatteryPandaCue.base(percent: 19, onPower: false, charging: false), .alert)
        XCTAssertNil(BatteryPandaCue.base(percent: 20, onPower: false, charging: false))
        XCTAssertNil(BatteryPandaCue.base(percent: 12, onPower: true, charging: false))
        XCTAssertNil(BatteryPandaCue.base(percent: 12, onPower: false, charging: true))
        XCTAssertNil(BatteryPandaCue.base(percent: nil, onPower: false, charging: false))
        XCTAssertNil(BatteryPandaCue.base(percent: 80, onPower: false, charging: false))
    }

    func testFullTarget() {
        XCTAssertEqual(BatteryPandaCue.fullTarget(effectiveLimit: nil), 100)
        XCTAssertEqual(BatteryPandaCue.fullTarget(effectiveLimit: 80), 80)
        XCTAssertEqual(BatteryPandaCue.fullTarget(effectiveLimit: 100), 100)
    }

    func testFullPulseLasts() {
        let pulse = BatteryPandaCue.fullPulse(at: t0)
        XCTAssertEqual(pulse.state, .done)
        XCTAssertEqual(pulse.until.timeIntervalSince(pulse.started), PandaMotion.doneHold, accuracy: 0.001)
        XCTAssertTrue(pulse.isActive(at: t0 + 1))
        XCTAssertFalse(pulse.isActive(at: t0 + PandaMotion.doneHold))
    }

    // MARK: 充满挥爪

    func testFullWavesOncePerCharge() {
        var w = BatteryFullWatch()
        XCTAssertFalse(w.update(percent: 60, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 99, onPower: true, target: 100))
        XCTAssertTrue(w.update(percent: 100, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 100, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 99, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 100, onPower: true, target: 100))
    }

    func testFullNotWhenPluggedInAlreadyFullOrAtLaunch() {
        var w = BatteryFullWatch()
        XCTAssertFalse(w.update(percent: 100, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 100, onPower: true, target: 100))
        var u = BatteryFullWatch()
        XCTAssertFalse(u.update(percent: 100, onPower: false, target: 100))
        XCTAssertFalse(u.update(percent: 100, onPower: true, target: 100))
    }

    func testFullAtChargeLimitWithBuffer() {
        var w = BatteryFullWatch()
        XCTAssertFalse(w.update(percent: 50, onPower: true, target: 80))
        XCTAssertTrue(w.update(percent: 80, onPower: true, target: 80))
        // 上限的缓冲区里来回不再挥。
        XCTAssertFalse(w.update(percent: 77, onPower: true, target: 80))
        XCTAssertFalse(w.update(percent: 80, onPower: true, target: 80))
        // 掉到线下 5% 再充回来，算新的一次。
        XCTAssertFalse(w.update(percent: 75, onPower: true, target: 80))
        XCTAssertTrue(w.update(percent: 80, onPower: true, target: 80))
    }

    func testUnplugResets() {
        var w = BatteryFullWatch()
        _ = w.update(percent: 90, onPower: true, target: 100)
        XCTAssertFalse(w.update(percent: 90, onPower: false, target: 100))
        XCTAssertFalse(w.update(percent: 100, onPower: true, target: 100))
        XCTAssertFalse(w.update(percent: 96, onPower: false, target: 100))
        XCTAssertFalse(w.update(percent: 96, onPower: true, target: 100))
        XCTAssertTrue(w.update(percent: 100, onPower: true, target: 100))
    }

    // MARK: 电量低系统通知防反复

    private func low(_ t: inout BatteryAlertTracker, _ percent: Int, power: Bool) -> [String] {
        t.check(BatteryReading(percent: percent, onPower: power), accessories: [],
                settings: BatteryAlertSettings()).filter { $0.id == "low" }.map(\.id)
    }

    func testLowAlertDoesNotRepeatWhenReplugAtThreshold() {
        var t = BatteryAlertTracker()
        _ = low(&t, 40, power: false)
        XCTAssertEqual(low(&t, 20, power: false), ["low"])
        _ = low(&t, 20, power: true)
        XCTAssertEqual(low(&t, 19, power: false), [])
        _ = low(&t, 24, power: true)
        XCTAssertEqual(low(&t, 23, power: false), [])
        XCTAssertEqual(low(&t, 20, power: false), [])
    }

    func testLowAlertRearmsFivePercentAbove() {
        var t = BatteryAlertTracker()
        _ = low(&t, 40, power: false)
        XCTAssertEqual(low(&t, 20, power: false), ["low"])
        _ = low(&t, 25, power: true)
        _ = low(&t, 25, power: false)
        XCTAssertEqual(low(&t, 20, power: false), ["low"])
    }

    func testLowAlertQuietAtLaunchBelowThreshold() {
        var t = BatteryAlertTracker()
        XCTAssertEqual(low(&t, 15, power: false), [])
        XCTAssertEqual(low(&t, 14, power: false), [])
    }

    // MARK: 蓝牙配件轻提示

    private func mouse(_ percent: Int?) -> AccessoryPresence {
        AccessoryPresence(id: "mouse", group: AccessoryPresence.peripheralGroup, percent: percent)
    }

    func testConnectDisconnectAfterWarmup() {
        var t = AccessoryChangeTracker()
        XCTAssertEqual(t.update([], now: t0), [:])
        let later = t0 + AccessoryChangeTracker.warmup + 1
        XCTAssertEqual(t.update([mouse(80)], now: later), ["mouse": .connected])
        XCTAssertEqual(t.flash(id: "mouse", group: "peripheral", now: later + 1), .connected)
        XCTAssertNil(t.flash(id: "mouse", group: "peripheral", now: later + AccessoryChangeTracker.duration))
        XCTAssertEqual(t.update([], now: later + 10), ["mouse": .disconnected])
        // 断开以后那一格找不到 id，按格找回。
        XCTAssertEqual(t.flash(id: nil, group: "peripheral", now: later + 11), .disconnected)
        XCTAssertTrue(t.prune(now: later + 10 + AccessoryChangeTracker.duration))
        XCTAssertNil(t.flash(id: nil, group: "peripheral", now: later + 13))
    }

    func testWarmupIsBaseline() {
        var t = AccessoryChangeTracker()
        XCTAssertEqual(t.update([], now: t0), [:])
        // 系统信息的配件一两秒后才报上来，不算「已连接」。
        XCTAssertEqual(t.update([mouse(10)], now: t0 + 2), [:])
        // 启动时就低的，也不再补一次。
        XCTAssertEqual(t.update([mouse(9)], now: t0 + AccessoryChangeTracker.warmup + 1), [:])
    }

    func testLowOncePerCrossing() {
        var t = AccessoryChangeTracker()
        _ = t.update([mouse(40)], now: t0)
        var now = t0 + AccessoryChangeTracker.warmup + 1
        XCTAssertEqual(t.update([mouse(20)], now: now), [:])
        now += 1
        XCTAssertEqual(t.update([mouse(19)], now: now), ["mouse": .low])
        now += 1
        XCTAssertEqual(t.update([mouse(21)], now: now), [:])
        now += 1
        XCTAssertEqual(t.update([mouse(18)], now: now), [:])
        now += 1
        XCTAssertEqual(t.update([mouse(30)], now: now), [:])
        now += 1
        XCTAssertEqual(t.update([mouse(15)], now: now), ["mouse": .low])
    }

    func testConnectingLowSaysLow() {
        var t = AccessoryChangeTracker()
        _ = t.update([], now: t0)
        XCTAssertEqual(t.update([mouse(8)], now: t0 + 30), ["mouse": .low])
    }

    func testCaseOnlySaysLow() {
        let pods = BluetoothBattery(id: "pods", name: "AirPods Pro", kind: .airpodsPro,
                                    left: 80, right: 80, caseLevel: 12)
        let open = AccessoryPresence.from([pods])
        XCTAssertEqual(open.map(\.group), ["buds", "case"])
        let closed = AccessoryPresence.from([BluetoothBattery(id: "pods", name: "AirPods Pro", kind: .airpodsPro,
                                                              left: 80, right: 80)])
        var t = AccessoryChangeTracker()
        _ = t.update(closed, now: t0)
        let now = t0 + 30
        XCTAssertEqual(t.update(open, now: now), [AccessoryPresence.caseID("pods"): .low])
        // 合盖不算断开；再开盖不重复说电量低。
        XCTAssertEqual(t.update(closed, now: now + 5), [:])
        XCTAssertEqual(t.update(open, now: now + 10), [:])
    }

    func testReconnectClearsGroupDisconnect() {
        var t = AccessoryChangeTracker()
        _ = t.update([mouse(80)], now: t0)
        let now = t0 + 30
        _ = t.update([], now: now)
        XCTAssertEqual(t.flash(id: nil, group: "peripheral", now: now + 0.5), .disconnected)
        _ = t.update([mouse(80)], now: now + 1)
        XCTAssertNil(t.flash(id: nil, group: "peripheral", now: now + 1.5))
        XCTAssertEqual(t.flash(id: "mouse", group: "peripheral", now: now + 1.5), .connected)
    }

    // MARK: 更新于

    func testPanelUpdatedLine() {
        XCTAssertNil(BatteryWords.panelUpdated(nil))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 9, minute: 5))!
        XCTAssertEqual(BatteryWords.clock(date), "09:05")
        XCTAssertTrue(BatteryWords.panelUpdated(date)?.contains("09:05") ?? false)
    }
}
