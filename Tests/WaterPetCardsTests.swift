import Foundation
import XCTest

/// 喝水看水位、电子宠物看角色：八个小杯、四个需求小格，以及六只角色从
/// 添加面板挪进设置以后，已经放好的卡片样子和 Pro 判定不变。
final class WaterPetCardsTests: XCTestCase {

    // MARK: 八个小杯

    func testCupsFollowTheShareAndOnlyFillAllAtTheGoal() {
        XCTAssertEqual(WaterPetCards.filledCups(total: 0, goal: 2000), 0)
        XCTAssertEqual(WaterPetCards.filledCups(total: 1250, goal: 2000), 5, "62% 是 5 杯")
        XCTAssertEqual(WaterPetCards.filledCups(total: 100, goal: 2000), 0, "5% 还没到半杯")
        XCTAssertEqual(WaterPetCards.filledCups(total: 150, goal: 2000), 1)
        XCTAssertEqual(WaterPetCards.filledCups(total: 1990, goal: 2000), 7, "差一口不算满")
        XCTAssertEqual(WaterPetCards.filledCups(total: 2000, goal: 2000), 8)
        XCTAssertEqual(WaterPetCards.filledCups(total: 3500, goal: 2000), 8, "超过目标也是 8 杯")
        XCTAssertEqual(WaterPetCards.filledCups(total: 500, goal: 0), 0, "没有目标时一杯不画")
        XCTAssertEqual(WaterPetCards.cupSlots, 8)
    }

    // MARK: 四个需求小格

    func testEachCellDoesItsOwnThing() {
        XCTAssertEqual(WaterPetCards.action(for: .food), .feed)
        XCTAssertEqual(WaterPetCards.action(for: .mood), .play)
        XCTAssertEqual(WaterPetCards.action(for: .energy), .sleep)
        XCTAssertEqual(WaterPetCards.action(for: .clean), .wash)
        // 四格正好对应面板里的四个按钮。
        XCTAssertEqual(Set(PetNeed.allCases.map(WaterPetCards.action(for:))), Set(PetAction.buttons))
    }

    func testTheLowestLowNeedIsMarked() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertNil(WaterPetCards.mostNeeded(PetState(at: now)), "都还好时不标")
        let hungry = PetState(food: 28, mood: 82, energy: 60, clean: 90, at: now)
        XCTAssertEqual(WaterPetCards.mostNeeded(hungry), .food)
        let both = PetState(food: 30, mood: 82, energy: 12, clean: 90, at: now)
        XCTAssertEqual(WaterPetCards.mostNeeded(both), .energy, "两项都低时标更低的")
        let edge = PetState(food: VirtualPet.lowLine, at: now)
        XCTAssertNil(WaterPetCards.mostNeeded(edge), "正好在线上不算低")
    }

    func testCellHelpNamesTheNeedAndTheAction() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let state = PetState(food: 28, at: now)
        XCTAssertEqual(WaterPetCards.cellHelp(.food, state: state), "饱食 28，点一下喂食")
        var asleep = PetState(energy: 40, at: now)
        asleep.sleepSince = now
        XCTAssertEqual(WaterPetCards.cellHelp(.energy, state: asleep), "精力 40，点一下叫醒")
    }

    func testTappingACellActsOnThePet() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let hungry = PetState(food: 20, mood: 80, energy: 80, clean: 80, at: now)
        let fed = VirtualPet.performing(WaterPetCards.action(for: .food), on: hungry, now: now)
        XCTAssertGreaterThan(fed.food, hungry.food)
    }

    // MARK: 添加面板和旧卡片

    func testTheLibraryNoLongerListsCharacters() {
        XCTAssertEqual(WidgetCatalog.entry(.water)?.variants.map(\.title), ["角色", "圆环", "液态"])
        XCTAssertEqual(WidgetCatalog.entry(.pet)?.variants.isEmpty, true)
        // 角色仍是两种小组件的设置项。
        XCTAssertTrue(WidgetCatalog.configurableKeys(.water).contains("character"))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.pet).contains("character"))
    }

    /// 旧版本里从“柴犬”卡片放上去的喝水：存的是 layout = character 加
    /// character = shiba。读回来配置原样，是“角色”样式、柴犬，仍是 Pro。
    func testAPlacedShibaWaterCardKeepsItsLook() throws {
        let old = WidgetInstance(kind: .water, config: WidgetConfig([
            "layout": .string("character"), "character": .string("shiba"),
            "cupSize": .number(300),
        ]))
        let decoded = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded, old)
        XCTAssertEqual(WaterCharacter.from(decoded.config), .shiba)
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: decoded.config, kind: .water), "角色")
        XCTAssertTrue(ProFeatures.isPro(decoded), "Pro 角色仍是 Pro")
        XCTAssertEqual(WaterCharacter.shown(decoded.config, unlocked: false), .redPanda, "没解锁时照旧画小熊猫")
        XCTAssertEqual(WaterCharacter.shown(decoded.config, unlocked: true), .shiba)
    }

    func testAPlacedRedPandaWaterCardStaysFree() throws {
        let old = WidgetInstance(kind: .water, config: WidgetConfig([
            "layout": .string("character"), "character": .string("panda"),
        ]))
        let decoded = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: decoded.config, kind: .water), "角色")
        XCTAssertFalse(ProFeatures.isPro(decoded))
    }

    func testAPlacedOtterPetKeepsItsCharacter() throws {
        let old = WidgetInstance(kind: .pet, config: WidgetConfig(["character": .string("otter")]))
        let decoded = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded, old)
        XCTAssertEqual(WaterCharacter.from(decoded.config), .otter)
        XCTAssertTrue(ProFeatures.isSupporterStyle(decoded.config.values), "水獭仍是 Pro 角色")
        XCTAssertTrue(ProFeatures.isPro(decoded))
    }

    /// 设置里选角色：小熊猫免费，其余五只是 Pro 选项。
    func testCharacterChoicesKeepTheirProMark() {
        for kind in [WidgetKind.water, .pet] {
            XCTAssertFalse(ProFeatures.isProChoice(kind: kind, key: "character", value: "panda"))
            for character in WaterCharacter.allCases where character != .redPanda {
                XCTAssertTrue(ProFeatures.isProChoice(kind: kind, key: "character", value: character.rawValue))
            }
        }
    }
}
