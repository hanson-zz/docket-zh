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
        XCTAssertFalse(strip.intersects(bar), "在菜单栏下方")
        XCTAssertEqual(strip.height, 38)
        XCTAssertEqual(strip.midX, notch.midX, "以刘海中线对称")
        XCTAssertEqual(strip.width, notch.width + 140, "窗口按每侧最多 70 留好")
        XCTAssertEqual(strip.maxY, frame.minY)
    }

    /// 胶囊宽度和刘海小岛同一套规则：13pt 字、放得进刘海就和刘海一样宽，放不下每侧最多加 70。
    func testStripCapsuleIsNotMuchWiderThanTheNotch() {
        XCTAssertEqual(AINotchLayout.stripWidth(.hint, service: nil, notchWidth: 185), 185, "「● AI 助手」和刘海同宽")
        XCTAssertEqual(AINotchLayout.stripWidth(.thinking, service: "ChatGPT", notchWidth: 185), 185,
                       "「ChatGPT 正在思考」加三个点也放得进刘海")
        XCTAssertEqual(AINotchLayout.stripWidth(.thinking, service: "DeepSeek", notchWidth: 185), 185)
        // 「ChatGPT 正在思考」：(7 × 0.62 + 0.28 + 4) × 13 = 112.06，加 6 + 13.2 的三个点。
        XCTAssertEqual(AINotchLayout.stripContentWidth(.thinking, service: "ChatGPT"), 131.26, accuracy: 0.01)
        // 「● AI 助手」：6 + 6 + (2 × 0.62 + 0.28 + 2) × 13 = 57.76。
        XCTAssertEqual(AINotchLayout.stripContentWidth(.hint, service: nil), 57.76, accuracy: 0.01)
        // 窄刘海（150）放不下：每侧多出 (131.26 + 24 − 150) / 2 取整 3。
        XCTAssertEqual(AINotchLayout.stripSideExtra(contentWidth: 131.26, notchWidth: 150), 3)
        XCTAssertEqual(AINotchLayout.stripWidth(.thinking, service: "ChatGPT", notchWidth: 150), 156)
        // 很长的自定义服务名：每侧最多 70，字截断。
        let long = AINotchLayout.stripWidth(.thinking, service: "My Very Long Custom Model Service", notchWidth: 185)
        XCTAssertEqual(long, 185 + 140)
        XCTAssertEqual(AINotchLayout.stripSideExtra(contentWidth: 1000, notchWidth: 185), NotchIslandLayout.maxWing)
        XCTAssertEqual(NotchIslandLayout.maxWing, 70)
        XCTAssertEqual(AINotchLayout.stripSideExtra(contentWidth: 10, notchWidth: 185), 0)
    }

    func testStripContent() {
        XCTAssertNil(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: false, generating: false))
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: true, generating: false), .hint)
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: false, generating: true), .thinking,
                       "生成中不需要悬停")
        XCTAssertEqual(AINotchLayout.stripContent(visible: true, panelOpen: false, hovering: true, generating: true), .thinking)
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

    func testPanelSitsBelowTheMenuBarLikeTheFocusCard() {
        for menuBar: CGFloat in [32, 37] {
            let screen = laptopScreen(menuBar: menuBar)
            let entry = AINotchLayout.entry(for: screen, shiduoRunning: false)!.frame
            let panel = AINotchLayout.panelFrame(below: entry, screen: laptop)
            let bar = AINotchLayout.menuBar(of: screen)
            XCTAssertEqual(panel.size, CGSize(width: 400, height: 520))
            XCTAssertEqual(panel.maxY, bar.minY - 6, "菜单栏下面空 6，和专注卡片一样")
            XCTAssertEqual(AINotchLayout.cardGap, NotchIslandLayout.cardGap)
            XCTAssertFalse(panel.intersects(bar), "不盖住菜单栏图标")
            XCTAssertEqual(panel.midX, notch.midX)
        }
    }

    func testPanelStillSitsUnderTheNotchWhileShiduoRuns() {
        let anchor = AINotchLayout.anchor(for: laptopScreen(), shiduoRunning: true)
        XCTAssertEqual(anchor.midX, notch.midX)
        let panel = AINotchLayout.panelFrame(below: anchor, screen: laptop)
        XCTAssertEqual(panel.maxY, notch.minY - 6)
    }

    func testPanelHangsBelowTheExternalCapsule() {
        let entry = AINotchLayout.entry(for: externalScreen(), shiduoRunning: false)!.frame
        let panel = AINotchLayout.panelFrame(below: entry, screen: external)
        XCTAssertLessThan(panel.maxY, entry.minY)
        XCTAssertEqual(panel.midX, external.midX)
    }

    func testPanelSitsBelowAShowingIslandInsteadOfCoveringIt() {
        let entry = AINotchLayout.entry(for: laptopScreen(), shiduoRunning: false)!.frame
        let plain = AINotchLayout.placement(below: entry, screen: laptop, avoiding: [])
        XCTAssertFalse(plain.clearedBlockers)
        XCTAssertEqual(plain.frame, AINotchLayout.panelFrame(below: entry, screen: laptop))

        // 专注计时小岛从刘海往下长出 40pt：面板挪到它下面，不盖住它。
        let island = CGRect(x: notch.minX - 40, y: notch.minY - 40, width: notch.width + 80, height: 72)
        let moved = AINotchLayout.placement(below: entry, screen: laptop, avoiding: [island])
        XCTAssertTrue(moved.clearedBlockers)
        XCTAssertEqual(moved.frame.maxY, island.minY - AINotchLayout.blockerGap)
        XCTAssertEqual(moved.frame.size, AINotchLayout.panelSize)
        XCTAssertEqual(moved.frame.midX, plain.frame.midX)

        // 只是碰到边（小岛正好在刘海那一段里）、在别的屏幕上的都不算挡着。
        let flush = CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: notch.height)
        XCTAssertFalse(AINotchLayout.placement(below: entry, screen: laptop, avoiding: [flush]).clearedBlockers)
        let elsewhere = CGRect(x: external.midX - 100, y: external.maxY - 60, width: 200, height: 60)
        XCTAssertFalse(AINotchLayout.placement(below: entry, screen: laptop, avoiding: [elsewhere]).clearedBlockers)
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

    func testPanelHeader() {
        XCTAssertFalse(AINotchPanelHeader.canSwitchService(serviceCount: 0))
        XCTAssertFalse(AINotchPanelHeader.canSwitchService(serviceCount: 1))
        XCTAssertTrue(AINotchPanelHeader.canSwitchService(serviceCount: 2))
        XCTAssertTrue(AINotchPanelHeader.showsWebControls(.web))
        XCTAssertFalse(AINotchPanelHeader.showsWebControls(.api))
        XCTAssertFalse(AINotchPanelHeader.showsWebControls(.jump))
    }
}
