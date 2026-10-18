import Foundation
import XCTest

final class ReminderSoundTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 音色

    func testDefaultTonesDifferPerKind() {
        let settings = ReminderSoundSettings()
        XCTAssertEqual(settings.tone(for: .reminders), .glass)
        XCTAssertEqual(settings.tone(for: .water), .pop)
        XCTAssertEqual(settings.tone(for: .todo), .tink)
        let names = ReminderSoundKind.allCases.compactMap { settings.tone(for: $0).soundName }
        XCTAssertEqual(Set(names).count, 3)
    }

    func testSetToneChangesOnlyThatKind() {
        var settings = ReminderSoundSettings()
        settings.setTone(.purr, for: .water)
        XCTAssertEqual(settings.water, .purr)
        XCTAssertEqual(settings.reminders, .glass)
        XCTAssertEqual(settings.todo, .tink)
    }

    func testEveryToneButOffIsASystemSound() {
        XCTAssertNil(ReminderTone.off.soundName)
        XCTAssertTrue(ReminderTone.off.fallbacks.isEmpty)
        for tone in ReminderTone.allCases where tone != .off {
            XCTAssertNotNil(tone.soundName)
            XCTAssertEqual(tone.fallbacks.first, tone.soundName)
            XCTAssertEqual(Set(tone.fallbacks).count, tone.fallbacks.count)
        }
    }

    // MARK: 解码

    func testOldStateFileDecodesToDefaults() throws {
        let settings = try JSONDecoder().decode(ReminderSoundSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, ReminderSoundSettings())
    }

    func testUnknownToneFallsBackToThatKindsDefault() throws {
        let json = #"{"enabled":false,"reminders":"chime2099","water":"off","todo":"morse"}"#
        let settings = try JSONDecoder().decode(ReminderSoundSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.reminders, .glass)
        XCTAssertEqual(settings.water, .off)
        XCTAssertEqual(settings.todo, .morse)
    }

    func testRoundTrip() throws {
        var settings = ReminderSoundSettings()
        settings.enabled = false
        settings.setTone(.hero, for: .reminders)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ReminderSoundSettings.self, from: data), settings)
    }

    func testPersistedStateWithoutTheKeyStillLoads() throws {
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.reminderSounds, ReminderSoundSettings())
    }

    // MARK: 该不该响

    func testMasterSwitchAndVolumeGateEverything() {
        let settings = ReminderSoundSettings()
        var master = WidgetSoundSettings()
        XCTAssertEqual(ReminderSoundDecision.tone(for: .water, settings: settings, master: master), .pop)
        master.enabled = false
        XCTAssertNil(ReminderSoundDecision.tone(for: .water, settings: settings, master: master))
        master.enabled = true
        master.volume = 0
        XCTAssertNil(ReminderSoundDecision.tone(for: .water, settings: settings, master: master))
    }

    func testReminderSwitchAndOffTone() {
        var settings = ReminderSoundSettings()
        let master = WidgetSoundSettings()
        settings.setTone(.off, for: .reminders)
        XCTAssertNil(ReminderSoundDecision.tone(for: .reminders, settings: settings, master: master))
        XCTAssertFalse(ReminderSoundDecision.notificationHasSound(.reminders, settings: settings, master: master))
        XCTAssertTrue(ReminderSoundDecision.notificationHasSound(.water, settings: settings, master: master))
        settings.enabled = false
        XCTAssertNil(ReminderSoundDecision.tone(for: .water, settings: settings, master: master))
    }

    func testFocusAndScreenSharingSilenceOnlyWhenKnown() {
        let settings = ReminderSoundSettings()
        let master = WidgetSoundSettings()
        func play(_ env: ReminderSoundEnvironment) -> ReminderTone? {
            ReminderSoundDecision.toneToPlay(for: .reminders, settings: settings, master: master, environment: env)
        }
        XCTAssertEqual(play(.init()), .glass)
        XCTAssertEqual(play(.init(focusActive: false, screenShared: false)), .glass)
        XCTAssertNil(play(.init(focusActive: true)))
        XCTAssertNil(play(.init(screenShared: true)))
    }

    // MARK: 通知标识

    func testNotificationIdentifiers() {
        XCTAssertEqual(ReminderSoundKind(notificationIdentifier: "docket.water.\(UUID().uuidString)"), .water)
        XCTAssertEqual(ReminderSoundKind(notificationIdentifier: "docket.reminder.x"), .reminders)
        XCTAssertEqual(ReminderSoundKind(notificationIdentifier: "docket.todo.x"), .todo)
        XCTAssertNil(ReminderSoundKind(notificationIdentifier: "docket.stock.AAPL"))
        XCTAssertNil(ReminderSoundKind(notificationIdentifier: "docket.posture.x"))
    }

    // MARK: 刚到点

    func testNewlyDueOnlyTimedOnesInsideTheTick() {
        let items: [(id: String, due: ReminderDue)] = [
            ("a", ReminderDue(date: base.addingTimeInterval(1), hasTime: true)),
            ("b", ReminderDue(date: base, hasTime: true)),                       // 上一刻已经算过
            ("c", ReminderDue(date: base.addingTimeInterval(1), hasTime: false)), // 全天的不响
            ("d", ReminderDue(date: base.addingTimeInterval(5), hasTime: true)),  // 还没到
        ]
        XCTAssertEqual(ReminderSoundDecision.newlyDue(items, after: base, upTo: base.addingTimeInterval(1)), ["a"])
    }

    func testNewlyDueOrdersByTime() {
        let items: [(id: String, due: ReminderDue)] = [
            ("late", ReminderDue(date: base.addingTimeInterval(40), hasTime: true)),
            ("early", ReminderDue(date: base.addingTimeInterval(10), hasTime: true)),
        ]
        XCTAssertEqual(ReminderSoundDecision.newlyDue(items, after: base, upTo: base.addingTimeInterval(60)),
                       ["early", "late"])
    }

    func testNoCatchUpAfterSleepOrBackwardsClock() {
        let items: [(id: String, due: ReminderDue)] = [
            ("a", ReminderDue(date: base.addingTimeInterval(100), hasTime: true)),
        ]
        XCTAssertTrue(ReminderSoundDecision.newlyDue(items, after: base, upTo: base.addingTimeInterval(3_600)).isEmpty)
        XCTAssertTrue(ReminderSoundDecision.newlyDue(items, after: base.addingTimeInterval(200),
                                                     upTo: base.addingTimeInterval(150)).isEmpty)
    }

    // MARK: 合并

    func testBurstChimesOnce() {
        var gate = ReminderSoundGate(window: 4)
        XCTAssertTrue(gate.allow(at: base))
        XCTAssertFalse(gate.allow(at: base.addingTimeInterval(0.5)))
        XCTAssertFalse(gate.allow(at: base.addingTimeInterval(3.9)))
        XCTAssertTrue(gate.allow(at: base.addingTimeInterval(4)))
    }

    func testGateRecoversFromClockGoingBack() {
        var gate = ReminderSoundGate()
        XCTAssertTrue(gate.allow(at: base))
        XCTAssertTrue(gate.allow(at: base.addingTimeInterval(-60)))
    }

    // MARK: 勿扰和屏幕共享

    func testFocusAssertionsFile() {
        let on = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}"#
        let off = #"{"data":[{"storeAssertionRecords":[]}]}"#
        let empty = #"{"data":[{}]}"#
        XCTAssertEqual(ReminderSoundDecision.focusActive(assertionsJSON: Data(on.utf8)), true)
        XCTAssertEqual(ReminderSoundDecision.focusActive(assertionsJSON: Data(off.utf8)), false)
        XCTAssertEqual(ReminderSoundDecision.focusActive(assertionsJSON: Data(#"{"data":[]}"#.utf8)), false)
        XCTAssertNil(ReminderSoundDecision.focusActive(assertionsJSON: Data(empty.utf8)))
        XCTAssertNil(ReminderSoundDecision.focusActive(assertionsJSON: nil))
        XCTAssertNil(ReminderSoundDecision.focusActive(assertionsJSON: Data("not json".utf8)))
    }

    func testScreenSharedValue() {
        XCTAssertEqual(ReminderSoundDecision.screenShared(sessionValue: true), true)
        XCTAssertEqual(ReminderSoundDecision.screenShared(sessionValue: NSNumber(value: 0)), false)
        XCTAssertNil(ReminderSoundDecision.screenShared(sessionValue: nil))
        XCTAssertNil(ReminderSoundDecision.screenShared(sessionValue: "yes"))
    }
}
