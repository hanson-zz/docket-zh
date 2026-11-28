import Foundation
import XCTest

final class TimeInsightsConsistencyTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private let midnight = Date(timeIntervalSince1970: 1_764_288_000)

    private func session(_ id: String, start: TimeInterval, end: TimeInterval,
                         browser: Bool = true, idle: Bool = false) -> ActivitySession {
        ActivitySession(id: id, start: midnight.addingTimeInterval(start), end: midnight.addingTimeInterval(end),
                        bundleID: browser ? "com.google.Chrome" : "com.apple.dt.Xcode", appName: browser ? "Chrome" : "Xcode",
                        domain: browser && !idle ? "example.com" : nil,
                        classification: .development,
                        source: idle ? .idleForeground : browser ? .browserBridge : .foreground)
    }

    func testPartialDayRangeCountsOnlySelectedMinutes() {
        let all = [session("browser", start: 0, end: 3600), session("code", start: 3600, end: 7200, browser: false)]
        let range = DateInterval(start: midnight.addingTimeInterval(1800), end: midnight.addingTimeInterval(5400))
        let period = TimeInsightsPeriod.make(all, interval: range, calendar: calendar)
        XCTAssertEqual(period.active, 3600)
        XCTAssertEqual(period.days.reduce(0) { $0 + $1.foreground }, 3600)
        XCTAssertEqual(period.apps.reduce(0) { $0 + $1.active }, 3600)
        XCTAssertEqual(TimeInsightsWebsiteUsage.ranking(all, interval: range).reduce(0) { $0 + $1.active }, 1800)
    }

    func testCrossMidnightRangeAgreesWithAppDetailsAndWebsiteRanking() {
        let all = [session("browser", start: 23 * 3600, end: 26 * 3600)]
        let range = DateInterval(start: midnight.addingTimeInterval(23.5 * 3600),
                                 end: midnight.addingTimeInterval(24.5 * 3600))
        let period = TimeInsightsPeriod.make(all, interval: range, calendar: calendar)
        XCTAssertEqual(period.active, 3600)
        XCTAssertEqual(period.days.map(\.active), [1800, 1800])
        XCTAssertEqual(TimeInsightsWebsiteUsage.ranking(all, interval: range).first?.active, 3600)
        let details = TimeInsightsActivityDetail.matchingSessions(all, bundleID: "com.google.Chrome", interval: range)
        XCTAssertEqual(details.reduce(0) { $0 + $1.duration }, period.active)
    }

    func testDuplicateCheckpointOutsideRangeIsNormalizedBeforeFiltering() {
        let all = [session("checkpoint", start: 0, end: 1800),
                   session("checkpoint", start: 0, end: 7200),
                   session("new", start: 7200, end: 9000)]
        let range = DateInterval(start: midnight.addingTimeInterval(3600), end: midnight.addingTimeInterval(10_800))
        let period = TimeInsightsPeriod.make(all, interval: range, calendar: calendar)
        XCTAssertEqual(period.active, 1800)
        XCTAssertEqual(TimeInsightsDay.make(all, day: midnight, calendar: calendar).active, 3600)
        XCTAssertEqual(TimeInsightsWebsiteUsage.ranking(all, interval: range).first?.active, period.active)
        let details = TimeInsightsActivityDetail.matchingSessions(all, bundleID: "com.google.Chrome", interval: range)
        XCTAssertEqual(details.reduce(0) { $0 + $1.duration }, period.active)
    }

    func testOverlapsAndIdleStayConsistentWithinPartialRange() {
        let all = [session("one", start: 0, end: 3600),
                   session("overlap", start: 1800, end: 5400, browser: false),
                   session("idle", start: 5400, end: 7200, idle: true)]
        let range = DateInterval(start: midnight.addingTimeInterval(2700), end: midnight.addingTimeInterval(6300))
        let period = TimeInsightsPeriod.make(all, interval: range, calendar: calendar)
        XCTAssertEqual(period.active, 2700)
        XCTAssertEqual(period.days.reduce(0) { $0 + $1.foreground }, 3600)
        XCTAssertEqual(period.apps.reduce(0) { $0 + $1.active }, period.active)
        XCTAssertEqual(period.categories.reduce(0) { $0 + $1.active }, period.active)
        XCTAssertEqual(TimeInsightsWebsiteUsage.ranking(all, interval: range).first?.active, 900)
    }

    func testEmptyRangeDoesNotCountTheRestOfTheDay() {
        let all = [session("one", start: 0, end: 3600)]
        let range = DateInterval(start: midnight.addingTimeInterval(1800), duration: 0)
        let period = TimeInsightsPeriod.make(all, interval: range, calendar: calendar)
        XCTAssertEqual(period.active, 0)
        XCTAssertTrue(period.apps.isEmpty)
    }
}
