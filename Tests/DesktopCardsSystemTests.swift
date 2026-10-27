import Foundation
import XCTest

/// 钉在桌面 · 系统组：三档各摆几个、几列几行、列表几行、电池那几行字。
final class DesktopCardsSystemTests: XCTestCase {
    typealias Plan = DesktopSystemCards

    func testTenKindsAllOfferSmall() {
        XCTAssertEqual(Plan.kinds.count, 10)
        for kind in [WidgetKind.battery, .system, .network, .gauges, .toggles,
                     .airdrop, .trash, .appSwitcher, .shortcut, .search] {
            XCTAssertTrue(Plan.handles(kind), "\(kind)")
        }
        XCTAssertFalse(Plan.handles(.clock))
        XCTAssertFalse(Plan.handles(.notes))
        // 原来电池和快速开关的小号放不下被拿掉；现在是专属布局，三档都给。
        XCTAssertEqual(DesktopPinSupport.sizes(.generic, smallFits: Plan.handles(.battery)),
                       [.small, .medium, .large])
        XCTAssertEqual(DesktopPinSupport.sizes(.generic, smallFits: Plan.handles(.toggles)),
                       [.small, .medium, .large])
    }

    func testToggleGridSmall() {
        XCTAssertEqual(Plan.toggleGrid(count: 0, size: .small), .empty)
        let one = Plan.toggleGrid(count: 1, size: .small)
        XCTAssertEqual([one.columns, one.rows, one.shown, one.overflow], [1, 1, 1, 0])
        XCTAssertTrue(one.showsCaption)
        let two = Plan.toggleGrid(count: 2, size: .small)
        XCTAssertEqual([two.columns, two.rows, two.shown], [1, 2, 2])
        XCTAssertTrue(two.showsCaption)
        let three = Plan.toggleGrid(count: 3, size: .small)
        XCTAssertEqual([three.columns, three.rows, three.shown, three.overflow], [2, 2, 3, 0])
        XCTAssertFalse(three.showsCaption)
        // 7 个：放 3 个，第 4 格写 +4。
        let seven = Plan.toggleGrid(count: 7, size: .small)
        XCTAssertEqual([seven.columns, seven.rows, seven.shown, seven.overflow], [2, 2, 3, 4])
    }

    func testToggleGridMediumAndLarge() {
        let four = Plan.toggleGrid(count: 4, size: .medium)
        XCTAssertEqual([four.columns, four.rows, four.shown], [4, 1, 4])
        XCTAssertTrue(four.showsCaption)
        let six = Plan.toggleGrid(count: 6, size: .medium)
        XCTAssertEqual([six.columns, six.rows, six.shown, six.overflow], [4, 2, 6, 0])
        XCTAssertFalse(six.showsCaption)
        let ten = Plan.toggleGrid(count: 10, size: .medium)
        XCTAssertEqual([ten.shown, ten.overflow], [7, 3])

        let five = Plan.toggleGrid(count: 5, size: .large)
        XCTAssertEqual([five.columns, five.rows, five.shown], [3, 2, 5])
        XCTAssertTrue(five.showsCaption)
        let nine = Plan.toggleGrid(count: 9, size: .large)
        XCTAssertEqual([nine.columns, nine.rows, nine.shown, nine.overflow], [3, 3, 9, 0])
        let all = Plan.toggleGrid(count: 21, size: .large)
        XCTAssertEqual([all.columns, all.rows, all.shown, all.overflow], [4, 4, 15, 6])
        XCTAssertFalse(all.showsCaption)

        XCTAssertTrue(Plan.showsAwakeChips(count: 6, hasKeepAwake: true, size: .large))
        XCTAssertFalse(Plan.showsAwakeChips(count: 6, hasKeepAwake: false, size: .large))
        XCTAssertFalse(Plan.showsAwakeChips(count: 12, hasKeepAwake: true, size: .large))
        XCTAssertFalse(Plan.showsAwakeChips(count: 3, hasKeepAwake: true, size: .medium))
    }

    func testGaugeGrid() {
        XCTAssertEqual(Plan.gaugeGrid(count: 0, size: .small), .empty)
        let one = Plan.gaugeGrid(count: 1, size: .small)
        XCTAssertEqual([one.columns, one.rows, one.shown], [1, 1, 1])
        let four = Plan.gaugeGrid(count: 4, size: .small)
        XCTAssertEqual([four.columns, four.rows, four.shown], [2, 2, 4])
        XCTAssertFalse(four.showsCaption)
        let medium = Plan.gaugeGrid(count: 3, size: .medium)
        XCTAssertEqual([medium.columns, medium.rows, medium.shown], [3, 1, 3])
        XCTAssertTrue(medium.showsCaption)
        let large = Plan.gaugeGrid(count: 6, size: .large)
        XCTAssertEqual([large.columns, large.rows, large.shown], [1, 4, 4])
    }

    func testAppGrid() {
        let small = Plan.appGrid(count: 5, size: .small)
        XCTAssertEqual([small.columns, small.rows, small.shown, small.overflow], [3, 2, 5, 0])
        let crowded = Plan.appGrid(count: 14, size: .small)
        XCTAssertEqual([crowded.shown, crowded.overflow], [8, 6])
        let medium = Plan.appGrid(count: 12, size: .medium)
        XCTAssertEqual([medium.columns, medium.rows, medium.shown, medium.overflow], [6, 2, 12, 0])
        let large = Plan.appGrid(count: 9, size: .large)
        XCTAssertEqual([large.columns, large.rows, large.shown, large.overflow], [1, 7, 6, 3])
        XCTAssertEqual(Plan.appGrid(count: 0, size: .large), .empty)
    }

    func testShortcutGrid() {
        let one = Plan.shortcutGrid(count: 1, size: .small)
        XCTAssertEqual([one.columns, one.shown], [1, 1])
        XCTAssertTrue(one.showsCaption)
        let two = Plan.shortcutGrid(count: 2, size: .small)
        XCTAssertEqual([two.columns, two.rows, two.shown], [1, 2, 2])
        XCTAssertTrue(two.showsCaption)
        let four = Plan.shortcutGrid(count: 6, size: .small)
        XCTAssertEqual([four.columns, four.rows, four.shown], [2, 2, 4])
        let medium = Plan.shortcutGrid(count: 3, size: .medium)
        XCTAssertEqual([medium.columns, medium.rows, medium.shown], [3, 1, 3])
        XCTAssertFalse(medium.showsCaption)
        let large = Plan.shortcutGrid(count: 8, size: .large)
        XCTAssertEqual([large.rows, large.shown, large.overflow], [5, 5, 3])
    }

    func testListRows() {
        XCTAssertEqual(Plan.rows(.batteryAccessories, size: .small), 0)
        XCTAssertEqual(Plan.rows(.batteryAccessories, size: .medium), 2)
        XCTAssertEqual(Plan.rows(.processes(metrics: 2), size: .large), 3)
        XCTAssertEqual(Plan.rows(.processes(metrics: 4), size: .large), 2)
        XCTAssertEqual(Plan.rows(.processes(metrics: 2), size: .medium), 0)
        XCTAssertEqual(Plan.rows(.trashRecent, size: .medium), 1)
        XCTAssertEqual(Plan.rows(.trashRecent, size: .large), 4)
        XCTAssertEqual(Plan.rows(.airDropRecent, size: .large), 3)
        XCTAssertEqual(Plan.rows(.fileResults, size: .small), 1)
        XCTAssertEqual(Plan.rows(.searchSites, size: .medium), 6)
    }

    func testSystemMetrics() {
        XCTAssertEqual(Plan.systemMetrics([], size: .small), ["cpu", "memory"])
        XCTAssertEqual(Plan.systemMetrics(["disk", "cpu", "memory"], size: .small), ["disk", "cpu"])
        XCTAssertEqual(Plan.systemMetrics(["cpu", "cpu", "bogus", "network", "disk", "battery", "memory"], size: .large),
                       ["cpu", "network", "disk", "battery"])
    }

    func testBatteryLines() {
        XCTAssertEqual(Plan.batteryRemaining(charging: true, onPower: true, minutesToFull: 80, minutesToEmpty: nil),
                       "约 1 小时 20 分钟充满")
        XCTAssertEqual(Plan.batteryRemaining(charging: false, onPower: false, minutesToFull: nil, minutesToEmpty: 185),
                       "还能用约 3 小时 5 分钟")
        // macOS 还在估（-1）或接着电源不充：不写。
        XCTAssertNil(Plan.batteryRemaining(charging: false, onPower: false, minutesToFull: nil, minutesToEmpty: -1))
        XCTAssertNil(Plan.batteryRemaining(charging: false, onPower: true, minutesToFull: nil, minutesToEmpty: 90))

        XCTAssertEqual(Plan.batteryState(present: false, charging: false, onPower: false, level: 0), "未连接")
        XCTAssertEqual(Plan.batteryState(present: true, charging: false, onPower: true, level: 1), "已充满")
        XCTAssertEqual(Plan.batteryState(present: true, charging: false, onPower: false, level: 0.5), "使用电池")

        XCTAssertEqual(Plan.batteryTone(level: 0.15, charging: false, onPower: false, present: true), .low)
        XCTAssertEqual(Plan.batteryTone(level: 0.08, charging: false, onPower: false, present: true), .critical)
        XCTAssertEqual(Plan.batteryTone(level: 0.08, charging: true, onPower: true, present: true), .normal)
        XCTAssertEqual(Plan.batteryTone(level: 0.5, charging: false, onPower: false, present: false), .absent)
    }
}
