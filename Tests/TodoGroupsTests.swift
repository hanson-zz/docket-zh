import Foundation
import XCTest

/// 快速待办面板改版：今天 / 稍后 / 已完成分组、拖动排序和跨组、新的一天把昨天没做完的
/// 排到今天最前面、截止时间胶囊、顶部进度，以及新字段的存取和旧存档兼容。
final class TodoGroupsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private let today = "2026-10-22"

    // MARK: 存取

    func testNewFieldsRoundTripAndOldStringsStillRead() {
        let rich = TodoItem(id: "a", text: "交稿", today: true, addedDay: "2026-10-21",
                            remindAt: Date(timeIntervalSince1970: 1_792_000_000),
                            todaySince: "2026-10-21", important: true, externalID: "EK-1", syncMark: "abc")
        var config = WidgetConfig()
        QuickTodo.store([rich], in: &config)
        XCTAssertEqual(QuickTodo.items(config), [rich])
        // 旧版本写下的星标条目：读出来就在「今天」，没有新字段。
        let old = TodoItem(decoding: "b\t0\t回复意见\ts=1\ta=2026-10-20", fallbackID: "f")
        XCTAssertEqual(old?.today, true)
        XCTAssertNil(old?.todaySince)
        XCTAssertEqual(old?.important, false)
        XCTAssertNil(old?.externalID)
        // 没有新字段时写出来和原来一模一样。
        XCTAssertEqual(TodoItem(id: "c", text: "买牛奶").encoded, "c\t0\t买牛奶")
    }

    // MARK: 分组

    func testGroupsAndProgress() {
        let items = [TodoItem(id: "a", text: "一", today: true),
                     TodoItem(id: "b", text: "二"),
                     TodoItem(id: "c", text: "三", today: true),
                     TodoItem(id: "d", text: "四", done: true, today: true),
                     TodoItem(id: "e", text: "五", done: true)]
        XCTAssertEqual(QuickTodo.items(in: .today, of: items).map(\.id), ["a", "c"])
        XCTAssertEqual(QuickTodo.items(in: .later, of: items).map(\.id), ["b"])
        XCTAssertEqual(QuickTodo.items(in: .done, of: items).map(\.id), ["d", "e"])
        let progress = QuickTodo.progress(items)
        XCTAssertEqual(progress, TodoProgress(left: 2, done: 2))
        XCTAssertEqual(progress.line, "今天还剩 2 件 · 已完成 2")
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(TodoProgress(left: 0, done: 0).fraction, 0)
        XCTAssertEqual(TodoGroup.allCases.map(\.title), ["今天", "稍后", "已完成"])
    }

    // MARK: 拖动

    func testDraggingIntoTodayReplacesTheStar() {
        let items = [TodoItem(id: "a", text: "一", today: true, todaySince: today),
                     TodoItem(id: "b", text: "二", today: true, todaySince: today),
                     TodoItem(id: "c", text: "三"),
                     TodoItem(id: "d", text: "四"),
                     TodoItem(id: "e", text: "五", done: true)]
        // 「稍后」的 d 拖到今天的 b 前面。
        let moved = QuickTodo.moving("d", to: .today, before: "b", in: items, today: today)
        XCTAssertEqual(QuickTodo.items(in: .today, of: moved).map(\.id), ["a", "d", "b"])
        XCTAssertEqual(moved.first { $0.id == "d" }?.todaySince, today)
        // 拖到「今天」的标题上：放在今天最后。
        let end = QuickTodo.moving("c", to: .today, before: nil, in: items, today: today)
        XCTAssertEqual(QuickTodo.items(in: .today, of: end).map(\.id), ["a", "b", "c"])
        // 拖回「稍后」：清掉今天的日子。
        let back = QuickTodo.moving("a", to: .later, before: "d", in: items, today: today)
        XCTAssertEqual(QuickTodo.items(in: .later, of: back).map(\.id), ["c", "a", "d"])
        XCTAssertNil(back.first { $0.id == "a" }?.todaySince)
        // 同组里排序。
        let sorted = QuickTodo.moving("b", to: .today, before: "a", in: items, today: today)
        XCTAssertEqual(QuickTodo.items(in: .today, of: sorted).map(\.id), ["b", "a"])
        XCTAssertEqual(sorted.first { $0.id == "b" }?.todaySince, today, "同组拖动不改日子")
        // 「已完成」不接受拖进来，做完的也拖不动，拖到自己前面不变。
        XCTAssertEqual(QuickTodo.moving("c", to: .done, before: nil, in: items, today: today), items)
        XCTAssertEqual(QuickTodo.moving("e", to: .today, before: nil, in: items, today: today), items)
        XCTAssertEqual(QuickTodo.moving("c", to: .later, before: "c", in: items, today: today), items)
    }

    func testDraggingIntoAnEmptyGroup() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二"),
                     TodoItem(id: "z", text: "完", done: true)]
        let first = QuickTodo.moving("b", to: .today, before: nil, in: items, today: today)
        XCTAssertEqual(first.map(\.id), ["b", "a", "z"], "今天空着：放在最前面")
        let allToday = items.map { item -> TodoItem in
            var copy = item
            copy.today = !item.done
            return copy
        }
        let later = QuickTodo.moving("a", to: .later, before: nil, in: allToday, today: today)
        XCTAssertEqual(later.map(\.id), ["b", "a", "z"], "稍后空着：放在没做完的最后")
    }

    func testImportantToggles() {
        let items = QuickTodo.togglingImportant("a", in: [TodoItem(id: "a", text: "一")])
        XCTAssertEqual(items.first?.important, true)
        XCTAssertEqual(QuickTodo.togglingImportant("a", in: items).first?.important, false)
    }

    // MARK: 新的一天

    func testYesterdaysUnfinishedTodayGoesToTheTop() {
        let items = [TodoItem(id: "new", text: "今天的", today: true, addedDay: today, todaySince: today),
                     TodoItem(id: "later", text: "稍后的", addedDay: "2026-10-20"),
                     TodoItem(id: "old", text: "昨天没做完", today: true, addedDay: "2026-10-20",
                              todaySince: "2026-10-21"),
                     TodoItem(id: "star", text: "老版本的星标", today: true, addedDay: "2026-10-19"),
                     TodoItem(id: "due", text: "今天到点", addedDay: "2026-10-20", remindAt: at(10, 22, 18)),
                     TodoItem(id: "late", text: "昨天就该做", addedDay: "2026-10-20", remindAt: at(10, 21, 18)),
                     TodoItem(id: "next", text: "明天的", remindAt: at(10, 23, 9)),
                     TodoItem(id: "done", text: "做完", done: true, today: true, doneDay: today)]
        let planned = QuickTodo.planningToday(items, today: today, calendar: calendar)
        XCTAssertEqual(QuickTodo.items(in: .today, of: planned).map(\.id), ["old", "star", "late", "new", "due"])
        XCTAssertEqual(QuickTodo.items(in: .later, of: planned).map(\.id), ["later", "next"])
        let star = planned.first { $0.id == "star" }
        XCTAssertEqual(star?.todaySince, "2026-10-19", "老版本的星标按记下那天算")
        XCTAssertTrue(QuickTodo.isCarried(star!, today: today))
        XCTAssertEqual(planned.first { $0.id == "due" }?.todaySince, today)
        XCTAssertFalse(QuickTodo.isCarried(planned.first { $0.id == "due" }!, today: today))
        XCTAssertTrue(QuickTodo.isCarried(planned.first { $0.id == "late" }!, today: today))
    }

    func testRolloverPlansTodayOncePerDay() {
        var config = WidgetConfig()
        QuickTodo.store([TodoItem(id: "a", text: "今天的", addedDay: "2026-10-21"),
                         TodoItem(id: "b", text: "昨天没做完", today: true, addedDay: "2026-10-21",
                                  todaySince: "2026-10-21")], in: &config)
        QuickTodo.applyRollover(in: &config, today: today, calendar: calendar)
        XCTAssertEqual(QuickTodo.items(config).map(\.id), ["b", "a"])
        // 当天把它拖回稍后，再打开不会又被挪回来。
        QuickTodo.store(QuickTodo.moving("b", to: .later, before: nil, in: QuickTodo.items(config), today: today),
                        in: &config)
        QuickTodo.applyRollover(in: &config, today: today, calendar: calendar)
        XCTAssertEqual(QuickTodo.items(in: .today, of: QuickTodo.items(config)), [])
    }

    // MARK: 截止时间胶囊

    func testDueBadges() {
        let now = at(10, 22, 16, 10)
        func badge(_ item: TodoItem) -> TodoDueBadge? { QuickTodo.dueBadge(item, now: now, calendar: calendar) }
        XCTAssertEqual(badge(TodoItem(id: "a", text: "过了", remindAt: at(10, 21, 18))),
                       TodoDueBadge(text: "昨天 18:00", tone: .late))
        XCTAssertEqual(badge(TodoItem(id: "b", text: "今天", remindAt: at(10, 22, 17, 30))),
                       TodoDueBadge(text: "17:30", tone: .today))
        XCTAssertEqual(badge(TodoItem(id: "c", text: "今天过了", remindAt: at(10, 22, 9))),
                       TodoDueBadge(text: "09:00", tone: .late))
        XCTAssertEqual(badge(TodoItem(id: "d", text: "以后", remindAt: at(10, 23, 10))),
                       TodoDueBadge(text: "明天 10:00", tone: .later))
        // 没有提醒时间、昨天顺下来的：写“昨天”标红。
        XCTAssertEqual(badge(TodoItem(id: "e", text: "顺下来", today: true, todaySince: "2026-10-21")),
                       TodoDueBadge(text: "昨天", tone: .late))
        XCTAssertNil(badge(TodoItem(id: "f", text: "今天放进来", today: true, todaySince: today)))
        XCTAssertNil(badge(TodoItem(id: "g", text: "做完了", done: true, remindAt: at(10, 21, 18))))
    }

    // MARK: 输入

    func testAddingWithAParsedTime() {
        let items = QuickTodo.adding("交稿", to: [TodoItem(id: "z", text: "完", done: true)], id: "a",
                                     day: today, today: true, remindAt: at(10, 22, 18))
        XCTAssertEqual(items.map(\.id), ["a", "z"])
        XCTAssertEqual(items.first?.today, true)
        XCTAssertEqual(items.first?.todaySince, today)
        XCTAssertEqual(items.first?.remindAt, at(10, 22, 18))
    }
}
