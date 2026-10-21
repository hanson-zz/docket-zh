import XCTest
@testable import Docket

/// 设置 ▸ 小组件管理的下半：未添加列表、分组计数、搜索、折叠。
final class WidgetManagementTests: XCTestCase {

    private func candidate(_ kind: WidgetKind, _ name: String, _ category: WidgetCategory,
                           aliases: [String] = []) -> WidgetManagement.Candidate {
        WidgetManagement.Candidate(kind: kind, name: name, category: category, aliases: aliases)
    }

    // MARK: 目录

    func testCatalogCandidatesFollowTheLibrary() {
        let all = WidgetManagement.catalogCandidates()
        let shippable = WidgetCatalog.entries.filter(\.selfContained)
        // 库里显示的每种各一行，不多不少。
        XCTAssertEqual(all.count, shippable.count)
        XCTAssertEqual(Set(all.map(\.kind)), Set(shippable.map(\.kind)))
        XCTAssertEqual(Set(all.map(\.kind)).count, all.count)
        // 不在目录里的旧种类（商业看板）不列。
        for gone in [WidgetKind.stripe, .paddle, .shopify] {
            XCTAssertFalse(all.contains { $0.kind == gone }, "\(gone)")
        }
        // 顺序和库一样按 displayOrder。
        let ranks = all.map { WidgetLibraryGroups.rank($0.kind) }
        XCTAssertEqual(ranks, ranks.sorted())
        // 名字和分类用库里的。
        let clock = all.first { $0.kind == .clock }
        XCTAssertEqual(clock?.name, "时钟")
        XCTAssertEqual(clock?.category, .time)
    }

    func testCandidateUsesTheFirstLibraryCardStyle() throws {
        let all = WidgetManagement.catalogCandidates()
        for entry in WidgetCatalog.entries where entry.selfContained {
            let c = try XCTUnwrap(all.first { $0.kind == entry.kind })
            XCTAssertEqual(c.overrides, entry.variants.first?.overrides ?? [:], "\(entry.kind)")
            // 用这套样式一定能做出小组件，和在库里点第一张卡片一样。
            XCTAssertNotNil(WidgetCatalog.make(c.kind, overrides: c.overrides), "\(entry.kind)")
        }
    }

    func testAliasesAreAttachedByName() {
        let all = WidgetManagement.catalogCandidates { $0 == "天气" ? ["Weather"] : [] }
        XCTAssertEqual(all.first { $0.kind == .weather }?.aliases, ["Weather"])
        XCTAssertEqual(all.first { $0.kind == .clock }?.aliases, [])
    }

    // MARK: 未添加

    func testPlacedKindsDisappearUnlessRepeatable() {
        let list = [candidate(.weather, "天气", .weather), candidate(.clock, "时钟", .time),
                    candidate(.battery, "电池", .system), candidate(.countdown, "倒计时", .time)]
        let left = WidgetManagement.unadded(list, placed: [.weather, .clock, .clock, .countdown])
        // 天气放过了，不列；时钟和倒计时可以放多个，照样列；电池没放。
        XCTAssertEqual(left.map(\.kind), [.clock, .battery, .countdown])
        XCTAssertEqual(WidgetManagement.unadded(list, placed: []).map(\.kind), list.map(\.kind))
        XCTAssertEqual(WidgetManagement.unadded([], placed: [.clock]), [])
    }

    func testUnaddedListsEachKindOnce() {
        let list = [candidate(.clock, "时钟", .time), candidate(.clock, "时钟", .time)]
        XCTAssertEqual(WidgetManagement.unadded(list, placed: []).count, 1)
    }

    func testRepeatableKindsAreShippable() {
        let shippable = Set(WidgetCatalog.entries.filter(\.selfContained).map(\.kind))
        XCTAssertTrue(WidgetManagement.repeatableKinds.isSubset(of: shippable))
        XCTAssertTrue(WidgetManagement.canAddAgain(.clock))
        XCTAssertTrue(WidgetManagement.canAddAgain(.countdown))
        XCTAssertFalse(WidgetManagement.canAddAgain(.weather))
        XCTAssertFalse(WidgetManagement.canAddAgain(.battery))
    }

    func testFullShelfWithOnlySinglesLeavesRepeatablesOnly() {
        let all = WidgetManagement.catalogCandidates()
        let left = WidgetManagement.unadded(all, placed: all.map(\.kind))
        XCTAssertEqual(Set(left.map(\.kind)), WidgetManagement.repeatableKinds)
    }

    // MARK: 分组和计数

    func testSectionsFollowLibraryCategoryOrderAndDropEmpty() {
        let list = [candidate(.weather, "天气", .weather), candidate(.clock, "时钟", .time),
                    candidate(.battery, "电池", .system), candidate(.world, "世界时钟", .time)]
        let sections = WidgetManagement.sections(list)
        XCTAssertEqual(sections.map(\.category), [.time, .system, .weather])
        XCTAssertEqual(sections.map(\.items.count), [2, 1, 1])
        XCTAssertEqual(sections[0].items.map(\.kind), [.clock, .world])
        XCTAssertEqual(WidgetManagement.sections([]), [])
    }

    func testSectionCountsAddUpForTheRealCatalog() {
        let all = WidgetManagement.catalogCandidates()
        let sections = WidgetManagement.sections(all)
        XCTAssertEqual(sections.reduce(0) { $0 + $1.items.count }, all.count)
        let order = sections.map(\.category)
        XCTAssertEqual(order, WidgetCategory.ordered.filter(order.contains))
    }

    // MARK: 搜索

    func testSearchMatchesChineseEnglishAndPinyin() {
        let list = [candidate(.weather, "天气", .weather, aliases: ["Weather"]),
                    candidate(.clock, "时钟", .time, aliases: ["Clock"]),
                    candidate(.battery, "电池", .system)]
        XCTAssertEqual(WidgetManagement.sections(list, query: "天气").flatMap(\.items).map(\.kind), [.weather])
        XCTAssertEqual(WidgetManagement.sections(list, query: "WEATHER").flatMap(\.items).map(\.kind), [.weather])
        XCTAssertEqual(WidgetManagement.sections(list, query: "shizhong").flatMap(\.items).map(\.kind), [.clock])
        XCTAssertEqual(WidgetManagement.sections(list, query: "battery").flatMap(\.items).map(\.kind), [.battery])
        XCTAssertEqual(WidgetManagement.sections(list, query: "没有这个"), [])
        // 空白搜索词等于没搜。
        XCTAssertEqual(WidgetManagement.sections(list, query: "  ").flatMap(\.items).count, 3)
    }

    func testFilterTopHalfByNames() {
        let clock = WidgetInstance(kind: .clock, config: WidgetConfig([:]))
        let weather = WidgetInstance(kind: .weather, config: WidgetConfig([:]))
        let names: (WidgetInstance) -> [String] = { $0.kind == .clock ? ["时钟", "Clock"] : ["天气", "Weather"] }
        XCTAssertEqual(WidgetManagement.filter([clock, weather], query: "clock", names: names).map(\.id), [clock.id])
        XCTAssertEqual(WidgetManagement.filter([clock, weather], query: "天气", names: names).map(\.id), [weather.id])
        XCTAssertEqual(WidgetManagement.filter([clock, weather], query: "", names: names).count, 2)
    }

    // MARK: 折叠

    func testOnlyFirstCategoryOpensByDefault() {
        let sections = WidgetManagement.sections([candidate(.clock, "时钟", .time),
                                                  candidate(.battery, "电池", .system),
                                                  candidate(.weather, "天气", .weather)])
        XCTAssertTrue(WidgetManagement.isExpanded(.time, in: sections, query: "", choices: [:]))
        XCTAssertFalse(WidgetManagement.isExpanded(.system, in: sections, query: "", choices: [:]))
        // 用户点过的照用户的。
        XCTAssertFalse(WidgetManagement.isExpanded(.time, in: sections, query: "", choices: [.time: false]))
        XCTAssertTrue(WidgetManagement.isExpanded(.system, in: sections, query: "", choices: [.system: true]))
        // 有搜索词时都展开。
        XCTAssertTrue(WidgetManagement.isExpanded(.system, in: sections, query: "dian", choices: [.system: false]))
        XCTAssertFalse(WidgetManagement.isExpanded(.time, in: [], query: "", choices: [:]))
        XCTAssertFalse(WidgetManagement.hasQuery(" \n"))
        XCTAssertTrue(WidgetManagement.hasQuery(" a"))
    }

    func testVisibleShowsFourThenMore() {
        let items = (0..<6).map { _ in candidate(.clock, "时钟", .time) }
        let folded = WidgetManagement.visible(items, showAll: false)
        XCTAssertEqual(folded.shown.count, 4)
        XCTAssertEqual(folded.more, 2)
        let open = WidgetManagement.visible(items, showAll: true)
        XCTAssertEqual(open.shown.count, 6)
        XCTAssertEqual(open.more, 0)
        let few = WidgetManagement.visible(Array(items.prefix(4)), showAll: false)
        XCTAssertEqual(few.shown.count, 4)
        XCTAssertEqual(few.more, 0)
        XCTAssertEqual(WidgetManagement.visible([], showAll: false).more, 0)
    }
}
