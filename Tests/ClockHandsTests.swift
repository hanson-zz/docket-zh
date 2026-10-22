import XCTest

/// 时钟标准卡片小表盘：三根指针的角度、秒针尺寸，以及秒针颜色跟着卡片
/// 颜色主题走、在浅色和深色卡片上都看得清。
final class ClockHandsTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22,
                                                  hour: hour, minute: minute, second: second))!
    }

    func testSecondHandStepsSixDegreesASecond() {
        XCTAssertEqual(ClockHands.angles(date(10, 0, 0), zone: utc).second, 0)
        XCTAssertEqual(ClockHands.angles(date(10, 0, 15), zone: utc).second, 90, accuracy: 0.0001)
        XCTAssertEqual(ClockHands.angles(date(10, 0, 30), zone: utc).second, 180, accuracy: 0.0001)
        XCTAssertEqual(ClockHands.angles(date(10, 0, 59), zone: utc).second, 354, accuracy: 0.0001)
    }

    func testHourAndMinuteHandsAreUnchangedBySeconds() {
        let a = ClockHands.angles(date(15, 30, 0), zone: utc)
        let b = ClockHands.angles(date(15, 30, 45), zone: utc)
        XCTAssertEqual(a.minute, b.minute)
        XCTAssertEqual(a.hour, b.hour)
        XCTAssertEqual(a.minute, 180, accuracy: 0.0001)
        // 3:30 的时针在 3 和 4 中间。
        XCTAssertEqual(a.hour, 105, accuracy: 0.0001)
    }

    func testAnglesFollowTheZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // UTC 0:00 是东京 9:00。
        XCTAssertEqual(ClockHands.angles(date(0, 0, 20), zone: tokyo).hour, 270, accuracy: 0.0001)
        XCTAssertEqual(ClockHands.angles(date(0, 0, 20), zone: tokyo).second, 120, accuracy: 0.0001)
    }

    func testSecondHandIsThinAndJustLongerThanTheMinuteHand() {
        XCTAssertGreaterThanOrEqual(ClockHands.secondWidth, 0.9)
        XCTAssertLessThanOrEqual(ClockHands.secondWidth, 1.0)
        XCTAssertEqual(ClockHands.secondLength, 0.40, accuracy: 0.0001)
        XCTAssertGreaterThan(ClockHands.secondLength, 0.37)
        // 26pt 的卡片表盘：中心点 3.12pt；20pt 小表盘也不小于 2.2pt。
        XCTAssertEqual(ClockHands.dotDiameter(26), 3.12, accuracy: 0.0001)
        XCTAssertEqual(ClockHands.dotDiameter(10), ClockHands.minimumDot)
    }

    func testDefaultTintIsTheClockAmber() {
        let config = WidgetConfig([:])
        let light = ClockHands.secondTint(config, dark: false, unlocked: false)!
        let dark = ClockHands.secondTint(config, dark: true, unlocked: false)!
        let amber = WidgetTint.defaultPalette(.clock).main
        XCTAssertEqual(dark, WidgetTint.readable(amber, dark: true))
        XCTAssertEqual(light, WidgetTint.readable(amber, dark: false))
    }

    func testChosenPresetIsUsed() {
        let config = WidgetConfig([WidgetTint.key: .string("blue")])
        let tint = ClockHands.secondTint(config, dark: true, unlocked: false)!
        XCTAssertEqual(tint, WidgetTint.readable(WidgetTint.Preset.blue.palette.main, dark: true))
    }

    func testFollowingTheSystemAccentLeavesItToTheView() {
        let config = WidgetConfig([WidgetTint.key: .string("system")])
        XCTAssertNil(ClockHands.secondTint(config, dark: false, unlocked: false))
    }

    func testCustomColourNeedsPro() {
        let config = WidgetConfig([WidgetTint.key: .string("#123456")])
        let locked = ClockHands.secondTint(config, dark: true, unlocked: false)!
        XCTAssertEqual(locked, WidgetTint.readable(WidgetTint.defaultPalette(.clock).main, dark: true))
        let unlocked = ClockHands.secondTint(config, dark: true, unlocked: true)!
        XCTAssertEqual(unlocked, WidgetTint.readable(ColorCode(hex: "#123456")!, dark: true))
    }

    /// 浅色卡片上的黄色、深色卡片上的深色自定义色都调到 3:1 以上。
    func testTintIsReadableOnLightAndDarkCards() {
        for raw in ["", "yellow", "blush", "lime", "blue", "purple"] {
            let config = WidgetConfig([WidgetTint.key: .string(raw)])
            for dark in [false, true] {
                let tint = ClockHands.secondTint(config, dark: dark, unlocked: true)!
                let card = dark ? WidgetTint.darkCard : WidgetTint.lightCard
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(tint, card), WidgetTint.minimumContrast - 0.01,
                                            "\(raw) dark=\(dark)")
            }
        }
        let navy = WidgetConfig([WidgetTint.key: .string("#101030")])
        let tint = ClockHands.secondTint(navy, dark: true, unlocked: true)!
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(tint, WidgetTint.darkCard), WidgetTint.minimumContrast - 0.01)
    }
}
