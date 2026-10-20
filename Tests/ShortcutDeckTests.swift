import Foundation
import XCTest

/// 快捷指令卡片放多个：列表的读写、旧单个名字的迁移、勾选排序改外观、
/// 卡片尺寸，以及面板上那行“今天 09:12 · 已完成”。
final class ShortcutDeckTests: XCTestCase {
    private func config(_ values: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(values) }

    private func item(_ name: String, _ color: ShortcutColor = .indigo, _ symbol: ShortcutSymbol = .bolt) -> ShortcutItem {
        ShortcutItem(name: name, color: color, symbol: symbol)
    }

    // MARK: 存取

    func testItemRoundTripsAndKeepsPipesInTheName() {
        let original = item("Rent | Bills", .orange, .photo)
        XCTAssertEqual(ShortcutItem(parsing: original.encoded), original)
    }

    func testUnknownColorOrSymbolFallsBackAndBlankNamesAreDropped() {
        let parsed = ShortcutItem(parsing: "teal|rocket|Focus")
        XCTAssertEqual(parsed?.name, "Focus")
        XCTAssertEqual(parsed?.color, ShortcutDeck.defaultStyle(at: 0).color)
        XCTAssertEqual(parsed?.symbol, ShortcutDeck.defaultStyle(at: 0).symbol)
        XCTAssertNil(ShortcutItem(parsing: "red|bolt|  "))
        XCTAssertNil(ShortcutItem(parsing: "just a name"))
    }

    func testDuplicatesKeepTheFirst() {
        let stored = config([ShortcutDeck.key: .list([.string("red|bolt|A"), .string("blue|moon|A"), .string("green|drop|B")])])
        XCTAssertEqual(ShortcutDeck.items(stored).map(\.name), ["A", "B"])
        XCTAssertEqual(ShortcutDeck.items(stored).first?.color, .red)
    }

    // MARK: 旧配置迁移

    /// 旧卡片只有一个名字，读出来就是列表第一项。
    func testLegacyNameBecomesTheFirstItem() {
        let legacy = config(["name": .string("  Morning Routine ")])
        XCTAssertEqual(ShortcutDeck.items(legacy).map(\.name), ["Morning Routine"])
    }

    /// 和目录默认合并后旧卡片同时有空的 items 和旧名字，旧名字照样算数。
    func testLegacyNameSurvivesMergingWithTheEmptyDefault() {
        let merged = config(["name": .string("Focus"), ShortcutDeck.key: .list([])])
        XCTAssertEqual(ShortcutDeck.items(merged).map(\.name), ["Focus"])
    }

    func testEmptyLegacyNameIsNoItems() {
        XCTAssertEqual(ShortcutDeck.items(config(["name": .string("")])), [])
        XCTAssertEqual(ShortcutDeck.items(WidgetConfig()), [])
    }

    /// 写一次列表就删掉旧键：全部取消勾选后旧名字不能又回来。
    func testWritingDropsTheLegacyKeySoAnEmptyListStaysEmpty() {
        var cfg = config(["name": .string("Focus")])
        ShortcutDeck.write([], into: &cfg)
        XCTAssertNil(cfg["name"])
        XCTAssertEqual(ShortcutDeck.items(cfg), [])
    }

    func testStoredListWinsOverALegacyName() {
        let cfg = config(["name": .string("Old"), ShortcutDeck.key: .list([.string("red|bolt|New")])])
        XCTAssertEqual(ShortcutDeck.items(cfg).map(\.name), ["New"])
    }

    // MARK: 勾选、排序、外观

    func testTogglingAddsAtTheEndWithAnUnusedColorAndRemovesAgain() {
        var list = ShortcutDeck.toggling("A", in: [])
        list = ShortcutDeck.toggling("B", in: list)
        XCTAssertEqual(list.map(\.name), ["A", "B"])
        XCTAssertNotEqual(list[0].color, list[1].color)
        XCTAssertNotEqual(list[0].symbol, list[1].symbol)
        XCTAssertEqual(ShortcutDeck.toggling("A", in: list).map(\.name), ["B"])
    }

    func testTogglingStopsAtTheLimit() {
        let full = (0..<ShortcutDeck.limit).map { item("S\($0)") }
        XCTAssertEqual(ShortcutDeck.toggling("One more", in: full), full)
        // 满了也还能取消勾选。
        XCTAssertEqual(ShortcutDeck.toggling("S0", in: full).count, ShortcutDeck.limit - 1)
    }

    func testRestylingChangesOnlyThatShortcut() {
        let list = [item("A", .indigo, .bolt), item("B", .green, .moon)]
        let restyled = ShortcutDeck.restyling("A", color: .red, in: list)
        XCTAssertEqual(restyled[0], item("A", .red, .bolt))
        XCTAssertEqual(restyled[1], list[1])
        XCTAssertEqual(ShortcutDeck.restyling("B", symbol: .clock, in: list)[1], item("B", .green, .clock))
    }

    func testMovingAndDropIndex() {
        let list = ["A", "B", "C", "D"].map { item($0) }
        XCTAssertEqual(ShortcutDeck.moving(from: 0, to: 2, in: list).map(\.name), ["B", "C", "A", "D"])
        XCTAssertEqual(ShortcutDeck.moving(from: 3, to: -5, in: list).map(\.name), ["D", "A", "B", "C"])
        XCTAssertEqual(ShortcutDeck.dropIndex(from: 0, translation: 80, rowHeight: 54, count: 4), 1)
        XCTAssertEqual(ShortcutDeck.dropIndex(from: 0, translation: 1000, rowHeight: 54, count: 4), 3)
        XCTAssertEqual(ShortcutDeck.dropIndex(from: 2, translation: -20, rowHeight: 54, count: 4), 2)
    }

    func testSearchMatchesNamesAndPinyin() {
        let names = ["图片压缩", "图片转 PDF", "今日待办", "Morning Routine"]
        XCTAssertEqual(ShortcutDeck.search("图", in: names), ["图片压缩", "图片转 PDF"])
        XCTAssertEqual(ShortcutDeck.search("", in: names), names)
        XCTAssertEqual(ShortcutDeck.search("morning", in: names), ["Morning Routine"])
    }

    func testMissingOnlyCountsOnceTheListIsKnown() {
        let list = [item("A"), item("Gone")]
        XCTAssertEqual(ShortcutDeck.missing(list, available: nil), [])
        XCTAssertEqual(ShortcutDeck.missing(list, available: ["A", "B"]), ["Gone"])
    }

    // MARK: 卡片尺寸

    func testTileShowsTheFirstFourAndGrowsWithTheCount() {
        let six = (0..<6).map { item("S\($0)") }
        var cfg = WidgetConfig()
        ShortcutDeck.write(six, into: &cfg)
        XCTAssertEqual(ShortcutDeck.tileItems(cfg).map(\.name), ["S0", "S1", "S2", "S3"])
        XCTAssertEqual(ShortcutDeck.tileWidth(count: 1), 60)
        XCTAssertEqual(ShortcutDeck.tileWidth(count: 4), 204)
        XCTAssertEqual(ShortcutDeck.tileWidth(count: 9), ShortcutDeck.tileWidth(count: 4))
        XCTAssertLessThan(ShortcutDeck.tileWidth(count: 2), ShortcutDeck.tileWidth(count: 3))
        XCTAssertEqual(ShortcutDeck.tileWidth(count: 0), 140)
        XCTAssertGreaterThan(ShortcutDeck.columnHeight(count: 4), ShortcutDeck.columnHeight(count: 2) - 1)
    }

    /// 列表在面板里管，设置页不出现快捷指令的选项。
    func testTheListIsNotASettingsRow() {
        XCTAssertEqual(WidgetCatalog.configurableKeys(.shortcut), [])
    }

    func testCatalogSizesTheCardByItsIcons() {
        var cfg = WidgetConfig()
        ShortcutDeck.write([item("A"), item("B"), item("C")], into: &cfg)
        let card = WidgetInstance(kind: .shortcut, config: cfg)
        XCTAssertEqual(WidgetCatalog.naturalSize(card).width, ShortcutDeck.tileWidth(count: 3))
        let legacy = WidgetInstance(kind: .shortcut, config: config(["name": .string("Focus")]))
        XCTAssertEqual(WidgetCatalog.naturalSize(legacy).width, ShortcutDeck.tileWidth(count: 1))
    }

    // MARK: 运行结果

    func testOutputIsTextOnly() {
        XCTAssertEqual(ShortcutRun.output(from: Data("  勿扰已开到 11:00\n".utf8)), "勿扰已开到 11:00")
        XCTAssertNil(ShortcutRun.output(from: Data()))
        XCTAssertNil(ShortcutRun.output(from: Data(" \n\t".utf8)))
        XCTAssertNil(ShortcutRun.output(from: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x1A])))
        let long = String(repeating: "a", count: ShortcutRun.outputLimit + 50)
        XCTAssertEqual(ShortcutRun.output(from: Data(long.utf8))?.count, ShortcutRun.outputLimit + 1)
    }

    func testReasonIsTheFirstStderrLineWithoutThePrefix() {
        XCTAssertEqual(ShortcutRun.reason(fromStderr: "Error: Couldn't find shortcut\nmore"), "Couldn't find shortcut")
        XCTAssertEqual(ShortcutRun.reason(fromStderr: "\nPlain reason"), "Plain reason")
        XCTAssertNil(ShortcutRun.reason(fromStderr: "  \n"))
    }

    func testWhenSaysTodayYesterdayOrTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 23))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 12))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18, minute: 40))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 7, minute: 5))!
        XCTAssertEqual(ShortcutRun.when(today, now: now, calendar: calendar), "今天 09:12")
        XCTAssertEqual(ShortcutRun.when(yesterday, now: now, calendar: calendar), "昨天 18:40")
        XCTAssertEqual(ShortcutRun.when(earlier, now: now, calendar: calendar), "10月8日 07:05")
    }

    func testStatusLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 23))!
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 12))!
        let ok = ShortcutRun.Record(finishedAt: at, status: .ok, output: nil)
        let failed = ShortcutRun.Record(finishedAt: at, status: .failed("Couldn't find shortcut"), output: nil)

        XCTAssertEqual(ShortcutRun.line(record: nil, running: false, now: now, calendar: calendar).tone, .plain)
        XCTAssertEqual(ShortcutRun.line(record: ok, running: true, now: now, calendar: calendar).tone, .running)
        let done = ShortcutRun.line(record: ok, running: false, now: now, calendar: calendar)
        XCTAssertEqual(done.text, "今天 09:12 · 已完成")
        XCTAssertEqual(done.tone, .success)
        let bad = ShortcutRun.line(record: failed, running: false, now: now, calendar: calendar)
        XCTAssertEqual(bad.text, "今天 09:12 · Couldn't find shortcut")
        XCTAssertEqual(bad.tone, .failure)
        XCTAssertEqual(ShortcutRun.line(record: ok, running: false, missing: true, now: now, calendar: calendar).tone,
                       .failure)
    }

    func testRecordsSurviveEncoding() throws {
        let record = ShortcutRun.Record(finishedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                        status: .failed("nope"), output: "out")
        let data = try JSONEncoder().encode(["A": record])
        XCTAssertEqual(try JSONDecoder().decode([String: ShortcutRun.Record].self, from: data)["A"], record)
    }

    func testHeader() {
        XCTAssertEqual(ShortcutRun.header(count: 5), "5 个已选 · 前 4 个放在卡片上")
        XCTAssertEqual(ShortcutRun.header(count: 3), "3 个已选 · 都放在卡片上")
    }
}
