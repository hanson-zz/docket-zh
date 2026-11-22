import XCTest

/// AI 助手扩展栏卡片（Dock 小组件）的纯逻辑：模型键上的字、放得下几块、放不下时留哪几块、
/// 高亮哪块，以及竖版那一行状态。
final class AIDockMiniTests: XCTestCase {

    private func service(_ id: String) -> AIService {
        AIServices.builtIn(id)!
    }

    // MARK: 模型键上的字

    func testKeyLabelComesFromTheServiceItself() {
        for service in AIServices.builtIn {
            let label = AIServices.keyLabel(service)
            XCTAssertFalse(label.isEmpty, service.id)
            XCTAssertLessThanOrEqual(label.count, 2, service.id)
            XCTAssertEqual(label, service.initial, "沿用服务现有的缩写：\(service.id)")
        }
    }

    func testKeyLabelFallsBackToTheTitleAndStaysShort() {
        let blank = AIService(id: "custom-x", title: "  mistral", initial: " ", region: .overseas,
                              home: "https://chat.mistral.ai")
        XCTAssertEqual(AIServices.keyLabel(blank), "M")
        let chinese = AIService(id: "custom-y", title: "海螺", initial: "", region: .domestic, home: "https://hailuoai.com")
        XCTAssertEqual(AIServices.keyLabel(chinese), "海")
        let long = AIService(id: "custom-z", title: "Long", initial: "ABC", region: .overseas, home: "https://a.b")
        XCTAssertEqual(AIServices.keyLabel(long), "AB")
        let wide = AIService(id: "custom-w", title: "通义千问", initial: "通义", region: .domestic, home: "https://a.b")
        XCTAssertEqual(AIServices.keyLabel(wide), "通", "汉字只放一个，13pt 才放得进 24pt 的键")
    }

    // MARK: 放得下几块

    func testCapacityMatchesTheNaturalTileWidth() {
        for count in 1 ... AIServices.maxCount {
            let content = AIServices.tileWidth(count: count, square: false) - 2 * 10
            XCTAssertEqual(AIServices.keyCapacity(contentWidth: content), count, "\(count) 块")
        }
    }

    func testCapacityShrinksWhenTheTileIsSqueezed() {
        let three = AIServices.tileWidth(count: 3, square: false) - 20
        XCTAssertEqual(AIServices.keyCapacity(contentWidth: three - 1), 2)
        XCTAssertEqual(AIServices.keyCapacity(contentWidth: 60), 0)
        XCTAssertEqual(AIServices.keyCapacity(contentWidth: 0), 0)
        XCTAssertEqual(AIServices.keyCapacity(contentWidth: .infinity), 0)
        XCTAssertEqual(AIServices.keyCapacity(contentWidth: 10_000), AIServices.maxCount)
    }

    // MARK: 放不下时留哪几块

    func testShelfKeysKeepOrderWhenEverythingFits() {
        let list = AIServices.defaults
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: "kimi", capacity: 5).map(\.id), list.map(\.id))
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: nil, capacity: 3).map(\.id), list.map(\.id))
    }

    func testShelfKeysDropFromTheEndButKeepTheCurrentOne() {
        let list = ["deepseek", "kimi", "doubao", "tongyi", "chatgpt"].map(service)
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: "kimi", capacity: 3).map(\.id),
                       ["deepseek", "kimi", "doubao"])
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: "chatgpt", capacity: 3).map(\.id),
                       ["deepseek", "kimi", "chatgpt"], "当前模型顶掉最后一块")
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: "chatgpt", capacity: 1).map(\.id), ["chatgpt"])
        XCTAssertEqual(AIServices.shelfKeys(list, currentID: "gone", capacity: 2).map(\.id), ["deepseek", "kimi"])
        XCTAssertTrue(AIServices.shelfKeys(list, currentID: "kimi", capacity: 0).isEmpty)
        XCTAssertTrue(AIServices.shelfKeys(list, currentID: "kimi", capacity: -3).isEmpty)
    }

    // MARK: 高亮哪块

    func testCurrentKeyPrefersLastUsedThenDefault() {
        let list = AIServices.defaults
        XCTAssertEqual(AIServices.currentKeyID(lastUsed: "kimi", in: list, defaultID: "deepseek"), "kimi")
        XCTAssertEqual(AIServices.currentKeyID(lastUsed: "chatgpt", in: list, defaultID: "deepseek"), "deepseek",
                       "上次用的不在这张卡片上，回到默认")
        XCTAssertEqual(AIServices.currentKeyID(lastUsed: nil, in: list, defaultID: "gone"), list.first?.id)
        XCTAssertNil(AIServices.currentKeyID(lastUsed: "kimi", in: [], defaultID: "kimi"))
    }

    // MARK: 状态

    func testStatusFollowsThePandaStates() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(AIDockStatus.resolve(base: .idle, pulse: nil, now: now), .idle)
        XCTAssertEqual(AIDockStatus.resolve(base: .thinking, pulse: nil, now: now), .generating)
        let done = PandaPulse(state: .done, started: now, until: now.addingTimeInterval(2))
        XCTAssertEqual(AIDockStatus.resolve(base: .idle, pulse: done, now: now.addingTimeInterval(1)), .done)
        XCTAssertEqual(AIDockStatus.resolve(base: .idle, pulse: done, now: now.addingTimeInterval(3)), .idle,
                       "完成只短暂显示，过了回待命")
        let failed = PandaPulse(state: .alert, started: now, until: now.addingTimeInterval(6))
        XCTAssertEqual(AIDockStatus.resolve(base: .idle, pulse: failed, now: now.addingTimeInterval(1)), .failed)
    }

    func testWebAndAppModesStayIdle() {
        // 网页、App 方式拿不到回答阶段：常态一律待命，不造假。
        let base = PandaStateResolver.ai(.thinking, mode: .web)
        XCTAssertEqual(AIDockStatus.resolve(base: base, pulse: nil, now: .now), .idle)
        XCTAssertEqual(AIDockStatus.resolve(base: PandaStateResolver.aiBase(nil), pulse: nil, now: .now), .idle)
        XCTAssertEqual(AIDockStatus.resolve(base: PandaStateResolver.aiBase(.answering), pulse: nil, now: .now),
                       .generating)
    }

    func testStatusLineAndColors() {
        XCTAssertEqual(AIDockStatus.idle.line(keyLabel: "D"), "待命 · D")
        XCTAssertEqual(AIDockStatus.generating.line(keyLabel: "豆"), "生成中 · 豆")
        XCTAssertEqual(AIDockStatus.idle.line(keyLabel: nil), "待命")
        XCTAssertEqual(AIDockStatus.done.line(keyLabel: ""), "完成")
        let all: [AIDockStatus] = [.idle, .generating, .done, .failed]
        XCTAssertEqual(Set(all.map(\.dotHex)).count, all.count)
        XCTAssertEqual(all.map(\.pandaState), [.idle, .thinking, .done, .alert])
    }

    // MARK: 竖版：状态陪伴卡

    func testHintsComeFromTheChosenQuickActions() {
        let hints = AIDockTips.hints(["截图提问", " 翻译内容 ", "", "截图提问", "总结剪贴板"])
        XCTAssertEqual(hints.map(\.short), ["截图提问", "翻译内容", "总结剪贴板"], "去空白、去空、去重，顺序不变")
        XCTAssertEqual(hints.first?.full, "可以试试：截图提问")
        XCTAssertEqual(AIDockTips.hints([]), [AIDockTips.fallback], "一个都没勾时有一句兜底，不写死快捷操作")
        XCTAssertEqual(AIDockTips.hints(["  "]), [AIDockTips.fallback])
        let names = AIDockChip.allCases.map(\.gridTitle)
        XCTAssertEqual(Set(names).count, names.count, "每个快捷操作的名字不同")
        XCTAssertEqual(AIDockChip.screenshot.gridTitle, "截图提问")
    }

    func testHintsRotateSlowlyAndStopForReduceMotion() {
        XCTAssertGreaterThanOrEqual(AIDockTips.interval, 8)
        let start = Date(timeIntervalSinceReferenceDate: 800)
        XCTAssertEqual(AIDockTips.index(at: start, count: 3, reduceMotion: false), 100 % 3)
        let first = AIDockTips.index(at: start, count: 3, reduceMotion: false)
        XCTAssertEqual(AIDockTips.index(at: start.addingTimeInterval(7.9), count: 3, reduceMotion: false), first,
                       "不到一个间隔不换")
        XCTAssertEqual(AIDockTips.index(at: start.addingTimeInterval(8), count: 3, reduceMotion: false),
                       (first + 1) % 3)
        XCTAssertEqual(AIDockTips.index(at: start.addingTimeInterval(8), count: 3, reduceMotion: true), 0,
                       "减弱动态效果时只显示第一条")
        XCTAssertEqual(AIDockTips.index(at: start, count: 1, reduceMotion: false), 0)
        XCTAssertEqual(AIDockTips.index(at: start, count: 0, reduceMotion: false), 0)
        XCTAssertEqual(AIDockTips.index(at: Date(timeIntervalSinceReferenceDate: -20), count: 3,
                                        reduceMotion: false), 0, "负的时间也落在范围里")
        for seconds in stride(from: -100.0, through: 100, by: 7) {
            let index = AIDockTips.index(at: Date(timeIntervalSinceReferenceDate: seconds), count: 4, reduceMotion: false)
            XCTAssertTrue((0 ..< 4).contains(index))
        }
    }

    func testHintLineShowsRealStatusWhenBusy() {
        let hints = AIDockTips.hints(["截图提问", "翻译内容"])
        XCTAssertEqual(AIDockTips.hint(for: .idle, hints: hints, index: 1).short, "翻译内容")
        XCTAssertEqual(AIDockTips.hint(for: .idle, hints: hints, index: 5).short, "翻译内容", "越界取余")
        XCTAssertEqual(AIDockTips.hint(for: .idle, hints: [], index: 0), AIDockTips.fallback)
        XCTAssertEqual(AIDockTips.hint(for: .generating, hints: hints, index: 0).short, AIDockStatus.generating.title)
        XCTAssertEqual(AIDockTips.hint(for: .done, hints: hints, index: 0).short, AIDockStatus.done.title)
        XCTAssertEqual(AIDockTips.hint(for: .failed, hints: hints, index: 0).short, AIDockStatus.failed.title)
        XCTAssertNotEqual(AIDockTips.hint(for: .generating, hints: hints, index: 0).full, hints[0].full,
                          "生成中不显示提示")
    }

    func testVerticalPandaDiffersFromTheShelfRow() {
        XCTAssertEqual(PandaStateResolver.aiDockPose(nil), .scene(.aiInput))
        XCTAssertEqual(PandaStateResolver.aiDockPose(.done), .scene(.aiInput))
        XCTAssertEqual(PandaStateResolver.aiDockPose(.failed("超时")), .scene(.aiInput))
        XCTAssertEqual(PandaStateResolver.aiDockPose(.thinking), .scene(.aiGenerating))
        XCTAssertEqual(PandaStateResolver.aiDockPose(.answering), .scene(.aiGenerating))
        XCTAssertNotEqual(PandaStateResolver.aiDockPose(nil), PandaStateResolver.aiPose(nil, typing: false),
                          "竖版和横版的小熊猫姿势不同")
    }
}
