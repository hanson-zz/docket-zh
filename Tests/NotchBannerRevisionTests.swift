import XCTest

/// 消息灵动岛：微信连着来消息时第二条起是原横幅就地换字（标识不变），要认成新的一条；
/// 同样的字再报一次不弹，空壳填上字顶替刚弹的那条，300ms 里又换字先等一下（防抖）。
final class NotchBannerRevisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let bannerID = "6A1F2C3D-0000-4000-8000-00000000BEEF"

    private func window(_ banners: [NotchBannerNode]) -> NotchBannerNode {
        NotchBannerNode(role: "AXWindow", subrole: "AXSystemDialog", title: "Notification Center", children: [
            NotchBannerNode(role: "AXGroup", subrole: "AXHostingView", children: [
                NotchBannerNode(role: "AXGroup", children: [
                    NotchBannerNode(role: "AXScrollArea", identifier: "AXNotificationListItems", children: [
                        NotchBannerNode(role: "AXGroup", children: banners),
                    ]),
                ]),
            ]),
        ])
    }

    private func text(_ id: String, _ value: String) -> NotchBannerNode {
        NotchBannerNode(role: "AXStaticText", identifier: id, value: value)
    }

    private func wechatBanner(title: String, body: String?) -> NotchBannerNode {
        var children = [text("header", "微信"), text("title", title)]
        if let body { children.append(text("body", body)) }
        return NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: bannerID,
                               children: children)
    }

    private func incoming(title: String = "王姐", body: String?) -> NotchIncoming? {
        NotchBannerParser.incoming(in: window([wechatBanner(title: title, body: body)]),
                                   enabled: NotchMessageApp.allCases).first
    }

    private func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    // MARK: 去重键

    func testInPlaceUpdateGetsANewKey() throws {
        let first = try XCTUnwrap(incoming(body: "在吗"))
        let second = try XCTUnwrap(incoming(body: "今晚七点到店里对一下货"))
        XCTAssertEqual(first.bannerID, bannerID)
        XCTAssertEqual(second.bannerID, bannerID, "就地换字，标识不变")
        XCTAssertNotEqual(first.key, second.key, "以前只按标识认，第二条被吞掉")
        var dedupe = NotchMessageDeduper()
        XCTAssertTrue(dedupe.isNew(first.key, now: now))
        XCTAssertFalse(dedupe.isNew(first.key, now: at(0.5)), "同一条排版变化又报一次")
        XCTAssertTrue(dedupe.isNew(second.key, now: at(3)), "换了字的算新的一条")
        XCTAssertFalse(dedupe.isNew(second.key, now: at(3.4)))
    }

    func testKeyIsAppSenderAndContent() {
        XCTAssertEqual(NotchIncoming.key(app: .wechat, sender: "王姐", preview: "在吗", bannerID: "X"),
                       "id:X|wechat|王姐|在吗")
        XCTAssertEqual(NotchIncoming.key(app: .wechat, sender: "王姐", preview: "在吗", bannerID: nil),
                       "text:wechat|王姐|在吗")
        XCTAssertEqual(NotchIncoming.key(app: .wechat, sender: "王姐", preview: "在吗", bannerID: ""),
                       "text:wechat|王姐|在吗", "空标识当没有")
        XCTAssertNotEqual(NotchIncoming.key(app: .wechat, sender: "王姐", preview: "在吗", bannerID: "X"),
                          NotchIncoming.key(app: .wechat, sender: "李哥", preview: "在吗", bannerID: "X"),
                          "换了人的同一句话也是新的")
    }

    func testRevisionKeyFollowsContent() {
        func banner(_ body: String, id: String?) -> NotchBanner {
            var b = NotchBanner()
            b.identifier = id
            b.header = "微信"
            b.title = "王姐"
            b.body = body
            return b
        }
        let a = NotchBannerParser.revisionKey(banner("在吗", id: "X"))
        XCTAssertEqual(a, NotchBannerParser.revisionKey(banner("在吗", id: "X")))
        XCTAssertNotEqual(a, NotchBannerParser.revisionKey(banner("好的", id: "X")))
        XCTAssertTrue(a.hasPrefix("id:X#"))
        XCTAssertEqual(NotchBannerParser.revisionKey(banner("在吗", id: nil)),
                       NotchBannerParser.identityKey(banner("在吗", id: nil)), "没有标识时和原来一样")
        XCTAssertEqual(NotchBannerParser.identityKey(banner("好的", id: "X")), "id:X", "诊断里认横幅的键不变")
    }

    // MARK: 就地更新的判断

    func testUnseenBannerIsFresh() throws {
        let revisions = NotchBannerRevisions()
        XCTAssertEqual(revisions.decide(try XCTUnwrap(incoming(body: "在吗")), now: now), .fresh)
    }

    func testSameContentIsUnchanged() throws {
        var revisions = NotchBannerRevisions()
        let first = try XCTUnwrap(incoming(body: "在吗"))
        revisions.record(first, messageID: UUID(), now: now)
        XCTAssertEqual(revisions.decide(first, now: at(0.1)), .unchanged)
        XCTAssertEqual(revisions.decide(first, now: at(4)), .unchanged)
    }

    func testNewMessageInSameBannerIsFresh() throws {
        var revisions = NotchBannerRevisions()
        revisions.record(try XCTUnwrap(incoming(body: "在吗")), messageID: UUID(), now: now)
        let second = try XCTUnwrap(incoming(body: "今晚七点到店里对一下货"))
        XCTAssertEqual(revisions.decide(second, now: at(2)), .updated)
        revisions.record(second, messageID: UUID(), now: at(2))
        let third = try XCTUnwrap(incoming(body: "带上样品"))
        XCTAssertEqual(revisions.decide(third, now: at(2.5)), .updated, "第三条也认")
        revisions.record(third, messageID: UUID(), now: at(2.5))
        XCTAssertEqual(revisions.decide(try XCTUnwrap(incoming(body: "在吗")), now: at(4)), .updated,
                       "又发了前面那句话：横幅的字换过，照样弹")
    }

    func testChangeWithinThrottleSettles() throws {
        var revisions = NotchBannerRevisions()
        revisions.record(try XCTUnwrap(incoming(body: "在吗")), messageID: UUID(), now: now)
        let quick = try XCTUnwrap(incoming(body: "今晚"))
        guard case .settle(let after) = revisions.decide(quick, now: at(0.1)) else {
            return XCTFail("300ms 里又换字，先等一下")
        }
        XCTAssertEqual(after, NotchBannerRevisions.throttle - 0.1, accuracy: 0.001)
        XCTAssertEqual(revisions.decide(quick, now: at(NotchBannerRevisions.throttle + 0.01)), .updated, "等够了再认")
    }

    func testShellFilledRefinesTheSameMessage() throws {
        var revisions = NotchBannerRevisions()
        // 横幅刚出现只有发件人，内容随后才填上。
        let shell = NotchIncoming(app: .wechat, sender: "王姐", preview: nil,
                                  key: NotchIncoming.key(app: .wechat, sender: "王姐", preview: nil, bannerID: bannerID),
                                  bannerID: bannerID)
        let id = UUID()
        revisions.record(shell, messageID: id, now: now)
        let filled = try XCTUnwrap(incoming(body: "在吗"))
        XCTAssertEqual(revisions.decide(filled, now: at(0.6)), .refine(id), "顶替刚弹的那条，不多弹一条")
        XCTAssertEqual(revisions.decide(filled, now: at(NotchBannerRevisions.fillWindow + 1)), .updated,
                       "过了填字的时限算新的一条")
        let other = try XCTUnwrap(incoming(title: "李哥", body: "在吗"))
        XCTAssertEqual(revisions.decide(other, now: at(0.6)), .updated, "换了人不算填字")
    }

    func testShellWithoutShownMessageIsFresh() throws {
        var revisions = NotchBannerRevisions()
        let shell = NotchIncoming(app: .wechat, sender: "王姐", preview: nil, key: "id:\(bannerID)|wechat|王姐|",
                                  bannerID: bannerID)
        revisions.record(shell, messageID: nil, now: now)
        XCTAssertEqual(revisions.decide(try XCTUnwrap(incoming(body: "在吗")), now: at(0.6)), .updated,
                       "空壳没弹过（正在看微信等）就照常走")
    }

    func testRepeatedReportDoesNotResetTheClock() throws {
        var revisions = NotchBannerRevisions()
        let first = try XCTUnwrap(incoming(body: "在吗"))
        revisions.record(first, messageID: UUID(), now: now)
        revisions.record(first, messageID: nil, now: at(0.25))
        XCTAssertEqual(revisions.decide(try XCTUnwrap(incoming(body: "好的")), now: at(0.35)), .updated,
                       "同样的字再报一次不算换字，节流从上次换字算")
    }

    func testBannersWithoutIdentifierAreLeftToTheDeduper() {
        var revisions = NotchBannerRevisions()
        let plain = NotchIncoming(app: .wechat, sender: "王姐", preview: "在吗", key: "text:wechat|王姐|在吗")
        revisions.record(plain, messageID: UUID(), now: now)
        XCTAssertEqual(revisions.decide(plain, now: at(0.1)), .fresh)
    }

    func testOldBannersAreForgotten() throws {
        var revisions = NotchBannerRevisions()
        let first = try XCTUnwrap(incoming(body: "在吗"))
        revisions.record(first, messageID: UUID(), now: now)
        XCTAssertEqual(revisions.decide(first, now: at(NotchBannerRevisions.keep + 1)), .fresh)
    }

    // MARK: 读通知中心的节流

    func testScanThrottle() {
        var throttle = NotchScanThrottle()
        XCTAssertEqual(throttle.delay(now: now, minimum: 0.12), 0.12, "第一次只等防抖")
        throttle.scanned(at: now)
        XCTAssertEqual(throttle.delay(now: at(0.05), minimum: 0.12), 0.25, accuracy: 0.001, "离上次读不到 300ms")
        XCTAssertEqual(throttle.delay(now: at(1), minimum: 0.12), 0.12, "隔得够久只等防抖")
        XCTAssertEqual(throttle.delay(now: at(0.1), minimum: 0.5), 0.5, "要求更长时按长的")
    }
}
