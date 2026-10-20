import XCTest

/// 喝水三种样式的分工：样式怎么读（`WaterLayout`），角色样式按进度换姿势
/// （`WaterPose`），液态的水体浓度。
final class WaterStylesTests: XCTestCase {

    // MARK: 样式

    func testLayoutReadsLegacyCardsAsCharacter() {
        XCTAssertEqual(WaterLayout.stored(WidgetConfig()), .character, "老卡片没存 layout，原来就是角色")
        XCTAssertEqual(WaterLayout.stored(WidgetConfig(["layout": .string("ring")])), .ring)
        XCTAssertEqual(WaterLayout.stored(WidgetConfig(["layout": .string("liquid")])), .liquid)
        XCTAssertEqual(WaterLayout.stored(WidgetConfig(["layout": .string("character")])), .character)
        XCTAssertEqual(WaterLayout.stored(WidgetConfig(["layout": .string("odd")])), .character)
        XCTAssertEqual(WaterLayout.newWidget, .ring)
        XCTAssertEqual(WaterLayout.liquid.rawValue, LiquidMotion.layout)
        XCTAssertEqual(WaterLayout.character.rawValue, WaterPetCards.characterLayout)
        XCTAssertFalse(WaterLayout.ring.isPro)
        XCTAssertTrue(WaterLayout.character.isPro)
        XCTAssertTrue(WaterLayout.liquid.isPro)
        // 目录默认值仍是角色（给老卡片补），新放的写圆环。
        XCTAssertEqual(WidgetCatalog.entry(.water)?.defaults.string("layout"), "character")
        XCTAssertEqual(WidgetCatalog.make(.water)?.config.string("layout"), "ring")
        // 选了别的样式放上去的照旧是那个样式。
        XCTAssertEqual(WidgetCatalog.make(.water, overrides: ["layout": .string("liquid")])?.config.string("layout"),
                       "liquid")
    }

    func testLibraryOrderIsRingCharacterLiquid() {
        XCTAssertEqual(WidgetCatalog.entry(.water)?.variants.map(\.title), ["圆环", "角色", "液态"])
    }

    // MARK: 分档

    func testStagesFollowProgress() {
        XCTAssertEqual(WaterPose.stage(total: 0, goal: 2000), .thirsty)
        XCTAssertEqual(WaterPose.stage(total: 599, goal: 2000), .thirsty, "29.95% 还渴着")
        XCTAssertEqual(WaterPose.stage(total: 600, goal: 2000), .sipping, "30% 起小口喝")
        XCTAssertEqual(WaterPose.stage(total: 1399, goal: 2000), .sipping)
        XCTAssertEqual(WaterPose.stage(total: 1400, goal: 2000), .nearlyFull, "70% 起快喝饱了")
        XCTAssertEqual(WaterPose.stage(total: 1999, goal: 2000), .nearlyFull, "差一口不算达标")
        XCTAssertEqual(WaterPose.stage(total: 2000, goal: 2000), .done)
        XCTAssertEqual(WaterPose.stage(total: 3500, goal: 2000), .done)
        XCTAssertEqual(WaterPose.stage(total: 500, goal: 0), .thirsty, "没有目标时不算喝饱")
    }

    func testCaptions() {
        XCTAssertEqual(WaterPose.Stage.thirsty.caption, "还渴着")
        XCTAssertEqual(WaterPose.Stage.sipping.caption, "小口喝着")
        XCTAssertEqual(WaterPose.Stage.nearlyFull.caption, "快喝饱了")
        XCTAssertEqual(WaterPose.Stage.done.caption, "达标啦")
        XCTAssertEqual(WaterPose.caption(.dry(hours: 2), stage: .thirsty), "2 小时没喝了")
        XCTAssertEqual(WaterPose.caption(.parched, stage: .thirsty), "渴成骷髅了")
        XCTAssertEqual(WaterPose.caption(.gulp, stage: .sipping), "小口喝着", "喝一口那一帧还写当前档位")
        XCTAssertEqual(WaterPose.dryBubble, "渴了")
    }

    // MARK: 渴了

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    private let window = WaterReminder(every: 60, start: 9 * 60, end: 21 * 60)

    func testDryAfterTwoHoursInsideTheReminderHours() {
        XCTAssertNil(WaterPose.dryHours(now: at(10, 59), lastDrink: nil, total: 0, goal: 2000,
                                        window: window, calendar: calendar), "时段 9 点开始，还没到 2 小时")
        XCTAssertEqual(WaterPose.dryHours(now: at(11), lastDrink: nil, total: 0, goal: 2000,
                                          window: window, calendar: calendar), 2)
        XCTAssertNil(WaterPose.dryHours(now: at(12), lastDrink: at(10, 30), total: 300, goal: 2000,
                                        window: window, calendar: calendar))
        XCTAssertEqual(WaterPose.dryHours(now: at(13, 40), lastDrink: at(10, 30), total: 300, goal: 2000,
                                          window: window, calendar: calendar), 3)
        // 昨晚喝的不算，从时段开始算起。
        let lastNight = at(8).addingTimeInterval(-12 * 3600)
        XCTAssertEqual(WaterPose.dryHours(now: at(11, 30), lastDrink: lastNight, total: 0, goal: 2000,
                                          window: window, calendar: calendar), 2)
        // 达标了、时段外、没有目标都不催。
        XCTAssertNil(WaterPose.dryHours(now: at(15), lastDrink: at(9), total: 2000, goal: 2000,
                                        window: window, calendar: calendar))
        XCTAssertNil(WaterPose.dryHours(now: at(22), lastDrink: at(9), total: 300, goal: 2000,
                                        window: window, calendar: calendar))
        XCTAssertNil(WaterPose.dryHours(now: at(15), lastDrink: nil, total: 0, goal: 0,
                                        window: window, calendar: calendar))
        XCTAssertLessThan(WaterPose.dryAfter, WaterParched.afterHours * 3600, "渴了比渴成骷髅早")
    }

    // MARK: 画什么

    func testLookPriority() {
        XCTAssertEqual(WaterPose.look(stage: .sipping, dryHours: nil, parched: false, gulping: false), .stage(.sipping))
        XCTAssertEqual(WaterPose.look(stage: .thirsty, dryHours: 2, parched: false, gulping: false), .dry(hours: 2))
        XCTAssertEqual(WaterPose.look(stage: .thirsty, dryHours: 5, parched: true, gulping: false), .parched,
                       "骷髅盖过渴了")
        XCTAssertEqual(WaterPose.look(stage: .thirsty, dryHours: 5, parched: true, gulping: true), .gulp,
                       "刚点了 + 先举竹筒")
        XCTAssertEqual(WaterPose.look(stage: .done, dryHours: 3, parched: true, gulping: false), .stage(.done))
        XCTAssertEqual(WaterPose.look(stage: .done, dryHours: nil, parched: false, gulping: true), .gulp)
    }

    func testRedPandaPictures() {
        XCTAssertEqual(WaterPose.imageName(.redPanda, .stage(.thirsty)), "pet-panda-hungry")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .stage(.sipping)), "pet-panda-sip")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .stage(.nearlyFull)), "pet-panda-idle")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .stage(.done)), "pet-panda-cheer")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .dry(hours: 2)), "pet-panda-hungry", "渴了是降饱和的口渴图")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .gulp), "pet-panda-drink")
        XCTAssertEqual(WaterPose.imageName(.redPanda, .parched), "WaterPanda-skeleton")
    }

    func testOtherCharactersReuseTheirPictures() {
        for character in WaterCharacter.allCases where character != .redPanda {
            let id = character.rawValue
            XCTAssertEqual(WaterPose.imageName(character, .stage(.thirsty)), "pet-\(id)-hungry")
            XCTAssertEqual(WaterPose.imageName(character, .stage(.sipping)), "water-\(id)-drink")
            XCTAssertEqual(WaterPose.imageName(character, .stage(.nearlyFull)), "water-\(id)-idle")
            XCTAssertEqual(WaterPose.imageName(character, .stage(.done)), "water-\(id)-cheer")
            XCTAssertEqual(WaterPose.imageName(character, .gulp), "water-\(id)-drink")
            XCTAssertEqual(WaterPose.imageName(character, .parched), "pet-\(id)-skeleton")
        }
    }

    func testEveryPictureIsBundled() throws {
        // 测试从仓库根目录读资源，确认每张用到的图都在 Resources 里。
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Resources/Pet", "Resources/Water"].map { root.appendingPathComponent($0) }
        guard FileManager.default.fileExists(atPath: folders[0].path) else {
            throw XCTSkip("没有仓库里的资源目录")
        }
        let looks: [WaterPose.Look] = [.stage(.thirsty), .stage(.sipping), .stage(.nearlyFull), .stage(.done),
                                       .dry(hours: 2), .gulp, .parched]
        for character in WaterCharacter.allCases {
            for look in looks {
                let name = WaterPose.imageName(character, look) + ".png"
                XCTAssertTrue(folders.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path) },
                              name)
            }
        }
    }

    func testBambooHasEightSegments() {
        XCTAssertEqual(WaterPose.bambooSlots, 8)
        XCTAssertEqual(WaterPose.gulpSeconds, 0.8, accuracy: 1e-9)
    }

    // MARK: 液态

    func testWaterLiquidIsDenserThanTheOthers() {
        XCTAssertEqual(LiquidLooks.waterDensity, LiquidDensity(top: 0.62, bottom: 0.46, back: 0.22))
        XCTAssertEqual(LiquidLooks.standardDensity, LiquidDensity(top: 0.30, bottom: 0.14, back: 0.12))
        XCTAssertGreaterThan(LiquidLooks.waterDensity.top, LiquidLooks.standardDensity.top)
        XCTAssertGreaterThan(LiquidLooks.waterDensity.bottom, LiquidLooks.standardDensity.bottom)
        XCTAssertGreaterThan(LiquidLooks.waterSplashOrigin(vertical: false), 0.5, "横排水珠溅在 + 那边")
        XCTAssertEqual(LiquidLooks.waterSplashOrigin(vertical: true), 0.5)
        // 点 + 的晃荡复用电池液态：一开始有倾斜，1.2 秒后平复。
        XCTAssertNotEqual(BatteryLiquidFX.slosh(.plugged, elapsed: 0.15), 0)
        XCTAssertEqual(BatteryLiquidFX.slosh(.plugged, elapsed: 1.3), 0)
        XCTAssertFalse(BatteryLiquidFX.droplets(.plugged, elapsed: 0.2).isEmpty)
    }
}
