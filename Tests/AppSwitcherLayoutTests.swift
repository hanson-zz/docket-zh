import XCTest

/// 应用切换器 v2 的排版、键盘移动和缩略图缓存（见 AppSwitcherLayout）。
final class AppSwitcherLayoutTests: XCTestCase {

    private typealias L = AppSwitcherLayout
    private typealias P = AppSwitcherLayout.Position

    func testColumnsFollowWidth() {
        // 320 面板内容区 288，尾巴在侧边时 280：都是 5 列；460 面板内容区 428：7 列。
        XCTAssertEqual(L.columns(width: 288), 5)
        XCTAssertEqual(L.columns(width: 280), 5)
        XCTAssertEqual(L.columns(width: 428), 7)
        XCTAssertEqual(L.columns(width: 52), 1)
        XCTAssertEqual(L.columns(width: 20), 1, "再窄也至少 1 列")
        XCTAssertEqual(L.columns(width: 0), 1)
    }

    func testRowsAndHeight() {
        XCTAssertEqual(L.rows(count: 0, columns: 5), 0)
        XCTAssertEqual(L.rows(count: 5, columns: 5), 1)
        XCTAssertEqual(L.rows(count: 10, columns: 5), 2)
        XCTAssertEqual(L.rows(count: 11, columns: 5), 3)
        XCTAssertEqual(L.gridHeight(count: 0, columns: 5), 0)
        XCTAssertEqual(L.gridHeight(count: 3, columns: 5), 52)
        XCTAssertEqual(L.gridHeight(count: 10, columns: 5), 52 * 2 + 6)
        XCTAssertEqual(L.gridHeight(count: 40, columns: 5, maxRows: 4), 52 * 4 + 6 * 3, "多了在里面滚")
    }

    func testTileFits() {
        XCTAssertEqual(L.tileContentWidth, 7 * 34 + 6 * 2)
        let all = AppStrip.fit(total: 7, capacity: L.tileCapacity)
        XCTAssertEqual([all.shown, all.overflow], [7, 0])
        let more = AppStrip.fit(total: 11, capacity: L.tileCapacity)
        XCTAssertEqual([more.shown, more.overflow], [6, 5], "6 个加「+5」")
    }

    func testThumbWidth() {
        let two = L.thumbWidth(count: 2, available: 264)
        XCTAssertEqual(two.width, 124, "两张放得下，最宽 124")
        XCTAssertFalse(two.scrolls)
        let four = L.thumbWidth(count: 4, available: 404)
        XCTAssertEqual(four.width, 92, accuracy: 0.01)
        XCTAssertFalse(four.scrolls)
        let five = L.thumbWidth(count: 5, available: 264)
        XCTAssertEqual(five.width, 92)
        XCTAssertTrue(five.scrolls, "放不下时 92 宽横向滚动")
        XCTAssertFalse(L.thumbWidth(count: 0, available: 264).scrolls)
    }

    func testStatus() {
        XCTAssertEqual(L.status(isActive: true, isRunning: true, windows: 3), "当前 · 3 个窗口")
        XCTAssertEqual(L.status(isActive: false, isRunning: true, windows: 2), "2 个窗口")
        XCTAssertEqual(L.status(isActive: true, isRunning: true, windows: nil), "当前")
        XCTAssertEqual(L.status(isActive: false, isRunning: true, windows: nil), "")
        XCTAssertEqual(L.status(isActive: false, isRunning: true, windows: 0), "没有窗口")
        XCTAssertEqual(L.status(isActive: true, isRunning: true, windows: 0), "当前 · 没有窗口")
        XCTAssertEqual(L.status(isActive: false, isRunning: false, windows: 2), "没开")
    }

    func testMoveStartsAtFirstFilledSection() {
        XCTAssertEqual(L.move(nil, .right, sections: [0, 4], columns: 5), P(section: 1, index: 0))
        XCTAssertEqual(L.move(nil, .down, sections: [3, 4], columns: 5), P(section: 0, index: 0))
        XCTAssertNil(L.move(nil, .down, sections: [0, 0], columns: 5))
        XCTAssertEqual(L.move(P(section: 0, index: 9), .left, sections: [0, 4], columns: 5), P(section: 1, index: 0),
                       "选中的那块空了，从头来")
    }

    func testMoveLeftRightCrossesSections() {
        let sections = [3, 10]
        XCTAssertEqual(L.move(P(section: 0, index: 2), .right, sections: sections, columns: 5), P(section: 1, index: 0))
        XCTAssertEqual(L.move(P(section: 1, index: 0), .left, sections: sections, columns: 5), P(section: 0, index: 2))
        XCTAssertEqual(L.move(P(section: 0, index: 0), .left, sections: sections, columns: 5), P(section: 0, index: 0))
        XCTAssertEqual(L.move(P(section: 1, index: 9), .right, sections: sections, columns: 5), P(section: 1, index: 9))
    }

    func testMoveUpDownKeepsColumn() {
        let sections = [3, 12]
        // 正在运行 12 个，5 列：0-4、5-9、10-11。
        XCTAssertEqual(L.move(P(section: 1, index: 7), .down, sections: sections, columns: 5), P(section: 1, index: 11),
                       "下一行短，落在最后一个")
        XCTAssertEqual(L.move(P(section: 1, index: 2), .down, sections: sections, columns: 5), P(section: 1, index: 7))
        XCTAssertEqual(L.move(P(section: 1, index: 11), .down, sections: sections, columns: 5), P(section: 1, index: 11))
        XCTAssertEqual(L.move(P(section: 1, index: 4), .up, sections: sections, columns: 5), P(section: 0, index: 2),
                       "上一块只有一行 3 个，落在最后一个")
        XCTAssertEqual(L.move(P(section: 1, index: 1), .up, sections: sections, columns: 5), P(section: 0, index: 1))
        XCTAssertEqual(L.move(P(section: 0, index: 2), .down, sections: sections, columns: 5), P(section: 1, index: 2))
        XCTAssertEqual(L.move(P(section: 0, index: 1), .up, sections: sections, columns: 5), P(section: 0, index: 1))
    }

    func testCacheExpiresAndEvicts() {
        var cache = ExpiringLRUCache<Int>(capacity: 2, lifetime: 10)
        let start = Date(timeIntervalSince1970: 1000)
        cache.insert(1, for: "a", at: start)
        cache.insert(2, for: "b", at: start)
        XCTAssertTrue(cache.isFresh("a", at: start.addingTimeInterval(9)))
        XCTAssertFalse(cache.isFresh("a", at: start.addingTimeInterval(10)), "过了寿命不新鲜")
        XCTAssertEqual(cache.peek("a"), 1, "不新鲜也还能读")
        _ = cache.value(for: "a")
        cache.insert(3, for: "c", at: start)
        XCTAssertNil(cache.peek("b"), "最久没用的 b 被挤掉")
        XCTAssertEqual(cache.peek("a"), 1)
        XCTAssertEqual(cache.count, 2)
        cache.remove("a")
        XCTAssertNil(cache.peek("a"))
        XCTAssertFalse(cache.isFresh("zzz", at: start))
    }
}
