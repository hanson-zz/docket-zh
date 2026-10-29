import Foundation
import XCTest
@testable import Docket

// Pure logic behind the v0.4.1 additions: per-widget visibility, fitting the
// shelf by shrinking, the stand-up reminder's schedule and the ring gauges.

final class WidgetPlateTests: XCTestCase {
    func testPlateIsShownByDefaultAndToggles() {
        let clock = WidgetCatalog.make(.clock)!
        XCTAssertFalse(WidgetPlate.isHidden(clock.config))
        let bare = WidgetPlate.toggled(clock)
        XCTAssertTrue(WidgetPlate.isHidden(bare.config))
        XCTAssertEqual(bare.id, clock.id)
        XCTAssertFalse(WidgetPlate.isHidden(WidgetPlate.toggled(bare).config))
    }

    /// Not a catalog default, so it is never offered as a generic option
    /// beside the widget's own settings.
    func testPlateIsNotAConfigurableKey() {
        for kind in WidgetKind.allCases {
            XCTAssertFalse(WidgetCatalog.configurableKeys(kind).contains(WidgetPlate.key), "\(kind)")
        }
    }
}

final class ShelfFitTests: XCTestCase {
    func testFitsAlreadyKeepsTheBase() {
        XCTAssertEqual(ShelfFit.fittedScale(base: 0.5, available: 1000) { $0 * 1000 }, 0.5)
    }

    func testShrinksToTheLargestScaleThatFits() {
        let fitted = ShelfFit.fittedScale(base: 0.6, available: 800) { $0 * 2000 }
        XCTAssertEqual(fitted, 0.4, accuracy: 0.001)
        XCTAssertLessThanOrEqual(fitted * 2000, 800)
    }

    func testNeverBelowTheMinimum() {
        // Would need 0.1; the floor is half of 0.6.
        let fitted = ShelfFit.fittedScale(base: 0.6, available: 200) { $0 * 2000 }
        XCTAssertEqual(fitted, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ShelfFit.minimum(for: 0.35), Geometry.scaleRange.lowerBound)
    }

    func testOverflowDecodesLeniently() throws {
        let decoded = try JSONDecoder().decode([ShelfOverflow].self, from: Data(#"["shrink","sideways"]"#.utf8))
        XCTAssertEqual(decoded, [.shrink, .scroll])
    }

    func testSettingsWithoutOverflowDefaultToScroll() throws {
        let settings = try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.overflow, .scroll)
        var changed = settings
        changed.overflow = .shrink
        let again = try JSONDecoder().decode(CustomDockSettings.self,
                                             from: JSONEncoder().encode(changed))
        XCTAssertEqual(again.overflow, .shrink)
    }
}

final class WidgetVisibilityTests: XCTestCase {
    private func widget(_ kind: WidgetKind, _ pairs: [String: WidgetConfig.Value] = [:]) -> WidgetInstance {
        WidgetInstance(kind: kind, config: WidgetConfig(pairs))
    }

    func testDefaultIsAlwaysAndPlateShown() {
        let music = widget(.music)
        XCTAssertEqual(WidgetVisibility.mode(music.config), .always)
        XCTAssertTrue(WidgetVisibility.isVisible(music, WidgetConditions(musicPlaying: false)))
    }

    func testUnknownModeFallsBackToAlways() {
        let w = widget(.clock, ["visibility": .string("sometimes")])
        XCTAssertEqual(WidgetVisibility.mode(w.config), .always)
    }

    func testHiddenIsHiddenEvenInSamples() {
        let w = widget(.clock, ["visibility": .string("hidden")])
        XCTAssertFalse(WidgetVisibility.isVisible(w, .unknown))
        XCTAssertFalse(WidgetVisibility.isVisible(w, .unknown, ignoringConditions: true))
    }

    func testMusicOnlyWhilePlaying() {
        let w = widget(.music, ["visibility": .string("conditional")])
        XCTAssertTrue(WidgetVisibility.isVisible(w, WidgetConditions(musicPlaying: true)))
        XCTAssertFalse(WidgetVisibility.isVisible(w, WidgetConditions(musicPlaying: false)))
        // Unreadable: stays visible.
        XCTAssertTrue(WidgetVisibility.isVisible(w, .unknown))
        // Samples ignore conditions.
        XCTAssertTrue(WidgetVisibility.isVisible(w, WidgetConditions(musicPlaying: false),
                                                 ignoringConditions: true))
    }

    func testMicrophoneAndMail() {
        let mic = widget(.microphone, ["visibility": .string("conditional")])
        XCTAssertFalse(WidgetVisibility.isVisible(mic, WidgetConditions(micInUse: false)))
        XCTAssertTrue(WidgetVisibility.isVisible(mic, WidgetConditions(micInUse: true)))
        let mail = widget(.mail, ["visibility": .string("conditional")])
        XCTAssertFalse(WidgetVisibility.isVisible(mail, WidgetConditions(mailUnread: 0)))
        XCTAssertTrue(WidgetVisibility.isVisible(mail, WidgetConditions(mailUnread: 2)))
        XCTAssertTrue(WidgetVisibility.isVisible(mail, WidgetConditions(mailUnread: nil)))
    }

    func testBatteryOnBatteryAndThreshold() {
        let any = widget(.battery, ["visibility": .string("conditional")])
        XCTAssertFalse(WidgetVisibility.isVisible(any, WidgetConditions(onBattery: false, batteryLevel: 0.5)))
        XCTAssertTrue(WidgetVisibility.isVisible(any, WidgetConditions(onBattery: true, batteryLevel: 0.9)))
        // A desktop Mac has no battery to read: visible.
        XCTAssertTrue(WidgetVisibility.isVisible(any, WidgetConditions(onBattery: nil)))

        let low = widget(.battery, ["visibility": .string("conditional"), "showBelow": .number(20)])
        XCTAssertFalse(WidgetVisibility.isVisible(low, WidgetConditions(onBattery: true, batteryLevel: 0.5)))
        XCTAssertTrue(WidgetVisibility.isVisible(low, WidgetConditions(onBattery: true, batteryLevel: 0.2)))
        XCTAssertTrue(WidgetVisibility.isVisible(low, WidgetConditions(onBattery: true, batteryLevel: 0.07)))
        XCTAssertFalse(WidgetVisibility.isVisible(low, WidgetConditions(onBattery: false, batteryLevel: 0.07)))
    }

    func testThresholdIsClamped() {
        XCTAssertEqual(WidgetVisibility.batteryThreshold(WidgetConfig(["showBelow": .number(0)])), 5)
        XCTAssertEqual(WidgetVisibility.batteryThreshold(WidgetConfig(["showBelow": .number(400)])), 100)
        XCTAssertEqual(WidgetVisibility.batteryThreshold(WidgetConfig()), 100)
    }

    func testKindsWithoutAConditionIgnoreConditional() {
        let clock = widget(.clock, ["visibility": .string("conditional")])
        XCTAssertTrue(WidgetVisibility.isVisible(clock, WidgetConditions(musicPlaying: false)))
        XCTAssertEqual(WidgetVisibility.modes(for: .clock), [.always, .hidden])
        XCTAssertEqual(WidgetVisibility.modes(for: .music), [.always, .conditional, .hidden])
        XCTAssertNil(WidgetVisibility.conditionTitle(.clock, config: WidgetConfig()))
        XCTAssertEqual(WidgetVisibility.conditionTitle(.battery, config: WidgetConfig(["showBelow": .number(20)])),
                       "使用电池且电量不高于 20% 时显示")
    }

    func testFilteringAndHiddenListKeepOrderAndRestore() {
        let a = widget(.clock)
        let b = widget(.music, ["visibility": .string("conditional")])
        let c = widget(.notes, ["visibility": .string("hidden")])
        let spacer = DockItem.spacer(id: UUID(), size: .small)
        let items: [DockItem] = [.widget(a), spacer, .widget(b), .widget(c)]
        let quiet = WidgetConditions(musicPlaying: false)

        let visible = WidgetVisibility.visibleItems(items, quiet)
        XCTAssertEqual(visible.map(\.id), [a.id, spacer.id])
        let hidden = WidgetVisibility.hiddenWidgets(items, quiet)
        XCTAssertEqual(hidden.map(\.id), [b.id, c.id])
        XCTAssertEqual(WidgetVisibility.hiddenReason(b), "条件未满足")
        XCTAssertEqual(WidgetVisibility.hiddenReason(c), "已隐藏")

        let back = WidgetVisibility.restored(c)
        XCTAssertEqual(back.id, c.id)
        XCTAssertTrue(WidgetVisibility.isVisible(back, quiet))
    }
}

final class MicrophoneTextTests: XCTestCase {
    func testMicrophoneText() {
        XCTAssertEqual(MicrophoneText.value(inUse: true, muted: false), "使用中")
        XCTAssertEqual(MicrophoneText.value(inUse: false, muted: false), "未使用")
        XCTAssertEqual(MicrophoneText.value(inUse: true, muted: true), "已静音")
        XCTAssertEqual(MicrophoneText.caption(deviceName: ""), "没有输入设备")
        XCTAssertEqual(MicrophoneText.caption(deviceName: "外置麦克风"), "外置麦克风")
    }

    func testMicrophoneIsInTheLibraryAndOpensSound() {
        XCTAssertNotNil(WidgetCatalog.make(.microphone))
        XCTAssertEqual(WidgetCatalog.openTarget(.microphone),
                       .settings("com.apple.Sound-Settings.extension"))
    }
}

final class PostureScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let schedule = PostureSchedule(interval: 1800, start: 9 * 60, end: 18 * 60)

    func testParsesTimes() {
        XCTAssertEqual(PostureSchedule.minutes("09:30"), 570)
        XCTAssertEqual(PostureSchedule.minutes("9:05"), 545)
        XCTAssertEqual(PostureSchedule.minutes("18：00"), 1080)
        XCTAssertNil(PostureSchedule.minutes("25:00"))
        XCTAssertNil(PostureSchedule.minutes("abc"))
        XCTAssertEqual(PostureSchedule.clock(570), "09:30")
    }

    func testIntervalHasAFloor() {
        XCTAssertEqual(PostureSchedule(interval: 10, start: 0, end: 0).interval, 300)
    }

    func testActiveHours() {
        XCTAssertTrue(schedule.isActive(at(12, 9, 0), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at(12, 18, 0), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at(12, 7, 0), calendar: calendar))
        let night = PostureSchedule(interval: 1800, start: 22 * 60, end: 6 * 60)
        XCTAssertTrue(night.isActive(at(12, 23, 0), calendar: calendar))
        XCTAssertTrue(night.isActive(at(12, 2, 0), calendar: calendar))
        XCTAssertFalse(night.isActive(at(12, 12, 0), calendar: calendar))
    }

    func testDueFromWindowStartWithoutABreak() {
        let due = schedule.due(lastBreak: nil, now: at(12, 9, 10), calendar: calendar)
        XCTAssertEqual(due, at(12, 9, 30))
        // A break from yesterday does not count.
        XCTAssertEqual(schedule.due(lastBreak: at(11, 17, 0), now: at(12, 9, 10), calendar: calendar),
                       at(12, 9, 30))
    }

    func testDueFromLastBreak() {
        XCTAssertEqual(schedule.due(lastBreak: at(12, 10, 5), now: at(12, 10, 20), calendar: calendar),
                       at(12, 10, 35))
        XCTAssertEqual(schedule.remaining(lastBreak: at(12, 10, 5), now: at(12, 10, 20), calendar: calendar), 900)
        XCTAssertEqual(schedule.progress(lastBreak: at(12, 10, 5), now: at(12, 10, 20), calendar: calendar),
                       0.5, accuracy: 0.0001)
    }

    func testIgnoredReminderRepeats() {
        let next = schedule.nextReminder(lastBreak: at(12, 10, 0), now: at(12, 10, 45), calendar: calendar)
        XCTAssertEqual(next, at(12, 11, 0))
        XCTAssertEqual(schedule.remaining(lastBreak: at(12, 10, 0), now: at(12, 10, 45), calendar: calendar), 0)
    }

    func testReminderWaitsForTheNextWindow() {
        let next = schedule.nextReminder(lastBreak: at(12, 17, 50), now: at(12, 17, 55), calendar: calendar)
        XCTAssertEqual(next, at(13, 9, 30))
    }

    func testTally() {
        let now = at(12, 15, 0)
        XCTAssertEqual(PostureTally.dayKey(now, calendar: calendar), "2026-10-12")
        XCTAssertEqual(PostureTally.today(storedDay: "2026-10-12", count: 3, now: now, calendar: calendar), 3)
        XCTAssertEqual(PostureTally.today(storedDay: "2026-10-11", count: 3, now: now, calendar: calendar), 0)
        let logged = PostureTally.logging(storedDay: "2026-10-11", count: 7, now: now, calendar: calendar)
        XCTAssertEqual(logged.day, "2026-10-12")
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(PostureTally.logging(storedDay: "2026-10-12", count: 2, now: now, calendar: calendar).count, 3)
    }
}

final class GaugeReadingTests: XCTestCase {
    func testUsedFraction() {
        XCTAssertEqual(GaugeReading.usedFraction(free: 250, total: 1000), 0.75, accuracy: 0.0001)
        XCTAssertEqual(GaugeReading.usedFraction(free: 10, total: 0), 0)
        XCTAssertEqual(GaugeReading.usedFraction(free: 2000, total: 1000), 0)
    }

    func testBytes() {
        XCTAssertEqual(GaugeReading.bytes(245_000_000_000), "245 GB")
        XCTAssertEqual(GaugeReading.bytes(1_234_000_000_000), "1.2 TB")
        XCTAssertEqual(GaugeReading.bytes(512_000_000), "512 MB")
        XCTAssertEqual(GaugeReading.bytes(900), "900 B")
        XCTAssertEqual(GaugeReading.percent(0.624), "62%")
    }

    func testRingsAreOrderedAndNeverEmpty() {
        XCTAssertEqual(GaugeReading.rings(WidgetConfig()), ["storage", "battery"])
        XCTAssertEqual(GaugeReading.rings(WidgetConfig(["rings": .list([.string("battery"), .string("storage")])])),
                       ["battery", "storage"])
        XCTAssertEqual(GaugeReading.rings(WidgetConfig(["rings": .list([.string("battery")])])), ["battery"])
        XCTAssertEqual(GaugeReading.rings(WidgetConfig(["rings": .list([.string("cpu")])])), ["cpu"])
        XCTAssertEqual(GaugeReading.rings(WidgetConfig(["rings": .list([.string("network")])])), ["storage", "battery"])
        let one = WidgetCatalog.naturalSize(WidgetInstance(kind: .gauges,
            config: WidgetConfig(["rings": .list([.string("battery")])])))
        let two = WidgetCatalog.naturalSize(WidgetCatalog.make(.gauges)!)
        XCTAssertLessThan(one.width, two.width)
    }

    func testNewKindsAreInTheLibrary() {
        for kind in [WidgetKind.gauges, .posture, .todo, .ambient, .lunar, .trash, .habit, .week, .crypto, .appVolume, .radio, .anniversary, .water, .translate, .pet, .podcast, .perfectDay, .slacker, .aiAssistant, .cassette, .minesweeper, .pullTooth, .divination] {
            XCTAssertNotNil(WidgetCatalog.entry(kind), "\(kind)")
            XCTAssertNotNil(WidgetCatalog.make(kind), "\(kind)")
        }
    }
}
