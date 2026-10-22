import Foundation
import XCTest
@testable import Docket

/// 「Codex 用量」的提示音：默认值、哪些变化出声、额度过 90%、防抖、小喇叭。
final class CodexChimeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testDefaultsOnlyRingForWaiting() {
        let s = CodexChimeSettings(config: WidgetCatalog.make(.aiUsage)!.config)
        XCTAssertTrue(s.waiting)
        XCTAssertFalse(s.done)
        XCTAssertFalse(s.quota)
        XCTAssertEqual(s.tone, "Glass")
        XCTAssertEqual(CodexChimeSettings(config: WidgetConfig()), s, "没存过的老卡片也是同样的默认")
    }

    func testUnknownToneFallsBack() {
        XCTAssertEqual(CodexChimeSettings(config: WidgetConfig(["tone": .string("Nope")])).tone, "Glass")
        XCTAssertEqual(CodexChimeSettings(config: WidgetConfig(["tone": .string("Ping")])).tone, "Ping")
        XCTAssertTrue(CodexChimeSettings.tones.contains(CodexChimeSettings.defaultTone))
    }

    func testDelivery() {
        let s = CodexChimeSettings()
        XCTAssertTrue(CodexChime.delivery(.waiting, banner: false, settings: s) == (true, true))
        XCTAssertTrue(CodexChime.delivery(.done, banner: true, settings: s) == (true, false))
        XCTAssertTrue(CodexChime.delivery(.done, banner: false, settings: s) == (false, false))
    }

    func testFirstScanNeverRings() {
        XCTAssertTrue(CodexChime.events(previous: nil, current: ["a": .waiting, "b": .done]).isEmpty)
    }

    func testOneChangeOneEvent() {
        let first = CodexChime.events(previous: ["a": .working], current: ["a": .waiting])
        XCTAssertEqual(first.map { $0.event }, [.waiting])
        XCTAssertEqual(first.map { $0.session }, ["a"])
        // 还在等：不再响。
        XCTAssertTrue(CodexChime.events(previous: ["a": .waiting], current: ["a": .waiting]).isEmpty)
        // 批准后接着跑：不响；做完：响完成。
        XCTAssertTrue(CodexChime.events(previous: ["a": .waiting], current: ["a": .working]).isEmpty)
        XCTAssertEqual(CodexChime.events(previous: ["a": .working], current: ["a": .done]).map { $0.event }, [.done])
        XCTAssertEqual(CodexChime.events(previous: ["a": .waiting], current: ["a": .done]).map { $0.event }, [.done])
    }

    func testDoneOnlyAfterWork() {
        // 新出现就是已完成（以前空闲）的不算完成。
        XCTAssertTrue(CodexChime.events(previous: [:], current: ["a": .done]).isEmpty)
        // 新会话一出来就在等：算。
        XCTAssertEqual(CodexChime.events(previous: [:], current: ["n": .waiting]).map { $0.event }, [.waiting])
    }

    func testSeveralSessionsAreSorted() {
        let e = CodexChime.events(previous: ["b": .working, "a": .working], current: ["b": .done, "a": .waiting])
        XCTAssertEqual(e.map { $0.session }, ["a", "b"])
        XCTAssertEqual(e.map { $0.event }, [.waiting, .done])
    }

    func testQuotaCrossesNinetyOnce() {
        XCTAssertTrue(CodexChime.quotaCrossed(previous: 0.85, current: 0.9))
        XCTAssertFalse(CodexChime.quotaCrossed(previous: 0.9, current: 0.95), "停在线上不再响")
        XCTAssertFalse(CodexChime.quotaCrossed(previous: nil, current: 0.95), "没有上一次读数不响")
        XCTAssertFalse(CodexChime.quotaCrossed(previous: 0.5, current: 0.89))
        // 重置回落后再升上来，再响一次。
        XCTAssertTrue(CodexChime.quotaCrossed(previous: 0.1, current: 0.92))
    }

    func testQuotaBannerAndSound() {
        // 横幅开、声音关：80% 发一条不出声的。
        let a = CodexChime.quota(previous: 0.7, current: 0.82, bannerOn: true, alertAt: 80, soundOn: false)
        XCTAssertEqual(a?.hit ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(a?.sound, false)
        // 横幅关、声音开：只在过 90% 时发，带声音。
        XCTAssertNil(CodexChime.quota(previous: 0.7, current: 0.82, bannerOn: false, alertAt: 80, soundOn: true))
        let b = CodexChime.quota(previous: 0.85, current: 0.91, bannerOn: false, alertAt: 80, soundOn: true)
        XCTAssertEqual(b?.hit ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(b?.sound, true)
        // 两个都开，一次跨过 90 和 95：一条通知，标题说 95%，带声音。
        let c = CodexChime.quota(previous: 0.85, current: 0.96, bannerOn: true, alertAt: 80, soundOn: true)
        XCTAssertEqual(c?.hit ?? 0, 0.95, accuracy: 1e-9)
        XCTAssertEqual(c?.sound, true)
        // 都关：没有。
        XCTAssertNil(CodexChime.quota(previous: 0.85, current: 0.96, bannerOn: false, alertAt: 80, soundOn: false))
        // 一下用完：标题说用完。
        XCTAssertEqual(CodexChime.quota(previous: 0.5, current: 1, bannerOn: false, alertAt: 80, soundOn: true)?.hit, 1)
    }

    func testGateDebouncesTheSameSessionAndCollapsesSounds() {
        var gate = CodexChimeGate(repeatWindow: 30, soundWindow: 3)
        XCTAssertTrue(gate.allow("a.waiting", at: t0))
        XCTAssertFalse(gate.allow("a.waiting", at: t0.addingTimeInterval(10)), "来回跳也只响一次")
        XCTAssertTrue(gate.allow("b.waiting", at: t0.addingTimeInterval(1)), "别的会话照发")
        XCTAssertTrue(gate.allow("a.waiting", at: t0.addingTimeInterval(31)))

        XCTAssertTrue(gate.allowSound(at: t0))
        XCTAssertFalse(gate.allowSound(at: t0.addingTimeInterval(1)), "几乎同时的第二条不再出声")
        XCTAssertTrue(gate.allowSound(at: t0.addingTimeInterval(4)))
    }

    func testSpeakerMark() {
        let s = CodexChimeSettings()
        XCTAssertEqual(CodexChime.speaker(for: .waiting, settings: s), .on)
        XCTAssertEqual(CodexChime.speaker(for: .done, settings: s), .off)
        XCTAssertEqual(CodexChime.speaker(for: .working, settings: s), .hidden)
        XCTAssertEqual(CodexChime.speaker(for: .idle, settings: s), .hidden)
        XCTAssertEqual(CodexChime.toggleKey(for: .waiting), "soundWaiting")
        XCTAssertEqual(CodexChime.toggleKey(for: .done), "soundDone")
        XCTAssertNil(CodexChime.toggleKey(for: .working))
    }

    func testSoundSwitchesAreNotificationSwitches() {
        for key in ["soundWaiting", "soundDone", "soundQuota"] {
            XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.aiUsage.rawValue, key: key), key)
        }
    }
}
