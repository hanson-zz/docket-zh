import Foundation
import SQLite3
import XCTest
@testable import Docket

/// 时间洞察 1.0 阶段 A（Core 的 `TimeInsights*`）：采集状态机的前台切换、空闲扣除、锁屏、
/// 心跳断开、排除、暂停和崩溃恢复，跨午夜拆分、去重、今日汇总，分类规则，SQLite 的版本迁移、
/// 写入去重和清空，CSV 导出，设置、Pro 范围和域名清洗，以及目录接入。
final class TimeInsightsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let xcode = TimeInsightsRecorder.App(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    private let safari = TimeInsightsRecorder.App(bundleID: "com.apple.Safari", name: "Safari")
    private let music = TimeInsightsRecorder.App(bundleID: "com.apple.Music", name: "音乐")

    /// 心跳断开的判断放宽，单独的测试再收紧。
    private func recorder(idle: TimeInterval = 300, excluded: Set<String> = []) -> TimeInsightsRecorder {
        TimeInsightsRecorder(idleAfter: idle, excluded: excluded, heartbeatGap: 100_000)
    }

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    // MARK: 前台切换

    func testSwitchingAppsEndsOneSegmentAndStartsTheNext() {
        var r = recorder()
        XCTAssertTrue(r.handle(.foreground(xcode), at: at(0)).isEmpty)
        XCTAssertTrue(r.handle(.tick, at: at(10)).isEmpty)
        let done = r.handle(.foreground(safari), at: at(60))
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done.first?.bundleID, xcode.bundleID)
        XCTAssertEqual(done.first?.duration, 60)
        XCTAssertEqual(done.first?.classification, .development)
        XCTAssertEqual(done.first?.source, .foreground)
        XCTAssertEqual(r.segment?.bundleID, safari.bundleID)
        XCTAssertEqual(r.segment?.start, at(60))
        XCTAssertEqual(r.status, .recording)
    }

    func testTheSameAppReportedAgainIsNotSplit() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        XCTAssertTrue(r.handle(.foreground(xcode), at: at(20)).isEmpty)
        XCTAssertTrue(r.handle(.foreground(xcode), at: at(40)).isEmpty)
        XCTAssertEqual(r.segment?.start, at(0))
        XCTAssertEqual(r.segment?.lastSeen, at(40))
        XCTAssertEqual(r.provisional(now: at(50))?.duration, 50)
    }

    func testASwitchShorterThanASecondIsDropped() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        XCTAssertEqual(r.handle(.foreground(safari), at: at(30)).count, 1)
        XCTAssertTrue(r.handle(.foreground(xcode), at: at(30.4)).isEmpty, "一闪而过的 Safari 不记")
    }

    // MARK: 空闲

    func testIdleTimeIsDeductedFromTheMomentOfTheLastInput() {
        var r = recorder(idle: 300)
        _ = r.handle(.foreground(xcode), at: at(0))
        XCTAssertTrue(r.handle(.idle(30), at: at(30)).isEmpty)
        // 400 秒时已经 310 秒没输入：上次输入在 90 秒，活跃段到 90 为止。
        let left = r.handle(.idle(310), at: at(400))
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.start, at(0))
        XCTAssertEqual(left.first?.end, at(90))
        XCTAssertEqual(left.first?.source, .foreground)
        XCTAssertEqual(r.status, .idle)
        XCTAssertEqual(r.segment?.idle, true)
        XCTAssertEqual(r.segment?.start, at(90))

        // 498 秒有输入回来：前台停留 90 到 498，不算活跃；新的活跃段从 498 开始。
        let back = r.handle(.idle(2), at: at(500))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.source, .idleForeground)
        XCTAssertEqual(back.first?.start, at(90))
        XCTAssertEqual(back.first?.end, at(498))
        XCTAssertEqual(r.segment?.idle, false)
        XCTAssertEqual(r.segment?.start, at(498))
        XCTAssertEqual(r.status, .recording)

        let day = TimeInsightsDay.make(left + back + [r.provisional(now: at(560))!], day: at(0), calendar: shanghai)
        XCTAssertEqual(day.active, 90 + 62)
        XCTAssertEqual(day.foreground, 560)
        XCTAssertEqual(day.idleForeground, 408)
    }

    func testIdleBeforeAWakeDoesNotReachBackIntoTheLockedTime() {
        var r = recorder(idle: 300)
        _ = r.handle(.foreground(xcode), at: at(0))
        _ = r.handle(.blocked(.locked), at: at(100))
        _ = r.handle(.unblocked(.locked), at: at(1000))
        XCTAssertEqual(r.segment?.start, at(1000))
        // 解锁后马上读到的空闲秒数还很大（锁屏期间没输入）：停留段不能早于 1000。
        let done = r.handle(.idle(900), at: at(1010))
        XCTAssertTrue(done.allSatisfy { $0.start >= at(1000) })
        XCTAssertEqual(r.segment?.start, at(1000))
        XCTAssertEqual(r.segment?.idle, true)
    }

    func testTheIdleThresholdCanBeChanged() {
        var r = recorder(idle: 60)
        _ = r.handle(.foreground(xcode), at: at(0))
        let done = r.handle(.idle(61), at: at(100))
        XCTAssertEqual(done.first?.end, at(39))
        XCTAssertEqual(r.status, .idle)
    }

    // MARK: 锁屏、休眠、暂停、排除

    func testLockingStopsTheClockUntilUnlocked() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        let locked = r.handle(.blocked(.locked), at: at(100))
        XCTAssertEqual(locked.first?.duration, 100)
        XCTAssertNil(r.segment)
        XCTAssertEqual(r.status, .away)
        XCTAssertTrue(r.handle(.tick, at: at(150)).isEmpty)
        XCTAssertNil(r.segment)
        _ = r.handle(.unblocked(.locked), at: at(200))
        XCTAssertEqual(r.segment?.start, at(200))
        let next = r.handle(.foreground(safari), at: at(260))
        XCTAssertEqual(next.first?.duration, 60)
        XCTAssertEqual((locked + next).reduce(0) { $0 + $1.duration }, 160)
    }

    func testEveryBlockHasToClearBeforeRecordingResumes() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        _ = r.handle(.blocked(.displayOff), at: at(10))
        _ = r.handle(.blocked(.asleep), at: at(11))
        _ = r.handle(.unblocked(.displayOff), at: at(20))
        XCTAssertNil(r.segment, "还在休眠")
        _ = r.handle(.unblocked(.asleep), at: at(30))
        XCTAssertEqual(r.segment?.start, at(30))
    }

    func testPausingClosesTheSegmentAndShowsPaused() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        XCTAssertEqual(r.handle(.blocked(.paused), at: at(45)).first?.duration, 45)
        XCTAssertEqual(r.status, .paused)
        XCTAssertTrue(r.handle(.foreground(safari), at: at(60)).isEmpty)
        XCTAssertNil(r.segment)
        _ = r.handle(.unblocked(.paused), at: at(90))
        XCTAssertEqual(r.segment?.bundleID, safari.bundleID)
    }

    func testExcludedAppsAreNeverRecorded() {
        var r = recorder(excluded: [music.bundleID])
        _ = r.handle(.foreground(music), at: at(0))
        XCTAssertNil(r.segment)
        XCTAssertEqual(r.status, .excluded)
        XCTAssertTrue(r.handle(.foreground(xcode), at: at(50)).isEmpty)
        XCTAssertEqual(r.segment?.start, at(50))
        let done = r.handle(.foreground(music), at: at(80))
        XCTAssertEqual(done.map(\.bundleID), [xcode.bundleID])
        XCTAssertNil(r.segment)
    }

    func testSystemScreensAreSkipped() {
        var r = recorder()
        _ = r.handle(.foreground(.init(bundleID: "com.apple.loginwindow", name: "loginwindow")), at: at(0))
        XCTAssertNil(r.segment)
    }

    // MARK: 心跳和崩溃恢复

    func testAMissedHeartbeatEndsTheSegmentAtTheLastOne() {
        var r = TimeInsightsRecorder(heartbeatGap: 90)
        _ = r.handle(.foreground(xcode), at: at(0))
        _ = r.handle(.tick, at: at(10))
        _ = r.handle(.tick, at: at(20))
        // 休眠却没收到通知：下一次心跳隔了 480 秒，空档不算。
        let done = r.handle(.tick, at: at(500))
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done.first?.end, at(20))
        XCTAssertEqual(r.segment?.start, at(500))
        XCTAssertEqual(r.handle(.foreground(safari), at: at(530)).first?.duration, 30)
    }

    func testRecoveryEndsAtTheLastHeartbeatNotAtLaunch() {
        let segment = TimeInsightsRecorder.Open(bundleID: xcode.bundleID, appName: xcode.name, start: at(0),
                                             lastSeen: at(120), idle: false, classification: .development)
        let recovered = TimeInsightsRecorder.recover(segment, now: at(9999))
        XCTAssertEqual(recovered?.start, at(0))
        XCTAssertEqual(recovered?.end, at(120))
        XCTAssertEqual(recovered?.id, segment.id, "同一段的 id 不变，再写一次也不会重复")
        XCTAssertEqual(TimeInsightsRecorder.recover(segment, now: at(60))?.end, at(60), "时钟往回调时不超过现在")
        var idle = segment
        idle.idle = true
        XCTAssertEqual(TimeInsightsRecorder.recover(idle, now: at(9999))?.source, .idleForeground)
    }

    func testFlushClosesTheOpenSegment() {
        var r = recorder()
        _ = r.handle(.foreground(xcode), at: at(0))
        XCTAssertEqual(r.flush(at: at(30)).first?.duration, 30)
        XCTAssertNil(r.segment)
    }

    // MARK: 跨午夜、去重、汇总

    func testSessionsAreSplitAtLocalMidnight() {
        let calendar = shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 23, minute: 50))!
        let session = ActivitySession(id: "a", start: start, end: start.addingTimeInterval(1800),
                                      bundleID: "x", appName: "X")
        let parts = TimeInsightsMath.splitByDay(session, calendar: calendar)
        XCTAssertEqual(parts.map(\.duration), [600, 1200])
        XCTAssertEqual(parts.map(\.id), ["a", "a#1"])
        XCTAssertEqual(calendar.component(.day, from: parts[1].start), 28)
        XCTAssertEqual(calendar.component(.hour, from: parts[1].start), 0)
        XCTAssertEqual(TimeInsightsMath.splitByDay(ActivitySession(id: "b", start: start, end: start,
                                                                   bundleID: "x", appName: "X")).count, 0)
    }

    func testOverlapsAndDuplicatesAreCountedOnce() {
        let a = ActivitySession(id: "a", start: at(0), end: at(100), bundleID: "x", appName: "X")
        let b = ActivitySession(id: "b", start: at(50), end: at(150), bundleID: "y", appName: "Y")
        let inside = ActivitySession(id: "c", start: at(10), end: at(20), bundleID: "z", appName: "Z")
        let clean = TimeInsightsMath.normalized([b, a, a, inside])
        XCTAssertEqual(clean.map(\.id), ["a", "b"])
        XCTAssertEqual(clean.reduce(0) { $0 + $1.duration }, 150)
    }

    func testTheDaySummarySeparatesActiveWorkOtherAndUncategorized() {
        let calendar = shanghai
        let nine = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 9))!
        func s(_ id: String, _ from: TimeInterval, _ length: TimeInterval, _ bundle: String,
               _ category: TimeInsightsCategory, _ source: ActivitySource = .foreground) -> ActivitySession {
            ActivitySession(id: id, start: nine.addingTimeInterval(from), end: nine.addingTimeInterval(from + length),
                            bundleID: bundle, appName: bundle.uppercased(), classification: category, source: source)
        }
        let sessions = [
            s("1", 0, 3000, "code", .development),
            s("2", 3000, 600, "chat", .communication),
            s("3", 3600, 1200, "web", .uncategorized),
            s("4", 4800, 900, "web", .uncategorized, .idleForeground),
            s("5", 5700, 300, "tv", .entertainment),
            // 前一天的不算进今天。
            ActivitySession(id: "old", start: nine.addingTimeInterval(-86_400), end: nine.addingTimeInterval(-86_000),
                            bundleID: "code", appName: "CODE", classification: .development),
        ]
        let day = TimeInsightsDay.make(sessions, day: nine, calendar: calendar)
        XCTAssertEqual(day.active, 5100)
        XCTAssertEqual(day.foreground, 6000)
        XCTAssertEqual(day.work, 3600)
        XCTAssertEqual(day.uncategorized, 1200)
        XCTAssertEqual(day.other, 300)
        XCTAssertEqual(day.apps.map(\.bundleID), ["code", "web", "chat", "tv"])
        XCTAssertEqual(day.apps.first?.active, 3000)
        XCTAssertEqual(day.longest?.bundleID, "code")
        XCTAssertEqual(day.segments, 4)
        XCTAssertEqual(day.hours[9], 3600)
        XCTAssertEqual(day.hours[10], 1500)
        XCTAssertEqual(day.hours.reduce(0, +), day.active)
    }

    func testTheFreeTopListStopsAtFive() {
        let sessions = (0..<7).map { i in
            ActivitySession(id: "\(i)", start: at(Double(i) * 100), end: at(Double(i) * 100 + Double(10 + i)),
                            bundleID: "app\(i)", appName: "App \(i)")
        }
        let day = TimeInsightsDay.make(sessions, day: at(0), calendar: shanghai)
        XCTAssertEqual(day.apps.count, 7)
        XCTAssertEqual(day.top().count, 5)
        XCTAssertEqual(day.top().first?.bundleID, "app6")
        XCTAssertEqual(TimeInsightsPro.topLimit(unlocked: false), 5)
        XCTAssertTrue(TimeInsightsDay.empty.isEmpty)
    }

    // MARK: 分类

    func testOnlyKnownAppsGetACategory() {
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.apple.dt.Xcode"), .development)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.figma.Desktop"), .design)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.tencent.xinWeChat"), .communication)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.apple.Safari"), .uncategorized, "浏览器不等于工作")
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.google.Chrome"), .uncategorized)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.unknown.app"), .uncategorized)
        XCTAssertEqual(TimeInsightsCategory(stored: "something-new"), .uncategorized)
        XCTAssertFalse(TimeInsightsCategory.uncategorized.countsAsWork)
        XCTAssertFalse(TimeInsightsCategory.entertainment.countsAsWork)
        XCTAssertEqual(TimeInsightsCategory.allCases.count, 7)
        XCTAssertEqual(Set(TimeInsightsCategory.allCases.map(\.title)).count, 7)
    }

    func testRulesGoByPriorityThenByOrder() {
        let rules = [
            TimeInsightsRule(.bundleID("com.apple.Safari"), category: .learning, priority: 0),
            TimeInsightsRule(.domain("github.com"), category: .development, priority: 5),
            TimeInsightsRule(.titleKeyword("bilibili"), category: .entertainment, priority: 5),
        ]
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.apple.Safari", rules: rules), .learning)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.apple.Safari", domain: "gist.github.com",
                                                       rules: rules), .development)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "com.apple.Safari", domain: "notgithub.com",
                                                       rules: rules), .learning)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "x", windowTitle: "看 Bilibili", rules: rules),
                       .entertainment)
        XCTAssertEqual(TimeInsightsClassifier.classify(bundleID: "x", rules: rules), .uncategorized,
                       "没有标题时标题规则不中")
        // 用户规则盖过内置规则。
        XCTAssertEqual(TimeInsightsClassifier.classify(
            bundleID: "com.apple.Music", rules: [TimeInsightsRule(.bundleID("com.apple.music"), category: .learning)]),
            .learning)
    }

    func testReclassifyingNeverChangesTheTimes() {
        let original = ActivitySession(id: "a", start: at(0), end: at(60), bundleID: "com.apple.Safari",
                                       appName: "Safari", source: .idleForeground)
        let rules = [TimeInsightsRule(.bundleID("com.apple.Safari"), category: .learning)]
        let changed = TimeInsightsClassifier.reclassify([original], rules: rules)[0]
        XCTAssertEqual(changed.classification, .learning)
        XCTAssertEqual(changed.start, original.start)
        XCTAssertEqual(changed.end, original.end)
        XCTAssertEqual(changed.source, original.source)
        XCTAssertEqual(changed.id, original.id)
    }

    // MARK: 数据库

    private func temporaryURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ti-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appending(path: "activity.sqlite")
    }

    func testMigrationPlans() {
        XCTAssertEqual(TimeInsightsSchema.plan(from: 0), .migrate([1]))
        XCTAssertEqual(TimeInsightsSchema.plan(from: TimeInsightsSchema.currentVersion), .upToDate)
        XCTAssertEqual(TimeInsightsSchema.plan(from: 9), .tooNew(9))
        XCTAssertEqual(TimeInsightsSchema.plan(from: 1, to: 3), .migrate([2, 3]))
        XCTAssertEqual(TimeInsightsSchema.plan(from: -1, to: 2), .migrate([1, 2]))
        for version in 1...TimeInsightsSchema.currentVersion {
            XCTAssertFalse(TimeInsightsSchema.migrations[version]?.isEmpty ?? true, "第 \(version) 版没有语句")
        }
    }

    func testANewDatabaseIsCreatedAtTheCurrentVersion() throws {
        let url = try temporaryURL()
        let db = try TimeInsightsDatabase(url: url)
        XCTAssertEqual(db.version, TimeInsightsSchema.currentVersion)
        XCTAssertEqual(try db.count(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWritingTheSameSessionTwiceKeepsOne() throws {
        let db = try TimeInsightsDatabase(url: try temporaryURL())
        let a = ActivitySession(id: "a", start: at(0), end: at(60), bundleID: "x", appName: "X, \"Y\"",
                                classification: .design, source: .idleForeground, privacyFlags: [.domainOnly])
        let b = ActivitySession(id: "b", start: at(100), end: at(160), bundleID: "y", appName: "Y")
        try db.insert([a, b])
        try db.insert([a])
        XCTAssertEqual(try db.count(), 2)
        let back = try db.allSessions()
        XCTAssertEqual(back.first, a)
        XCTAssertEqual(back.last?.id, "b")
        let window = try db.sessions(overlapping: DateInterval(start: at(30), end: at(90)))
        XCTAssertEqual(window.map(\.id), ["a"])
        try db.prune(endingBefore: at(80))
        XCTAssertEqual(try db.allSessions().map(\.id), ["b"])
        try db.delete(bundleID: "y")
        XCTAssertEqual(try db.count(), 0)
    }

    func testDataSurvivesReopening() throws {
        let url = try temporaryURL()
        do {
            let db = try TimeInsightsDatabase(url: url)
            try db.insert([ActivitySession(id: "a", start: at(0), end: at(60), bundleID: "x", appName: "X")])
        }
        let again = try TimeInsightsDatabase(url: url)
        XCTAssertEqual(try again.count(), 1)
        XCTAssertEqual(again.version, TimeInsightsSchema.currentVersion)
    }

    func testTheOpenSegmentIsKeptForRecovery() throws {
        let db = try TimeInsightsDatabase(url: try temporaryURL())
        XCTAssertNil(try db.loadOpen())
        let segment = TimeInsightsRecorder.Open(bundleID: "x", appName: "X", start: at(0), lastSeen: at(30),
                                             idle: false, classification: .other)
        try db.saveOpen(segment)
        XCTAssertEqual(try db.loadOpen(), segment)
        var later = segment
        later.lastSeen = at(40)
        try db.saveOpen(later)
        XCTAssertEqual(try db.loadOpen()?.lastSeen, at(40))
        try db.saveOpen(nil)
        XCTAssertNil(try db.loadOpen())
    }

    func testClearingRemovesEverything() throws {
        let db = try TimeInsightsDatabase(url: try temporaryURL())
        try db.insert([ActivitySession(id: "a", start: at(0), end: at(60), bundleID: "x", appName: "X")])
        try db.saveOpen(.init(bundleID: "x", appName: "X", start: at(60), lastSeen: at(70), idle: false,
                              classification: .uncategorized))
        try db.deleteAll()
        XCTAssertEqual(try db.count(), 0)
        XCTAssertNil(try db.loadOpen())
    }

    func testAFileFromANewerVersionIsRefusedAndLeftAlone() throws {
        let url = try temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(raw, "CREATE TABLE keep(x); PRAGMA user_version = 9", nil, nil, nil), SQLITE_OK)
        sqlite3_close(raw)
        XCTAssertThrowsError(try TimeInsightsDatabase(url: url)) { error in
            XCTAssertEqual(error as? TimeInsightsDatabase.Failure, .tooNew(9))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "不删、不覆盖")
    }

    // MARK: 导出

    func testTheBasicExportHasNoTitlesOrDomains() {
        let session = ActivitySession(id: "a", start: at(0), end: at(90), bundleID: "com.x", appName: "=Hi, \"you\"",
                                      windowTitle: "秘密标题", domain: "secret.example", classification: .learning)
        let csv = TimeInsightsCSV.make([session])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, TimeInsightsCSV.header)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(",90,com.x,"))
        XCTAssertTrue(lines[1].contains("\"'=Hi, \"\"you\"\"\""))
        XCTAssertTrue(lines[1].hasSuffix(",learning,foreground"))
        XCTAssertFalse(csv.contains("秘密标题"))
        XCTAssertFalse(csv.contains("secret.example"))
        XCTAssertEqual(TimeInsightsCSV.escape("plain"), "plain")
    }

    // MARK: 设置、Pro、域名

    func testSettingsDefaultsAndOldFiles() throws {
        let fresh = TimeInsightsSettings()
        XCTAssertFalse(fresh.paused)
        XCTAssertEqual(fresh.idleMinutes, 5)
        XCTAssertEqual(fresh.idleThreshold, 300)
        XCTAssertFalse(fresh.windowTitlesOptIn, "默认不采窗口标题")
        XCTAssertFalse(fresh.websitesOptIn, "默认不采网站")
        XCTAssertTrue(fresh.customRules.isEmpty, "旧版设置默认没有规则")
        XCTAssertTrue(TimeInsightsSettings.idleChoices.contains(TimeInsightsSettings.defaultIdleMinutes))

        let old = TimeInsightsSettings.decode(Data(#"{"paused":true,"idleMinutes":0}"#.utf8))
        XCTAssertTrue(old.paused)
        XCTAssertEqual(old.idleMinutes, 1)
        XCTAssertEqual(old.retentionDays, TimeInsightsSettings.defaultRetentionDays)
        XCTAssertTrue(old.customRules.isEmpty)
        XCTAssertEqual(TimeInsightsSettings.decode(Data("garbage".utf8)), TimeInsightsSettings())
        XCTAssertEqual(TimeInsightsSettings.decode(nil), TimeInsightsSettings())

        var settings = fresh
        settings.exclude("com.x")
        settings.exclude("com.x")
        settings.exclude("")
        XCTAssertEqual(settings.excludedBundleIDs, ["com.x"])
        XCTAssertTrue(settings.isExcluded("com.x"))
        settings.customRules = [TimeInsightsRule(.bundleID("com.test.app"), category: .design)]
        let round = TimeInsightsSettings.decode(settings.encoded())
        XCTAssertEqual(round, settings)
        settings.include("com.x")
        XCTAssertTrue(settings.excludedBundleIDs.isEmpty)
    }

    func testProWindowTitlesRequirePurchaseAndSeparateConsent() {
        var settings = TimeInsightsSettings()
        XCTAssertFalse(TimeInsightsPro.collectsWindowTitles(settings, unlocked: true), "买了 Pro 不等于同意")
        XCTAssertFalse(TimeInsightsPro.collectsWebsites(settings, unlocked: true))
        settings.windowTitlesOptIn = true
        settings.websitesOptIn = true
        XCTAssertFalse(TimeInsightsPro.collectsWindowTitles(settings, unlocked: false), "没解锁时同意了也不采")
        XCTAssertTrue(TimeInsightsPro.collectsWindowTitles(settings, unlocked: true), "阶段 B 源已接通，还需系统授权")
        XCTAssertTrue(TimeInsightsPro.collectsWebsites(settings, unlocked: true))
        XCTAssertFalse(TimeInsightsPro.collectsWebsites(settings, unlocked: false))
        XCTAssertTrue(TimeInsightsProFeature.trends.isConnected, "周/月真实统计已接通")
        XCTAssertTrue(TimeInsightsProFeature.windowTitles.isConnected)
        XCTAssertTrue(TimeInsightsProFeature.customRules.isConnected)
        XCTAssertTrue(TimeInsightsProFeature.websites.isConnected)
        XCTAssertFalse(TimeInsightsProFeature.detailedTimeline.isConnected)
        XCTAssertFalse(TimeInsightsProFeature.fullExport.isConnected)
        XCTAssertEqual(Set(TimeInsightsProFeature.allCases.filter(\.needsConsent)), [.windowTitles, .websites])
        XCTAssertTrue(TimeInsightsPro.canControlPrivacy(unlocked: false), "暂停、排除、清空、导出免费")
        XCTAssertEqual(UnconnectedBrowserBridge().state, .notConnected)
        XCTAssertNil(UnconnectedBrowserBridge().currentTab(for: "com.apple.Safari"))
        XCTAssertNil(UnconnectedWindowTitleSource().title(forProcess: 1))
    }

    func testTitlePrivacyAndRuleValidation() {
        XCTAssertFalse(TimeInsightsTitlePrivacy.allows(bundleID: "com.apple.Safari"))
        XCTAssertFalse(TimeInsightsTitlePrivacy.allows(bundleID: "com.google.Chrome"))
        XCTAssertFalse(TimeInsightsTitlePrivacy.allows(bundleID: "com.1password.1password"))
        XCTAssertTrue(TimeInsightsTitlePrivacy.allows(bundleID: "com.apple.dt.Xcode"))
        XCTAssertNil(TimeInsightsTitlePrivacy.sanitize("  "))
        let hidden = TimeInsightsTitlePrivacy.sanitize("文档 a@example.com 123456789")
        XCTAssertEqual(hidden, "文档 [邮箱] [数字]")
        XCTAssertEqual(TimeInsightsTitlePrivacy.sanitize(String(repeating: "A", count: 250))?.count, 120)
        XCTAssertNotNil(TimeInsightsRuleInput.make(kind: .app, text: "com.example.app", category: .design))
        XCTAssertNil(TimeInsightsRuleInput.make(kind: .app, text: "example", category: .design))
        XCTAssertNil(TimeInsightsRuleInput.make(kind: .title, text: "\n", category: .design))
        XCTAssertNil(TimeInsightsRuleInput.make(kind: .domain, text: "https://example.com/path", category: .learning))
        XCTAssertNotNil(TimeInsightsRuleInput.make(kind: .domain, text: "Example.COM", category: .learning))
    }

    func testBrowserSamplePrivacyPolicyFailsClosedUntilSeparateConsent() {
        var settings = TimeInsightsSettings()
        let now = at(500)

        func evaluate(_ url: String = "https://www.Example.com/work?private_token=secret#fragment",
                      browser: String = "com.apple.Safari", foreground: String? = "com.apple.Safari",
                      isPrivate: Bool = false, isSensitive: Bool = false, age: TimeInterval = 1,
                      unlocked: Bool = true) -> BrowserTabSample? {
            TimeInsightsBrowserSamplePolicy.accept(
                browserBundleID: browser, foregroundBundleID: foreground,
                rawURL: url, isPrivate: isPrivate, isSensitive: isSensitive,
                capturedAt: now.addingTimeInterval(-age), now: now,
                settings: settings, unlocked: unlocked)
        }

        XCTAssertNil(evaluate(), "默认关闭，不得接收浏览器数据")
        settings.websitesOptIn = true
        XCTAssertNil(evaluate(unlocked: false), "Pro 未解锁，即使保留了 opt-in 也不得接收")
        let safe = evaluate()
        XCTAssertEqual(safe?.domain, "example.com", "不保留 path、query、fragment")
        XCTAssertEqual(safe?.browserBundleID, "com.apple.Safari")
        XCTAssertNil(safe?.title, "标签页标题必须有第三项独立授权，不能沿用窗口标题开关")
        XCTAssertFalse(safe?.isPrivate ?? true)

        settings.windowTitlesOptIn = true
        XCTAssertNil(evaluate()?.title, "即使允许 AX 窗口标题也不可偷偷采集浏览器标签标题")
        XCTAssertNil(evaluate(isPrivate: true))
        XCTAssertNil(evaluate(isSensitive: true))
        XCTAssertNil(evaluate(age: 25), "过期标签不能归给当前前台应用")
        XCTAssertNil(evaluate(age: -1), "未来时间戳也不能被接受")
        XCTAssertNil(evaluate(foreground: "com.apple.dt.Xcode"), "非前台标签必须丢弃")
        XCTAssertNil(evaluate(browser: "com.unverified.browser"), "未知浏览器不能假冒已核验扩展")
        XCTAssertNil(evaluate("file:///Users/test/a"))
        XCTAssertNil(evaluate("https://localhost/test"))
        XCTAssertNil(evaluate("https://accounts.example.com/home"), "账户和单点登录页直接跳过")
        XCTAssertNil(evaluate("https://example.com/login"), "登录路径必须跳过")
        XCTAssertNil(evaluate("https://example.com/oauth2/authorize"), "OAuth 路径必须跳过")
        XCTAssertNil(evaluate("https://user:password@example.com/work"), "URL 凭据不能被处理")

        settings.exclude("com.apple.Safari")
        XCTAssertNil(evaluate(), "排除的应用不能通过浏览器桥重新进入")
        settings.include("com.apple.Safari")
        settings.paused = true
        XCTAssertNil(evaluate(), "暂停时桥接不能采集")
        settings.paused = false
        XCTAssertEqual(evaluate(browser: "com.google.Chrome.beta", foreground: "com.google.Chrome.beta")?.domain,
                       "example.com")
        XCTAssertEqual(UnconnectedBrowserBridge().state, .notConnected,
                       "纯逻辑协议准备好不代表扩展已经接通")
        XCTAssertTrue(TimeInsightsProFeature.websites.isConnected)
    }

    func testChromiumWireDomainRejectsURLsAndPrivateHosts() {
        let settings = TimeInsightsSettings(websitesOptIn: true)
        let chrome = "com.google.Chrome"
        func accept(_ host: String, browser: String = "com.google.Chrome") -> BrowserTabSample? {
            TimeInsightsBrowserSamplePolicy.acceptDomain(
                host, browserBundleID: browser, foregroundBundleID: chrome,
                capturedAt: at(10), now: at(11), settings: settings, unlocked: true
            )
        }
        XCTAssertEqual(accept("www.example.com")?.domain, "example.com")
        for host in ["http://example.com", "example.com/path", "example.com?x=1", "user@example.com",
                     "accounts.example.com", "127.0.0.1", "printer.local", "example..com", "-bad.com"] {
            XCTAssertNil(accept(host), host)
        }
        XCTAssertNil(accept("example.com", browser: "com.apple.Safari"))
        XCTAssertNil(accept("example.com", browser: "com.microsoft.edgemac"))
    }

    func testWebsiteSwitchAndDisconnectPartitionTheSameAppTime() throws {
        var recorder = recorder()
        let chrome = TimeInsightsRecorder.App(bundleID: "com.google.Chrome", name: "Chrome")
        recorder.rules = [TimeInsightsRule(.domain("example.com"), category: .learning)]
        _ = recorder.handle(.foreground(chrome), at: at(0))
        recorder.updateWebsite("example.com", at: at(0.25), observedAt: at(0.5))
        recorder.updateWebsite("example.org", at: at(5), observedAt: at(5.2))
        recorder.updateWebsite(nil, at: at(8), observedAt: at(8.1))
        let snapshot = try XCTUnwrap(recorder.checkpoint)
        let decoded = try JSONDecoder().decode(TimeInsightsRecorder.Open.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(TimeInsightsRecorder.recoverCheckpoint(decoded, now: at(9)).map(\.id),
                       recorder.provisionalSessions(now: at(8.1)).map(\.id))
        let slices = recorder.handle(.foreground(xcode), at: at(10))
        XCTAssertEqual(slices.map(\.duration), [0.25, 4.75, 3, 2])
        XCTAssertEqual(slices.compactMap(\.domain), ["example.com", "example.org"])
        XCTAssertEqual(slices[1].classification, .learning)
        XCTAssertEqual(slices[1].source, .browserBridge)
        XCTAssertEqual(slices[1].privacyFlags, .domainOnly)
        XCTAssertNil(slices[1].windowTitle)
        XCTAssertEqual(slices[3].source, .foreground)

        let range = DateInterval(start: at(1), end: at(7))
        let ranking = TimeInsightsWebsiteUsage.ranking(slices + slices, interval: range)
        XCTAssertEqual(ranking.map(\.active), [4, 2])
        XCTAssertEqual(ranking.map(\.domain), ["example.com", "example.org"])
    }

    func testIdleBackdatingTrimsWebsiteChangesAfterLastInput() {
        var recorder = recorder(idle: 10)
        let edge = TimeInsightsRecorder.App(bundleID: "com.microsoft.edgemac", name: "Edge")
        _ = recorder.handle(.foreground(edge), at: at(0))
        recorder.updateWebsite("example.com", at: at(1), observedAt: at(1))
        recorder.updateWebsite("example.org", at: at(8), observedAt: at(8))
        recorder.updateWebsite(nil, at: at(11), observedAt: at(11))
        let finished = recorder.handle(.idle(10), at: at(14))
        XCTAssertEqual(finished.map(\.duration), [1, 3])
        XCTAssertEqual(finished.compactMap(\.domain), ["example.com"])
        XCTAssertEqual(recorder.segment?.start, at(4))
        XCTAssertNil(recorder.segment?.domain)
        XCTAssertEqual(recorder.provisional(now: at(14))?.source, .idleForeground)
        _ = recorder.handle(.blocked(.locked), at: at(15))
        recorder.updateWebsite("example.net", at: at(16), observedAt: at(16))
        XCTAssertNil(recorder.segment)
    }

    func testBrowserAndPasswordManagerVariantsNeverExposeAccessibilityTitles() {
        for bundleID in ["com.google.Chrome.beta", "com.google.Chrome.dev",
                         "com.microsoft.edgemac.Dev", "org.mozilla.firefoxdeveloperedition",
                         "org.mozilla.nightly", "com.brave.Browser.beta",
                         "com.1password.beta", "com.bitwarden.desktop.beta"] {
            XCTAssertFalse(TimeInsightsTitlePrivacy.allows(bundleID: bundleID), bundleID)
        }
        XCTAssertTrue(TimeInsightsTitlePrivacy.allows(bundleID: "com.apple.dt.Xcode"))
        XCTAssertEqual(TimeInsightsTitlePrivacy.sanitize(
            "设计稿 https://example.com/work?token=secret 联系 a@example.com"),
                       "设计稿 [网址] 联系 [邮箱]")
    }

    func testTitleChangeSplitsSegmentsAndReclassifiesWithoutDoubleCounting() {
        let titleRule = TimeInsightsRule(.titleKeyword("Design"), category: .design)
        var recorder = TimeInsightsRecorder(rules: [titleRule], heartbeatGap: 100_000)
        _ = recorder.handle(.foreground(xcode), at: at(0))
        let before = recorder.updateWindowTitle("Design Notes", at: at(20))
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before[0].duration, 20)
        XCTAssertNil(before[0].windowTitle)
        XCTAssertEqual(recorder.segment?.classification, .design)
        XCTAssertTrue(recorder.updateWindowTitle("Design Notes", at: at(30)).isEmpty)
        let after = recorder.updateWindowTitle(nil, at: at(45))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].duration, 25)
        XCTAssertEqual(after[0].windowTitle, "Design Notes")
        XCTAssertEqual(after[0].classification, .design)
        let last = recorder.flush(at: at(60))
        XCTAssertEqual(last.first?.duration, 15)
        XCTAssertNil(last.first?.windowTitle)
        XCTAssertEqual(last.first?.classification, .development)
        XCTAssertEqual(before[0].duration + after[0].duration + (last.first?.duration ?? 0), 60)
    }

    func testOnlyTheDomainIsKept() {
        XCTAssertEqual(TimeInsightsDomain.sanitize("https://www.Example.com/path/to?q=secret#frag"), "example.com")
        XCTAssertEqual(TimeInsightsDomain.sanitize("http://user:pw@Sub.Site.cn:8080/a"), "sub.site.cn")
        XCTAssertNil(TimeInsightsDomain.sanitize("file:///Users/me/a.txt"))
        XCTAssertNil(TimeInsightsDomain.sanitize("about:blank"))
        XCTAssertNil(TimeInsightsDomain.sanitize("not a url"))
    }

    func testDurationsReadNaturally() {
        XCTAssertEqual(TimeInsightsFormat.duration(30), "不到 1 分")
        XCTAssertEqual(TimeInsightsFormat.duration(45 * 60), "45 分")
        XCTAssertEqual(TimeInsightsFormat.duration(3600), "1 小时")
        XCTAssertEqual(TimeInsightsFormat.duration(3 * 3600 + 12 * 60 + 40), "3 小时 12 分")
        XCTAssertEqual(TimeInsightsFormat.compactDuration(0), "0m")
        XCTAssertEqual(TimeInsightsFormat.compactDuration(30), "<1m")
        XCTAssertEqual(TimeInsightsFormat.compactDuration(45 * 60), "45m")
        XCTAssertEqual(TimeInsightsFormat.compactDuration(3600), "1h")
        XCTAssertEqual(TimeInsightsFormat.compactDuration(3 * 3600 + 12 * 60 + 40), "3h 12m")
        XCTAssertEqual(TimeInsightsFormat.clock(3 * 3600 + 12 * 60), "3:12")
        XCTAssertEqual(TimeInsightsFormat.barFraction(4 * 3600), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TimeInsightsFormat.barFraction(20 * 3600), 1)
    }

    // MARK: 目录接入

    func testTheWidgetSitsNextToTheFocusTimer() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.timeInsights))
        XCTAssertEqual(entry.name, "时间洞察")
        XCTAssertEqual(entry.category, WidgetCatalog.entry(.timer)?.category, "和专注计时同一个分类")
        XCTAssertEqual(WidgetLibraryGroups.rank(.timeInsights), WidgetLibraryGroups.rank(.timer) + 1)
        XCTAssertTrue(entry.selfContained)
        XCTAssertNotNil(WidgetCatalog.make(.timeInsights))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.timeInsights).isEmpty, "设置是全局的，不存在卡片里")
        XCTAssertFalse(ProFeatures.isProKind(.timeInsights), "免费层可用")
        XCTAssertTrue(ProLicenseGate.canAdd(.timeInsights, overrides: [:], unlocked: false))
        XCTAssertNil(WidgetCatalog.openTarget(.timeInsights), "点卡片打开面板")
        XCTAssertTrue(WidgetLibraryGroups.isNew(.timeInsights))
        XCTAssertNotNil(WidgetSearch.keywords["time-insights"])
        XCTAssertEqual(WidgetKind.timeInsights.rawValue, "time-insights")
        let card = try XCTUnwrap(WidgetCatalog.make(.timeInsights))
        XCTAssertEqual(WidgetCatalog.naturalSize(card), CGSize(width: 204, height: 62))
        XCTAssertEqual(WidgetCatalog.verticalHeight(card), 104)
    }
}
