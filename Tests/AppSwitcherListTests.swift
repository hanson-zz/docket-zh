import XCTest

/// 应用切换器的固定、隐藏和排序（见 AppSwitcherList）。
final class AppSwitcherListTests: XCTestCase {

    private typealias App = AppSwitcherList.App

    /// 打开先后：访达、浏览器、微信、音乐；当前在微信。
    private let apps: [App] = [
        App(id: "finder", name: "访达", isActive: false),
        App(id: "browser", name: "Safari", isActive: false),
        App(id: "wechat", name: "WeChat", isActive: true),
        App(id: "music", name: "Music", isActive: false),
    ]

    private let english = Locale(identifier: "en_US")

    func testReadingCleansTheLists() {
        var config = WidgetConfig()
        XCTAssertEqual(AppSwitcherList.sort(config), .recent, "默认最近使用")
        XCTAssertEqual(AppSwitcherList.pinned(config), [])
        XCTAssertEqual(AppSwitcherList.hidden(config), [])

        config.set(AppSwitcherList.pinnedKey, .list([.string("a"), .string(" "), .string("b"), .string("a")]))
        config.set(AppSwitcherList.hiddenKey, .list([.string("b"), .string("c"), .string("c")]))
        config.set(AppSwitcherList.sortKey, .string("bogus"))
        XCTAssertEqual(AppSwitcherList.pinned(config), ["a", "b"], "去空、去重")
        XCTAssertEqual(AppSwitcherList.hidden(config), ["c"], "固定的不算隐藏")
        XCTAssertEqual(AppSwitcherList.sort(config), .recent, "认不出的排序退回最近使用")

        let many = (0..<20).map { WidgetConfig.Value.string("app\($0)") }
        config.set(AppSwitcherList.pinnedKey, .list(many))
        XCTAssertEqual(AppSwitcherList.pinned(config).count, AppSwitcherList.maxPinned)
    }

    func testPinAndHideAreExclusive() {
        var lists = AppSwitcherList.toggleHide("finder", pinned: [], hidden: [])
        XCTAssertEqual(lists.hidden, ["finder"])
        lists = AppSwitcherList.togglePin("finder", pinned: lists.pinned, hidden: lists.hidden)
        XCTAssertEqual(lists.pinned, ["finder"], "固定会把它从隐藏里拿出来")
        XCTAssertEqual(lists.hidden, [])
        lists = AppSwitcherList.toggleHide("finder", pinned: lists.pinned, hidden: lists.hidden)
        XCTAssertEqual(lists.pinned, [], "隐藏顺带取消固定")
        XCTAssertEqual(lists.hidden, ["finder"])
        lists = AppSwitcherList.toggleHide("finder", pinned: lists.pinned, hidden: lists.hidden)
        XCTAssertEqual(lists.hidden, [], "再点一次取消隐藏")
        XCTAssertEqual(AppSwitcherList.toggleHide("", pinned: [], hidden: []).hidden, [])
    }

    func testPinningStopsAtTheLimit() {
        let full = (0..<AppSwitcherList.maxPinned).map { "app\($0)" }
        let lists = AppSwitcherList.togglePin("more", pinned: full, hidden: ["more"])
        XCTAssertEqual(lists.pinned, full, "满了固定不了")
        XCTAssertEqual(lists.hidden, ["more"], "固定不了时也不动隐藏")
        XCTAssertEqual(AppSwitcherList.togglePin("app0", pinned: full, hidden: []).pinned.count,
                       AppSwitcherList.maxPinned - 1, "满了也能取消固定")
        XCTAssertEqual(AppSwitcherList.togglePin("only", pinned: ["only"], hidden: []).pinned, [], "取消最后一个")
    }

    func testMovingPins() {
        let pins = ["a", "b", "c"]
        XCTAssertEqual(AppSwitcherList.move("b", by: -1, in: pins), ["b", "a", "c"])
        XCTAssertEqual(AppSwitcherList.move("b", by: 1, in: pins), ["a", "c", "b"])
        XCTAssertEqual(AppSwitcherList.move("a", by: -1, in: pins), pins, "到头不动")
        XCTAssertEqual(AppSwitcherList.move("c", by: 1, in: pins), pins)
        XCTAssertEqual(AppSwitcherList.move("x", by: 1, in: pins), pins)
    }

    func testRecentlyUsed() {
        var recent = AppSwitcherList.noteActive("music", recent: [])
        recent = AppSwitcherList.noteActive("browser", recent: recent)
        recent = AppSwitcherList.noteActive("music", recent: recent)
        XCTAssertEqual(recent, ["music", "browser"], "切回来挪到最前，不重复")
        XCTAssertEqual(AppSwitcherList.noteActive(nil, recent: recent), recent)

        let ordered = AppSwitcherList.byRecency(apps, recent: recent).map(\.id)
        XCTAssertEqual(ordered, ["wechat", "music", "browser", "finder"],
                       "当前的在最前，再按最近切到，没切过的按打开先后")
        XCTAssertEqual(AppSwitcherList.byRecency(apps, recent: []).map(\.id), ["wechat", "finder", "browser", "music"],
                       "没记过时和原来一样：当前的在前，其余按打开先后")

        var lots: [String] = []
        for i in 0..<100 { lots = AppSwitcherList.noteActive("app\(i)", recent: lots) }
        XCTAssertEqual(lots.count, AppSwitcherList.maxRecent)
        XCTAssertEqual(lots.first, "app99")
    }

    func testSortingTheRunningList() {
        let recent = ["music", "browser"]
        XCTAssertEqual(AppSwitcherList.running(apps, recent: recent, pinned: [], hidden: [], sort: .name,
                                               locale: english).map(\.name),
                       ["Music", "Safari", "WeChat", "访达"])
        XCTAssertEqual(AppSwitcherList.running(apps, recent: recent, pinned: ["finder", "browser"], hidden: [],
                                               sort: .pinnedFirst).map(\.id),
                       ["finder", "browser", "wechat", "music"], "固定的按固定先后在前，其余按最近使用")
        XCTAssertEqual(AppSwitcherList.running(apps, recent: recent, pinned: [], hidden: ["finder", "music"],
                                               sort: .recent).map(\.id),
                       ["wechat", "browser"], "隐藏的不列")
        XCTAssertEqual(AppSwitcherList.running([], recent: recent, pinned: ["x"], hidden: [], sort: .pinnedFirst), [],
                       "没开的固定 App 不进运行列表")
        XCTAssertEqual(AppSwitcherList.running(apps, recent: [], pinned: [], hidden: apps.map(\.id), sort: .recent), [],
                       "全隐藏时是空的")
    }

    func testNameSortIgnoresCaseAndReadsNumbers() {
        let named = [App(id: "1", name: "app 10", isActive: false), App(id: "2", name: "App 9", isActive: false),
                     App(id: "3", name: "Zed", isActive: false), App(id: "4", name: "app 9", isActive: false)]
        XCTAssertEqual(AppSwitcherList.byName(named, locale: english).map(\.id), ["2", "4", "1", "3"])
    }

    func testTheTilePutsPinsFirst() {
        let slots = AppSwitcherList.tile(apps, recent: ["music"], pinned: ["notes", "browser"], hidden: ["finder"],
                                         sort: .recent)
        XCTAssertEqual(slots.map(\.id), ["notes", "browser", "wechat", "music"])
        XCTAssertEqual(slots.map(\.isRunning), [false, true, true, true], "没开的固定 App 也在")
        XCTAssertEqual(slots.map(\.isPinned), [true, true, false, false])
        XCTAssertEqual(slots.first(where: \.isActive)?.id, "wechat")

        let byName = AppSwitcherList.tile(apps, recent: [], pinned: [], hidden: [], sort: .name, locale: english)
        XCTAssertEqual(byName.map(\.id), ["music", "browser", "wechat", "finder"])
        let pinnedFirst = AppSwitcherList.tile(apps, recent: [], pinned: ["music"], hidden: [], sort: .pinnedFirst)
        XCTAssertEqual(pinnedFirst.map(\.id), ["music", "wechat", "finder", "browser"])
        XCTAssertEqual(AppSwitcherList.tile([], recent: [], pinned: [], hidden: [], sort: .recent), [])
    }

    func testWords() {
        XCTAssertEqual(AppSwitcherList.subtitle(pinned: 4, running: 6), "固定 4 个 · 运行中 6 个")
        XCTAssertEqual(AppSwitcherList.subtitle(pinned: 0, running: 6), "6 个应用正在运行")
        XCTAssertEqual(AppSwitcherList.windowTitle("  ", minimized: false), "无标题窗口")
        XCTAssertEqual(AppSwitcherList.windowTitle(nil, minimized: true), "无标题窗口（已最小化）")
        XCTAssertEqual(AppSwitcherList.windowTitle("码头官网", minimized: false), "码头官网")
        XCTAssertEqual(AppSwitcherList.Sort.allCases.map(\.title), ["最近使用", "名称", "固定在前"])
    }
}
