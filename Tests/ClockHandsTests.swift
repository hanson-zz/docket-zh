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

    func testSecondHandIsThinButVisible() {
        // 0.9pt 在扩展栏缩小后的淡色徽章上看不见，加粗到 1.2pt，仍比分针（1.6）细。
        XCTAssertEqual(ClockHands.secondWidth, 1.2, accuracy: 0.0001)
        XCTAssertLessThan(ClockHands.secondWidth, 1.6)
        XCTAssertEqual(ClockHands.secondLength, 0.40, accuracy: 0.0001)
        XCTAssertGreaterThan(ClockHands.secondLength, 0.37)
        // 26pt 的卡片表盘：中心点约 3.64pt，比秒针粗得多；小表盘也不小于 2.6pt。
        XCTAssertEqual(ClockHands.dotDiameter(26), 3.64, accuracy: 0.0001)
        XCTAssertEqual(ClockHands.dotDiameter(10), ClockHands.minimumDot)
        XCTAssertGreaterThan(ClockHands.dotDiameter(26), ClockHands.secondWidth * 2.5)
    }

    // MARK: 开关

    func testSecondHandIsOnByDefault() {
        XCTAssertTrue(ClockHands.showsSecondHand(WidgetConfig([:])))
        XCTAssertTrue(ClockHands.showsSecondHand(WidgetConfig([ClockHands.secondHandKey: .bool(true)])))
        XCTAssertFalse(ClockHands.showsSecondHand(WidgetConfig([ClockHands.secondHandKey: .bool(false)])))
    }

    /// 真机上看不到秒针的原因之一：老卡片配置里 seconds=false。标准样式改读
    /// secondHand，老配置不再藏掉秒针；用户在新开关里关掉才不画。
    func testOldSecondsOffNoLongerHidesTheSecondHand() {
        let old = WidgetConfig(["layout": .string("standard"), "seconds": .bool(false)])
        XCTAssertTrue(ClockHands.showsSecondHand(old))
        // 卡片读的是补齐了目录默认值的配置（WidgetTile.resolved）。
        let defaults = WidgetCatalog.entry(.clock)!.defaults
        XCTAssertEqual(defaults.values[ClockHands.secondHandKey], .bool(true))
        XCTAssertTrue(ClockHands.showsSecondHand(old.merging(defaults: defaults)))
        // 旧的显示秒原样保留，数字样式照旧读它。
        XCTAssertFalse(old.merging(defaults: defaults).bool("seconds", default: true))
        var off = old
        off.set(ClockHands.secondHandKey, .bool(false))
        XCTAssertFalse(ClockHands.showsSecondHand(off.merging(defaults: defaults)))
    }

    func testSecondsSwitchesAreListedPerStyle() {
        XCTAssertEqual(ClockHands.applies("secondHand", isStandard: true), true)
        XCTAssertEqual(ClockHands.applies("secondHand", isStandard: false), false)
        XCTAssertEqual(ClockHands.applies("seconds", isStandard: true), false)
        XCTAssertEqual(ClockHands.applies("seconds", isStandard: false), true)
        XCTAssertNil(ClockHands.applies("clockSize", isStandard: true))
        // 没写 layout 的老卡片是标准样式。
        XCTAssertTrue(ClockStyles.applies("secondHand", to: WidgetConfig([:])))
        XCTAssertFalse(ClockStyles.applies("seconds", to: WidgetConfig([:])))
        // 标准样式选了大号数字画成数字，没有小表盘，列「显示秒」。
        let big = WidgetConfig(["layout": .string("standard"), ClockStyles.Key.size: .string("large")])
        XCTAssertTrue(ClockStyles.applies("seconds", to: big))
        XCTAssertFalse(ClockStyles.applies("secondHand", to: big))
        for id in ["digital", "analog", "flip", "pixel", "words", "neon", "lcd"] {
            let config = WidgetConfig(["layout": .string(id)])
            XCTAssertTrue(ClockStyles.applies("seconds", to: config), id)
            XCTAssertFalse(ClockStyles.applies("secondHand", to: config), id)
        }
    }

    // MARK: 颜色

    /// 没选颜色：卡片和面板同一个默认色，是时钟琥珀，不是系统橙。
    func testDefaultSourceIsTheClockAmber() {
        XCTAssertEqual(ClockHands.defaultColor, ColorCode(hex: "#FFB340")!)
        XCTAssertEqual(ClockHands.defaultColor, WidgetTint.defaultPalette(.clock).main)
        XCTAssertEqual(ClockHands.source(WidgetConfig([:]), unlocked: false), .color(ClockHands.defaultColor))
        XCTAssertEqual(ClockHands.source(WidgetConfig([:]), unlocked: true), .color(ClockHands.defaultColor))
    }

    /// 选了颜色：和面板强调色同一个来源（panelAccent 判定选了颜色），用那个颜色的主色。
    func testChosenPresetMatchesThePanelAccent() {
        for preset in WidgetTint.Preset.allCases {
            let config = WidgetConfig([WidgetTint.key: .string(preset.rawValue)])
            XCTAssertEqual(ClockHands.source(config, unlocked: false), .color(preset.palette.main), preset.rawValue)
            let choice = WidgetTint.shownChoice(config, unlocked: false)
            XCTAssertEqual(WidgetTint.panelAccent(choice, kind: .clock),
                           .color(WidgetTint.readable(preset.palette.main, dark: true)), preset.rawValue)
        }
    }

    func testFollowingTheSystemAccentLeavesItToTheView() {
        let config = WidgetConfig([WidgetTint.key: .string("system")])
        XCTAssertEqual(ClockHands.source(config, unlocked: false), .system)
    }

    func testCustomColourNeedsPro() {
        let config = WidgetConfig([WidgetTint.key: .string("#123456")])
        XCTAssertEqual(ClockHands.source(config, unlocked: false), .color(ClockHands.defaultColor))
        XCTAssertEqual(ClockHands.source(config, unlocked: true), .color(ColorCode(hex: "#123456")!))
    }

    /// 秒针和徽章淡底同色：紫色主题原来在徽章上只有约 2.7 到 3:1，加上 0.9pt
    /// 细线和扩展栏缩小，真机上看不见。现在按徽章底调到 3.5:1 以上。
    func testCardColourIsReadableOnItsOwnTintedBadge() {
        let purple = WidgetTint.Preset.purple.palette.main
        for dark in [false, true] {
            let old = WidgetTint.readable(purple, dark: dark)
            let badge = ClockHands.badgeBackground(tint: purple, dark: dark)
            XCTAssertLessThan(WidgetTint.contrastRatio(old, badge), ClockHands.handContrast, "dark=\(dark)")
        }
        var bases = WidgetTint.Preset.allCases.map(\.palette.main)
        bases += [ClockHands.defaultColor, ColorCode(hex: "#101030")!, ColorCode(hex: "#FFFF66")!,
                  ColorCode(hex: "#007AFF")!]
        for base in bases {
            for dark in [false, true] {
                let hand = ClockHands.cardColor(base, dark: dark)
                let badge = ClockHands.badgeBackground(tint: base, dark: dark)
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(hand, badge), ClockHands.handContrast - 0.01,
                                            "\(base) dark=\(dark)")
                let panel = ClockHands.panelColor(base, dark: dark)
                let glass = dark ? WidgetTint.darkCard : WidgetTint.lightCard
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(panel, glass), ClockHands.handContrast - 0.01,
                                            "\(base) dark=\(dark)")
            }
        }
    }

    /// 卡片和面板只调明暗，色相和基色一致。
    func testCardAndPanelKeepTheSameHue() {
        for base in WidgetTint.Preset.allCases.map(\.palette.main) + [ClockHands.defaultColor] {
            let hsl = base.hslComponents
            guard hsl.s > 0.05 else { continue }
            for dark in [false, true] {
                for adjusted in [ClockHands.cardColor(base, dark: dark), ClockHands.panelColor(base, dark: dark)] {
                    let a = adjusted.hslComponents
                    guard a.s > 0.05, a.l > 0.02, a.l < 0.98 else { continue }
                    var diff = abs(a.h - hsl.h)
                    diff = min(diff, 360 - diff)
                    XCTAssertLessThan(diff, 1.0, "\(base) dark=\(dark)")
                }
            }
        }
    }

    func testReadableLeavesEnoughContrastAlone() {
        let white = ColorCode(red: 1, green: 1, blue: 1)
        XCTAssertEqual(ClockHands.readable(white, dark: true, on: WidgetTint.darkCard), white)
    }
}
