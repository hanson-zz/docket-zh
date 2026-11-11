import Foundation
import XCTest

/// 小熊猫做「状态助手」：文件暂存成功以后怎么回应（排队、叼过去、就地提示、合并、待查看超时）。
final class DesktopPetDirectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let shelf = UUID()
    private let dock = DesktopPetTrack(edge: .bottom, style: .stroll, base: 80, lane: 100...700, trashX: 680)

    private func stored(_ count: Int, ids: [String]? = nil, x: Double = 400, widget: UUID? = nil) -> DesktopPetEvent {
        .fileStored(count: count, widgetID: widget ?? shelf,
                    newItemIDs: ids ?? (0..<count).map { "/tmp/f\($0)" }, at: CGPoint(x: x, y: 60))
    }

    private func context(track: DesktopPetTrack?, settling: Bool = false, petX: Double = 200,
                         sameScreen: Bool = true, now: Date? = nil,
                         recent: DesktopPetErrand? = nil) -> DesktopPetDirectorContext {
        DesktopPetDirectorContext(now: now ?? t0, settling: settling, track: track, petX: petX,
                                  sameScreen: sameScreen, recent: recent)
    }

    func testQueuesWhileNotSettledAndKeepsOnlyTheLatestOfAKind() {
        XCTAssertEqual(DesktopPetDirector.decide(stored(1), context: context(track: dock, settling: true)), .queue)

        var queue = DesktopPetDirector.enqueue(stored(1, ids: ["/a"], x: 300), into: [])
        queue = DesktopPetDirector.enqueue(.welcomeBack(nil), into: queue)
        queue = DesktopPetDirector.enqueue(stored(2, ids: ["/b", "/a"], x: 500), into: queue)
        XCTAssertEqual(queue.count, 2, "同类只留一件")
        XCTAssertEqual(queue.last, .fileStored(count: 3, widgetID: shelf, newItemIDs: ["/b", "/a"],
                                               at: CGPoint(x: 500, y: 60)),
                       "同一张卡片：计数相加，新条目去重，位置用最新的")

        let other = UUID()
        queue = DesktopPetDirector.enqueue(stored(1, ids: ["/c"], widget: other), into: queue)
        XCTAssertEqual(queue.filter { $0.kind == "fileStored" }.count, 1)
        XCTAssertEqual(queue.last, stored(1, ids: ["/c"], widget: other), "换了卡片只留最新那件")

        XCTAssertEqual(DesktopPetDirector.decide(.shelfExpired(count: 1, widgetID: shelf), context: context(track: dock)),
                       .ignore, "到期移出平时不演")
        XCTAssertEqual(DesktopPetDirector.decide(stored(1), context: context(track: nil)), .ignore)
    }

    func testDeliversBesideTheCardOnAWalkableDockOnTheSameScreen() {
        let reaction = DesktopPetDirector.decide(stored(2, x: 400), context: context(track: dock, petX: 200))
        guard case .deliver(let errand, let goal) = reaction else { return XCTFail("同屏程序坞上沿：叼过去") }
        XCTAssertEqual(goal, 400 - DesktopPetAssist.besideGap, "从小熊猫这一侧靠过去，停在卡片旁")
        XCTAssertEqual(errand.count, 2)
        XCTAssertEqual(errand.widgetID, shelf)

        guard case .deliver(_, let fromRight) = DesktopPetDirector.decide(stored(1, x: 400),
                                                                           context: context(track: dock, petX: 650))
        else { return XCTFail() }
        XCTAssertEqual(fromRight, 400 + DesktopPetAssist.besideGap)

        XCTAssertEqual(DesktopPetDirector.beside(card: 110, from: 300, lane: 100...700, scale: 1),
                       110 + DesktopPetAssist.besideGap, "靠近一端时换到另一侧")
    }

    func testNoticesInPlaceOnOtherScreensSideDocksAndEdges() {
        let other = DesktopPetDirector.decide(stored(1), context: context(track: dock, sameScreen: false))
        guard case .notice(let errand, swing: false) = other else { return XCTFail("异屏：就地提示") }
        XCTAssertEqual(errand.count, 1)

        let edges: [(DesktopPetAnchor, Bool)] = [(.bottom, false), (.left, false), (.right, false),
                                                 (.top, true), (.free, false)]
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 800)
        for (anchor, swing) in edges {
            let track = DesktopPetTracks.edge(anchor, visible: visible, length: 56, spot: DesktopPetSpot())
            guard case .notice(_, let swung) = DesktopPetDirector.decide(stored(1), context: context(track: track))
            else { return XCTFail("\(anchor)：就地提示") }
            XCTAssertEqual(swung, swing, "\(anchor)：只有吊着的晃大一下")
        }

        // 侧边程序坞：小熊猫贴在左右边，不是程序坞上沿那条能走的线。
        let side = DesktopPetTrack(edge: .left, style: .side, base: 70, lane: 100...700)
        XCTAssertFalse(DesktopPetDirector.canDeliver(track: side, sameScreen: true))
        guard case .notice = DesktopPetDirector.decide(stored(1), context: context(track: side)) else { return XCTFail() }

        // 就地提示的动作：吊着跳一下（晃大），其余抬头或探头。
        let resting = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(9)), since: t0)
        XCTAssertEqual(DesktopPetBrain.noticed(resting, style: .hang, now: t0).activity, .jump(since: t0))
        XCTAssertEqual(DesktopPetBrain.noticed(resting, style: .side, now: t0).activity,
                       .peek(until: t0.addingTimeInterval(DesktopPetBrain.peekDuration)))
        let sitting = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: t0)
        let looking = DesktopPetBrain.noticed(sitting, style: .stroll, now: t0)
        XCTAssertEqual(DesktopPetBrain.pose(looking, now: t0.addingTimeInterval(0.5), style: .stroll).image,
                       DesktopPetStrip.lookup.imageName(3), "站着的抬头看")
    }

    func testMergesStoresWithinThreeSeconds() {
        guard case .deliver(let first, _) = DesktopPetDirector.decide(stored(2, ids: ["/a", "/b"]),
                                                                      context: context(track: dock))
        else { return XCTFail() }
        let soon = t0.addingTimeInterval(DesktopPetAssist.mergeWindow - 0.5)
        guard case .deliver(let merged, _) = DesktopPetDirector.decide(
            stored(1, ids: ["/c", "/a"], x: 500), context: context(track: dock, now: soon, recent: first))
        else { return XCTFail() }
        XCTAssertEqual(merged.count, 3, "3 秒内合并一趟，计数相加")
        XCTAssertEqual(merged.itemIDs, ["/c", "/a", "/b"])
        XCTAssertEqual(merged.at, CGPoint(x: 500, y: 60))
        XCTAssertEqual(merged.lastAt, soon)

        let late = t0.addingTimeInterval(DesktopPetAssist.mergeWindow + 0.5)
        guard case .deliver(let fresh, _) = DesktopPetDirector.decide(
            stored(1, ids: ["/d"]), context: context(track: dock, now: late, recent: first))
        else { return XCTFail() }
        XCTAssertEqual(fresh.count, 1, "超过 3 秒另起一趟")

        let elsewhere = DesktopPetDirector.merged(count: 1, widgetID: UUID(), itemIDs: ["/e"],
                                                  at: .zero, into: first, now: soon)
        XCTAssertEqual(elsewhere.count, 1, "别的卡片不合并")

        XCTAssertTrue(DesktopPetAssist.storedText(1).contains("1"))
        XCTAssertTrue(DesktopPetAssist.storedText(3).contains("3"))
        XCTAssertNotEqual(DesktopPetAssist.storedText(1), DesktopPetAssist.storedText(3))
    }

    func testReviewWaitsBesideTheCardAndExpires() {
        let errand = DesktopPetErrand(widgetID: shelf, count: 2, itemIDs: ["/a", "/b"], at: .zero, lastAt: t0)
        let review = DesktopPetReview(errand, now: t0)
        XCTAssertEqual(review.until, t0.addingTimeInterval(DesktopPetAssist.reviewDuration))
        XCTAssertEqual(review.itemIDs, ["/a", "/b"])
        XCTAssertFalse(review.expired(at: t0.addingTimeInterval(59)))
        XCTAssertTrue(review.expired(at: t0.addingTimeInterval(60)))

        // 到了卡片旁坐着等，不走开，到点才继续平时的样子。
        let carrying = DesktopPetState(x: 300, activity: .fileDelivery(to: 300), since: t0)
        let waiting = DesktopPetBrain.waitingBeside(carrying, until: review.until, now: t0)
        let later = DesktopPetBrain.step(waiting, dt: 0.1, now: t0.addingTimeInterval(30), lane: 100...700,
                                         userIdle: 0, focusing: false, random: { 0.9 })
        XCTAssertEqual(later.activity, .putDown(until: review.until))
        XCTAssertEqual(later.x, 300)

        // 放下纸团：drop 6 帧约 8fps 播一次，之后停在纸团在脚边那一帧；到点回到平时的样子。
        XCTAssertEqual(DesktopPetBrain.pose(waiting, now: t0).image, DesktopPetStrip.drop.imageName(0))
        XCTAssertEqual(DesktopPetBrain.pose(waiting, now: t0.addingTimeInterval(0.3)).image,
                       DesktopPetStrip.drop.imageName(2))
        XCTAssertEqual(DesktopPetBrain.pose(waiting, now: t0.addingTimeInterval(20)).image,
                       DesktopPetStrip.drop.imageName(5))
        XCTAssertEqual(DesktopPetStrip.drop.frameCount, 6)
        let done = DesktopPetBrain.step(waiting, dt: 0.1, now: review.until, lane: 100...700,
                                        userIdle: 0, focusing: false, random: { 0.5 })
        guard case .idle = done.activity else { return XCTFail("到点继续平时的样子") }
    }

    // MARK: 专注完成

    func testFocusFinishedLooksTowardTheTimerThenCheersOnceAndSits() {
        let timer = UUID()
        let card = CGPoint(x: 600, y: 60)
        // 同屏：朝计时器卡片那边看；异屏或看不见：就地。
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card),
                                                 context: context(track: dock, petX: 200)),
                       .celebrate(widgetID: timer, toward: 600, swing: false))
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card),
                                                 context: context(track: dock, sameScreen: false)),
                       .celebrate(widgetID: timer, toward: nil, swing: false))
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: nil, at: nil), context: context(track: dock)),
                       .celebrate(widgetID: nil, toward: nil, swing: false))
        // 吊着：晃大一下；左右边按纵坐标看。
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 800)
        let top = DesktopPetTracks.edge(.top, visible: visible, length: 56, spot: DesktopPetSpot())
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card), context: context(track: top)),
                       .celebrate(widgetID: timer, toward: 600, swing: true))
        let left = DesktopPetTracks.edge(.left, visible: visible, length: 56, spot: DesktopPetSpot())
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card), context: context(track: left)),
                       .celebrate(widgetID: timer, toward: 60, swing: false))
        // 拖着、落地中：排队，站稳再演；同类只留最新的一件。
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card),
                                                 context: context(track: dock, settling: true)), .queue)
        var queue = DesktopPetDirector.enqueue(.focusFinished(widgetID: timer, at: nil), into: [])
        queue = DesktopPetDirector.enqueue(stored(1), into: queue)
        queue = DesktopPetDirector.enqueue(.focusFinished(widgetID: timer, at: card), into: queue)
        XCTAssertEqual(queue, [stored(1), .focusFinished(widgetID: timer, at: card)])
        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished(widgetID: timer, at: card), context: context(track: nil)),
                       .ignore, "没显示时不管")

        // 动作：转头朝计时器，抬头看一眼，cheer 播一遍，再坐回去等到待查看结束。
        let review = DesktopPetReview(widgetID: timer, text: DesktopPetAssist.focusDoneText, now: t0)
        XCTAssertEqual(review.widgetID, timer)
        XCTAssertEqual(review.text, DesktopPetAssist.focusDoneText)
        XCTAssertTrue(review.itemIDs.isEmpty)
        let sitting = DesktopPetState(x: 300, facingLeft: true, activity: .idle(until: t0.addingTimeInterval(5)), since: t0)
        let party = DesktopPetBrain.celebrate(sitting, toward: 600, until: review.until, now: t0)
        XCTAssertFalse(party.facingLeft, "转向计时器那边")
        XCTAssertEqual(party.activity, .celebrate(since: t0, until: review.until))
        XCTAssertEqual(DesktopPetBrain.pose(party, now: t0.addingTimeInterval(0.5), style: .stroll).image,
                       DesktopPetStrip.lookup.imageName(3), "先抬头看")
        let look = DesktopPetAssist.focusLook
        XCTAssertEqual(DesktopPetBrain.pose(party, now: t0.addingTimeInterval(look + 0.01), style: .stroll).image,
                       DesktopPetStrip.cheer.imageName(0), "再欢呼")
        XCTAssertEqual(DesktopPetBrain.pose(party, now: t0.addingTimeInterval(look + DesktopPetAssist.cheerOnce - 0.01),
                                            style: .stroll).image,
                       DesktopPetStrip.cheer.imageName(5), "cheer 只播一遍")
        XCTAssertEqual(DesktopPetAssist.cheerOnce, 6.0 / 8, accuracy: 0.0001)
        let mid = DesktopPetBrain.step(party, dt: 0.1, now: t0.addingTimeInterval(0.5), lane: 100...700,
                                       userIdle: 999, focusing: false, random: { 0.5 })
        XCTAssertEqual(mid.activity, party.activity, "演完再说，不被睡觉打断")
        let after = DesktopPetBrain.step(party, dt: 0.1, now: t0.addingTimeInterval(DesktopPetAssist.celebrateDuration + 0.01),
                                         lane: 100...700, userIdle: 0, focusing: false, random: { 0.5 })
        XCTAssertEqual(after.activity, .idle(until: review.until), "坐回去等着")
        let curled = DesktopPetBrain.step(party, dt: 0.1, now: t0.addingTimeInterval(DesktopPetAssist.celebrateDuration + 0.01),
                                          lane: 100...700, userIdle: 0, focusing: false, style: .curl, random: { 0.5 })
        guard case .curl = curled.activity else { return XCTFail("屏幕下边缘的趴回去") }
        // 吊着欢呼时帧速加快、晃大一点。
        let hanging = DesktopPetBrain.pose(party, now: t0.addingTimeInterval(1), style: .hang)
        XCTAssertTrue(hanging.image.hasPrefix("pet-sprite-hang-"))
        // 拖着时不打断。
        let dragged = DesktopPetState(x: 300, activity: .dragged(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.celebrate(dragged, toward: 600, until: review.until, now: t0), dragged)

        // 计时器卡片：文件夹里的也算，取第一张。
        let clock = WidgetInstance(kind: .clock, config: WidgetConfig())
        let first = WidgetInstance(kind: .timer, config: WidgetConfig())
        let second = WidgetInstance(kind: .timer, config: WidgetConfig())
        XCTAssertEqual(DesktopPetDirector.timerWidget(in: [clock, first, second]), first.id)
        XCTAssertNil(DesktopPetDirector.timerWidget(in: [clock]))
    }

    // MARK: 离开回来

    func testAwayEventsMergeIntoOneWelcomeByPriority() {
        var log = DesktopPetAwayLog()
        XCTAssertFalse(log.hold(stored(1)), "没离开：照常演")
        XCTAssertNil(log.handle(.idle(DesktopPetAssist.awayAfter - 1), at: t0))
        XCTAssertFalse(log.isAway)
        XCTAssertNil(log.handle(.idle(DesktopPetAssist.awayAfter), at: t0))
        XCTAssertTrue(log.isAway, "空闲满 5 分钟算离开")

        let timer = UUID()
        XCTAssertTrue(log.hold(stored(2, ids: ["/a", "/b"])), "离开时先记下不演")
        XCTAssertTrue(log.hold(.shelfExpired(count: 3, widgetID: shelf)))
        XCTAssertTrue(log.hold(.focusFinished(widgetID: timer, at: nil)))
        XCTAssertTrue(log.hold(stored(1, ids: ["/c"])))
        XCTAssertEqual(log.missed.count, 4)

        // 还没动：不回来。
        XCTAssertNil(log.handle(.idle(DesktopPetAssist.awayAfter + 60), at: t0.addingTimeInterval(60)))
        // 动了一下：回来，合并成一条，专注结束最重要。
        let back = log.handle(.idle(0), at: t0.addingTimeInterval(120))
        XCTAssertEqual(back, .welcomeBack(DesktopPetWelcome(text: DesktopPetWelcome.focusText, widgetID: timer)))
        XCTAssertFalse(log.isAway)
        XCTAssertTrue(log.missed.isEmpty)

        // 优先级：专注结束 > 新暂存 > 到期移出；同一类计数相加，新条目最新的在前。
        let stores = DesktopPetWelcome.summary([.filesExpired(count: 4, widgetID: shelf),
                                                .filesStored(count: 2, widgetID: shelf, itemIDs: ["/a", "/b"]),
                                                .filesStored(count: 1, widgetID: shelf, itemIDs: ["/c", "/a"])])
        XCTAssertEqual(stores, DesktopPetWelcome(text: DesktopPetWelcome.storedText(3), widgetID: shelf,
                                                 itemIDs: ["/c", "/a", "/b"]))
        let expired = DesktopPetWelcome.summary([.filesExpired(count: 1, widgetID: shelf),
                                                 .filesExpired(count: 2, widgetID: shelf)])
        XCTAssertEqual(expired, DesktopPetWelcome(text: DesktopPetWelcome.expiredText(3), widgetID: shelf))
        XCTAssertNil(DesktopPetWelcome.summary([]))
        XCTAssertNotEqual(DesktopPetWelcome.storedText(1), DesktopPetWelcome.storedText(2))
        XCTAssertTrue(DesktopPetWelcome.storedText(2).contains("2"))
        XCTAssertTrue(DesktopPetWelcome.expiredText(5).contains("5"))
        XCTAssertGreaterThan(DesktopPetMissed.focusFinished(widgetID: nil).priority,
                             DesktopPetMissed.filesStored(count: 1, widgetID: shelf, itemIDs: []).priority)
    }

    func testAwayByLockAndQuietReturns() {
        // 锁屏一来就算离开；满 5 分钟回来、什么都没发生：只探头，不说话。
        var log = DesktopPetAwayLog()
        XCTAssertNil(log.handle(.blocked(.locked), at: t0))
        XCTAssertTrue(log.isAway)
        XCTAssertNil(log.handle(.idle(0), at: t0.addingTimeInterval(400)), "锁着时空闲读数不作数")
        XCTAssertEqual(log.handle(.unblocked(.locked), at: t0.addingTimeInterval(DesktopPetAssist.awayAfter)),
                       .welcomeBack(nil))

        // 锁屏一小会儿、什么都没发生：不算离开一阵。
        XCTAssertNil(log.handle(.blocked(.locked), at: t0))
        XCTAssertNil(log.handle(.unblocked(.locked), at: t0.addingTimeInterval(60)))

        // 锁屏一小会儿但专注结束了：照样说一句。
        XCTAssertNil(log.handle(.blocked(.displayOff), at: t0))
        XCTAssertTrue(log.hold(.focusFinished(widgetID: nil, at: nil)))
        XCTAssertEqual(log.handle(.unblocked(.displayOff), at: t0.addingTimeInterval(60)),
                       .welcomeBack(DesktopPetWelcome(text: DesktopPetWelcome.focusText, widgetID: nil)))

        // 专注计时走着时不碰键盘鼠标不算离开（看书、想事情），锁屏照样算。
        XCTAssertNil(log.handle(.idle(DesktopPetAssist.awayAfter * 2), at: t0, focusing: true))
        XCTAssertFalse(log.isAway)
        XCTAssertNil(log.handle(.blocked(.locked), at: t0, focusing: true))
        XCTAssertTrue(log.isAway)
        XCTAssertFalse(log.hold(.welcomeBack(nil)), "回来那件本身不记")

        // 回来：拖着时排队，站稳了从睡着抬头探看；吊着的晃一下。
        let summary = DesktopPetWelcome(text: DesktopPetWelcome.focusText, widgetID: nil)
        XCTAssertEqual(DesktopPetDirector.decide(.welcomeBack(summary), context: context(track: dock, settling: true)),
                       .queue)
        XCTAssertEqual(DesktopPetDirector.decide(.welcomeBack(summary), context: context(track: dock)),
                       .welcome(summary, swing: false))
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 800)
        let top = DesktopPetTracks.edge(.top, visible: visible, length: 56, spot: DesktopPetSpot())
        XCTAssertEqual(DesktopPetDirector.decide(.welcomeBack(nil), context: context(track: top)),
                       .welcome(nil, swing: true))
        let asleep = DesktopPetState(x: 300, activity: .sleep(since: t0), since: t0)
        let woke = DesktopPetBrain.wokeUp(asleep, style: .stroll, now: t0.addingTimeInterval(600))
        XCTAssertEqual(woke.activity, .peek(until: t0.addingTimeInterval(600 + DesktopPetBrain.peekDuration)))
        XCTAssertEqual(DesktopPetBrain.pose(woke, now: t0.addingTimeInterval(601), style: .stroll).image,
                       DesktopPetStrip.lookup.imageName(3), "抬头探看")
        let still = DesktopPetBrain.step(woke, dt: 0.1, now: t0.addingTimeInterval(600.5), lane: 100...700,
                                         userIdle: 0, focusing: false, random: { 0.5 })
        guard case .peek = still.activity else { return XCTFail("探看完再说") }
    }

    // MARK: 吊着打盹

    func testHangingDozesAfterTwentyQuietSeconds() {
        XCTAssertEqual(DesktopPetHang.dozeAfter, 20)
        let hanging = DesktopPetBrain.placed(at: 300, style: .hang, now: t0)
        let awake = DesktopPetBrain.step(hanging, dt: 0.1, now: t0, lane: 100...700, userIdle: 0, focusing: false,
                                         style: .hang, hangQuiet: DesktopPetHang.dozeAfter - 1, random: { 0.5 })
        if case .sleep = awake.activity { XCTFail("19 秒还醒着") }
        let dozing = DesktopPetBrain.step(hanging, dt: 0.1, now: t0, lane: 100...700, userIdle: 0, focusing: false,
                                          style: .hang, hangQuiet: DesktopPetHang.dozeAfter, random: { 0.5 })
        guard case .sleep = dozing.activity else { return XCTFail("吊着没人理 20 秒打盹") }
        XCTAssertTrue(DesktopPetBrain.pose(dozing, now: t0.addingTimeInterval(4), style: .hang).image
            .hasPrefix("pet-sprite-hang-sleep-"), "闭眼呼吸")
        XCTAssertEqual(DesktopPetBrain.step(dozing, dt: 0.1, now: t0.addingTimeInterval(30), lane: 100...700,
                                            userIdle: 0, focusing: false, style: .hang,
                                            hangQuiet: 30, random: { 0.5 }).activity,
                       dozing.activity, "接着睡")
        // 鼠标靠近（没人理的时间清零）就醒。
        let woke = DesktopPetBrain.step(dozing, dt: 0.1, now: t0.addingTimeInterval(31), lane: 100...700,
                                        userIdle: 0, focusing: false, style: .hang, attention: 320,
                                        hangQuiet: 0, random: { 0.5 })
        if case .sleep = woke.activity { XCTFail("有人理就醒") }
        // 只管吊着的：程序坞上沿不因为没人理就睡。
        let strolling = DesktopPetBrain.initial(lane: 100...700, now: t0)
        let fine = DesktopPetBrain.step(strolling, dt: 0.1, now: t0, lane: 100...700, userIdle: 0, focusing: false,
                                        style: .stroll, hangQuiet: 999, random: { 0.5 })
        if case .sleep = fine.activity { XCTFail("程序坞上沿不打盹") }
        // 专注陪着时照样坐着。
        let focused = DesktopPetBrain.step(hanging, dt: 0.1, now: t0, lane: 100...700, userIdle: 0, focusing: true,
                                           style: .hang, hangQuiet: 999, random: { 0.5 })
        XCTAssertEqual(focused.activity, .sit)
    }
}
