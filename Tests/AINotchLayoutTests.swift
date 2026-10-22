import XCTest

/// 刘海入口放在哪：入口就是刘海本身、下沿条、外接屏胶囊、避让拾掇、
/// 灵动提示让位、展开面板的位置。
final class AINotchLayoutTests: XCTestCase {
    /// 14 英寸 MacBook Pro 的样子：1512 x 982，刘海约 185 宽、32 高。
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    private var notch: CGRect {
        AINotchLayout.notchRect(screen: laptop, topInset: 32,
                                leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
                                rightArea: CGRect(x: 848, y: 950, width: 664, height: 32))!
    }

    private func laptopScreen(menuBar: CGFloat = 32) -> AINotchScreen {
        AINotchScreen(id: 1, frame: laptop, notch: notch, menuBarHeight: menuBar, isMain: true)
    }

    private func externalScreen(menuBar: CGFloat = 24) -> AINotchScreen {
        AINotchScreen(id: 2, frame: external, notch: nil, menuBarHeight: menuBar, isMain: false)
    }

    /// 菜单栏里刘海以外的部分，也就是菜单和状态图标所在的地方。
    private func iconAreas(of screen: AINotchScreen) -> [CGRect] {
        let bar = AINotchLayout.menuBar(of: screen)
        guard let notch = screen.notch else { return [bar] }
        return [CGRect(x: bar.minX, y: bar.minY, width: notch.minX - bar.minX, height: bar.height),
                CGRect(x: notch.maxX, y: bar.minY, width: bar.maxX - notch.maxX, height: bar.height)]
    }

    func testNotchIsTheGapBetweenTheTwoAuxiliaryAreas() {
        XCTAssertEqual(notch, CGRect(x: 663, y: 950, width: 185, height: 32))
        XCTAssertNil(AINotchLayout.notchRect(screen: external, topInset: 0, leftArea: nil, rightArea: nil))
        XCTAssertNil(AINotchLayout.notchRect(screen: laptop, topInset: 32, leftArea: nil,
                                             rightArea: CGRect(x: 848, y: 950, width: 664, height: 32)))
    }

    func testEntryIsTheNotchItselfWithNoWings() {
        for menuBar: CGFloat in [32, 37, 0] {
            let screen = laptopScreen(menuBar: menuBar)
            guard case .notch(let frame, _) = AINotchLayout.entry(for: screen, shiduoRunning: false) else {
                return XCTFail("有刘海时入口是刘海本身")
            }
            XCTAssertGreaterThanOrEqual(frame.minX, notch.minX, "不向左超出刘海")
            XCTAssertLessThanOrEqual(frame.maxX, notch.maxX, "不向右超出刘海")
            XCTAssertEqual(frame.width, notch.width)
            XCTAssertEqual(frame.maxY, laptop.maxY)
            XCTAssertEqual(frame.height, AINotchLayout.menuBar(of: screen).height, "高度是菜单栏高度")
        }
    }

    func testStripHangsBelowTheMenuBar() {
        let screen = laptopScreen(menuBar: 37)
        guard case .notch(let frame, let strip) = AINotchLayout.entry(for: screen, shiduoRunning: false) else {
            return XCTFail("有刘海时入口是刘海本身")
        }
        let bar = AINotchLayout.menuBar(of: screen)
        XCTAssertEqual(strip.maxY, bar.minY, "和刘海下沿连成一体")
        XCTAssertLessThanOrEqual(strip.maxY, bar.minY, "在菜单栏下方")
        XCTAssertFalse(strip.intersects(bar))
        XCTAssertEqual(strip.height, AINotchLayout.stripHeight)
        XCTAssertEqual(strip.minX, notch.minX)
        XCTAssertEqual(strip.width, notch.width, "和刘海同宽")
        XCTAssertEqual(strip.maxY, frame.minY)
    }

    func testStripContent() {
        XCTAssertNil(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: false, generating: false))
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: true, generating: false), .panda)
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: false, generating: true), .dots,
                       "生成中不需要悬停")
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: true, generating: true), .dots)
        XCTAssertNil(AINotchLayout.stripContent(visible: true, panelOpen: true, hovering: true, generating: true),
                     "面板开着时不显示")
        XCTAssertNil(AINotchLayout.stripContent(visible: false, panelOpen: false, hovering: true, generating: true))
    }

    func testExternalScreenCapsuleSitsBelowTheMenuBar() {
        for menuBar: CGFloat in [24, 0] {
            let screen = externalScreen(menuBar: menuBar)
            guard case .capsule(let frame) = AINotchLayout.entry(for: screen, shiduoRunning: false) else {
                return XCTFail("没有刘海时是胶囊")
            }
            let bar = AINotchLayout.menuBar(of: screen)
            XCTAssertFalse(frame.intersects(bar), "不在菜单栏里")
            XCTAssertLessThanOrEqual(frame.maxY, bar.minY)
            XCTAssertGreaterThanOrEqual(frame.maxY, bar.minY - 4, "紧挨菜单栏下沿")
            XCTAssertEqual(frame.midX, external.midX)
            XCTAssertEqual(frame.size, CGSize(width: 44, height: 18))
        }
    }

    func testCapsuleOpacity() {
        XCTAssertEqual(AINotchLayout.capsuleOpacity(hovering: false, generating: false), 0.4)
        XCTAssertEqual(AINotchLayout.capsuleOpacity(hovering: true, generating: false), 1)
        XCTAssertEqual(AINotchLayout.capsuleOpacity(hovering: false, generating: true), 1)
    }

    func testShiduoGetsNoNotchEntry() {
        XCTAssertNil(AINotchLayout.entry(for: laptopScreen(), shiduoRunning: true), "拾掇运行时刘海上不放入口")
        XCTAssertNil(AINotchLayout.entry(for: laptopScreen(menuBar: 0), shiduoRunning: true))
    }

    func testShiduoDoesNotMatterWithoutANotch() {
        XCTAssertEqual(AINotchLayout.entry(for: externalScreen(), shiduoRunning: true),
                       AINotchLayout.entry(for: externalScreen(), shiduoRunning: false))
    }

    /// 任何状态下入口窗口和下沿条都不碰菜单栏里放菜单和状态图标的地方。
    func testNeverCoversMenuBarIcons() {
        let screens = [laptopScreen(), laptopScreen(menuBar: 37), laptopScreen(menuBar: 0),
                       externalScreen(), externalScreen(menuBar: 0)]
        for screen in screens {
            for shiduo in [false, true] {
                guard let entry = AINotchLayout.entry(for: screen, shiduoRunning: shiduo) else { continue }
                var rects = [entry.frame]
                if case .notch(_, let strip) = entry { rects.append(strip) }
                for rect in rects {
                    for area in iconAreas(of: screen) {
                        XCTAssertFalse(rect.intersects(area), "\(rect) 压到了菜单栏图标区域 \(area)")
                    }
                }
            }
        }
    }

    func testShiduoDetection() {
        XCTAssertEqual(AIShiduo.bundleID, "io.github.hanson-zz.shiduo")
        XCTAssertTrue(AIShiduo.isRunning(["com.apple.finder", nil, "io.github.hanson-zz.shiduo"]))
        XCTAssertTrue(AIShiduo.isRunning(["IO.GITHUB.HANSON-ZZ.SHIDUO"]))
        XCTAssertFalse(AIShiduo.isRunning(["io.github.hanson-zz.shiduo.tests", nil]))
        XCTAssertFalse(AIShiduo.isRunning([]))
    }

    func testMainScreenOnly() {
        let both = [externalScreen(), laptopScreen()]
        XCTAssertEqual(AINotchLayout.screens(both, mainOnly: false).count, 2)
        XCTAssertEqual(AINotchLayout.screens(both, mainOnly: true).map(\.id), [1])
        XCTAssertEqual(AINotchLayout.screens([externalScreen()], mainOnly: true).map(\.id), [2],
                       "找不到主屏时用第一块")
        XCTAssertEqual(AINotchLayout.screens([], mainOnly: true), [])
    }

    func testIslandTakesPrecedence() {
        XCTAssertTrue(AINotchLayout.isVisible(enabled: true, islandShowing: false))
        XCTAssertFalse(AINotchLayout.isVisible(enabled: true, islandShowing: true))
        XCTAssertFalse(AINotchLayout.isVisible(enabled: false, islandShowing: false))
    }

    func testPanelGrowsDownFromTheNotch() {
        let entry = AINotchLayout.entry(for: laptopScreen(), shiduoRunning: false)!.frame
        let panel = AINotchLayout.panelFrame(below: entry, screen: laptop)
        XCTAssertEqual(panel.size, CGSize(width: 420, height: 520))
        XCTAssertEqual(panel.maxY, notch.minY, "接在刘海下面")
        XCTAssertEqual(panel.midX, notch.midX)
    }

    func testPanelStillGrowsFromTheNotchWhileShiduoRuns() {
        let anchor = AINotchLayout.anchor(for: laptopScreen(), shiduoRunning: true)
        XCTAssertEqual(anchor.midX, notch.midX)
        let panel = AINotchLayout.panelFrame(below: anchor, screen: laptop)
        XCTAssertEqual(panel.maxY, notch.minY)
    }

    func testPanelHangsBelowTheExternalCapsule() {
        let entry = AINotchLayout.entry(for: externalScreen(), shiduoRunning: false)!.frame
        let panel = AINotchLayout.panelFrame(below: entry, screen: external)
        XCTAssertLessThan(panel.maxY, entry.minY)
        XCTAssertEqual(panel.midX, external.midX)
    }

    func testPanelStaysOnScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let entry = CGRect(x: 950, y: 656, width: 44, height: 18)
        let panel = AINotchLayout.panelFrame(below: entry, screen: narrow)
        XCTAssertLessThanOrEqual(panel.maxX, narrow.maxX - AINotchLayout.margin)
        XCTAssertLessThan(panel.maxY, entry.minY)
        XCTAssertGreaterThanOrEqual(panel.minY, narrow.minY)
    }

    func testOnlyNotchAnchorsKeepThePanelBlack() {
        let notchEntry = AINotchLayout.entry(for: laptopScreen(), shiduoRunning: false)!.frame
        XCTAssertTrue(AINotchLayout.hangsFromNotch(notchEntry))
        XCTAssertTrue(AINotchLayout.hangsFromNotch(AINotchLayout.anchor(for: laptopScreen(), shiduoRunning: true)))
        // 菜单栏自动隐藏（量出来是 0）时按刘海高度算，仍然挂在刘海下面。
        XCTAssertTrue(AINotchLayout.hangsFromNotch(AINotchLayout.anchor(for: laptopScreen(menuBar: 0),
                                                                       shiduoRunning: false)))
        let capsule = AINotchLayout.entry(for: externalScreen(), shiduoRunning: false)!.frame
        XCTAssertFalse(AINotchLayout.hangsFromNotch(capsule))
        // 外接屏没有入口窗口时按屏幕中点算，宽度是 0。
        XCTAssertFalse(AINotchLayout.hangsFromNotch(CGRect(x: external.midX, y: 1416, width: 0, height: 24)))
    }

    func testNotchBlendSitsUnderTheNotchOnly() {
        let screen = laptopScreen()
        let entry = AINotchLayout.entry(for: screen, shiduoRunning: false)!.frame
        let panel = AINotchLayout.panelFrame(below: entry, screen: screen.frame)
        guard let blend = AINotchLayout.notchBlend(entry: entry, panel: panel) else {
            return XCTFail("刘海下面应有黑色过渡")
        }
        // 和刘海同宽、正对刘海，从面板顶边往下。
        XCTAssertEqual(blend.width, entry.width, accuracy: 0.001)
        XCTAssertEqual(blend.minX, entry.minX - panel.minX, accuracy: 0.001)
        XCTAssertEqual(blend.midX, panel.width / 2, accuracy: 0.001)
        XCTAssertEqual(blend.minY, 0)
        XCTAssertEqual(blend.height, AINotchLayout.notchBlendHeight)
        XCTAssertTrue((8 ... 12).contains(AINotchLayout.notchBlendHeight))
        // 面板被推开时跟着刘海走，超出面板的部分裁掉。
        // 刘海 185 宽：面板左边推到刘海里 100 处，只剩右边 85 在面板里。
        XCTAssertEqual(entry.width, 185, accuracy: 0.001)
        let shifted = CGRect(x: entry.minX + 100, y: panel.minY, width: panel.width, height: panel.height)
        let clipped = AINotchLayout.notchBlend(entry: entry, panel: shifted)
        XCTAssertEqual(clipped?.minX, 0)
        XCTAssertEqual(clipped?.width ?? 0, entry.width - 100, accuracy: 0.001)
        let away = CGRect(x: entry.maxX + 10, y: panel.minY, width: panel.width, height: panel.height)
        XCTAssertNil(AINotchLayout.notchBlend(entry: entry, panel: away))
        // 外接屏胶囊下面没有黑色过渡。
        let capsule = AINotchLayout.entry(for: externalScreen(), shiduoRunning: false)!.frame
        let capsulePanel = AINotchLayout.panelFrame(below: capsule, screen: external)
        XCTAssertNil(AINotchLayout.notchBlend(entry: capsule, panel: capsulePanel))
    }

    func testHeaderClearsTheNotchBlend() {
        XCTAssertEqual(AINotchLayout.headerTopPadding(hangsFromNotch: true), AINotchLayout.notchBlendHeight)
        XCTAssertEqual(AINotchLayout.headerTopPadding(hangsFromNotch: false), 10)
    }

    func testPanelHeaderMergesServiceNameAndWebControls() {
        XCTAssertFalse(AINotchPanelHeader.showsServiceChips(serviceCount: 0))
        XCTAssertFalse(AINotchPanelHeader.showsServiceChips(serviceCount: 1))
        XCTAssertTrue(AINotchPanelHeader.showsServiceChips(serviceCount: 2))
        XCTAssertTrue(AINotchPanelHeader.showsWebControls(.web))
        XCTAssertFalse(AINotchPanelHeader.showsWebControls(.api))
        XCTAssertFalse(AINotchPanelHeader.showsWebControls(.jump))
    }
}
