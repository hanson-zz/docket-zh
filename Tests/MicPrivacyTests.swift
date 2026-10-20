import Foundation
import XCTest
@testable import Docket

/// 麦克风与摄像头面板：使用记录、全局静音、提醒、电平和设置。
final class MicPrivacyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private let meeting = MicActiveUse(app: "com.example.meet", name: "会议软件", source: .microphone)
    private let memo = MicActiveUse(app: "com.apple.VoiceMemos", name: "语音备忘", source: .microphone)

    // MARK: 记录

    func testStartAndStopMakeOneSession() {
        var log = MicUsageLog()
        XCTAssertEqual(log.update(active: [meeting], now: at(20, 9, 30)), [meeting])
        XCTAssertEqual(log.update(active: [meeting], now: at(20, 9, 31)), [], "still running is not a new start")
        XCTAssertEqual(log.open.count, 1)
        log.update(active: [], now: at(20, 10, 18))
        XCTAssertTrue(log.open.isEmpty)
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertEqual(log.sessions[0].end, at(20, 10, 18))
    }

    func testDuplicatesInOnePollCountOnce() {
        var log = MicUsageLog()
        XCTAssertEqual(log.update(active: [meeting, meeting], now: at(20, 9)).count, 1)
        XCTAssertEqual(log.sessions.count, 1)
    }

    func testAQuickRestartJoinsThePreviousSessionWithoutANewAlert() {
        var log = MicUsageLog()
        log.update(active: [meeting], now: at(20, 9))
        log.update(active: [], now: at(20, 9, 10))
        XCTAssertEqual(log.update(active: [meeting], now: at(20, 9, 10, 3)), [], "back within 5 s")
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertNil(log.sessions[0].end)
        log.update(active: [], now: at(20, 9, 20))
        XCTAssertEqual(log.update(active: [meeting], now: at(20, 9, 21)), [meeting], "a minute later is a new start")
        XCTAssertEqual(log.sessions.count, 2)
    }

    func testDanglingSessionsCloseAtTheLastSave() {
        var log = MicUsageLog(sessions: [MicUsageSession(app: "a", name: "A", source: .microphone, start: at(20, 9))],
                              savedAt: at(20, 9, 40))
        log.closeDangling()
        XCTAssertEqual(log.sessions[0].end, at(20, 9, 40))

        var unsaved = MicUsageLog(sessions: [MicUsageSession(app: "a", name: "A", source: .microphone, start: at(20, 9))])
        unsaved.closeDangling()
        XCTAssertEqual(unsaved.sessions[0].end, at(20, 9), "never earlier than the start")
    }

    func testRowsAddUpPerAppLongestFirstAndCameraApart() {
        var log = MicUsageLog()
        log.update(active: [memo], now: at(20, 8, 12))
        log.update(active: [], now: at(20, 8, 14))
        log.update(active: [meeting, .camera], now: at(20, 9, 30))
        log.update(active: [], now: at(20, 10, 0))
        log.update(active: [meeting], now: at(20, 10, 20))
        log.update(active: [], now: at(20, 10, 38))
        let rows = log.rows(on: at(20, 0), now: at(20, 12), calendar: calendar)
        XCTAssertEqual(rows.map(\.app), [meeting.app, MicActiveUse.cameraID, memo.app])
        XCTAssertEqual(rows[0].total, 48 * 60)
        XCTAssertEqual(rows[0].lastStart, at(20, 10, 20), "the most recent start")
        XCTAssertEqual(rows[1].source, .camera)
        XCTAssertEqual(rows[2].total, 2 * 60)
        XCTAssertFalse(rows.contains { $0.active })
    }

    func testAnOpenSessionCountsUpToNowAndIsActive() {
        var log = MicUsageLog()
        log.update(active: [meeting], now: at(20, 9))
        let rows = log.rows(on: at(20, 0), now: at(20, 9, 12, 48), calendar: calendar)
        XCTAssertEqual(rows.first?.total, 12 * 60 + 48)
        XCTAssertEqual(rows.first?.active, true)
    }

    func testASessionAcrossMidnightIsSplitBetweenTheDays() {
        var log = MicUsageLog()
        log.update(active: [meeting], now: at(19, 23, 30))
        log.update(active: [], now: at(20, 0, 15))
        XCTAssertEqual(log.rows(on: at(19, 12), now: at(20, 12), calendar: calendar).first?.total, 30 * 60)
        XCTAssertEqual(log.rows(on: at(20, 12), now: at(20, 12), calendar: calendar).first?.total, 15 * 60)
        XCTAssertEqual(log.rows(on: at(20, 12), now: at(20, 12), calendar: calendar).first?.lastStart, at(20, 0))
    }

    func testEmptyLogHasNoRowsAndOnlyToday() {
        let log = MicUsageLog()
        XCTAssertTrue(log.rows(on: at(20, 0), now: at(20, 10), calendar: calendar).isEmpty)
        XCTAssertEqual(log.days(now: at(20, 10), unlocked: true, calendar: calendar), [at(20, 0)])
    }

    func testFreeSeesOnlyTodayProSeesThirtyDays() {
        var log = MicUsageLog()
        log.update(active: [meeting], now: at(15, 9))
        log.update(active: [], now: at(15, 10))
        log.update(active: [meeting], now: at(18, 9))
        log.update(active: [], now: at(18, 10))
        XCTAssertEqual(log.days(now: at(20, 10), unlocked: false, calendar: calendar), [at(20, 0)])
        XCTAssertEqual(log.days(now: at(20, 10), unlocked: true, calendar: calendar),
                       [at(20, 0), at(18, 0), at(15, 0)])
    }

    func testHistoryIsAProFeature() {
        XCTAssertTrue(ProLicenseGate.micHistoryActive(unlocked: true))
        XCTAssertFalse(ProLicenseGate.micHistoryActive(unlocked: false))
    }

    func testPruneDropsOlderThanThirtyDaysButKeepsOpenOnes() {
        let old = MicUsageSession(app: "a", name: "A", source: .microphone,
                                  start: at(1, 9).addingTimeInterval(-40 * 86_400),
                                  end: at(1, 10).addingTimeInterval(-40 * 86_400))
        let recent = MicUsageSession(app: "b", name: "B", source: .microphone, start: at(19, 9), end: at(19, 10))
        let open = MicUsageSession(app: "c", name: "C", source: .microphone, start: at(1, 9).addingTimeInterval(-40 * 86_400))
        var log = MicUsageLog(sessions: [old, recent, open])
        log.prune(now: at(20, 10), calendar: calendar)
        XCTAssertEqual(log.sessions.map(\.app), ["b", "c"])
    }

    func testPruneCapsTheNumberOfSessions() {
        let start = at(20, 0)
        var sessions = (0..<(MicUsageLog.maxSessions + 10)).map {
            MicUsageSession(app: "a\($0)", name: "A", source: .microphone,
                            start: start.addingTimeInterval(Double($0)), end: start.addingTimeInterval(Double($0) + 1))
        }
        sessions.append(MicUsageSession(app: "open", name: "O", source: .microphone, start: start))
        var log = MicUsageLog(sessions: sessions)
        log.prune(now: at(20, 23), calendar: calendar)
        XCTAssertEqual(log.sessions.count, MicUsageLog.maxSessions)
        XCTAssertEqual(log.sessions.first?.app, "a11", "the oldest finished ones go first")
        XCTAssertTrue(log.sessions.contains { $0.app == "open" })
    }

    func testLogSurvivesARoundTrip() throws {
        var log = MicUsageLog()
        log.update(active: [meeting, .camera], now: at(20, 9))
        log.savedAt = at(20, 9, 1)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(MicUsageLog.self, from: data), log)
    }

    func testStartOfOpen() {
        var log = MicUsageLog()
        log.update(active: [meeting], now: at(20, 9))
        XCTAssertEqual(log.startOfOpen(app: meeting.app, source: .microphone), at(20, 9))
        XCTAssertNil(log.startOfOpen(app: meeting.app, source: .camera))
        log.update(active: [], now: at(20, 9, 5))
        XCTAssertNil(log.startOfOpen(app: meeting.app, source: .microphone))
    }

    // MARK: 静音

    func testMuteRemembersTheVolumeAndRestoresIt() {
        XCTAssertEqual(MicMute.remembered(current: 0.7, previous: nil), 0.7)
        XCTAssertEqual(MicMute.remembered(current: 0, previous: 0.4), 0.4, "already at zero keeps the old one")
        XCTAssertEqual(MicMute.remembered(current: nil, previous: nil), MicMute.fallbackVolume)
        XCTAssertEqual(MicMute.remembered(current: 0, previous: 0), MicMute.fallbackVolume)
        XCTAssertEqual(MicMute.restored(0.7), 0.7)
        XCTAssertEqual(MicMute.restored(nil), MicMute.fallbackVolume)
        XCTAssertEqual(MicMute.restored(0), MicMute.fallbackVolume, "never restore to silence")
        XCTAssertEqual(MicMute.restored(3), 1)
    }

    func testRaisingTheVolumeElsewhereEndsTheMute() {
        XCTAssertTrue(MicMute.stillMuted(flag: true, volume: 0))
        XCTAssertFalse(MicMute.stillMuted(flag: true, volume: 0.3))
        XCTAssertTrue(MicMute.stillMuted(flag: true, volume: nil))
        XCTAssertFalse(MicMute.stillMuted(flag: false, volume: 0))
    }

    // MARK: 提醒

    func testNoAlertOnTheFirstPollThenOncePerMinute() {
        var tracker = MicAlertTracker()
        XCTAssertTrue(tracker.alerts(started: [meeting], notifyMic: true, notifyCamera: true, now: at(20, 9)).isEmpty,
                      "already running when Docket started")
        XCTAssertEqual(tracker.alerts(started: [memo], notifyMic: true, notifyCamera: true, now: at(20, 9, 1)).count, 1)
        XCTAssertTrue(tracker.alerts(started: [memo], notifyMic: true, notifyCamera: true, now: at(20, 9, 1, 30)).isEmpty)
        XCTAssertEqual(tracker.alerts(started: [memo], notifyMic: true, notifyCamera: true, now: at(20, 9, 3)).count, 1)
    }

    func testAlertsFollowTheSwitches() {
        var tracker = MicAlertTracker()
        _ = tracker.alerts(started: [], notifyMic: true, notifyCamera: true, now: at(20, 9))
        XCTAssertTrue(tracker.alerts(started: [meeting], notifyMic: false, notifyCamera: true, now: at(20, 9, 1)).isEmpty)
        let camera = tracker.alerts(started: [.camera], notifyMic: false, notifyCamera: true, now: at(20, 9, 2))
        XCTAssertEqual(camera.map(\.title), ["摄像头亮起了"])
        XCTAssertTrue(tracker.alerts(started: [.camera], notifyMic: true, notifyCamera: false, now: at(20, 9, 5)).isEmpty)
        let mic = tracker.alerts(started: [meeting], notifyMic: true, notifyCamera: false, now: at(20, 9, 6))
        XCTAssertEqual(mic.map(\.title), ["会议软件 开始用麦克风"])
    }

    // MARK: 电平

    func testLevelMapsDecibelsToSegments() {
        XCTAssertEqual(MicLevel.normalized(decibels: -60), 0)
        XCTAssertEqual(MicLevel.normalized(decibels: -120), 0)
        XCTAssertEqual(MicLevel.normalized(decibels: 0), 1)
        XCTAssertEqual(MicLevel.normalized(decibels: -30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MicLevel.normalized(decibels: -.infinity), 0)
        XCTAssertEqual(MicLevel.lit(0), 0)
        XCTAssertEqual(MicLevel.lit(1), MicLevel.segments)
        XCTAssertEqual(MicLevel.lit(0.5), 12)
        XCTAssertEqual(MicLevel.lit(.nan), 0)
        XCTAssertEqual(MicLevel.lit(2), MicLevel.segments)
    }

    // MARK: 设置

    func testSettingsDefaultsAndHotKey() {
        let defaults = MicPrivacySettings(config: WidgetConfig())
        XCTAssertTrue(defaults.notifyMic)
        XCTAssertTrue(defaults.notifyCamera)
        XCTAssertTrue(defaults.redWhenMuted)
        XCTAssertEqual(defaults.muteKey, MicPrivacySettings.defaultMuteKey)
        XCTAssertEqual(defaults.muteKey?.displayString, "⌥⌘M")

        var cleared = WidgetConfig()
        cleared.set(MicPrivacySettings.muteKeyKey, .string(MicPrivacySettings.encode(nil)))
        XCTAssertNil(MicPrivacySettings(config: cleared).muteKey, "an empty string means no shortcut")
    }

    func testHotKeyEncodingRoundTripsAndRejectsJunk() {
        let combo = KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.control | KeyCombo.Modifier.shift)
        XCTAssertEqual(MicPrivacySettings.decode(MicPrivacySettings.encode(combo)), combo)
        XCTAssertNil(MicPrivacySettings.decode("abc"))
        XCTAssertNil(MicPrivacySettings.decode("46"))
        XCTAssertNil(MicPrivacySettings.decode("46:\(KeyCombo.Modifier.shift)"), "Shift alone would eat typing")
    }

    func testCatalogDefaultsMatchTheSettingsDefaults() {
        let widget = WidgetCatalog.make(.microphone)!
        XCTAssertEqual(MicPrivacySettings(config: widget.config), MicPrivacySettings(config: WidgetConfig()))
    }

    // MARK: 文案

    func testTexts() {
        XCTAssertEqual(MicPrivacyText.subtitle(micApps: 2, camera: false, muted: false), "2 个 App 正在用")
        XCTAssertEqual(MicPrivacyText.subtitle(micApps: 0, camera: true, muted: false), "摄像头开着")
        XCTAssertEqual(MicPrivacyText.subtitle(micApps: 0, camera: false, muted: false), "现在没有 App 在用")
        XCTAssertEqual(MicPrivacyText.subtitle(micApps: 1, camera: true, muted: true), "静音中")
        XCTAssertEqual(MicPrivacyText.clock(190), "03:10")
        XCTAssertEqual(MicPrivacyText.clock(3723), "1:02:03")
        XCTAssertEqual(MicPrivacyText.clock(-5), "00:00")
        XCTAssertEqual(MicPrivacyText.duration(30), "不到 1 分钟")
        XCTAssertEqual(MicPrivacyText.duration(48 * 60), "48 分钟")
        XCTAssertEqual(MicPrivacyText.duration(3600), "1 小时")
        XCTAssertEqual(MicPrivacyText.duration(3900), "1 小时 5 分钟")
        XCTAssertNil(MicPrivacyText.mutedNote(names: []))
        XCTAssertEqual(MicPrivacyText.mutedNote(names: ["会议软件"]), "会议软件 在用麦克风，听不到你")
        XCTAssertEqual(MicPrivacyText.mutedNote(names: ["会议软件", "浏览器"]), "会议软件 等 2 个 App 在用麦克风，听不到你")
        XCTAssertEqual(MicPrivacyText.initial("zoom"), "Z")
        XCTAssertEqual(MicPrivacyText.initial(""), "?")
        XCTAssertTrue(MicPrivacyText.initialColors.contains(MicPrivacyText.initialColor("会议软件")))
        XCTAssertEqual(MicPrivacyText.time(at(20, 9, 5), calendar: calendar), "09:05")
        XCTAssertEqual(MicPrivacyText.dayTitle(at(20, 1), now: at(20, 9), calendar: calendar), "今天")
        XCTAssertEqual(MicPrivacyText.dayTitle(at(19, 1), now: at(20, 9), calendar: calendar), "昨天")
        XCTAssertEqual(MicPrivacyText.dayTitle(at(18, 1), now: at(20, 9), calendar: calendar), "10月18日 周日")
        XCTAssertEqual(MicrophoneText.caption(deviceName: "内建麦克风", apps: []), "内建麦克风")
        XCTAssertEqual(MicrophoneText.caption(deviceName: "内建麦克风", apps: ["会议软件"]), "会议软件")
        XCTAssertEqual(MicrophoneText.caption(deviceName: "", apps: ["会议软件", "浏览器"]), "会议软件 等 2 个")
    }
}
