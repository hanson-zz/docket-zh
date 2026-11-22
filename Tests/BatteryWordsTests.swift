import XCTest

/// 迷你电池卡片、多设备悬停和面板头部的说法。
final class BatteryWordsTests: XCTestCase {
    func testTitleUsesOneRounding() {
        XCTAssertEqual(BatteryWords.title(name: BatteryWords.macName, level: 0.8, present: true), "MacBook · 80%")
        XCTAssertEqual(BatteryWords.title(name: BatteryWords.macName, level: 0.795, present: true), "MacBook · 80%")
        XCTAssertEqual(BatteryWords.title(name: BatteryWords.macName, level: 0.8, present: false), "MacBook · -")
        // 和面板、圆环同一种取整。
        XCTAssertEqual(BatteryWords.percentText(level: 0.804, present: true), "\(BatteryColorMap.percent(0.804))%")
    }

    func testPowerLine() {
        XCTAssertEqual(BatteryWords.powerLine(level: 0.8, charging: false, onPower: true, present: true),
                       "接通电源 · 未充电")
        XCTAssertEqual(BatteryWords.powerLine(level: 0.6, charging: true, onPower: true, present: true),
                       "接通电源 · 正在充电")
        XCTAssertEqual(BatteryWords.powerLine(level: 1, charging: false, onPower: true, present: true),
                       "接通电源 · 已充满")
        XCTAssertEqual(BatteryWords.powerLine(level: 0.8, charging: false, onPower: true, present: true, charged: true),
                       "接通电源 · 已充满")
        XCTAssertEqual(BatteryWords.powerLine(level: 0.5, charging: false, onPower: false, present: true), "使用电池")
        XCTAssertEqual(BatteryWords.powerLine(level: 0.5, charging: true, onPower: false, present: true), "正在充电")
        XCTAssertEqual(BatteryWords.powerLine(level: 0, charging: false, onPower: false, present: false), "未连接")
    }

    func testHeroWords() {
        XCTAssertEqual(BatteryWords.source(onPower: true, charging: false), "已接电源")
        XCTAssertEqual(BatteryWords.source(onPower: false, charging: false), "使用电池")
        XCTAssertEqual(BatteryWords.chargeWord(level: 0.8, charging: false, onPower: true), "未充电")
        XCTAssertNil(BatteryWords.chargeWord(level: 0.8, charging: false, onPower: false))
    }

    func testHoverHasNameStatusAndTime() {
        let now = Date(timeIntervalSince1970: 50_000)
        let text = BatteryWords.hover(name: "AirPods Pro", level: 0.85, charging: false, onPower: false,
                                      present: true, updated: now.addingTimeInterval(-3), now: now)
        XCTAssertEqual(text.components(separatedBy: "\n"), ["AirPods Pro", "已连接 · 85% · 使用电池", "更新于 刚刚"])
        let absent = BatteryWords.hover(name: "鼠标", level: 0, charging: false, onPower: false, present: false,
                                        updated: nil, now: now)
        XCTAssertEqual(absent, "鼠标\n未连接")
        XCTAssertEqual(BatteryWords.updatedText(now.addingTimeInterval(-30), now: now), "30 秒前")
    }
}
