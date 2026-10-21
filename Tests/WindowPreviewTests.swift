import CoreGraphics
import Foundation
import XCTest

final class WindowPreviewTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: 悬停状态机

    func testOpensOnlyAfterHalfASecond() {
        var hover = WindowPreviewHover()
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: false, now: at(0)))
        XCTAssertEqual(hover.deadline, at(0).addingTimeInterval(WindowPreview.openDelay))
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: false, now: at(0.3)))
        XCTAssertEqual(hover.update(tile: "a", overPopup: false, blocked: false, now: at(0.5)), .show(id: "a"))
        XCTAssertEqual(hover.openID, "a")
        XCTAssertNil(hover.deadline)
    }

    func testPassingOverATileDoesNotOpen() {
        var hover = WindowPreviewHover()
        _ = hover.update(tile: "a", overPopup: false, blocked: false, now: at(0))
        _ = hover.update(tile: nil, overPopup: false, blocked: false, now: at(0.2))
        XCTAssertEqual(hover.phase, .idle)
        XCTAssertNil(hover.update(tile: nil, overPopup: false, blocked: false, now: at(1)))
    }

    func testMovingToAnotherTileRestartsTheWait() {
        var hover = WindowPreviewHover()
        _ = hover.update(tile: "a", overPopup: false, blocked: false, now: at(0))
        XCTAssertNil(hover.update(tile: "b", overPopup: false, blocked: false, now: at(0.4)))
        XCTAssertNil(hover.update(tile: "b", overPopup: false, blocked: false, now: at(0.6)))
        XCTAssertEqual(hover.update(tile: "b", overPopup: false, blocked: false, now: at(0.95)), .show(id: "b"))
    }

    func testOpenSwitchesStraightAwayToAnotherApp() {
        var hover = opened("a")
        XCTAssertEqual(hover.update(tile: "b", overPopup: false, blocked: false, now: at(2)), .show(id: "b"))
        XCTAssertEqual(hover.openID, "b")
    }

    func testStaysOpenWhileOverThePopupAndClosesAfterGrace() {
        var hover = opened("a")
        // 从格子走到小窗中间的空隙。
        XCTAssertNil(hover.update(tile: nil, overPopup: false, blocked: false, now: at(2)))
        XCTAssertEqual(hover.openID, "a")
        XCTAssertNil(hover.update(tile: nil, overPopup: true, blocked: false, now: at(2.1)))
        XCTAssertEqual(hover.phase, .open(id: "a"))
        // 离开小窗。
        XCTAssertNil(hover.update(tile: nil, overPopup: false, blocked: false, now: at(3)))
        XCTAssertEqual(hover.deadline, at(3).addingTimeInterval(WindowPreview.closeGrace))
        XCTAssertNil(hover.update(tile: nil, overPopup: false, blocked: false, now: at(3.1)))
        XCTAssertEqual(hover.update(tile: nil, overPopup: false, blocked: false, now: at(3.35)), .hide)
        XCTAssertEqual(hover.phase, .idle)
    }

    func testBlockedNeverOpensAndClosesAnOpenOne() {
        var hover = WindowPreviewHover()
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: true, now: at(0)))
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: true, now: at(5)))
        XCTAssertEqual(hover.phase, .idle)

        var open = opened("a")
        XCTAssertEqual(open.update(tile: "a", overPopup: false, blocked: true, now: at(2)), .hide)
        XCTAssertEqual(open.phase, .idle)
    }

    func testAfterAClickTheSameTileWaitsForThePointerToLeave() {
        var hover = opened("a")
        hover.reset(suppress: "a")
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: false, now: at(2)))
        XCTAssertNil(hover.update(tile: "a", overPopup: false, blocked: false, now: at(5)))
        XCTAssertEqual(hover.phase, .idle)
        // 离开后再回来照常等 0.5 秒弹出。
        _ = hover.update(tile: nil, overPopup: false, blocked: false, now: at(6))
        XCTAssertNil(hover.suppressedID)
        _ = hover.update(tile: "a", overPopup: false, blocked: false, now: at(7))
        XCTAssertEqual(hover.update(tile: "a", overPopup: false, blocked: false, now: at(7.5)), .show(id: "a"))
    }

    func testSuppressionDoesNotStopAnotherTile() {
        var hover = WindowPreviewHover()
        hover.reset(suppress: "a")
        _ = hover.update(tile: "b", overPopup: false, blocked: false, now: at(0))
        XCTAssertEqual(hover.update(tile: "b", overPopup: false, blocked: false, now: at(0.5)), .show(id: "b"))
    }

    private func opened(_ id: String) -> WindowPreviewHover {
        var hover = WindowPreviewHover()
        _ = hover.update(tile: id, overPopup: false, blocked: false, now: at(0))
        _ = hover.update(tile: id, overPopup: false, blocked: false, now: at(1))
        XCTAssertEqual(hover.openID, id)
        return hover
    }

    // MARK: 排序和截断

    func testMinimizedGoLastAndOrderIsKept() {
        let list = [
            WindowPreview.Entry(index: 0, title: "下载", minimized: false),
            WindowPreview.Entry(index: 1, title: "旧的", minimized: true),
            WindowPreview.Entry(index: 2, title: "文稿", minimized: false),
            WindowPreview.Entry(index: 3, title: "另一个", minimized: true),
        ]
        let result = WindowPreview.arrange(list)
        XCTAssertEqual(result.shown.map(\.title), ["下载", "文稿", "旧的", "另一个"])
        XCTAssertEqual(result.more, 0)
    }

    func testCapsAtEight() {
        let list = (0..<11).map { WindowPreview.Entry(index: $0, title: "w\($0)", minimized: $0 == 0) }
        let result = WindowPreview.arrange(list)
        XCTAssertEqual(result.shown.count, WindowPreview.maxWindows)
        XCTAssertEqual(result.more, 3)
        XCTAssertEqual(result.shown.first?.title, "w1")
        XCTAssertFalse(result.shown.contains { $0.title == "w0" }, "最小化的排到后面先被截掉")
    }

    func testEmptyAndOddLimits() {
        XCTAssertEqual(WindowPreview.arrange([]).shown, [])
        XCTAssertEqual(WindowPreview.arrange([]).more, 0)
        let one = [WindowPreview.Entry(index: 0, title: "a", minimized: false)]
        XCTAssertEqual(WindowPreview.arrange(one, limit: -1).more, 1)
    }

    func testDisplayTitle() {
        XCTAssertEqual(WindowPreview.displayTitle("  报价单.pdf \n"), "报价单.pdf")
        XCTAssertEqual(WindowPreview.displayTitle(""), "无标题窗口")
        XCTAssertEqual(WindowPreview.displayTitle(nil), "无标题窗口")
        XCTAssertEqual(WindowPreview.header(appName: "访达", count: 3), "访达 · 3 个窗口")
    }

    // MARK: 尺寸和方向

    func testColumnsCapAndScreenWidth() {
        XCTAssertEqual(WindowPreview.visibleColumns(count: 0, visibleWidth: 1440), 1)
        XCTAssertEqual(WindowPreview.visibleColumns(count: 2, visibleWidth: 1440), 2)
        XCTAssertEqual(WindowPreview.visibleColumns(count: 8, visibleWidth: 1440), 4)
        XCTAssertEqual(WindowPreview.visibleColumns(count: 8, visibleWidth: 500), 2)
        XCTAssertEqual(WindowPreview.visibleColumns(count: 8, visibleWidth: 100), 1)
    }

    func testPanelSizeGrowsWithNoticeAndThumbnails() {
        let plain = WindowPreview.panelSize(count: 3, thumbnails: true, notice: false, visibleWidth: 1440)
        let text = WindowPreview.panelSize(count: 3, thumbnails: false, notice: true, visibleWidth: 1440)
        XCTAssertGreaterThan(plain.height, text.height - WindowPreview.noticeHeight - WindowPreview.spacing)
        XCTAssertEqual(plain.width, 3 * 184 + 2 * 10 + 28)
        let empty = WindowPreview.panelSize(count: 0, thumbnails: true, notice: true, visibleWidth: 1440)
        XCTAssertEqual(empty.width, WindowPreview.minWidth)
        let narrow = WindowPreview.panelSize(count: 8, thumbnails: true, notice: false, visibleWidth: 280)
        XCTAssertLessThanOrEqual(narrow.width, max(WindowPreview.minWidth, 280))
    }

    func testOpensAwayFromEachEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 400, height: 200)
        let bottom = WindowPreview.origin(edge: .bottom, anchor: CGPoint(x: 700, y: 60), size: size, visible: visible)
        XCTAssertEqual(bottom, CGPoint(x: 500, y: 70))
        let top = WindowPreview.origin(edge: .top, anchor: CGPoint(x: 700, y: 840), size: size, visible: visible)
        XCTAssertEqual(top, CGPoint(x: 500, y: 630))
        let left = WindowPreview.origin(edge: .left, anchor: CGPoint(x: 60, y: 450), size: size, visible: visible)
        XCTAssertEqual(left, CGPoint(x: 70, y: 350))
        let right = WindowPreview.origin(edge: .right, anchor: CGPoint(x: 1380, y: 450), size: size, visible: visible)
        XCTAssertEqual(right, CGPoint(x: 970, y: 350))
    }

    func testClampsIntoTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 400, height: 200)
        let corner = WindowPreview.origin(edge: .bottom, anchor: CGPoint(x: 20, y: 60), size: size, visible: visible)
        XCTAssertEqual(corner.x, WindowPreview.screenMargin)
        let farRight = WindowPreview.origin(edge: .bottom, anchor: CGPoint(x: 1430, y: 60), size: size, visible: visible)
        XCTAssertEqual(farRight.x, 1440 - 400 - WindowPreview.screenMargin)
        let low = WindowPreview.origin(edge: .left, anchor: CGPoint(x: 60, y: 10), size: size, visible: visible)
        XCTAssertEqual(low.y, WindowPreview.screenMargin)
    }

    // MARK: 截图配对和尺寸

    func testFrameMatching() {
        let a = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertTrue(WindowPreview.framesMatch(a, a.offsetBy(dx: 1, dy: -1)))
        XCTAssertFalse(WindowPreview.framesMatch(a, a.offsetBy(dx: 5, dy: 0)))
        XCTAssertFalse(WindowPreview.framesMatch(a, CGRect(x: 100, y: 50, width: 700, height: 600)))
    }

    func testCaptureSizeKeepsAspect() {
        let wide = WindowPreview.captureSize(window: CGSize(width: 1600, height: 500), scale: 2)
        XCTAssertEqual(wide.width, 368)
        XCTAssertEqual(wide.height, 115)
        let tall = WindowPreview.captureSize(window: CGSize(width: 400, height: 1000), scale: 1)
        XCTAssertEqual(tall.height, 116)
        XCTAssertEqual(tall.width, 46)
        let tiny = WindowPreview.captureSize(window: CGSize(width: 50, height: 40), scale: 2)
        XCTAssertEqual(tiny, CGSize(width: 100, height: 80), "小窗口不放大")
        let none = WindowPreview.captureSize(window: .zero, scale: 2)
        XCTAssertEqual(none, CGSize(width: 368, height: 232))
    }

    // MARK: 设置和 Pro

    func testSettingDefaultsOffForOldState() throws {
        let old = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{"position": "left"}"#.utf8))
        XCTAssertFalse(old.hoverWindowPreview)
        var on = CustomDockSettings()
        on.hoverWindowPreview = true
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.hoverWindowPreview)
        let odd = try JSONDecoder().decode(CustomDockSettings.self,
                                           from: Data(#"{"hoverWindowPreview": "yes"}"#.utf8))
        XCTAssertFalse(odd.hoverWindowPreview, "认不出的值不能把整个扩展栏配置丢掉")
    }

    func testProGate() {
        var settings = CustomDockSettings()
        XCTAssertFalse(ProLicenseGate.windowPreviewActive(settings, unlocked: true))
        settings.hoverWindowPreview = true
        XCTAssertTrue(ProLicenseGate.windowPreviewActive(settings, unlocked: true))
        XCTAssertFalse(ProLicenseGate.windowPreviewActive(settings, unlocked: false))
        XCTAssertTrue(settings.hoverWindowPreview, "没解锁不改写用户的开关")
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.windowPreview)))
    }
}
