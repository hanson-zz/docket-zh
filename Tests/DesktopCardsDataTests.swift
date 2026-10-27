import Foundation
import XCTest

/// 桌面卡片 · 数据组：接管哪些种类、每档几条、溢出、Codex 小号挑哪个额度、用量柱、温度条。
final class DesktopCardsDataTests: XCTestCase {

    func testHandlesItsKindsOnly() {
        for kind: WidgetKind in [.weather, .crypto, .watchlist, .stock, .github, .aiUsage, .mail,
                                 .calculator, .translate, .colorPicker, .emoji] {
            XCTAssertTrue(DesktopCardsDataPlan.handles(kind), "\(kind)")
        }
        for kind: WidgetKind in [.notes, .clock, .todo, .stripe, .paddle, .shopify, .music] {
            XCTAssertFalse(DesktopCardsDataPlan.handles(kind), "\(kind)")
        }
    }

    func testWidePanelsAreOpenedByDedicatedLayouts() {
        XCTAssertEqual(DesktopCardsDataPlan.widePanelKinds, [.stock, .watchlist])
        XCTAssertTrue(DesktopCardsDataPlan.widePanelKinds.isSubset(of: DesktopCardsDataPlan.kinds))
    }

    func testDedicatedModeOpensWidePanels() {
        XCTAssertEqual(DesktopPinSupport.mode(.stock, hasDetail: true, panelWidth: 360), .dedicated)
        XCTAssertEqual(DesktopPinSupport.mode(.watchlist, hasDetail: true, panelWidth: 360), .dedicated)
        XCTAssertEqual(DesktopPinSupport.mode(.github, hasDetail: true, panelWidth: 320), .dedicated)
        XCTAssertEqual(DesktopPinSupport.sizes(.dedicated), DesktopPinSize.allCases)
    }

    func testRowsGrowWithSize() {
        for kind in DesktopCardsDataPlan.kinds {
            let small = DesktopCardsDataPlan.rows(kind, size: .small)
            let medium = DesktopCardsDataPlan.rows(kind, size: .medium)
            let large = DesktopCardsDataPlan.rows(kind, size: .large)
            XCTAssertLessThanOrEqual(small, max(medium, large), "\(kind)")
        }
        XCTAssertEqual(DesktopCardsDataPlan.rows(.crypto, size: .small), 1)
        XCTAssertEqual(DesktopCardsDataPlan.rows(.crypto, size: .medium), 3)
        XCTAssertEqual(DesktopCardsDataPlan.rows(.crypto, size: .large), 6)
        XCTAssertEqual(DesktopCardsDataPlan.rows(.mail, size: .small), 0)
        XCTAssertEqual(DesktopCardsDataPlan.rows(.notes, size: .large), 0)
    }

    func testGridsMatchRowCounts() {
        for size in DesktopPinSize.allCases {
            let grid = DesktopCardsDataPlan.emojiGrid(size)
            XCTAssertEqual(grid.columns * grid.rows, DesktopCardsDataPlan.rows(.emoji, size: size), "\(size)")
        }
        for size: DesktopPinSize in [.medium, .large] {
            let grid = DesktopCardsDataPlan.colorGrid(size)
            XCTAssertEqual(grid.columns * grid.rows, DesktopCardsDataPlan.rows(.colorPicker, size: size), "\(size)")
        }
    }

    func testOverflowGivesLastSlotToMore() {
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: 3, capacity: 4), .init(shown: 3, hidden: 0))
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: 4, capacity: 4), .init(shown: 4, hidden: 0))
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: 9, capacity: 4), .init(shown: 3, hidden: 6))
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: 5, capacity: 1), .init(shown: 1, hidden: 4))
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: -2, capacity: 4), .init(shown: 0, hidden: 0))
        XCTAssertEqual(DesktopCardsDataPlan.overflow(count: 2, capacity: 0), .init(shown: 0, hidden: 2))
    }

    func testFeaturedWindowIsTheMostUsed() {
        XCTAssertEqual(DesktopCardsDataPlan.featuredWindow(usedFractions: [0.38, 0.61]), 1)
        XCTAssertEqual(DesktopCardsDataPlan.featuredWindow(usedFractions: [0.9, 0.61]), 0)
        XCTAssertEqual(DesktopCardsDataPlan.featuredWindow(usedFractions: [0.5, 0.5]), 0)
        XCTAssertEqual(DesktopCardsDataPlan.featuredWindow(usedFractions: [.nan, 0.2]), 1)
        XCTAssertNil(DesktopCardsDataPlan.featuredWindow(usedFractions: []))
    }

    func testUsageBarsNormaliseAndPad() {
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([10, 20, 40], count: 3), [0.25, 0.5, 1])
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([40], count: 3), [0, 0, 1])
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([5, 10, 20, 40], count: 2), [0.5, 1])
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([0, 0], count: 2), [0, 0])
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([-3, 6], count: 2), [0, 1])
        XCTAssertEqual(DesktopCardsDataPlan.usageBars([1, 2], count: 0), [])
    }

    func testRangeBarClampsToScale() {
        let mid = DesktopCardsDataPlan.rangeBar(low: 10, high: 20, scaleLow: 0, scaleHigh: 40)
        XCTAssertEqual(mid.start, 0.25, accuracy: 1e-9)
        XCTAssertEqual(mid.end, 0.5, accuracy: 1e-9)
        let out = DesktopCardsDataPlan.rangeBar(low: -10, high: 50, scaleLow: 0, scaleHigh: 40)
        XCTAssertEqual(out.start, 0)
        XCTAssertEqual(out.end, 1)
        let flat = DesktopCardsDataPlan.rangeBar(low: 5, high: 5, scaleLow: 5, scaleHigh: 5)
        XCTAssertEqual(flat.start, 0)
        XCTAssertEqual(flat.end, 1)
    }
}
