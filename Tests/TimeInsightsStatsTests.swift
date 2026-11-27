import Foundation
import XCTest
@testable import Docket

/// 时间洞察的统计（Core 的 `TimeInsightsStats.swift`）：按小时分类堆叠、按应用堆叠、
/// 较昨日、占比、码头自身不计入、周月汇总、历史区间、完整导出和面板宽度。
final class TimeInsightsStatsTests: XCTestCase {

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        shanghai.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func session(_ id: String, _ start: Date, minutes: Double, _ bundle: String,
                         _ category: TimeInsightsCategory = .uncategorized,
                         source: ActivitySource = .foreground) -> ActivitySession {
        ActivitySession(id: id, start: start, end: start.addingTimeInterval(minutes * 60), bundleID: bundle,
                        appName: bundle.uppercased(), classification: category, source: source)
    }

    // MARK: 按小时堆叠

    func testHoursStackByCategoryInAFixedOrder() {
        let sessions = [
            session("1", date(25, 9, 30), minutes: 60, "code", .development),
            session("2", date(25, 10, 30), minutes: 15, "web"),
            session("3", date(25, 10, 45), minutes: 5, "web", source: .idleForeground),
        ]
        let day = TimeInsightsDay.make(sessions, day: date(25, 12), calendar: shanghai)
        XCTAssertEqual(day.hourCategories[.development]?[9], 1800)
        XCTAssertEqual(day.hourCategories[.development]?[10], 1800)
        XCTAssertEqual(day.hourCategories[.uncategorized]?[10], 900, "前台停留不算进活跃的柱子")
        XCTAssertEqual(day.categories[.development], 3600)
        XCTAssertEqual(day.categories[.uncategorized], 900)

        let slices = TimeInsightsChart.byCategory(day)
        XCTAssertEqual(slices.map(\.id), ["9-development", "10-development", "10-uncategorized"])
        XCTAssertEqual(slices.map(\.order), [0, 0, 6], "从下往上按分类固定顺序")
        XCTAssertEqual(slices.first?.colorHex, TimeInsightsCategory.development.colorHex)
        XCTAssertEqual(TimeInsightsChart.legend(slices).map(\.key), ["development", "uncategorized"])
        XCTAssertEqual(TimeInsightsChart.legend(slices).first?.seconds, 3600)
        XCTAssertEqual(TimeInsightsChart.axisMinutes(slices), 45, "最高一根 45 分")
        XCTAssertEqual(TimeInsightsChart.axisMinutes([]), 15)
        XCTAssertEqual(day.apps.first(where: { $0.bundleID == "web" })?.segments, 1)
        XCTAssertEqual(day.categoryRanking.map(\.category), [.development, .uncategorized])
    }

    func testEveryCategoryHasItsOwnColour() {
        let colours = TimeInsightsCategory.allCases.map(\.colorHex)
        XCTAssertEqual(Set(colours).count, colours.count)
        XCTAssertTrue(colours.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
    }

    func testHoursStackByAppWithTheRestTogether() {
        let sessions = (0..<7).map { i in
            session("\(i)", date(25, 14, i * 5), minutes: Double(5 - (i % 2)), "app\(i)")
        }
        let day = TimeInsightsDay.make(sessions, day: date(25, 14), calendar: shanghai)
        let slices = TimeInsightsChart.byApp(day, restLabel: "其他应用")
        XCTAssertEqual(slices.filter { $0.key != TimeInsightsChart.restKey }.count, TimeInsightsChart.appSeries)
        let rest = slices.first { $0.key == TimeInsightsChart.restKey }
        XCTAssertEqual(rest?.label, "其他应用")
        XCTAssertEqual(rest?.hour, 14)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.seconds }, day.active, "堆起来正好是整天的活跃")
    }

    func testAppDetailAggregatesOnlyTheSelectedApplication() {
        let sessions = [
            session("x1", date(25, 9), minutes: 20, "xcode", .development),
            session("x2", date(25, 10), minutes: 30, "xcode", .development),
            session("other", date(25, 11), minutes: 35, "music", .entertainment),
        ]
        let filtered = sessions.filter { $0.bundleID == "xcode" }
        let day = TimeInsightsDay.make(filtered, day: date(25, 12), calendar: shanghai)
        XCTAssertEqual(day.active, 50 * 60)
        XCTAssertEqual(day.apps.count, 1)
        XCTAssertEqual(day.apps.first?.segments, 2)
        XCTAssertEqual(day.hourCategories[.development]?[9], 20 * 60)
        XCTAssertEqual(day.hourCategories[.development]?[10], 30 * 60)
        XCTAssertNil(day.hourCategories[.entertainment])

        let interval = TimeInsightsPeriod.interval(.week, containing: date(25, 12), calendar: shanghai)
        let period = TimeInsightsPeriod.make(filtered, interval: interval, calendar: shanghai)
        XCTAssertEqual(period.active, 50 * 60)
        XCTAssertEqual(period.apps.map(\.bundleID), ["xcode"])
        XCTAssertEqual(period.categories.map(\.category), [.development])
    }

    func testActivitySegmentsUseGlobalDeDupAndDoNotExposeTitles() {
        let start = date(25, 9)
        let xcode = ActivitySession(id: "code", start: start, end: start.addingTimeInterval(30 * 60),
                                    bundleID: "code", appName: "Xcode", windowTitle: "Private document",
                                    domain: "internal.test", classification: .development)
        let overlapping = ActivitySession(id: "web", start: start.addingTimeInterval(20 * 60),
                                          end: start.addingTimeInterval(50 * 60),
                                          bundleID: "web", appName: "Browser", classification: .uncategorized)
        let idle = ActivitySession(id: "idle", start: start.addingTimeInterval(50 * 60),
                                   end: start.addingTimeInterval(60 * 60),
                                   bundleID: "code", appName: "Xcode", classification: .development,
                                   source: .idleForeground)
        let later = ActivitySession(id: "later", start: start.addingTimeInterval(60 * 60),
                                    end: start.addingTimeInterval(80 * 60),
                                    bundleID: "code", appName: "Xcode", classification: .development)
        let interval = TimeInsightsMath.dayInterval(start, calendar: shanghai)
        let all = [overlapping, xcode, idle, later, xcode]

        let codeRows = TimeInsightsActivityDetail.recentSessions(all, bundleID: "code", interval: interval)
        XCTAssertEqual(codeRows.map(\.id), ["later", "code"])
        XCTAssertEqual(codeRows.reduce(0) { $0 + $1.duration }, 50 * 60)
        XCTAssertNil(codeRows.last?.windowTitle)
        XCTAssertNil(codeRows.last?.domain)
        XCTAssertEqual(TimeInsightsActivityDetail.recentSessions(all, bundleID: "code", interval: interval, limit: 1).count, 1)

        let webRows = TimeInsightsActivityDetail.recentSessions(all, bundleID: "web", interval: interval)
        XCTAssertEqual(webRows.count, 1)
        XCTAssertEqual(webRows[0].duration, 20 * 60, "重叠部分不得再计入浏览器")
        XCTAssertEqual(TimeInsightsActivityDetail.recentSessions(all, bundleID: TimeInsightsDefaults.ownBundleID,
                                                                 interval: interval), [])
    }

    // MARK: 较昨日和占比

    func testComparedWithYesterdayOnlyWithRealData() {
        XCTAssertNil(TimeInsightsStats.change(today: 3600, yesterday: nil), "没有昨天的记录不比")
        XCTAssertNil(TimeInsightsStats.change(today: 3600, yesterday: .empty), "昨天是空的也不比")
        var yesterday = TimeInsightsDay.empty
        yesterday.active = 3600
        let change = TimeInsightsStats.change(today: 3960, yesterday: yesterday)
        XCTAssertEqual(change ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(TimeInsightsStats.changeText(0.1), "+10%")
        XCTAssertEqual(TimeInsightsStats.changeText(-0.25), "-25%")
        XCTAssertEqual(TimeInsightsStats.changeText(0.001), "持平")
        XCTAssertEqual(TimeInsightsStats.percent(30, of: 120), 25)
        XCTAssertEqual(TimeInsightsStats.percent(30, of: 0), 0)
    }

    // MARK: 码头自身

    func testDocklingItselfIsNeverCounted() {
        XCTAssertTrue(TimeInsightsDefaults.alwaysSkipped.contains(TimeInsightsDefaults.ownBundleID))
        XCTAssertEqual(TimeInsightsDefaults.ownBundleID, "com.docket-zh.app")
        let sessions = [
            session("own", date(25, 9), minutes: 30, TimeInsightsDefaults.ownBundleID),
            session("code", date(25, 10), minutes: 10, "code", .development),
        ]
        let day = TimeInsightsDay.make(sessions, day: date(25, 9), calendar: shanghai)
        XCTAssertEqual(day.active, 600, "旧版本记过的码头自身也不算")
        XCTAssertEqual(day.apps.map(\.bundleID), ["code"])

        var r = TimeInsightsRecorder(heartbeatGap: 100_000)
        let own = TimeInsightsRecorder.App(bundleID: TimeInsightsDefaults.ownBundleID, name: "码头")
        _ = r.handle(.foreground(own), at: date(25, 9))
        XCTAssertNil(r.segment)
        XCTAssertEqual(r.status, .ownApp)
    }

    // MARK: 周、月、历史

    func testAWeekStartsOnMondayAndSumsByDay() {
        let wednesday = date(25, 12)
        let week = TimeInsightsPeriod.interval(.week, containing: wednesday, calendar: shanghai)
        XCTAssertEqual(week.start, date(23, 0))
        XCTAssertEqual(week.end, date(30, 0))
        let month = TimeInsightsPeriod.interval(.month, containing: wednesday, calendar: shanghai)
        XCTAssertEqual(month.start, date(1, 0))
        XCTAssertEqual(month.end, date(1, 0, month: 12))

        let sessions = [
            session("a", date(23, 9), minutes: 60, "code", .development),
            session("b", date(25, 9), minutes: 30, "code", .development),
            session("c", date(25, 11), minutes: 45, "web"),
            // 下周的不算。
            session("d", date(30, 9), minutes: 60, "code", .development),
            // 跨午夜的一段拆到两天。
            session("e", date(26, 23, 30), minutes: 60, "chat", .communication),
        ]
        let period = TimeInsightsPeriod.make(sessions, interval: week, calendar: shanghai)
        XCTAssertEqual(period.days.count, 7)
        XCTAssertEqual(period.days.map(\.date).first, date(23, 0))
        XCTAssertEqual(period.days[0].active, 3600)
        XCTAssertEqual(period.days[2].active, 75 * 60)
        XCTAssertEqual(period.days[3].active, 30 * 60)
        XCTAssertEqual(period.days[4].active, 30 * 60)
        XCTAssertEqual(period.active, (60 + 75 + 60) * 60)
        XCTAssertEqual(period.work, (60 + 30 + 60) * 60)
        XCTAssertEqual(period.uncategorized, 45 * 60)
        XCTAssertEqual(period.activeDays, 4)
        XCTAssertEqual(period.averagePerActiveDay, period.active / 4)
        XCTAssertEqual(period.apps.map(\.bundleID), ["code", "chat", "web"])
        XCTAssertEqual(period.apps.first?.active, 90 * 60)
        XCTAssertEqual(period.apps.first?.segments, 2)
        XCTAssertEqual(period.categories.first?.category, .development)
        XCTAssertEqual(period.days[2].topApp?.bundleID, "web")
        XCTAssertFalse(period.days[1].hasData)
        XCTAssertFalse(period.isEmpty)
    }

    func testShiftingAndRecentDays() {
        let wednesday = date(25, 12)
        XCTAssertEqual(TimeInsightsPeriod.shift(wednesday, kind: .week, by: -1, calendar: shanghai), date(18, 12))
        XCTAssertEqual(TimeInsightsPeriod.shift(wednesday, kind: .month, by: 1, calendar: shanghai),
                       date(25, 12, month: 12))
        let recent = TimeInsightsPeriod.recent(days: 7, endingOn: wednesday, calendar: shanghai)
        XCTAssertEqual(recent.start, date(19, 0))
        XCTAssertEqual(recent.end, date(26, 0))
        let empty = TimeInsightsPeriod.make([], interval: recent, calendar: shanghai)
        XCTAssertEqual(empty.days.count, 7)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.averagePerActiveDay, 0)
    }

    // MARK: 导出和面板宽度

    func testTheFullExportCarriesTitlesAndDomains() {
        let s = ActivitySession(id: "a", start: date(25, 9), end: date(25, 9, 1), bundleID: "com.apple.Safari",
                                appName: "Safari", windowTitle: "报告, 草稿", domain: "github.com")
        let csv = TimeInsightsCSV.makeFull([s])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, TimeInsightsCSV.fullHeader)
        XCTAssertTrue(lines[1].hasSuffix(",\"报告, 草稿\",github.com"))
        XCTAssertFalse(TimeInsightsCSV.make([s]).contains("github.com"), "基础导出照旧不带")
    }

    func testThePanelWidensOnlyWhenTheScreenHasRoom() {
        XCTAssertEqual(TimeInsightsLayout.panelWidth(screenWidth: 1440), 440)
        XCTAssertEqual(TimeInsightsLayout.panelWidth(screenWidth: 700), 440)
        XCTAssertEqual(TimeInsightsLayout.panelWidth(screenWidth: 450), 340)
        XCTAssertEqual(TimeInsightsLayout.panelWidth(screenWidth: nil), 440)
        XCTAssertTrue(TimeInsightsLayout.isWide(contentWidth: 408))
        XCTAssertFalse(TimeInsightsLayout.isWide(contentWidth: 308))
        XCTAssertLessThanOrEqual(TimeInsightsLayout.wideWidth, 480)
        XCTAssertGreaterThanOrEqual(TimeInsightsLayout.wideWidth, 400)
    }
}
