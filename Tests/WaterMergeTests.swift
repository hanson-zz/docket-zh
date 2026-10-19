import Foundation
import XCTest

/// 喝水提醒 (`hydration`) folded into 喝水 (`water`), and the 喝水
/// characters that are 赞助者专属.
final class WaterMergeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute))!
    }

    /// A saved shelf as an older build wrote it: the instance encoded, with
    /// its kind swapped for the old raw value.
    private func legacyJSON(_ instance: WidgetInstance, kind: String) throws -> Data {
        let data = try JSONEncoder().encode(instance)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["kind"] = kind
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Library

    func testTheOldWidgetIsGoneFromTheLibrary() {
        XCTAssertNil(WidgetKind(rawValue: WaterIntake.legacyHydrationKind))
        XCTAssertFalse(WidgetCatalog.entries.contains { $0.name == "喝水提醒" })
        XCTAssertEqual(WidgetCatalog.entries.filter { $0.name == "喝水" }.map(\.kind), [.water])
    }

    // MARK: Migration

    func testASavedHydrationWidgetComesBackAsWater() throws {
        let id = UUID()
        let old = WidgetInstance(id: id, kind: .water, expanded: true,
                                 config: WidgetConfig(["duration": .number(2700),
                                                       "lastDrink": .number(1_760_000_000),
                                                       "hidePlate": .bool(true)]))
        let migrated = try JSONDecoder().decode(WidgetInstance.self,
                                                from: legacyJSON(old, kind: "hydration"))
        XCTAssertEqual(migrated.id, id, "same id, so the tile keeps its place")
        XCTAssertEqual(migrated.kind, .water)
        XCTAssertEqual(migrated.config.string("remindEvery"), "45")
        XCTAssertEqual(WaterIntake.reminderMinutes(migrated.config), 45)
        XCTAssertNil(migrated.config["duration"])
        XCTAssertNil(migrated.config["lastDrink"], "no amount, so no glass is invented")
        XCTAssertTrue(migrated.config.bool("hidePlate"), "other keys are kept")
        XCTAssertTrue(WaterIntake.days(migrated.config).isEmpty)

        // One-time: the next save writes it as water.
        let resaved = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: resaved) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "water")
        XCTAssertEqual(try JSONDecoder().decode(WidgetInstance.self, from: resaved), migrated)
    }

    func testAHydrationWithNoConfigGetsTheOldDefaultInterval() throws {
        let old = WidgetInstance(kind: .water, config: WidgetConfig())
        let migrated = try JSONDecoder().decode(WidgetInstance.self,
                                                from: legacyJSON(old, kind: "hydration"))
        XCTAssertEqual(migrated.kind, .water)
        XCTAssertEqual(WaterIntake.reminderMinutes(migrated.config), 45)
        // Drawn with water's defaults filled in.
        let drawn = migrated.config.merging(defaults: WidgetCatalog.entry(.water)!.defaults)
        // No hand-set goal: the personal recommendation with nothing filled in.
        XCTAssertEqual(WaterIntake.goal(drawn), 1600)
        XCTAssertEqual(WaterCharacter.from(drawn), .redPanda)
    }

    func testTheOldIntervalMapsToTheNearestReminderThatIsNotOff() {
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 60), 15)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 1200), 20)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 2700), 45)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 3600), 60)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 6000), 90)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 14_400), 240)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: 99_999), 240)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: -5), 15)
        XCTAssertEqual(WaterIntake.nearestReminder(seconds: .nan), 60)
        for seconds in stride(from: 60.0, through: 14_400, by: 300) {
            let minutes = WaterIntake.nearestReminder(seconds: seconds)
            XCTAssertTrue(WaterIntake.reminderChoices.contains(minutes))
            XCTAssertGreaterThan(minutes, 0)
        }
    }

    func testAShelfWithTheOldWidgetKeepsEveryTile() throws {
        let clock = WidgetCatalog.make(.clock)!
        let old = WidgetInstance(kind: .water, config: WidgetConfig(["duration": .number(5400)]))
        let profile = DockProfile(kind: .customDock, name: "工作",
                                  items: [.widget(clock), .widget(old)])
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(profile), encoding: .utf8))
        // The water tile's kind written as the old one, as an older build saved it.
        let legacy = json.replacingOccurrences(of: "\"kind\":\"water\"", with: "\"kind\":\"hydration\"")
        XCTAssertNotEqual(legacy, json, "precondition: the kind was swapped")

        let decoded = try JSONDecoder().decode(DockProfile.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.items.count, 2, "no tile lost")
        XCTAssertEqual(decoded.items.compactMap(\.widget).map(\.kind), [.clock, .water])
        XCTAssertEqual(decoded.items[1].id, old.id)
        XCTAssertEqual(WaterIntake.reminderMinutes(decoded.items[1].widget!.config), 90)
    }

    func testAnUnknownKindIsStillRejected() throws {
        let some = WidgetInstance(kind: .water, config: WidgetConfig())
        XCTAssertThrowsError(try JSONDecoder().decode(WidgetInstance.self,
                                                      from: legacyJSON(some, kind: "not-a-widget")))
    }

    // MARK: The old readout, on 喝水's schedule

    func testDueReportsUpcomingOverdueMetAndOff() {
        let reminder = WaterReminder(every: 45, start: 9 * 60, end: 21 * 60)
        XCTAssertEqual(reminder.due(now: at(10), lastDrink: at(9, 50), todayTotal: 250, goal: 2000,
                                    calendar: calendar), .upcoming(at(10, 35)))
        XCTAssertEqual(reminder.due(now: at(11), lastDrink: at(10), todayTotal: 250, goal: 2000,
                                    calendar: calendar), .overdue(15 * 60))
        XCTAssertEqual(reminder.due(now: at(9, 30), lastDrink: nil, todayTotal: 0, goal: 2000,
                                    calendar: calendar), .overdue(30 * 60), "due from the window's start")
        XCTAssertEqual(reminder.due(now: at(7), lastDrink: nil, todayTotal: 0, goal: 2000,
                                    calendar: calendar), .upcoming(at(9)))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: at(9))!
        XCTAssertEqual(reminder.due(now: at(22), lastDrink: at(20), todayTotal: 1000, goal: 2000,
                                    calendar: calendar), .upcoming(tomorrow))
        XCTAssertEqual(reminder.due(now: at(14), lastDrink: at(13), todayTotal: 2000, goal: 2000,
                                    calendar: calendar), .met(tomorrow))
        XCTAssertEqual(WaterReminder(every: 0, start: 540, end: 1260)
            .due(now: at(10), lastDrink: nil, todayTotal: 0, goal: 2000, calendar: calendar), .off)
    }

    func testTheReminderMenuCoversTheOldRange() {
        for minutes in [15, 20, 180, 240] {
            XCTAssertEqual(WaterIntake.reminderMinutes(WidgetConfig(["remindEvery": .string("\(minutes)")])), minutes)
        }
    }

    // MARK: 赞助者专属角色

    /// 小熊猫免费，柴犬、橘猫靠达标天数解锁（见 WaterCharacterAccessTests），
    /// 企鹅、水獭、章鱼是 Pro。
    func testOnlyThreeCharactersAreSupporterOnly() {
        for character in [WaterCharacter.redPanda, .shiba, .cat] {
            XCTAssertFalse(character.isSupporterOnly, "\(character)")
            XCTAssertFalse(WidgetCatalog.isSupporterOnly(["character": .string(character.rawValue)]))
        }
        for character in [WaterCharacter.penguin, .otter, .octopus] {
            XCTAssertTrue(character.isSupporterOnly, "\(character)")
            XCTAssertTrue(WidgetCatalog.isSupporterOnly(["character": .string(character.rawValue)]))
        }
        XCTAssertEqual(WidgetCatalog.supporterWaterCharacters, ["penguin", "otter", "octopus"])
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string("character")]))
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string("ring")]))
    }

    func testTheClockFacesAreStillSupporterOnly() {
        for layout in ["neon", "nixie", "lcd", "minimal"] {
            XCTAssertTrue(WidgetCatalog.isSupporterOnly(["layout": .string(layout)]), layout)
        }
        for layout in ["standard", "flip"] {
            XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string(layout)]), layout)
        }
        XCTAssertFalse(WidgetCatalog.isSupporterOnly([:]))
    }

    func testALockedCharacterIsDrawnAsTheRedPanda() {
        let shiba = WidgetConfig(["character": .string("shiba")])
        XCTAssertEqual(WaterCharacter.shown(shiba, unlocked: false), .redPanda)
        XCTAssertEqual(WaterCharacter.shown(shiba, unlocked: true), .shiba)
        XCTAssertEqual(WaterCharacter.shown(WidgetConfig(["character": .string("panda")]), unlocked: false), .redPanda)
        XCTAssertEqual(WaterCharacter.shown(WidgetConfig(), unlocked: false), .redPanda)
        let otter = WidgetConfig(["character": .string("otter")])
        XCTAssertEqual(WaterCharacter.shown(otter, unlocked: false), .redPanda)
        XCTAssertEqual(WaterCharacter.shown(otter, unlocked: true), .otter)
        // The stored choice is kept, so unlocking brings it back.
        XCTAssertEqual(WaterCharacter.from(shiba), .shiba)
    }

    /// 角色挪进了设置：添加面板只列角色、圆环、液态，柴犬卡片读出来是
    /// “角色”样式加柴犬。柴犬改为达标解锁，不算 Pro；水獭仍是 Pro。
    func testTheLibraryListsLooksNotCharacters() {
        let entry = WidgetCatalog.entry(.water)!
        XCTAssertEqual(entry.variants.map(\.title), ["角色", "圆环", "液态"])
        XCTAssertFalse(entry.variants.contains { WidgetCatalog.isSupporterOnly($0.overrides) })
        let shiba = WidgetCatalog.make(.water, overrides: ["layout": .string("character"),
                                                           "character": .string("shiba")])!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: shiba.config, kind: .water), "角色")
        XCTAssertFalse(ProFeatures.isPro(shiba))
        let otter = WidgetCatalog.make(.water, overrides: ["layout": .string("character"),
                                                           "character": .string("otter")])!
        XCTAssertTrue(ProFeatures.isPro(otter))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetCatalog.make(.water)!.config, kind: .water),
                       "角色")
        XCTAssertFalse(ProFeatures.isPro(WidgetCatalog.make(.water)!))
    }
}
