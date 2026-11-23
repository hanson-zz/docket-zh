import XCTest

/// 刘海避让的两处残余：AI 对话面板打开以后才出现的倒计时小岛（下面那条剩余时间）压进面板顶上，
/// 面板要往下挪开；插电霓虹动画播放期间弹出的快捷结果卡片要去备用浮窗、不压在动画上。
final class NotchAvoidTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let bar = CGRect(x: 0, y: 950, width: 1512, height: 32)
    private let notchEntry = CGRect(x: 663, y: 950, width: 185, height: 32)
    private let geometry = NotchIslandGeometry(notchWidth: 185, notchHeight: 32, hasNotch: true)

    /// 倒计时卡片的计时器在小岛上：收起态刘海下面有一条剩余时间。
    private var countdown: NotchIslandActivity {
        .timer(deadline: Date().addingTimeInterval(600), pausedLeft: nil, total: 900, focus: false,
               source: .countdown(widget: UUID(), timer: "main"), name: "泡茶")
    }

    /// 小岛窗口（`NotchIslandOccupancy` 发出来的就是它）。
    private func islandWindow(_ form: NotchIslandForm) -> CGRect {
        let extent = NotchIslandLayout.extent(NotchIslandLayout.pieces(geometry, form: form))
        return NotchIslandLayout.windowFrame(centerX: notchEntry.midX, screenTop: laptop.maxY,
                                             halfWidth: extent.halfWidth, height: extent.height)
    }

    // MARK: 面板打开以后才出现的小岛

    func testCountdownChinOverlapsPanelOpenedBeforeIt() {
        let panel = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: []).frame
        let body = NotchIslandLayout.body(geometry, countdown)
        XCTAssertEqual(body.height, geometry.notchHeight + NotchIslandLayout.chinHeight, "下面那条约 26 点")
        let chin = NotchIslandLayout.screenRect(body, centerX: notchEntry.midX, screenTop: laptop.maxY)
        XCTAssertEqual(panel.maxY - chin.minY, NotchIslandLayout.chinHeight - AINotchLayout.cardGap,
                       "原来面板只在打开那一刻避让，后出现的那条伸进面板顶上约 20 点")
    }

    func testPanelMovesBelowIslandThatAppearsLater() throws {
        let panel = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: []).frame
        let island = islandWindow(.compact(countdown))
        let moved = try XCTUnwrap(AINotchLayout.avoidance(current: panel, screen: laptop, avoiding: [island]))
        XCTAssertEqual(moved.maxY, island.minY - AINotchLayout.blockerGap, "挪到小岛下沿下面，留一点空")
        XCTAssertEqual(moved.size, panel.size, "大小不变")
        XCTAssertEqual(moved.minX, panel.minX, "只上下挪")
        XCTAssertEqual(moved, AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: [island]).frame,
                       "和打开时小岛已经在的摆法一样")
        XCTAssertNil(AINotchLayout.avoidance(current: moved, screen: laptop, avoiding: [island]), "挪好了不再动")
    }

    func testPanelFollowsIslandGrowingTaller() throws {
        let compact = NotchIslandActivity.download(fraction: 0.4, done: false)
        let low = islandWindow(.compact(compact))
        let panel = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: [low]).frame
        // 下载之外又来了倒计时，排在前面后多出下面那一条，小岛变高。
        let tall = islandWindow(.split(countdown, compact))
        XCTAssertLessThan(tall.minY, low.minY)
        let moved = try XCTUnwrap(AINotchLayout.avoidance(current: panel, screen: laptop, avoiding: [tall]))
        XCTAssertLessThanOrEqual(moved.maxY, tall.minY - AINotchLayout.blockerGap)
    }

    func testPanelOnlyMovesDown() {
        let island = islandWindow(.compact(countdown))
        let lowered = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: [island]).frame
        XCTAssertNil(AINotchLayout.avoidance(current: lowered, screen: laptop, avoiding: []),
                     "小岛收起时不往上回，免得小岛闪一下面板就上下跳")
        let elsewhere = island.offsetBy(dx: 3000, dy: 0)
        let panel = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: []).frame
        XCTAssertNil(AINotchLayout.avoidance(current: panel, screen: laptop, avoiding: [elsewhere]), "别的屏幕上的不管")
    }

    func testPanelStaysOnScreen() throws {
        let panel = AINotchLayout.placement(below: notchEntry, screen: laptop, avoiding: []).frame
        let huge = CGRect(x: 500, y: 300, width: 500, height: 682)
        let moved = try XCTUnwrap(AINotchLayout.avoidance(current: panel, screen: laptop, avoiding: [huge]))
        XCTAssertEqual(moved.minY, laptop.minY + AINotchLayout.margin, "底边不出屏幕")
        XCTAssertNil(AINotchLayout.avoidance(current: moved, screen: laptop, avoiding: [huge]), "到底了不再反复挪")
    }

    // MARK: 插电动画期间的快捷结果卡片

    private var plug: CGRect {
        let notch = CGRect(x: notchEntry.minX, y: 950, width: notchEntry.width, height: 32)
        return BatteryNeon.Plug.window(screen: laptop, notch: notch, menuBarHeight: 32).frame
    }

    func testPlugWindowGeometry() {
        XCTAssertEqual(BatteryNeon.Plug.fallbackMenuBarHeight, AINotchLayout.fallbackMenuBarHeight)
        let window = BatteryNeon.Plug.window(screen: laptop, notch: notchEntry, menuBarHeight: 32)
        XCTAssertEqual(window.frame.width, BatteryNeon.Plug.windowWidth)
        XCTAssertEqual(window.frame.midX, notchEntry.midX, accuracy: 0.5, "以刘海中线对称")
        XCTAssertEqual(window.frame.maxY, laptop.maxY, "顶边贴屏幕顶")
        XCTAssertEqual(window.digitsCenter, max(32 + 120, laptop.height * 0.27))
        XCTAssertEqual(window.frame.height, window.digitsCenter + 130)
        let hidden = BatteryNeon.Plug.window(screen: laptop, notch: nil, menuBarHeight: 0)
        XCTAssertEqual(hidden.menuBar, BatteryNeon.Plug.fallbackMenuBarHeight)
        XCTAssertEqual(hidden.centerX, laptop.midX)
        let narrow = CGRect(x: 2000, y: 0, width: 400, height: 600)
        XCTAssertEqual(BatteryNeon.Plug.window(screen: narrow, notch: nil, menuBarHeight: 24).frame.minX, narrow.minX,
                       "窄屏收到屏幕宽，不出屏幕")
    }

    func testNotchCardWouldSitOnThePlugAnimation() {
        let card = AIQuickResult.notchFrame(below: notchEntry, screen: laptop, height: 200, avoiding: [])
        XCTAssertTrue(card.intersects(plug), "原来刘海下的卡片压在光滴和霓虹数字上")
        XCTAssertEqual(AIQuickResult.relocated(.notchCard, notchOccupied: true), .floating, "播放期间去备用浮窗")
        XCTAssertEqual(AIQuickResult.relocated(.floating, notchOccupied: false), .notchCard, "播完回刘海下")
    }

    func testFloatingCardAvoidsThePlugAnimation() {
        let plain = AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200, blockers: [])
        let during = AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200,
                                                 blockers: [], animation: plug)
        XCTAssertEqual(during, plain, "宽屏上右上角本来就不碰动画，位置不变")
        XCTAssertFalse(during.intersects(plug))
        let elsewhere = plug.offsetBy(dx: 3000, dy: 0)
        XCTAssertEqual(AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200,
                                                   blockers: [], animation: elsewhere), plain, "别的屏幕上的动画不管")
    }

    func testFloatingCardGoesBelowAnimationOnNarrowScreen() {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 700)
        let menu = CGRect(x: 0, y: 676, width: 900, height: 24)
        let entry = CGRect(x: 450, y: 676, width: 0, height: 24)
        let animation = BatteryNeon.Plug.window(screen: screen, notch: nil, menuBarHeight: 24).frame
        let card = AIQuickResult.floatingFrame(screen: screen, menuBar: menu, entry: entry, height: 200,
                                               blockers: [], animation: animation)
        XCTAssertLessThanOrEqual(card.maxY, animation.minY - AINotchLayout.blockerGap, "右上角也压到时挪到动画下面")
        XCTAssertGreaterThanOrEqual(card.minY, screen.minY + AINotchLayout.margin)
        XCTAssertTrue(screen.contains(card))
    }

    func testFloatingUnderIslandStillAvoidsAnimation() {
        let island = CGRect(x: 600, y: 860, width: 312, height: 122)
        let card = AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200,
                                               blockers: [island], animation: plug)
        XCTAssertFalse(card.intersects(plug.insetBy(dx: 1, dy: 1)), "小岛下面那格压到动画时不放那里")
    }
}
