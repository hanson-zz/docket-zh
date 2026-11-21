import XCTest
@testable import Docket

final class LiveBadgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testBundleIDs() {
        XCTAssertEqual(LiveBadgeApp(bundleID: "com.apple.MobileSMS"), .messages)
        XCTAssertEqual(LiveBadgeApp(bundleID: "com.tencent.xinwechat"), .wechat)
        XCTAssertEqual(LiveBadgeApp(bundleID: "com.apple.mail"), .mail)
        XCTAssertNil(LiveBadgeApp(bundleID: "com.apple.Safari"))
    }

    func testTiers() {
        XCTAssertEqual(LiveBadgeTier(count: 0), .idle)
        XCTAssertEqual(LiveBadgeTier(count: 1), .one)
        XCTAssertEqual(LiveBadgeTier(count: 3), .few)
        XCTAssertEqual(LiveBadgeTier(count: 4), .several)
        XCTAssertEqual(LiveBadgeTier(count: 6), .several)
        XCTAssertEqual(LiveBadgeTier(count: 8), .many)
        XCTAssertEqual(LiveBadgeTier(count: 9), .lots)
        XCTAssertEqual(LiveBadgeTier(count: -2), .idle)
    }

    func testReadingFromDockBadge() {
        XCTAssertEqual(LiveBadgeReading(.missing), .unknown)
        XCTAssertEqual(LiveBadgeReading(.none), .count(0))
        XCTAssertEqual(LiveBadgeReading(.count(5)), .count(5))
        XCTAssertEqual(LiveBadgeReading(.mark), .mark)
        XCTAssertNil(LiveBadgeReading.mark.reliableCount)
    }

    func testUnknownAndZeroArePlain() {
        for style in LiveBadgeStyle.allCases {
            XCTAssertEqual(LiveBadgeLook.of(.wechat, reading: .unknown, style: style), .plain)
            XCTAssertEqual(LiveBadgeLook.of(.wechat, reading: .count(0), style: style), .plain)
        }
    }

    func testSubtleKeepsBrandColour() {
        let look = LiveBadgeLook.of(.messages, reading: .count(7), style: .subtle)
        XCTAssertEqual(look.badgeText, "7")
        XCTAssertEqual(look.hueRotation, 0)
        XCTAssertEqual(look.accent, .none)
    }

    func testPlayfulShiftsColourByTier() {
        XCTAssertEqual(LiveBadgeLook.of(.wechat, reading: .count(1), style: .playful).hueRotation, 0)
        let few = LiveBadgeLook.of(.wechat, reading: .count(2), style: .playful)
        XCTAssertEqual(few.hueRotation, 75, accuracy: 1e-9)
        XCTAssertEqual(few.accent, .sparkle)
        XCTAssertEqual(LiveBadgeLook.of(.wechat, reading: .count(5), style: .playful).accent, .flame)
        XCTAssertEqual(LiveBadgeLook.of(.wechat, reading: .count(12), style: .playful).accent, .drip)
        // 走近的一边：绿 130 到红 352 往回转 138 度。
        XCTAssertEqual(LiveBadgeLook.of(.messages, reading: .count(9), style: .playful).hueRotation, -138, accuracy: 1e-9)
    }

    func testMarkHasNoFakeNumber() {
        let look = LiveBadgeLook.of(.mail, reading: .mark, style: .playful)
        XCTAssertEqual(look.badgeText, "")
        XCTAssertEqual(look.hueRotation, 0)
    }

    func testBadgeText() {
        XCTAssertEqual(LiveBadgeLook.text(3), "3")
        XCTAssertEqual(LiveBadgeLook.text(150), "99+")
    }

    func testPulseOnlyOnIncreaseAndCoalesced() {
        var pulse = LiveBadgePulse()
        XCTAssertFalse(pulse.update(.count(3), now: t0), "从未知变成有数不弹")
        XCTAssertTrue(pulse.update(.count(4), now: t0.addingTimeInterval(5)))
        XCTAssertFalse(pulse.update(.count(5), now: t0.addingTimeInterval(5.4)), "1 秒内合并")
        XCTAssertFalse(pulse.update(.count(2), now: t0.addingTimeInterval(9)), "变少不弹")
        XCTAssertTrue(pulse.update(.count(3), now: t0.addingTimeInterval(10)))
        XCTAssertEqual(pulse.generation, 2)
        XCTAssertFalse(pulse.update(.unknown, now: t0.addingTimeInterval(20)))
        XCTAssertFalse(pulse.update(.count(9), now: t0.addingTimeInterval(21)), "从未知回来不弹")
    }
}

final class LiveBrowserTests: XCTestCase {
    func testBundleIDs() {
        XCTAssertEqual(LiveBrowser(bundleID: "com.google.Chrome"), .chrome)
        XCTAssertEqual(LiveBrowser(bundleID: "com.apple.Safari"), .safari)
        XCTAssertNil(LiveBrowser(bundleID: "com.apple.mail"))
    }

    func testHoverEndsUpright() {
        for browser in LiveBrowser.allCases {
            XCTAssertEqual(browser.hoverKeyframes.last, 0)
            XCTAssertLessThanOrEqual(browser.hoverKeyframes.map(abs).max() ?? 0, 18)
        }
    }

    func testRingHeadWraps() {
        XCTAssertEqual(LiveBrowserRing.head(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(LiveBrowserRing.head(at: 2.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(LiveBrowserRing.head(at: -0.25), 0.75, accuracy: 1e-9)
    }
}
