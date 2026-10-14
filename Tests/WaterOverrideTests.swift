import XCTest

/// A next reminder picked by hand in the 喝水 panel.
final class WaterOverrideTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func noon() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
    }

    func testPickedTimeTodayOrTomorrow() {
        let now = noon()
        let later = WaterReminder.pickedTime(minutes: 14 * 60, now: now, calendar: calendar)
        XCTAssertEqual(later.timeIntervalSince(now), 2 * 3600)
        let earlier = WaterReminder.pickedTime(minutes: 9 * 60, now: now, calendar: calendar)
        XCTAssertEqual(earlier.timeIntervalSince(now), 21 * 3600)
    }

    func testOverrideHoldsWhileAhead() {
        let now = noon()
        var config = WidgetConfig(["remindEvery": .string("60")])
        let at = now.addingTimeInterval(1800)
        config.set(WaterReminder.overrideKey, .number(at.timeIntervalSince1970))
        XCTAssertEqual(WaterReminder.override(config, now: now, calendar: calendar), at)
        XCTAssertNil(WaterReminder.override(config, now: at.addingTimeInterval(1), calendar: calendar))
        config.set("remindEvery", .string("0"))
        XCTAssertNil(WaterReminder.override(config, now: now, calendar: calendar))
    }
}
