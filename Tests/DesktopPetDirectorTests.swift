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
        queue = DesktopPetDirector.enqueue(.welcomeBack, into: queue)
        queue = DesktopPetDirector.enqueue(stored(2, ids: ["/b", "/a"], x: 500), into: queue)
        XCTAssertEqual(queue.count, 2, "同类只留一件")
        XCTAssertEqual(queue.last, .fileStored(count: 3, widgetID: shelf, newItemIDs: ["/b", "/a"],
                                               at: CGPoint(x: 500, y: 60)),
                       "同一张卡片：计数相加，新条目去重，位置用最新的")

        let other = UUID()
        queue = DesktopPetDirector.enqueue(stored(1, ids: ["/c"], widget: other), into: queue)
        XCTAssertEqual(queue.filter { $0.kind == "fileStored" }.count, 1)
        XCTAssertEqual(queue.last, stored(1, ids: ["/c"], widget: other), "换了卡片只留最新那件")

        XCTAssertEqual(DesktopPetDirector.decide(.focusFinished, context: context(track: dock)), .ignore)
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
        XCTAssertEqual(later.activity, .idle(until: review.until))
        XCTAssertEqual(later.x, 300)
    }
}
