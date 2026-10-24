import XCTest

/// 消息卡放在哪：认拾掇和常见刘海 App、自动让位（落在它下面 / 等它收起 / 改用胶囊）、
/// 三种位置设置、收起态的耳朵和胶囊、坐标换算、全屏判断。
final class NotchMessagePlacementTests: XCTestCase {
    /// 14 英寸 MacBook Pro：1512 x 982，刘海 185 宽、32 高，居中。
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    private var screen: AINotchScreen {
        AINotchScreen(id: 1, frame: laptop, notch: notch, menuBarHeight: 32, isMain: true)
    }

    private var external: AINotchScreen {
        AINotchScreen(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), notch: nil,
                      menuBarHeight: 24, isMain: false)
    }

    /// 拾掇的刘海暂存架展开时：宽 580、从屏幕顶上挂下来、高 32 + 卡片 + 92。
    private var shiduoShelf: NotchForeignWindow {
        NotchForeignWindow(ownerName: "拾掇", bundleID: "io.github.hanson-zz.shiduo", ownerPID: 42,
                           frame: CGRect(x: 466, y: 982 - 214, width: 580, height: 214), layer: 26)
    }

    /// 拾掇的专注指示：刘海加左右两块，和菜单栏一样高。
    private var shiduoFocus: NotchForeignWindow {
        NotchForeignWindow(ownerName: "Shiduo", ownerPID: 42,
                           frame: CGRect(x: 663.5 - 70, y: 950, width: 185 + 140, height: 32), layer: 26)
    }

    // MARK: 认 App

    func testRecognisesShiduoByBundleOrName() {
        XCTAssertEqual(NotchNeighbors.shiduo.bundleIDs, [AIShiduo.bundleID])
        XCTAssertNotNil(NotchNeighbors.app(ownerName: "随便", bundleID: "IO.GITHUB.HANSON-ZZ.SHIDUO"))
        XCTAssertNotNil(NotchNeighbors.app(ownerName: "拾掇", bundleID: nil))
        XCTAssertNotNil(NotchNeighbors.app(ownerName: "Shiduo", bundleID: nil))
        XCTAssertNotNil(NotchNeighbors.app(ownerName: "NotchNook", bundleID: nil))
        XCTAssertNotNil(NotchNeighbors.app(ownerName: "boringNotch", bundleID: nil))
        XCTAssertNil(NotchNeighbors.app(ownerName: "Safari", bundleID: "com.apple.Safari"))
        XCTAssertNil(NotchNeighbors.app(ownerName: "", bundleID: nil))
    }

    func testNeighborsOnlyCountsWindowsHangingNearTheNotch() {
        let floating = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 600, y: 400, width: 300, height: 200))
        let far = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 10, y: 950, width: 100, height: 32))
        let hidden = NotchForeignWindow(ownerName: "拾掇", frame: shiduoShelf.frame, alpha: 0)
        let other = NotchForeignWindow(ownerName: "Safari", frame: shiduoShelf.frame)
        let near = NotchMessagePlacement.neighbors([floating, far, hidden, other, shiduoFocus], screen: screen)
        XCTAssertEqual(near, [shiduoFocus], "悬浮暂存架、离得远的、透明的、别的 App 都不算")
    }

    // MARK: 卡片

    func testAutoHangsBelowNotchWhenNothingIsThere() {
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [], waited: 0),
                       .hang(top: 950, fromNotch: true))
        // 拾掇在运行但刘海附近没有它的窗口：照样接在刘海下面。
        let elsewhere = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 1200, y: 300, width: 200, height: 200))
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [elsewhere], waited: 0),
                       .hang(top: 950, fromNotch: true))
    }

    func testAutoWaitsForExpandedShelfThenFallsBackToCapsule() {
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [shiduoShelf], waited: 0), .wait)
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [shiduoShelf], waited: 7.9), .wait)
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [shiduoShelf],
                                                  waited: NotchMessagePriority.maxWait), .capsule)
    }

    func testAutoDropsBelowAShallowNotchWindow() {
        // 刘海下沿长出 20pt 的提示条：卡片落在它下面。
        let strip = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 663.5, y: 930, width: 185, height: 52))
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [strip], waited: 0),
                       .hang(top: 930 - NotchMessagePlacement.gap, fromNotch: false))
        // 只在菜单栏那一条里的（专注指示）：卡片照常接在刘海下面。
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: screen, windows: [shiduoFocus], waited: 0),
                       .hang(top: 950, fromNotch: true))
    }

    func testFixedPositionsIgnoreNeighbors() {
        XCTAssertEqual(NotchMessagePlacement.card(.belowNotch, screen: screen, windows: [shiduoShelf], waited: 0),
                       .hang(top: 950, fromNotch: true))
        XCTAssertEqual(NotchMessagePlacement.card(.capsule, screen: screen, windows: [], waited: 0), .capsule)
    }

    func testNoNotchHangsUnderMenuBar() {
        let bar = AINotchLayout.menuBar(of: external)
        XCTAssertEqual(NotchMessagePlacement.card(.auto, screen: external, windows: [], waited: 0),
                       .hang(top: bar.minY - NotchMessagePlacement.gap, fromNotch: false))
    }

    func testCardFrameCentredOnNotchAndClamped() {
        let size = CGSize(width: 452, height: 260)
        let frame = NotchMessagePlacement.cardFrame(top: 950, screen: screen, size: size)
        XCTAssertEqual(frame.midX, notch.midX, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, 950)
        let tiny = AINotchScreen(id: 3, frame: CGRect(x: 0, y: 0, width: 400, height: 300), notch: nil,
                                 menuBarHeight: 24, isMain: true)
        let squeezed = NotchMessagePlacement.cardFrame(top: 276, screen: tiny, size: size)
        XCTAssertGreaterThanOrEqual(squeezed.minY, 8)
    }

    func testCardBelowCapsuleAvoidsNotchCentre() {
        let capsule = NotchMessagePlacement.capsuleFrame(screen: screen, windows: [], apps: 1)
        let frame = NotchMessagePlacement.cardFrame(belowCapsule: capsule, screen: screen,
                                                    size: CGSize(width: 452, height: 200))
        XCTAssertGreaterThan(frame.minX, notch.maxX, "胶囊点开的卡片不压刘海中间")
        XCTAssertLessThanOrEqual(frame.maxX, laptop.maxX - NotchMessagePlacement.margin)
        XCTAssertLessThan(frame.maxY, 950 + 0.01)
    }

    // MARK: 收起态

    func testEarsHugTheNotch() {
        guard case .ears(let left, let right) = NotchMessagePlacement.indicator(.auto, screen: screen, windows: [],
                                                                                 apps: 2) else {
            return XCTFail("有刘海时是耳朵")
        }
        XCTAssertEqual(left.maxX, notch.minX)
        XCTAssertEqual(right?.minX, notch.maxX)
        XCTAssertEqual(left.height, 32)
        XCTAssertLessThanOrEqual(left.maxX, notch.minX, "不盖刘海本身（那是 AI 入口）")
        XCTAssertGreaterThanOrEqual(right?.minX ?? 0, notch.maxX)
        guard case .ears(_, let none) = NotchMessagePlacement.indicator(.belowNotch, screen: screen, windows: [],
                                                                         apps: 1) else { return XCTFail() }
        XCTAssertNil(none, "只有一个 App 时只有左耳")
        XCTAssertEqual(NotchMessagePlacement.earWidth(items: 2), 108)
        XCTAssertEqual(NotchMessagePlacement.earWidth(items: 0), 0)
    }

    func testCapsuleWhenAskedOrWhenEarsAreTaken() {
        guard case .capsule(let asked) = NotchMessagePlacement.indicator(.capsule, screen: screen, windows: [],
                                                                          apps: 2) else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(asked.minX, notch.maxX + NotchMessagePlacement.capsuleGap, "完全不占刘海中间")
        XCTAssertGreaterThanOrEqual(asked.minY, 950)
        guard case .capsule(let moved) = NotchMessagePlacement.indicator(.auto, screen: screen, windows: [shiduoFocus],
                                                                          apps: 1) else {
            return XCTFail("拾掇的专注指示占着耳朵的位置：改胶囊")
        }
        XCTAssertGreaterThanOrEqual(moved.minX, shiduoFocus.frame.maxX + NotchMessagePlacement.capsuleGap)
        // 「刘海下方」不让：照样耳朵。
        if case .capsule = NotchMessagePlacement.indicator(.belowNotch, screen: screen, windows: [shiduoFocus], apps: 1) {
            XCTFail("刘海下方不管别人")
        }
        // 没有刘海：胶囊挂在菜单栏下沿正中。
        guard case .capsule(let plain) = NotchMessagePlacement.indicator(.auto, screen: external, windows: [],
                                                                          apps: 3) else { return XCTFail() }
        XCTAssertEqual(plain.midX, external.frame.midX, accuracy: 0.01)
        XCTAssertLessThan(plain.maxY, AINotchLayout.menuBar(of: external).minY)
        XCTAssertEqual(plain.width, NotchMessagePlacement.capsuleWidth(items: 3))
    }

    func testCapsuleStaysOnScreen() {
        let wide = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 600, y: 950, width: 912, height: 32))
        let frame = NotchMessagePlacement.capsuleFrame(screen: screen, windows: [wide], apps: 3)
        XCTAssertLessThanOrEqual(frame.maxX, laptop.maxX - NotchMessagePlacement.margin)
    }

    // MARK: 坐标和全屏

    func testCGToAppKit() {
        let cg = CGRect(x: 466, y: 0, width: 580, height: 214)
        XCTAssertEqual(NotchWindowGeometry.appKit(cg, primaryHeight: 982), CGRect(x: 466, y: 768, width: 580, height: 214))
    }

    private let menuBarWindow = NotchForeignWindow(ownerName: "Window Server", ownerPID: 1,
                                                   frame: CGRect(x: 0, y: 950, width: 1512, height: 32), layer: 24)

    func testFullscreenDetection() {
        let keynote = NotchForeignWindow(ownerName: "Keynote", ownerPID: 7, frame: laptop, layer: 0)
        XCTAssertTrue(NotchFullscreen.isFullscreen([keynote], screen: laptop, frontmostPID: 7, ownPID: 99))
        XCTAssertFalse(NotchFullscreen.isFullscreen([keynote], screen: laptop, frontmostPID: 8, ownPID: 99),
                       "盖满屏幕的普通窗口不在前台不算")
        let show = NotchForeignWindow(ownerName: "Keynote", ownerPID: 7, frame: laptop, layer: 1000)
        XCTAssertTrue(NotchFullscreen.isFullscreen([show], screen: laptop, frontmostPID: 3, ownPID: 99), "放映在高层级")
        let dock = NotchForeignWindow(ownerName: "Dock", ownerPID: 5, frame: laptop, layer: 18)
        XCTAssertFalse(NotchFullscreen.isFullscreen([dock], screen: laptop, frontmostPID: 5, ownPID: 99), "调度中心不算")
        let mine = NotchForeignWindow(ownerName: "码头", ownerPID: 99, frame: laptop, layer: 25)
        XCTAssertFalse(NotchFullscreen.isFullscreen([mine], screen: laptop, frontmostPID: 99, ownPID: 99))
        let maximized = NotchForeignWindow(ownerName: "Safari", ownerPID: 7,
                                           frame: CGRect(x: 0, y: 0, width: 1512, height: 950), layer: 0)
        XCTAssertFalse(NotchFullscreen.isFullscreen([maximized, menuBarWindow], screen: laptop, topInset: 32,
                                                    frontmostPID: 7, ownPID: 99),
                       "缩放到最大的普通窗口，菜单栏还在：不算全屏")
        XCTAssertTrue(NotchFullscreen.isFullscreen([maximized], screen: laptop, topInset: 32,
                                                   frontmostPID: 7, ownPID: 99),
                      "全屏空间里菜单栏收起，内容落在刘海下面：算全屏")
        XCTAssertFalse(NotchFullscreen.isFullscreen([maximized], screen: laptop, topInset: 0,
                                                    frontmostPID: 7, ownPID: 99), "没有刘海时要盖满")
        XCTAssertFalse(NotchFullscreen.isFullscreen([], screen: laptop, frontmostPID: nil, ownPID: 99))
    }

    func testMenuBarVisible() {
        XCTAssertTrue(NotchFullscreen.menuBarVisible([menuBarWindow], screen: laptop))
        XCTAssertFalse(NotchFullscreen.menuBarVisible([], screen: laptop))
        let lowLayer = NotchForeignWindow(ownerName: "Window Server", frame: menuBarWindow.frame, layer: 0)
        XCTAssertFalse(NotchFullscreen.menuBarVisible([lowLayer], screen: laptop))
    }
}
