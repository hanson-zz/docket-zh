import XCTest

/// 刘海入口放在哪：贴刘海、外接屏的小胶囊、避让拾掇、灵动提示让位、
/// 展开面板的位置。
final class AINotchLayoutTests: XCTestCase {
    /// 14 英寸 MacBook Pro 的样子：1512 x 982，刘海约 185 宽、32 高。
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    private var notch: CGRect {
        AINotchLayout.notchRect(screen: laptop, topInset: 32,
                                leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
                                rightArea: CGRect(x: 848, y: 950, width: 664, height: 32))!
    }

    private var laptopScreen: AINotchScreen {
        AINotchScreen(id: 1, frame: laptop, notch: notch, menuBarHeight: 32, isMain: true)
    }

    private var externalScreen: AINotchScreen {
        AINotchScreen(id: 2, frame: external, notch: nil, menuBarHeight: 24, isMain: false)
    }

    func testNotchIsTheGapBetweenTheTwoAuxiliaryAreas() {
        XCTAssertEqual(notch, CGRect(x: 663, y: 950, width: 185, height: 32))
        XCTAssertNil(AINotchLayout.notchRect(screen: external, topInset: 0, leftArea: nil, rightArea: nil))
        XCTAssertNil(AINotchLayout.notchRect(screen: laptop, topInset: 32, leftArea: nil,
                                             rightArea: CGRect(x: 848, y: 950, width: 664, height: 32)))
    }

    func testHugsTheNotchWithAWingOnEachSide() {
        let entry = AINotchLayout.entry(for: laptopScreen, shiduoRunning: false)
        guard case .notch(let frame, let inner) = entry else { return XCTFail("应当贴着刘海") }
        XCTAssertEqual(inner, notch)
        XCTAssertTrue(frame.contains(notch))
        XCTAssertEqual(frame.midX, notch.midX)
        XCTAssertEqual(frame.maxY, laptop.maxY)
        XCTAssertEqual(frame.height, notch.height)
        XCTAssertEqual(frame.width, notch.width + 2 * (AINotchLayout.wing + AINotchLayout.hoverGrow))
    }

    func testHoverOnlyWidensALittle() {
        let entry = AINotchLayout.entry(for: laptopScreen, shiduoRunning: false)
        let rest = AINotchLayout.visibleWidth(entry, hovering: false)
        let hover = AINotchLayout.visibleWidth(entry, hovering: true)
        XCTAssertEqual(hover - rest, AINotchLayout.hoverGrow * 2)
        XCTAssertEqual(hover, entry.frame.width, "变宽后正好撑满窗口，不会被裁掉")
    }

    func testExternalScreenGetsACapsuleAtTheTopCentre() {
        let entry = AINotchLayout.entry(for: externalScreen, shiduoRunning: false)
        guard case .capsule(let frame, let aside) = entry else { return XCTFail("没有刘海时是胶囊") }
        XCTAssertFalse(aside)
        XCTAssertEqual(frame.midX, external.midX)
        XCTAssertLessThanOrEqual(frame.maxY, external.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, external.maxY - 24, "在菜单栏这一条里")
    }

    func testShiduoMovesTheEntryOffTheNotch() {
        let entry = AINotchLayout.entry(for: laptopScreen, shiduoRunning: true)
        guard case .capsule(let frame, let aside) = entry else { return XCTFail("拾掇在运行时不贴刘海") }
        XCTAssertTrue(aside)
        XCTAssertFalse(frame.intersects(notch), "不和刘海区域重叠")
        XCTAssertFalse(frame.intersects(notch.insetBy(dx: -8, dy: 0)), "还留出一点距离")
        XCTAssertGreaterThan(frame.minX, notch.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, laptop.maxY)
        XCTAssertLessThan(frame.maxX, laptop.maxX)
    }

    func testShiduoDoesNotMatterWithoutANotch() {
        XCTAssertEqual(AINotchLayout.entry(for: externalScreen, shiduoRunning: true),
                       AINotchLayout.entry(for: externalScreen, shiduoRunning: false))
    }

    func testShiduoDetection() {
        XCTAssertEqual(AIShiduo.bundleID, "io.github.hanson-zz.shiduo")
        XCTAssertTrue(AIShiduo.isRunning(["com.apple.finder", nil, "io.github.hanson-zz.shiduo"]))
        XCTAssertTrue(AIShiduo.isRunning(["IO.GITHUB.HANSON-ZZ.SHIDUO"]))
        XCTAssertFalse(AIShiduo.isRunning(["io.github.hanson-zz.shiduo.tests", nil]))
        XCTAssertFalse(AIShiduo.isRunning([]))
    }

    func testMainScreenOnly() {
        let both = [externalScreen, laptopScreen]
        XCTAssertEqual(AINotchLayout.screens(both, mainOnly: false).count, 2)
        XCTAssertEqual(AINotchLayout.screens(both, mainOnly: true).map(\.id), [1])
        XCTAssertEqual(AINotchLayout.screens([externalScreen], mainOnly: true).map(\.id), [2],
                       "找不到主屏时用第一块")
        XCTAssertEqual(AINotchLayout.screens([], mainOnly: true), [])
    }

    func testIslandTakesPrecedence() {
        XCTAssertTrue(AINotchLayout.isVisible(enabled: true, islandShowing: false))
        XCTAssertFalse(AINotchLayout.isVisible(enabled: true, islandShowing: true))
        XCTAssertFalse(AINotchLayout.isVisible(enabled: false, islandShowing: false))
    }

    func testPanelGrowsDownFromTheNotch() {
        let entry = AINotchLayout.entry(for: laptopScreen, shiduoRunning: false).frame
        let panel = AINotchLayout.panelFrame(below: entry, screen: laptop)
        XCTAssertEqual(panel.size, CGSize(width: 420, height: 520))
        XCTAssertEqual(panel.maxY, notch.minY, "接在刘海下面")
        XCTAssertEqual(panel.midX, notch.midX)
    }

    func testPanelStaysOnScreenNextToAnAsideCapsule() {
        let narrow = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let entry = CGRect(x: 900, y: 678, width: 76, height: 22)
        let panel = AINotchLayout.panelFrame(below: entry, screen: narrow)
        XCTAssertLessThanOrEqual(panel.maxX, narrow.maxX - AINotchLayout.margin)
        XCTAssertLessThan(panel.maxY, entry.minY)
        XCTAssertGreaterThanOrEqual(panel.minY, narrow.minY)
    }
}
