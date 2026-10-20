import XCTest

/// 面板分页和折叠记在哪、怎么读。
final class DetailPanelSectionsTests: XCTestCase {
    private enum Page: String, CaseIterable { case now, hours, days }

    func testKeysAreScopedByKind() {
        XCTAssertEqual(DetailPanelSections.pageKey(.weather), "detailPanel.page.weather")
        XCTAssertEqual(DetailPanelSections.foldKey(.posture, "week"), "detailPanel.fold.posture.week")
        XCTAssertNotEqual(DetailPanelSections.pageKey(.water), DetailPanelSections.pageKey(.lunar))
    }

    func testStoredPageIsUsedWhileItIsAvailable() {
        XCTAssertEqual(DetailPanelSections.page(stored: "hours", available: Page.allCases), .hours)
    }

    func testUnknownOrMissingPageFallsBackToTheFirst() {
        XCTAssertEqual(DetailPanelSections.page(stored: "", available: Page.allCases), .now)
        XCTAssertEqual(DetailPanelSections.page(stored: "gone", available: Page.allCases), .now)
        // 记着的那页被关掉了（比如农历关掉了宜忌）。
        XCTAssertEqual(DetailPanelSections.page(stored: "hours", available: [Page.now, .days]), .now)
        XCTAssertNil(DetailPanelSections.page(stored: "hours", available: [Page]()))
    }

    func testCollapsiblePagesStartClosed() {
        XCTAssertNil(DetailPanelSections.openPage(stored: "", available: Page.allCases))
        XCTAssertNil(DetailPanelSections.openPage(stored: "gone", available: Page.allCases))
        XCTAssertEqual(DetailPanelSections.openPage(stored: "days", available: Page.allCases), .days)
    }

    func testNewUserOpensTheInitialPage() {
        // 从没记过：打开给定的默认页；没给默认页时都收起。
        XCTAssertEqual(DetailPanelSections.openPage(stored: nil, available: Page.allCases, initial: .now), .now)
        XCTAssertNil(DetailPanelSections.openPage(stored: nil, available: Page.allCases))
        // 默认页不在能选的页里时都收起。
        XCTAssertNil(DetailPanelSections.openPage(stored: nil, available: [Page.hours, .days], initial: .now))
    }

    func testRememberedChoiceBeatsTheInitialPage() {
        // 用户收起过（存的空字符串）就保持收起。
        XCTAssertNil(DetailPanelSections.openPage(stored: "", available: Page.allCases, initial: .now))
        XCTAssertEqual(DetailPanelSections.openPage(stored: "days", available: Page.allCases, initial: .now), .days)
        // 收起默认页后再读出来仍是收起。
        let closed = DetailPanelSections.toggled(Page.now, open: .now)
        XCTAssertNil(DetailPanelSections.openPage(stored: closed, available: Page.allCases, initial: .now))
    }

    func testTappingTheOpenPageClosesIt() {
        XCTAssertEqual(DetailPanelSections.toggled(Page.days, open: .days), "")
        XCTAssertEqual(DetailPanelSections.toggled(Page.days, open: .now), "days")
        XCTAssertEqual(DetailPanelSections.toggled(Page.now, open: nil), "now")
    }
}
