import XCTest

/// AI 助手小组件面板和刘海对话的联动：快捷操作胶囊的勾选、提交后交给谁、
/// 刘海对话里显示的字和回答下面的按钮。
final class AIAssistantFlowTests: XCTestCase {

    // MARK: 快捷操作胶囊

    func testDockChipsDefaultToTheFourCommonOnes() {
        XCTAssertEqual(AIDockChips.resolved(nil), [.screenshot, .clipboardSummary, .translate, .polish],
                       "同效果图：截图提问、剪贴板总结、翻译、润色")
        XCTAssertEqual(AIDockChips.resolved(nil).map(\.title), ["截图提问", "剪贴板总结", "翻译", "润色"])
        XCTAssertEqual(AIDockChips.resolved([]), [], "存了空列表就是一个都不显示")
    }

    func testDockChipsSkipUnknownAndKeepAFixedOrder() {
        XCTAssertEqual(AIDockChips.resolved(["summarize", "teleport", "screenshot", "summarize"]),
                       [.screenshot, .summarize])
        XCTAssertEqual(AIDockChips.resolved(AIDockChip.allCases.map(\.rawValue)).count, AIDockChips.maxCount)
    }

    func testDockChipsToggle() {
        let removed = AIDockChips.toggled(.clipboardSummary, in: nil)
        XCTAssertEqual(removed, ["screenshot", "translate", "polish"])
        let added = AIDockChips.toggled(.explain, in: removed)
        XCTAssertEqual(added, ["screenshot", "translate", "polish", "explain"])
        XCTAssertFalse(AIDockChips.canToggle(.summarize, in: added), "满了勾不上")
        XCTAssertEqual(AIDockChips.toggled(.summarize, in: added), added)
        XCTAssertTrue(AIDockChips.canToggle(.explain, in: added), "勾上的总能取消")
    }

    func testOnlyPromptChipsCarryAQuickAction() {
        XCTAssertNil(AIDockChip.screenshot.quickAction)
        XCTAssertNil(AIDockChip.clipboard.quickAction)
        XCTAssertEqual(AIDockChip.clipboardSummary.quickAction, .summarize, "剪贴板总结套总结的提示词")
        XCTAssertTrue(AIDockChip.clipboardSummary.usesClipboardOnly)
        XCTAssertTrue(AIDockChip.clipboard.usesClipboardOnly)
        XCTAssertFalse(AIDockChip.summarize.usesClipboardOnly)
        XCTAssertEqual(AIDockChip.translate.quickAction, .translate)
        XCTAssertEqual(AIDockChip.summarize.quickAction, .summarize)
    }

    func testSettingsKeepTheChipChoice() throws {
        XCTAssertNil(AINotchSettings().panelChips)
        var settings = AINotchSettings()
        settings.panelChips = ["translate"]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AINotchSettings.self, from: data).panelChips, ["translate"])
        let old = try JSONDecoder().decode(AINotchSettings.self, from: Data("{}".utf8))
        XCTAssertNil(old.panelChips, "旧设置没有这一项时用默认")
    }

    // MARK: 交给刘海对话

    func testHandoffByMode() {
        XCTAssertEqual(AIHandoff.plan("  ", mode: .api, notchUnlocked: true), .blocked)
        XCTAssertEqual(AIHandoff.plan(" 你好 ", mode: .api, notchUnlocked: true), .notchAPI("你好"))
        XCTAssertEqual(AIHandoff.plan("你好", mode: .web, notchUnlocked: true), .notchWeb("你好"))
        XCTAssertEqual(AIHandoff.plan("你好", mode: .jump, notchUnlocked: true), .app)
        XCTAssertEqual(AIHandoff.plan("你好", mode: .jump, notchUnlocked: false), .app, "App 方式免费")
        XCTAssertEqual(AIHandoff.plan("你好", mode: .api, notchUnlocked: false), .paywall)
        XCTAssertEqual(AIHandoff.plan("你好", mode: .web, notchUnlocked: false), .paywall)
    }

    func testOnlyANotchHandoffClosesTheDockPanel() {
        XCTAssertTrue(AIHandoff.notchAPI("a").closesDockPanel)
        XCTAssertTrue(AIHandoff.notchWeb("a").closesDockPanel)
        XCTAssertFalse(AIHandoff.app.closesDockPanel)
        XCTAssertFalse(AIHandoff.paywall.closesDockPanel)
        XCTAssertFalse(AIHandoff.blocked.closesDockPanel)
    }

    func testWebNoticeNeverClaimsItWasSent() {
        let notice = AIHandoff.webNotice(service: "豆包")
        XCTAssertTrue(notice.contains("已复制"))
        XCTAssertTrue(notice.contains("豆包"))
        XCTAssertFalse(notice.contains("已发送"))
    }

    func testModeActionSaysWhatSubmitDoes() {
        XCTAssertEqual(AIHandoff.modeAction(.api, appInstalled: false, supportsAsk: false), "在刘海里直接回答")
        XCTAssertEqual(AIHandoff.modeAction(.web, appInstalled: true, supportsAsk: true), "复制后在刘海网页里粘贴")
        XCTAssertEqual(AIHandoff.modeAction(.jump, appInstalled: true, supportsAsk: true), "复制后打开 App")
        XCTAssertEqual(AIHandoff.modeAction(.jump, appInstalled: false, supportsAsk: true), "带着问题打开网页")
        XCTAssertEqual(AIHandoff.modeAction(.jump, appInstalled: false, supportsAsk: false), "复制后打开网页")
    }

    // MARK: 刘海对话

    func testNotchTexts() {
        XCTAssertEqual(AINotchChatText.entryTitle, "AI 助手", "圆点是画的，不在字里")
        XCTAssertEqual(AINotchChatText.thinking("DeepSeek"), "DeepSeek 正在思考")
        XCTAssertEqual(AINotchChatText.thinking(nil), "AI 正在思考")
        XCTAssertEqual(AINotchChatText.thinking("  "), "AI 正在思考")
        XCTAssertEqual(AINotchChatText.inputPlaceholder(hasMessages: false), "想让 AI 帮你做什么？")
        XCTAssertEqual(AINotchChatText.inputPlaceholder(hasMessages: true), "继续追问……")
    }

    func testAnswerActions() {
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: true, generating: false,
                                                     streaming: false, hasText: true), [.copy, .followUp, .regenerate])
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: false, generating: false,
                                                     streaming: false, hasText: true), [.copy],
                       "继续追问、重新生成只给最后一条")
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: true, generating: true,
                                                     streaming: true, hasText: true), [], "还在流的不放按钮")
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: true, generating: false,
                                                     streaming: false, hasText: false), [.regenerate],
                       "出错没有字时只能重新生成")
        XCTAssertEqual(AINotchChatText.answerActions(mode: .web, isLast: true, generating: false,
                                                     streaming: false, hasText: true), [])
        XCTAssertEqual(AINotchChatText.answerActions(mode: .jump, isLast: true, generating: false,
                                                     streaming: false, hasText: true), [])
    }

    // MARK: 小组件底栏

    func testServiceSegmentsShowTheFirstThree() {
        let ids = ["chatgpt", "claude", "gemini", "deepseek", "kimi"]
        let split = AIServiceSegments.split(ids)
        XCTAssertEqual(split.shown, ["chatgpt", "claude", "gemini"])
        XCTAssertEqual(split.overflow, ["deepseek", "kimi"])
        XCTAssertEqual(AIServiceSegments.split(ids, limit: 2).shown, ["chatgpt", "claude"])
        XCTAssertEqual(AIServiceSegments.split(["a"]).shown, ["a"])
        XCTAssertEqual(AIServiceSegments.split(["a"]).overflow, [])
        XCTAssertEqual(AIServiceSegments.split([String]()).shown, [])
        XCTAssertEqual(AIServiceSegments.split(ids, limit: 0).overflow.count, 5)
        XCTAssertEqual(AIServiceSegments.fallbackLimits, [3, 2, 1])
        XCTAssertTrue(AIServiceSegments.overflowSelected("kimi", overflow: split.overflow))
        XCTAssertFalse(AIServiceSegments.overflowSelected("claude", overflow: split.overflow))
        XCTAssertFalse(AIServiceSegments.overflowSelected(nil as String?, overflow: split.overflow))
    }

    func testModeOptionsFollowWhatTheServiceHas() {
        XCTAssertEqual(AIModeChoice.options(hasAPI: true, hasWeb: true).map(\.mode), [.api, .web, .jump])
        XCTAssertEqual(AIModeChoice.options(hasAPI: false, hasWeb: true).map(\.available), [false, true, true])
        XCTAssertEqual(AIModeChoice.options(hasAPI: false, hasWeb: false).map(\.available), [false, false, true],
                       "App 总能选")
    }

    func testModeCapsuleCyclesThroughUsableModes() {
        XCTAssertEqual(AIModeChoice.next(after: .api, hasAPI: true, hasWeb: true), .web)
        XCTAssertEqual(AIModeChoice.next(after: .web, hasAPI: true, hasWeb: true), .jump)
        XCTAssertEqual(AIModeChoice.next(after: .jump, hasAPI: true, hasWeb: true), .api)
        XCTAssertEqual(AIModeChoice.next(after: .web, hasAPI: false, hasWeb: true), .jump, "没密钥跳过 API")
        XCTAssertEqual(AIModeChoice.next(after: .jump, hasAPI: false, hasWeb: true), .web)
        XCTAssertEqual(AIModeChoice.next(after: .jump, hasAPI: false, hasWeb: false), .jump, "只有一种时不变")
        XCTAssertEqual(AIModeChoice.next(after: .api, hasAPI: false, hasWeb: true), .web, "当前不能用时回到第一种能用的")
    }

    func testModeCapsuleTitles() {
        XCTAssertEqual(AIModeChoice.capsuleTitle(.api), "API 模式")
        XCTAssertEqual(AIModeChoice.capsuleTitle(.web), "网页模式")
        XCTAssertEqual(AIModeChoice.capsuleTitle(.jump), "App 模式")
        XCTAssertNotNil(AIModeChoice.unavailableReason(.api))
        XCTAssertNil(AIModeChoice.unavailableReason(.jump))
    }
}
