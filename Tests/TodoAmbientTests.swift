import Foundation
import XCTest

final class QuickTodoTests: XCTestCase {
    private func config(_ raw: [String]) -> WidgetConfig {
        WidgetConfig([QuickTodo.key: .list(raw.map { .string($0) })])
    }

    func testRoundTripKeepsOrderAndState() {
        var items = QuickTodo.adding("买牛奶", to: [], id: "a")
        items = QuickTodo.adding("回邮件", to: items, id: "b")
        items = QuickTodo.toggling("a", in: items)
        var stored = WidgetConfig()
        QuickTodo.store(items, in: &stored)
        let read = QuickTodo.items(stored)
        XCTAssertEqual(read.map(\.text), ["回邮件", "买牛奶"])
        XCTAssertEqual(read.map(\.done), [false, true])
        XCTAssertEqual(QuickTodo.openCount(stored), 1)
    }

    func testNewItemsGoAfterOpenOnesAndBeforeDoneOnes() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二", done: true)]
        let added = QuickTodo.adding("三", to: items, id: "c")
        XCTAssertEqual(added.map(\.id), ["a", "c", "b"])
    }

    func testReopenedItemGoesToTheEndOfTheOpenList() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二"),
                     TodoItem(id: "c", text: "三", done: true)]
        let reopened = QuickTodo.toggling("c", in: items)
        XCTAssertEqual(reopened.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(reopened.allSatisfy { !$0.done })
        let finished = QuickTodo.toggling("a", in: reopened)
        XCTAssertEqual(finished.map(\.id), ["b", "c", "a"])
    }

    func testBlankAndMultilineInputIsCleaned() {
        XCTAssertEqual(QuickTodo.adding("   ", to: []).count, 0)
        XCTAssertEqual(QuickTodo.clean("  第一行\n第二行\t尾  "), "第一行 第二行 尾")
        XCTAssertEqual(QuickTodo.clean(String(repeating: "字", count: 500))?.count, QuickTodo.maxLength)
    }

    func testLooseStringsAreStillTasks() {
        let read = QuickTodo.items(config(["写周报", "", "x\t1\t完成的", "x\t0\t同号"]))
        XCTAssertEqual(read.map(\.text), ["写周报", "同号", "完成的"])
        XCTAssertEqual(Set(read.map(\.id)).count, 3, "duplicate ids must be split")
    }

    func testRenameRemoveAndClear() {
        var items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二", done: true)]
        items = QuickTodo.renaming("a", to: "改过", in: items)
        XCTAssertEqual(items.first?.text, "改过")
        XCTAssertEqual(QuickTodo.renaming("a", to: "  ", in: items).map(\.id), ["b"])
        XCTAssertEqual(QuickTodo.removing("b", from: items).map(\.id), ["a"])
        XCTAssertEqual(QuickTodo.clearingDone(items).map(\.id), ["a"])
    }

    func testCaption() {
        XCTAssertEqual(QuickTodo.caption(open: 0, done: 0), "点按添加待办")
        XCTAssertEqual(QuickTodo.caption(open: 0, done: 2), "全部完成")
        XCTAssertEqual(QuickTodo.caption(open: 1, done: 0), "只剩这一项")
        XCTAssertEqual(QuickTodo.caption(open: 4, done: 0), "另外还有 3 项")
    }

    func testItemsAreNotASetting() {
        XCTAssertFalse(WidgetCatalog.configurableKeys(.todo).contains(QuickTodo.key))
    }

    func testShowsOnlyWithOpenItemsWhenConditional() {
        var instance = WidgetCatalog.make(.todo)!
        instance.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertFalse(WidgetVisibility.isVisible(instance, .unknown))
        QuickTodo.store([TodoItem(text: "一")], in: &instance.config)
        XCTAssertTrue(WidgetVisibility.isVisible(instance, .unknown))
    }
}

final class AmbientSynthTests: XCTestCase {
    private func render(_ sounds: [AmbientSound], seconds: Double = 1, volume: Double = 1,
                        seed: UInt64 = 7) -> [Float] {
        var synth = AmbientSynth(sampleRate: 22_050, seed: seed)
        synth.setVolume(volume)
        synth.setSounds(sounds)
        return (0..<Int(22_050 * seconds)).map { _ in synth.next() }
    }

    private func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }

    func testEverySoundIsAudibleAndInRange() {
        for sound in AmbientSound.allCases {
            let out = render([sound])
            XCTAssertTrue(out.allSatisfy { $0.isFinite && abs($0) <= 1 }, "\(sound)")
            XCTAssertGreaterThan(rms(Array(out.suffix(11_025))), 0.01, "\(sound) is too quiet")
        }
    }

    func testTheWholeMixStaysInRange() {
        let out = render(AmbientSound.allCases, seconds: 2)
        XCTAssertTrue(out.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    func testNothingSelectedIsSilence() {
        XCTAssertTrue(render([]).allSatisfy { $0 == 0 })
    }

    func testVolumeScalesTheOutput() {
        let loud = rms(render([.pink], volume: 1).suffix(11_025).map { $0 })
        let quiet = rms(render([.pink], volume: 0.2).suffix(11_025).map { $0 })
        XCTAssertLessThan(quiet, loud * 0.4)
    }

    func testFadeOutReachesSilence() {
        var synth = AmbientSynth(sampleRate: 22_050)
        synth.setVolume(1)
        synth.setSounds([.rain])
        for _ in 0..<22_050 { _ = synth.next() }
        XCTAssertFalse(synth.isSilent)
        synth.fadeOut()
        for _ in 0..<44_100 { _ = synth.next() }
        XCTAssertTrue(synth.isSilent)
    }

    func testSameSeedSameSound() {
        XCTAssertEqual(render([.rain, .fire], seconds: 0.2), render([.rain, .fire], seconds: 0.2))
        XCTAssertNotEqual(render([.white], seconds: 0.1, seed: 1), render([.white], seconds: 0.1, seed: 2))
    }

    func testParseAndSummary() {
        XCTAssertEqual(AmbientSound.parse(["waves", "nope", "rain", "waves"]), [.waves, .rain])
        XCTAssertEqual(AmbientSound.summary([.rain, .waves]), "雨声 + 海浪")
        XCTAssertEqual(AmbientSound.summary([.rain, .waves, .fire]), "雨声 等 3 种")
        XCTAssertEqual(AmbientSound.summary([]), "未选择声音")
    }

    func testTimerText() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(AmbientTimer.remaining(until: now.addingTimeInterval(725), now: now), "12:05")
        XCTAssertEqual(AmbientTimer.remaining(until: now.addingTimeInterval(3_661), now: now), "1:01:01")
        XCTAssertEqual(AmbientTimer.title(0), "不定时")
        XCTAssertEqual(AmbientTimer.title(90), "90 分钟")
        XCTAssertEqual(AmbientTimer.title(60), "1 小时")
    }
}
