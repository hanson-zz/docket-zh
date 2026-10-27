import Foundation
import XCTest

/// 桌面卡片 · 时间组：每档列几条、挑哪几条、专注计时开始 / 暂停 / 重置。
final class DesktopTimeCardsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: 种类和条数

    func testElevenKindsAllOfferSmall() {
        XCTAssertEqual(DesktopTimeCards.kinds.count, 11)
        for kind: WidgetKind in [.clock, .world, .stopwatch, .timer, .countdown, .alarm,
                                 .progress, .week, .lunar, .anniversary, .calendar] {
            XCTAssertTrue(DesktopTimeCards.kinds.contains(kind), "\(kind)")
        }
        XCTAssertFalse(DesktopTimeCards.kinds.contains(.notes))
        XCTAssertFalse(DesktopTimeCards.kinds.contains(.todo))
    }

    func testRowsGrowWithSize() {
        for kind in DesktopTimeCards.kinds {
            let small = DesktopTimeCards.rows(kind, .small)
            let medium = DesktopTimeCards.rows(kind, .medium)
            let large = DesktopTimeCards.rows(kind, .large)
            XCTAssertLessThanOrEqual(small, max(medium, 1), "\(kind)")
            XCTAssertLessThanOrEqual(small, large, "\(kind)")
            // 大号 340 高，列表最多 5 行，一行不低于 44pt 才放得下核心那块。
            XCTAssertLessThanOrEqual(large, 5, "\(kind)")
        }
        XCTAssertEqual(DesktopTimeCards.rows(.world, .small), 1)
        XCTAssertEqual(DesktopTimeCards.rows(.world, .medium), 3)
        XCTAssertEqual(DesktopTimeCards.rows(.clock, .large), 0)
    }

    // MARK: 世界时钟

    func testSmallWorldClockPicksFirstCityAway() {
        let shanghai = WorldCity(name: "上海", zone: "Asia/Shanghai")
        let london = WorldCity(name: "伦敦", zone: "Europe/London")
        let tokyo = WorldCity(name: "东京", zone: "Asia/Tokyo")
        let here = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(DesktopTimeCards.worldCities([shanghai, london, tokyo], size: .small, here: here).map(\.name), ["伦敦"])
        // 都在本地时区时放第一个。
        XCTAssertEqual(DesktopTimeCards.worldCities([shanghai], size: .small, here: here).map(\.name), ["上海"])
        XCTAssertEqual(DesktopTimeCards.worldCities([], size: .small, here: here).count, 0)
        // 中号、大号按顺序取前几个。
        XCTAssertEqual(DesktopTimeCards.worldCities([shanghai, london, tokyo], size: .medium, here: here).map(\.name),
                       ["上海", "伦敦", "东京"])
        let many = (0..<8).map { WorldCity(name: "\($0)", zone: "Europe/London") }
        XCTAssertEqual(DesktopTimeCards.worldCities(many, size: .large, here: here).count, 5)
        XCTAssertEqual(DesktopTimeCards.worldCities(many, size: .medium, here: here).count, 3)
    }

    // MARK: 秒表

    func testLapRowsNewestFirstWithMarks() {
        let rows = DesktopTimeCards.lapRows([30, 25, 40, 28], limit: 3)
        XCTAssertEqual(rows.map(\.number), [4, 3, 2])
        XCTAssertEqual(rows.first { $0.number == 2 }?.fastest, true)
        XCTAssertEqual(rows.first { $0.number == 3 }?.slowest, true)
        XCTAssertEqual(DesktopTimeCards.lapRows([], limit: 5).count, 0)
        XCTAssertEqual(DesktopTimeCards.lapRows([1, 2], limit: 0).count, 0)
    }

    // MARK: 闹钟

    func testAlarmRowsLiveFirstThenOffWithoutHeadline() {
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a", minutes: 9 * 60, name: "A"),
            AlarmItem(id: "b", minutes: 15 * 60, name: "B"),
            AlarmItem(id: "c", minutes: 7 * 60, name: "C", enabled: false),
            AlarmItem(id: "d", minutes: 20 * 60, name: "D"),
        ], in: &config)
        let now = date(2026, 10, 27, 8, 0)
        let headline = AlarmBook.headline(config, now: now, calendar: calendar)?.id
        XCTAssertEqual(headline, "a")
        let rows = DesktopTimeCards.alarmRows(config, now: now, limit: 4, excluding: headline, calendar: calendar)
        XCTAssertEqual(rows.map(\.item.id), ["b", "d", "c"])
        XCTAssertEqual(rows.map(\.live), [true, true, false])
        XCTAssertEqual(DesktopTimeCards.alarmRows(config, now: now, limit: 2, excluding: headline,
                                                  calendar: calendar).map(\.item.id), ["b", "d"])
    }

    // MARK: 日历

    func testUpcomingSkipsEndedAndPutsAllDayLast() {
        let now = date(2026, 10, 27, 11, 0)
        let entries = [
            WeekEntry(id: "1", title: "站会", start: date(2026, 10, 27, 9), end: date(2026, 10, 27, 9, 30)),
            WeekEntry(id: "2", title: "周会", start: date(2026, 10, 27, 10, 30), end: date(2026, 10, 27, 11, 30)),
            WeekEntry(id: "3", title: "评审", start: date(2026, 10, 27, 14), end: date(2026, 10, 27, 15)),
            WeekEntry(id: "4", title: "生日", start: date(2026, 10, 27), end: date(2026, 10, 28), isAllDay: true),
        ]
        XCTAssertEqual(DesktopTimeCards.upcoming(entries, now: now, limit: 3).map(\.id), ["2", "3", "4"])
        XCTAssertEqual(DesktopTimeCards.upcoming(entries, now: now, limit: 3, includeAllDay: false).map(\.id), ["2", "3"])
        XCTAssertEqual(DesktopTimeCards.upcoming(entries, now: now, limit: 1).map(\.id), ["2"])
        XCTAssertTrue(DesktopTimeCards.isOngoing(entries[1], now: now))
        XCTAssertFalse(DesktopTimeCards.isOngoing(entries[2], now: now))
        XCTAssertFalse(DesktopTimeCards.isOngoing(entries[3], now: now))
    }

    func testBusyDaysCoverMultiDayButNotEndingMidnight() {
        let entries = [
            WeekEntry(id: "1", title: "a", start: date(2026, 10, 5, 10), end: date(2026, 10, 5, 11)),
            WeekEntry(id: "2", title: "trip", start: date(2026, 10, 8), end: date(2026, 10, 10), isAllDay: true),
        ]
        let days = DesktopTimeCards.busyDays(entries, calendar: calendar)
        XCTAssertEqual(days, [date(2026, 10, 5), date(2026, 10, 8), date(2026, 10, 9)])
    }

    // MARK: 时间进度、农历

    func testNextPeriodCycles() {
        XCTAssertEqual(DesktopTimeCards.nextPeriod(.day), .week)
        XCTAssertEqual(DesktopTimeCards.nextPeriod(.week), .month)
        XCTAssertEqual(DesktopTimeCards.nextPeriod(.month), .year)
        XCTAssertEqual(DesktopTimeCards.nextPeriod(.year), .day)
    }

    func testMonthRows() {
        // 2026 年 2 月 1 日是周日，28 天：6 格空 + 28 = 34 → 5 行。
        XCTAssertEqual(DesktopTimeCards.monthRows(year: 2026, month: 2), 5)
        // 2026 年 3 月 1 日是周日，31 天：6 + 31 = 37 → 6 行。
        XCTAssertEqual(DesktopTimeCards.monthRows(year: 2026, month: 3), 6)
        // 2027 年 2 月 1 日是周一，28 天 → 4 行。
        XCTAssertEqual(DesktopTimeCards.monthRows(year: 2027, month: 2), 4)
    }

    // MARK: 纪念日

    func testOtherReadingsExcludeFeatured() {
        let today = date(2026, 10, 27, 12)
        let events = [
            AnniversaryEvent(id: "a", title: "A", day: "20261101"),
            AnniversaryEvent(id: "b", title: "B", day: "20261201"),
            AnniversaryEvent(id: "c", title: "C", day: "20270101"),
        ]
        let readings = Anniversary.readings(events, today: today)
        XCTAssertEqual(DesktopTimeCards.otherReadings(readings, featured: "a", limit: 4).map(\.event.id), ["b", "c"])
        XCTAssertEqual(DesktopTimeCards.otherReadings(readings, featured: nil, limit: 2).map(\.event.id), ["a", "b"])
    }

    // MARK: 倒计时

    func testCountdownRowsActiveThenDatesThenIdle() {
        var config = WidgetConfig()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        CountdownList.adding(name: "泡面", duration: 180, to: &config, now: now)
        CountdownList.adding(name: "晾衣服", duration: 600, to: &config, now: now)
        let extras = CountdownList.extras(config)
        XCTAssertEqual(extras.count, 2)
        // 加上就开始；泡面停掉，变成没开始的那种，排到最后。
        CountdownList.update(extras[0].id, in: &config) { $0 = CountdownList.stopping($0) }
        let rows = DesktopTimeCards.countdownRows(config, now: now, shown: CountdownList.mainID, limit: 3)
        XCTAssertEqual(rows.map(\.id), ["t-\(extras[1].id)", "t-\(extras[0].id)"])
    }

    // MARK: 专注计时

    func testFocusToggleStartPauseResumeReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var state = TimerState()
        state.work = 25
        XCTAssertEqual(DesktopTimeCards.focusRemaining(state, now: now).left, 25 * 60)

        let started = DesktopTimeCards.focusToggled(state, now: now)
        XCTAssertEqual(started.deadline, now.addingTimeInterval(25 * 60))
        XCTAssertEqual(started.duration, 25 * 60)
        XCTAssertNil(started.paused)

        let later = now.addingTimeInterval(60)
        let paused = DesktopTimeCards.focusToggled(started, now: later)
        XCTAssertNil(paused.deadline)
        XCTAssertEqual(paused.paused ?? 0, 24 * 60, accuracy: 0.001)

        let resumed = DesktopTimeCards.focusToggled(paused, now: later.addingTimeInterval(300))
        XCTAssertEqual(resumed.deadline, later.addingTimeInterval(300 + 24 * 60))

        // 走完了再按是重新开始一整段。
        let done = later.addingTimeInterval(3600)
        let restarted = DesktopTimeCards.focusToggled(resumed, now: done)
        XCTAssertEqual(restarted.deadline, done.addingTimeInterval(25 * 60))

        let reset = DesktopTimeCards.focusReset(restarted)
        XCTAssertNil(reset.deadline)
        XCTAssertNil(reset.paused)
        XCTAssertNil(reset.duration)
    }
}
