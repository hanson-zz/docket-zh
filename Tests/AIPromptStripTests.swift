import XCTest

/// 刘海对话和 AI 任意门迷你提问面板共用的那一排：剪贴板按钮出不出现、
/// 第二行显示什么、迷你面板点了快捷指令之后交出去什么。
final class AIPromptStripTests: XCTestCase {

    func testClipboardChipOnlyWhereThereIsAnInputBox() {
        XCTAssertTrue(AIPromptStrip.showsClipboardChip(hasInput: true))
        XCTAssertFalse(AIPromptStrip.showsClipboardChip(hasInput: false), "刘海对话的网页模式没有输入框")
    }

    func testStatusLinePrefersTheNotice() {
        XCTAssertEqual(AIPromptStrip.statusLine(notice: "已复制", clipboardPreview: "hello"), .notice("已复制"))
        XCTAssertEqual(AIPromptStrip.statusLine(notice: nil, clipboardPreview: "hello"), .clipboard("hello"))
        XCTAssertEqual(AIPromptStrip.statusLine(notice: "  \n", clipboardPreview: "hello"), .clipboard("hello"),
                       "空白的提示当没有")
        XCTAssertEqual(AIPromptStrip.statusLine(notice: nil, clipboardPreview: nil), .none)
        XCTAssertEqual(AIPromptStrip.statusLine(notice: nil, clipboardPreview: ""), .none)
    }

    func testMiniPanelUsesTheDraftFirst() {
        let template = AIQuickAction.translate.template
        XCTAssertEqual(AIPromptStrip.outcome(template: template, draft: " hello ", clipboard: "剪贴板"),
                       .ask(AIPrompts.fill(template, with: "hello")))
    }

    func testMiniPanelFallsBackToTheClipboard() {
        XCTAssertEqual(AIPromptStrip.outcome(template: "总结：{文本}", draft: "   ", clipboard: "一段话"),
                       .ask("总结：一段话"))
        XCTAssertEqual(AIPromptStrip.outcome(template: "帮我改正式一点", draft: "", clipboard: "明天不来了"),
                       .ask("帮我改正式一点\n\n明天不来了"), "常用提示词没写 {文本} 时接在后面")
    }

    func testMiniPanelNeedsSomeText() {
        XCTAssertEqual(AIPromptStrip.outcome(template: "{文本}", draft: "", clipboard: nil), .needsText)
        XCTAssertEqual(AIPromptStrip.outcome(template: "{文本}", draft: " ", clipboard: "\n"), .needsText)
        XCTAssertEqual(AIPromptStrip.needsTextHint, "先在输入框里写字，或者复制要处理的文字。")
    }

    func testPasteHint() {
        XCTAssertEqual(AIPromptStrip.pasteHint(clipboard: nil), "剪贴板里没有文字。")
        XCTAssertEqual(AIPromptStrip.pasteHint(clipboard: "  "), "剪贴板里没有文字。")
        XCTAssertNil(AIPromptStrip.pasteHint(clipboard: "短短一句"))
        let long = String(repeating: "字", count: AIClipboard.insertLimit + 1)
        XCTAssertEqual(AIPromptStrip.pasteHint(clipboard: long),
                       "剪贴板太长，只带进了前 \(AIClipboard.insertLimit) 个字。")
    }
}
