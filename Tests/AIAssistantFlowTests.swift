import XCTest

/// AI 助手小组件面板和刘海对话的联动：快捷操作胶囊的勾选、提交后交给谁、
/// 刘海对话里显示的字和回答下面的按钮。
final class AIAssistantFlowTests: XCTestCase {

    // MARK: 快捷操作胶囊

    func testDockChipsDefaultToTheFourCommonOnes() {
        XCTAssertEqual(AIDockChips.resolved(nil), [.screenshot, .clipboard, .translate, .summarize])
        XCTAssertEqual(AIDockChips.resolved([]), [], "存了空列表就是一个都不显示")
    }

    func testDockChipsSkipUnknownAndKeepAFixedOrder() {
        XCTAssertEqual(AIDockChips.resolved(["summarize", "teleport", "screenshot", "summarize"]),
                       [.screenshot, .summarize])
        XCTAssertEqual(AIDockChips.resolved(AIDockChip.allCases.map(\.rawValue)).count, AIDockChips.maxCount)
    }

    func testDockChipsToggle() {
        let removed = AIDockChips.toggled(.clipboard, in: nil)
        XCTAssertEqual(removed, ["screenshot", "translate", "summarize"])
        let added = AIDockChips.toggled(.explain, in: removed)
        XCTAssertEqual(added, ["screenshot", "translate", "summarize", "explain"])
        XCTAssertFalse(AIDockChips.canToggle(.polish, in: added), "满了勾不上")
        XCTAssertEqual(AIDockChips.toggled(.polish, in: added), added)
        XCTAssertTrue(AIDockChips.canToggle(.explain, in: added), "勾上的总能取消")
    }

    func testOnlyPromptChipsCarryAQuickAction() {
        XCTAssertNil(AIDockChip.screenshot.quickAction)
        XCTAssertNil(AIDockChip.clipboard.quickAction)
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
        XCTAssertEqual(AINotchChatText.entryTitle, "✦ AI 助手")
        XCTAssertEqual(AINotchChatText.thinking("DeepSeek"), "DeepSeek 正在思考")
        XCTAssertEqual(AINotchChatText.thinking(nil), "AI 正在思考")
        XCTAssertEqual(AINotchChatText.thinking("  "), "AI 正在思考")
        XCTAssertEqual(AINotchChatText.inputPlaceholder(hasMessages: false), "想让 AI 帮你做什么？")
        XCTAssertEqual(AINotchChatText.inputPlaceholder(hasMessages: true), "继续追问……")
    }

    func testAnswerActions() {
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: true, generating: false,
                                                     streaming: false, hasText: true), [.copy, .regenerate])
        XCTAssertEqual(AINotchChatText.answerActions(mode: .api, isLast: false, generating: false,
                                                     streaming: false, hasText: true), [.copy],
                       "重新生成只给最后一条")
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
}
