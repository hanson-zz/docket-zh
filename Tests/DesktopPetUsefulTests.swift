import Foundation
import XCTest

/// 让小熊猫「有用」的三件事：拖文件到身上暂存、连续打字提醒活动、下载完成提示。
final class DesktopPetUsefulTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let dock = DesktopPetTrack(edge: .bottom, style: .stroll, base: 80, lane: 100...700, trashX: 680)
    private let side = DesktopPetTrack(edge: .left, style: .side, base: 70, lane: 100...700)

    private func context(track: DesktopPetTrack?, settling: Bool = false, petX: Double = 200,
                         now: Date? = nil, downloads: DesktopPetDownloads? = nil) -> DesktopPetDirectorContext {
        DesktopPetDirectorContext(now: now ?? t0, settling: settling, track: track, petX: petX,
                                  sameScreen: true, recentDownloads: downloads)
    }

    private var hang: DesktopPetTrack? {
        DesktopPetTracks.edge(.top, visible: CGRect(x: 0, y: 80, width: 1440, height: 800), length: 56,
                              spot: DesktopPetSpot())
    }

    // MARK: 设置

    func testSettingsDefaultsAndLegacyFiles() throws {
        let fresh = DesktopPetSettings()
        XCTAssertFalse(fresh.stretchReminder, "活动提醒默认关")
        XCTAssertTrue(fresh.downloadNotice, "下载完成提示默认开")

        let legacy = try JSONDecoder().decode(DesktopPetSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertFalse(legacy.stretchReminder)
        XCTAssertTrue(legacy.downloadNotice)

        let changed = DesktopPetSettings(enabled: true, stretchReminder: true, downloadNotice: false)
        let round = try JSONDecoder().decode(DesktopPetSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(round, changed)
    }

    // MARK: 拖文件到身上

    func testDropsGoToTheFirstShownFileShelf() {
        let clock = WidgetInstance(kind: .clock, config: WidgetConfig())
        var hidden = WidgetInstance(kind: .fileShelf, config: WidgetConfig())
        hidden.config.set(WidgetVisibility.modeKey, .string(WidgetVisibilityMode.hidden.rawValue))
        let shelf = WidgetInstance(kind: .fileShelf, config: WidgetConfig())
        XCTAssertEqual(DesktopPetDirector.shelfWidget(in: [clock, hidden, shelf])?.id, shelf.id, "隐藏的卡片不算")
        XCTAssertNil(DesktopPetDirector.shelfWidget(in: [clock, hidden]), "没有文件暂存：不接")
        XCTAssertNil(DesktopPetDirector.shelfWidget(in: []))
        XCTAssertFalse(DesktopPetAssist.needsShelfText.isEmpty)
    }

    func testLooksUpWhileFilesHoverAndLiesBackWhenTheyLeave() {
        let idle = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(5)), since: t0)
        let now = t0.addingTimeInterval(1)
        let waiting = DesktopPetBrain.expecting(idle, now: now)
        XCTAssertEqual(waiting.activity, .peek(until: now.addingTimeInterval(DesktopPetAssist.expectHold)))
        XCTAssertEqual(waiting.since, now)

        let later = now.addingTimeInterval(2)
        let again = DesktopPetBrain.expecting(waiting, now: later)
        XCTAssertEqual(again.since, now, "已经抬着头：不从头再抬一次")

        let back = DesktopPetBrain.stopExpecting(again, now: later)
        XCTAssertEqual(back.activity, .peek(until: later.addingTimeInterval(0.4)), "移开了：快点趴回去")
        XCTAssertEqual(DesktopPetBrain.stopExpecting(idle, now: later), idle, "没在等：不动")

        let held = DesktopPetState(x: 300, activity: .dragged(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.expecting(held, now: now), held, "拖着时不理会")
        let carrying = DesktopPetState(x: 300, activity: .fileDelivery(to: 500), since: t0)
        XCTAssertEqual(DesktopPetBrain.expecting(carrying, now: now), carrying, "叼着纸团时不打断")
    }

    // MARK: 活动提醒

    func testRemindsAfterFiftyMinutesOfTypingThenWaitsAnotherFifty() {
        var clock = DesktopPetStretchClock()
        XCTAssertFalse(clock.tick(now: t0, keyIdle: 1, focusing: false))
        var fired: [Int] = []
        for minute in 1...100 where clock.tick(now: t0.addingTimeInterval(Double(minute) * 60), keyIdle: 20,
                                                focusing: false) {
            fired.append(minute)
        }
        XCTAssertEqual(fired, [50, 100], "满 50 分钟提醒一次，之后 50 分钟内不再提醒")
    }

    func testAPauseOfFiveMinutesOrAGapRestartsTheCount() {
        var clock = DesktopPetStretchClock()
        for minute in 0...40 { XCTAssertFalse(clock.tick(now: t0.addingTimeInterval(Double(minute) * 60), keyIdle: 10,
                                                         focusing: false)) }
        // 停下 5 分钟：不算连续了。
        XCTAssertFalse(clock.tick(now: t0.addingTimeInterval(41 * 60), keyIdle: DesktopPetAssist.stretchBreak,
                                  focusing: false))
        XCTAssertNil(clock.activeSince)
        var fired: [Int] = []
        for minute in 42...95 where clock.tick(now: t0.addingTimeInterval(Double(minute) * 60), keyIdle: 0,
                                               focusing: false) {
            fired.append(minute)
        }
        XCTAssertEqual(fired, [92], "从回来接着打字那一刻重新算 50 分钟")

        // 两次查看隔太久（睡眠、卡住）：当中断。
        var gap = DesktopPetStretchClock()
        XCTAssertFalse(gap.tick(now: t0, keyIdle: 0, focusing: false))
        XCTAssertFalse(gap.tick(now: t0.addingTimeInterval(3600), keyIdle: 1, focusing: false))

        // 离开电脑由外面重置。
        var away = DesktopPetStretchClock()
        XCTAssertFalse(away.tick(now: t0, keyIdle: 0, focusing: false))
        away.reset()
        XCTAssertNil(away.activeSince)
    }

    func testNoRemindersDuringFocusAndCountingStartsAfterIt() {
        var clock = DesktopPetStretchClock()
        for minute in 0...60 {
            XCTAssertFalse(clock.tick(now: t0.addingTimeInterval(Double(minute) * 60), keyIdle: 5, focusing: true),
                           "专注计时进行中不提醒")
        }
        var fired: [Int] = []
        for minute in 61...120 where clock.tick(now: t0.addingTimeInterval(Double(minute) * 60), keyIdle: 0,
                                                focusing: false) {
            fired.append(minute)
        }
        XCTAssertEqual(fired, [111], "专注结束后从头算")
    }

    func testStretchReactionAndPose() {
        XCTAssertEqual(DesktopPetDirector.decide(.stretchReminder, context: context(track: dock)), .stretch(swing: false))
        XCTAssertEqual(DesktopPetDirector.decide(.stretchReminder, context: context(track: dock, settling: true)), .queue)
        XCTAssertEqual(DesktopPetDirector.decide(.stretchReminder, context: context(track: hang)), .stretch(swing: true))
        XCTAssertEqual(DesktopPetDirector.decide(.stretchReminder, context: context(track: nil)), .ignore)

        let idle = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(5)), since: t0)
        XCTAssertEqual(DesktopPetBrain.stretched(idle, style: .stroll, now: t0).activity, .stretch(since: t0))
        XCTAssertEqual(DesktopPetBrain.stretched(idle, style: .hang, now: t0).activity, .jump(since: t0),
                       "吊着不伸懒腰，晃一下")
        let held = DesktopPetState(x: 300, activity: .dragged(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.stretched(held, style: .stroll, now: t0), held)
        XCTAssertFalse(DesktopPetAssist.stretchText.isEmpty)
    }

    // MARK: 下载完成

    func testDownloadWatchReportsNewFilesOnceTheirSizeSettles() {
        var watch = DesktopPetDownloadWatch()
        XCTAssertEqual(watch.observe(["old.pdf": 10, ".DS_Store": 1], now: t0), [], "第一次看到的都是老文件")
        XCTAssertTrue(watch.primed)

        // 浏览器先写临时文件：不算。
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip.crdownload": 5, "b.download": 0, "c.part": 3,
                                      ".hidden": 9], now: t0.addingTimeInterval(1)), [])
        XCTAssertFalse(watch.waiting)

        // 下完改成真名：等大小 2 秒不变。
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100], now: t0.addingTimeInterval(2)), [])
        XCTAssertTrue(watch.waiting)
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100], now: t0.addingTimeInterval(3)), [])
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100], now: t0.addingTimeInterval(4)), ["a.zip"])
        XCTAssertFalse(watch.waiting)
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100], now: t0.addingTimeInterval(9)), [], "只报一次")

        // 直接写真名、还在变大：大小变了重新等。
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100, "big.iso": 1], now: t0.addingTimeInterval(10)), [])
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100, "big.iso": 2], now: t0.addingTimeInterval(12.5)), [])
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100, "big.iso": 2], now: t0.addingTimeInterval(14)), [])
        XCTAssertEqual(watch.observe(["old.pdf": 10, "a.zip": 100, "big.iso": 2], now: t0.addingTimeInterval(14.5)),
                       ["big.iso"])

        // 等着的时候被删了：不报。删掉的老文件再出现算新的。
        XCTAssertEqual(watch.observe(["a.zip": 100, "gone.txt": 1], now: t0.addingTimeInterval(20)), [])
        XCTAssertEqual(watch.observe(["a.zip": 100, "old.pdf": 10], now: t0.addingTimeInterval(21)), [])
        XCTAssertEqual(watch.observe(["a.zip": 100, "old.pdf": 10], now: t0.addingTimeInterval(23)), ["old.pdf"])
        XCTAssertFalse(watch.waiting)

        XCTAssertTrue(DesktopPetDownloadWatch.ignored("x.CRDOWNLOAD"))
        XCTAssertFalse(DesktopPetDownloadWatch.ignored("report.pdf"))
    }

    func testDownloadTextsMergeAndShortenLongNames() {
        let one = DesktopPetAssist.downloadedText(["/Users/me/Downloads/report.pdf"])
        XCTAssertTrue(one.contains("report.pdf"))
        let two = DesktopPetAssist.downloadedText(["/d/a", "/d/b"])
        XCTAssertTrue(two.contains("2"))
        XCTAssertNotEqual(one, two)

        XCTAssertEqual(DesktopPetAssist.shortName("short.pdf"), "short.pdf")
        let long = DesktopPetAssist.shortName("a-very-long-file-name-from-the-internet-2026-final.pdf")
        XCTAssertEqual(long.count, DesktopPetAssist.downloadNameLimit)
        XCTAssertTrue(long.contains("…"))
        XCTAssertTrue(long.hasSuffix(".pdf"), "留住扩展名")
        XCTAssertTrue(long.hasPrefix("a-very"))

        let first = DesktopPetDownloads.merged(["/d/a"], into: nil, now: t0)
        let merged = DesktopPetDownloads.merged(["/d/b", "/d/a"], into: first, now: t0.addingTimeInterval(2))
        XCTAssertEqual(merged.paths, ["/d/a", "/d/b"], "3 秒内合并、去重")
        let apart = DesktopPetDownloads.merged(["/d/c"], into: merged, now: t0.addingTimeInterval(6))
        XCTAssertEqual(apart.paths, ["/d/c"], "隔久了另起一批")
    }

    func testDownloadReactions() {
        let event = DesktopPetEvent.downloadFinished(paths: ["/d/a"])
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: dock, settling: true)), .queue)
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: nil)), .ignore)

        // 程序坞上沿：朝中间跑一小段放下。
        let batch = DesktopPetDownloads(paths: ["/d/a"], lastAt: t0)
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: dock, petX: 200)),
                       .fetch(batch, to: 200 + DesktopPetAssist.fetchRun, swing: false))
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: dock, petX: 650)),
                       .fetch(batch, to: 650 - DesktopPetAssist.fetchRun, swing: false))
        XCTAssertEqual(DesktopPetDirector.fetchSpot(from: 120, lane: 100...150, scale: 1), 150, "夹在可走范围里")

        // 贴边、吊着：就地。
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: side)), .fetch(batch, to: nil, swing: false))
        XCTAssertEqual(DesktopPetDirector.decide(event, context: context(track: hang)), .fetch(batch, to: nil, swing: true))

        // 3 秒内又下好一个：并成一批。
        let recent = DesktopPetDownloads(paths: ["/d/x"], lastAt: t0)
        guard case .fetch(let merged, _, _) = DesktopPetDirector.decide(
            event, context: context(track: dock, now: t0.addingTimeInterval(1), downloads: recent))
        else { return XCTFail() }
        XCTAssertEqual(merged.paths, ["/d/x", "/d/a"])
        XCTAssertTrue(merged.text.contains("2"))

        // 没站稳时排队：下载的路径并在一起。
        var queue = DesktopPetDirector.enqueue(.downloadFinished(paths: ["/d/a"]), into: [])
        queue = DesktopPetDirector.enqueue(.stretchReminder, into: queue)
        queue = DesktopPetDirector.enqueue(.downloadFinished(paths: ["/d/b", "/d/a"]), into: queue)
        XCTAssertEqual(queue, [.stretchReminder, .downloadFinished(paths: ["/d/a", "/d/b"])])
    }

    func testDownloadsWhileAwayJoinTheWelcomeAfterNewShelfFiles() {
        let shelf = UUID()
        var log = DesktopPetAwayLog()
        XCTAssertFalse(log.hold(.downloadFinished(paths: ["/d/a"])), "没离开：照常演")

        XCTAssertNil(log.handle(.blocked(.locked), at: t0))
        XCTAssertTrue(log.hold(.downloadFinished(paths: ["/d/a"])))
        XCTAssertTrue(log.hold(.downloadFinished(paths: ["/d/b"])))
        XCTAssertTrue(log.hold(.shelfExpired(count: 2, widgetID: shelf)))
        XCTAssertTrue(log.hold(.stretchReminder), "人不在：不提醒")
        XCTAssertEqual(log.missed.count, 3, "活动提醒不记")
        XCTAssertEqual(log.handle(.unblocked(.locked), at: t0.addingTimeInterval(60)),
                       .welcomeBack(DesktopPetWelcome(text: DesktopPetAssist.downloadedText(["/d/a", "/d/b"]),
                                                      widgetID: nil, revealPaths: ["/d/a", "/d/b"])),
                       "下载好了排在到期移出前面，单击在访达中显示")

        XCTAssertNil(log.handle(.blocked(.locked), at: t0))
        XCTAssertTrue(log.hold(.downloadFinished(paths: ["/d/c"])))
        XCTAssertTrue(log.hold(.fileStored(count: 1, widgetID: shelf, newItemIDs: ["/s/1"], at: .zero)))
        XCTAssertEqual(log.handle(.unblocked(.locked), at: t0.addingTimeInterval(60)),
                       .welcomeBack(DesktopPetWelcome(text: DesktopPetWelcome.storedText(1), widgetID: shelf,
                                                      itemIDs: ["/s/1"])),
                       "新暂存排在下载前面")

        XCTAssertGreaterThan(DesktopPetMissed.filesStored(count: 1, widgetID: shelf, itemIDs: []).priority,
                             DesktopPetMissed.downloaded(paths: []).priority)
        XCTAssertGreaterThan(DesktopPetMissed.downloaded(paths: []).priority,
                             DesktopPetMissed.filesExpired(count: 1, widgetID: shelf).priority)
    }
}
