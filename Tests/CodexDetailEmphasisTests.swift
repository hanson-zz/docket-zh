import XCTest

/// Codex 用量详情面板跟着卡片样式走：小卡用量优先（圆环或液态杯），中卡会话优先。
final class CodexDetailEmphasisTests: XCTestCase {
    func testSmallCardIsUsageFirstWithRings() {
        let config = WidgetConfig(["layout": .string(CodexCard.small)])
        let emphasis = CodexDetailEmphasis.from(config)
        XCTAssertEqual(emphasis, .usageRings)
        XCTAssertTrue(emphasis.usageFirst)
        XCTAssertTrue(emphasis.foldsSessions)
        XCTAssertFalse(emphasis.showsPanda)
    }

    func testMediumCardIsSessionsFirst() {
        let config = WidgetConfig(["layout": .string(CodexCard.medium)])
        let emphasis = CodexDetailEmphasis.from(config)
        XCTAssertEqual(emphasis, .sessions)
        XCTAssertFalse(emphasis.usageFirst)
        XCTAssertFalse(emphasis.foldsSessions)
        XCTAssertTrue(emphasis.showsPanda)
    }

    /// 没存 layout 的老卡片按小卡读；读不懂的 layout 也是。
    func testOldCardWithoutLayoutReadsAsSmall() {
        XCTAssertEqual(CodexDetailEmphasis.from(WidgetConfig()), .usageRings)
        XCTAssertEqual(CodexDetailEmphasis.from(WidgetConfig(["layout": .string("wide")])), .usageRings)
        XCTAssertEqual(CodexDetailEmphasis.from(WidgetConfig([LiquidLooks.key: .string("liquid")])), .usageLiquid)
    }

    func testLiquidLookOnSmallCardDrawsCups() {
        let config = WidgetConfig(["layout": .string(CodexCard.small),
                                   LiquidLooks.key: .string(LiquidLooks.CodexLook.liquid.rawValue)])
        XCTAssertEqual(CodexDetailEmphasis.from(config), .usageLiquid)
        XCTAssertTrue(CodexDetailEmphasis.usageLiquid.usageFirst)
    }

    /// 液态只画在小卡上，中卡存着 look = liquid 也还是会话优先。
    func testLiquidLookIsIgnoredOnMediumCard() {
        let config = WidgetConfig(["layout": .string(CodexCard.medium),
                                   LiquidLooks.key: .string(LiquidLooks.CodexLook.liquid.rawValue)])
        XCTAssertEqual(CodexDetailEmphasis.from(config), .sessions)
    }

    /// 目录里的两种样式点开各是一套，不再一模一样。
    func testCatalogVariantsOpenDifferentPanels() {
        let small = WidgetCatalog.make(.aiUsage, overrides: ["layout": .string(CodexCard.small)])!
        let medium = WidgetCatalog.make(.aiUsage, overrides: ["layout": .string(CodexCard.medium)])!
        XCTAssertEqual(CodexDetailEmphasis.from(WidgetCatalog.make(.aiUsage)!.config), .usageRings)
        XCTAssertEqual(CodexDetailEmphasis.from(small.config), .usageRings)
        XCTAssertEqual(CodexDetailEmphasis.from(medium.config), .sessions)
    }

    func testSessionSummary() {
        XCTAssertEqual(CodexDetailEmphasis.sessionSummary([]), "现在没有进行中的会话")
        XCTAssertEqual(CodexDetailEmphasis.sessionSummary([.working, .working]), "2 个会话进行中")
        XCTAssertEqual(CodexDetailEmphasis.sessionSummary([.waiting, .working, .done]), "3 个会话 · 1 个等你确认")
        XCTAssertEqual(CodexDetailEmphasis.sessionSummary([.done, .done]), "2 个会话已完成")
        XCTAssertEqual(CodexDetailEmphasis.sessionSummary([.working, .done]), "1 个会话进行中")
    }

    func testSummaryDotPrefersWaiting() {
        XCTAssertEqual(CodexDetailEmphasis.summaryState([.done, .waiting, .working]), .waiting)
        XCTAssertEqual(CodexDetailEmphasis.summaryState([.done, .working]), .working)
        XCTAssertEqual(CodexDetailEmphasis.summaryState([.done]), .done)
        XCTAssertEqual(CodexDetailEmphasis.summaryState([]), .idle)
    }

    /// 大圆环直径和粗进度条比卡片上的大（卡片圆环 36、进度条 6）。
    func testPanelGaugesAreBiggerThanTheCard() {
        XCTAssertGreaterThan(CodexDetailEmphasis.gaugeDiameter, 36 * 2)
        XCTAssertGreaterThan(CodexDetailEmphasis.mainBarHeight, 6)
        XCTAssertGreaterThan(CodexDetailEmphasis.groupBarHeight, 6)
    }
}
