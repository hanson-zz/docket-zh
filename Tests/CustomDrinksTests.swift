import Foundation
import XCTest

/// 自定义饮料：用户自己起名、定计入比例和图标，存在小组件配置里，记录里
/// 显示它的名字。
final class CustomDrinksTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute))!
    }

    private func added(_ name: String, factor: Double = 1, symbol: String = CustomDrinks.defaultSymbol,
                       id: String, to drinks: [CustomDrink] = []) -> [CustomDrink] {
        guard case .success(let list) = CustomDrinks.adding(name: name, factor: factor, symbol: symbol,
                                                            id: id, to: drinks) else {
            XCTFail("could not add \(name)")
            return drinks
        }
        return list
    }

    // MARK: Storing

    func testRoundTripThroughTheConfig() {
        var drinks = added("椰子水", factor: 0.9, symbol: "leaf.fill", id: "a1")
        drinks = added("豆浆", factor: 0.8, id: "b2", to: drinks)
        var config = WidgetConfig()
        CustomDrinks.store(drinks, in: &config)
        XCTAssertFalse(config.string(CustomDrinks.key).isEmpty)
        XCTAssertEqual(CustomDrinks.all(config), drinks)
        XCTAssertEqual(CustomDrinks.visible(config).map(\.name), ["椰子水", "豆浆"])

        CustomDrinks.store([], in: &config)
        XCTAssertNil(config[CustomDrinks.key])
        XCTAssertEqual(CustomDrinks.all(config), [])
    }

    func testUnreadableOrPartialJSONIsHandledGently() {
        XCTAssertEqual(CustomDrinks.all(WidgetConfig([CustomDrinks.key: .string("not json")])), [])
        // A missing share or symbol takes the default; a bad id or a repeat is dropped.
        let raw = #"[{"id":"ok1","name":"可乐"},{"id":"BAD ID","name":"x"},{"id":"ok1","name":"重复"},"#
            + #"{"id":"ok2","name":"酸奶","factor":3,"symbol":"no.such.symbol"}]"#
        let drinks = CustomDrinks.all(WidgetConfig([CustomDrinks.key: .string(raw)]))
        XCTAssertEqual(drinks.map(\.id), ["ok1", "ok2"])
        XCTAssertEqual(drinks[0].factor, 1)
        XCTAssertEqual(drinks[0].symbol, CustomDrinks.defaultSymbol)
        XCTAssertEqual(drinks[1].factor, 1.5, "clamped")
        XCTAssertEqual(drinks[1].symbol, CustomDrinks.defaultSymbol)
    }

    // MARK: Rules

    func testNamesAreTrimmedAndCut() {
        XCTAssertNil(CustomDrinks.cleanName("   "))
        XCTAssertNil(CustomDrinks.cleanName("\n"))
        XCTAssertEqual(CustomDrinks.cleanName("  椰子水 "), "椰子水")
        XCTAssertEqual(CustomDrinks.cleanName("一二三四五六七八九十"), "一二三四五六七八")
        XCTAssertEqual(CustomDrinks.cleanName("a\nb"), "a b")
    }

    func testFactorIsTenToOneHundredFiftyInTens() {
        XCTAssertEqual(CustomDrinks.clampFactor(0), 0.1)
        XCTAssertEqual(CustomDrinks.clampFactor(2), 1.5)
        XCTAssertEqual(CustomDrinks.clampFactor(0.84), 0.8)
        XCTAssertEqual(CustomDrinks.clampFactor(.nan), 1)
    }

    func testIDs() {
        XCTAssertEqual(CustomDrinks.validID("abc123"), "abc123")
        XCTAssertNil(CustomDrinks.validID(""))
        XCTAssertNil(CustomDrinks.validID("ABC"))
        XCTAssertNil(CustomDrinks.validID("a#b"))
        XCTAssertNil(CustomDrinks.validID("abcdefghijklm"))
        let seed = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890")!
        XCTAssertEqual(CustomDrinks.newID(among: [], seed: seed), "abcdef")
        let taken = [CustomDrink(id: "abcdef", name: "x", factor: 1, symbol: "drop.fill")]
        XCTAssertEqual(CustomDrinks.newID(among: taken, seed: seed), "abcdef1")
    }

    // MARK: Editing

    func testAddingRefusesEmptyDuplicateAndTooMany() {
        XCTAssertEqual(CustomDrinks.adding(name: " ", factor: 1, symbol: "drop.fill", id: "a", to: []),
                       .failure(.emptyName))
        let one = added("可乐", id: "a")
        XCTAssertEqual(CustomDrinks.adding(name: "可乐", factor: 1, symbol: "drop.fill", id: "b", to: one),
                       .failure(.duplicateName))
        var many: [CustomDrink] = []
        for i in 0..<CustomDrinks.maxCount { many = added("饮料\(i)", id: "d\(i)", to: many) }
        XCTAssertEqual(CustomDrinks.adding(name: "再来一个", factor: 1, symbol: "drop.fill", id: "zz", to: many),
                       .failure(.tooMany))
    }

    func testUpdatingKeepsTheIDAndChecksTheName() {
        var drinks = added("可乐", factor: 0.6, id: "a")
        drinks = added("豆浆", id: "b", to: drinks)
        guard case .success(let changed) = CustomDrinks.updating(id: "a", name: "无糖可乐", factor: 0.7,
                                                                 symbol: "wineglass.fill", in: drinks) else {
            return XCTFail("update failed")
        }
        XCTAssertEqual(changed[0], CustomDrink(id: "a", name: "无糖可乐", factor: 0.7, symbol: "wineglass.fill"))
        XCTAssertEqual(CustomDrinks.updating(id: "a", name: "豆浆", factor: 1, symbol: "drop.fill", in: drinks),
                       .failure(.duplicateName))
        XCTAssertEqual(CustomDrinks.updating(id: "nope", name: "x", factor: 1, symbol: "drop.fill", in: drinks),
                       .failure(.notFound))
        // Its own name again is fine.
        if case .failure = CustomDrinks.updating(id: "a", name: "可乐", factor: 0.5, symbol: "drop.fill", in: drinks) {
            XCTFail("renaming to its own name should work")
        }
    }

    /// 删除：今天的记录还在用的留着名字（标记删除），没人用的直接删掉。
    func testRemovingKeepsANameTheLogStillUses() {
        var drinks = added("可乐", id: "a")
        drinks = added("豆浆", id: "b", to: drinks)
        let days = WaterIntake.logging(.custom, amount: 330, factor: 0.6, drinkID: "a", in: [], goal: 2000,
                                       now: at(15), calendar: calendar)
        let afterA = CustomDrinks.removing(id: "a", in: drinks, days: days)
        XCTAssertEqual(afterA.map(\.id), ["a", "b"])
        XCTAssertTrue(afterA[0].removed)
        var config = WidgetConfig()
        CustomDrinks.store(afterA, in: &config)
        XCTAssertEqual(CustomDrinks.visible(config).map(\.id), ["b"])
        XCTAssertEqual(CustomDrinks.title(of: days[0].entries[0], in: CustomDrinks.all(config)), "可乐")

        let afterB = CustomDrinks.removing(id: "b", in: afterA, days: days)
        XCTAssertEqual(afterB.map(\.id), ["a"])

        // Once the row is gone, so is the removed drink.
        XCTAssertEqual(CustomDrinks.pruned(afterB, days: []), [])
        XCTAssertEqual(CustomDrinks.pruned(drinks, days: []), drinks, "visible drinks are never pruned")
    }

    // MARK: The log

    func testANamedDrinkIsLoggedWithItsID() {
        var days = WaterIntake.logging(.custom, amount: 300, factor: 0.9, drinkID: "k3f9a2", in: [], goal: 2000,
                                       now: at(16), calendar: calendar)
        days = WaterIntake.logging(.custom, amount: 200, factor: 0.7, in: days, goal: 2000,
                                   now: at(17), calendar: calendar)
        var config = WidgetConfig()
        WaterIntake.store(days, in: &config, now: at(18), calendar: calendar)
        XCTAssertEqual(config.strings(WaterIntake.key), ["20261019|2000|1600x300@90#k3f9a2,1700x200@70"])
        let read = WaterIntake.days(config)
        XCTAssertEqual(read, days)
        XCTAssertEqual(read[0].entries[0].drinkID, "k3f9a2")
        XCTAssertNil(read[0].entries[1].drinkID)
        XCTAssertEqual(read[0].total, 270 + 140)
    }

    func testAnIDOnlyBelongsToACustomDrinkAndABadOneLosesOnlyTheName() {
        XCTAssertNil(WaterEntry(minute: 600, type: .water, amount: 250, drinkID: "abc").drinkID)
        let config = WidgetConfig([WaterIntake.key: .list([
            .string("20261019|2000|0900x250#BAD!,1000x250@80#ok,1100w250#zz"),
        ])])
        let entries = WaterIntake.days(config)[0].entries
        XCTAssertEqual(entries.count, 3, "every drink still counts")
        XCTAssertNil(entries[0].drinkID)
        XCTAssertEqual(entries[1].drinkID, "ok")
        XCTAssertEqual(entries[1].factor, 0.8)
        XCTAssertNil(entries[2].drinkID)
        XCTAssertEqual(entries[2].type, .water)
    }

    /// 旧的“自定义”记录照常读出，显示“自定义”；删掉的饮料也退回“自定义”。
    func testRowNames() {
        let drinks = added("椰子水", symbol: "leaf.fill", id: "a")
        let named = WaterEntry(minute: 600, type: .custom, amount: 250, factor: 0.9, drinkID: "a")
        let old = WaterEntry(minute: 600, type: .custom, amount: 250, factor: 0.7)
        let gone = WaterEntry(minute: 600, type: .custom, amount: 250, drinkID: "zz")
        let tea = WaterEntry(minute: 600, type: .tea, amount: 250)
        XCTAssertEqual(CustomDrinks.title(of: named, in: drinks), "椰子水")
        XCTAssertEqual(CustomDrinks.symbol(of: named, in: drinks), "leaf.fill")
        XCTAssertEqual(CustomDrinks.title(of: old, in: drinks), "自定义")
        XCTAssertEqual(CustomDrinks.symbol(of: old, in: drinks), DrinkType.custom.symbol)
        XCTAssertEqual(CustomDrinks.title(of: gone, in: drinks), "自定义")
        XCTAssertEqual(CustomDrinks.title(of: tea, in: drinks), "茶")
        XCTAssertEqual(CustomDrinks.referencedIDs([WaterDay(key: "20261019", goal: 2000, entries: [named, old, tea])]),
                       ["a"])
    }

    func testSymbolsAreAShortFixedList() {
        XCTAssertTrue((6...8).contains(CustomDrinks.symbols.count))
        XCTAssertEqual(Set(CustomDrinks.symbols).count, CustomDrinks.symbols.count)
        XCTAssertTrue(CustomDrinks.symbols.contains(CustomDrinks.defaultSymbol))
    }
}
