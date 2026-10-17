import XCTest

/// AI 助手 P1 的纯逻辑：提示词的占位替换、文字从哪来、常用提示词的增删改
/// 排序和读写、剪贴板预览和接力、输入法选字时不提交、面板回到哪块屏幕。
final class AIPromptsTests: XCTestCase {

    // MARK: 占位替换

    func testFillReplacesEveryPlaceholder() {
        XCTAssertEqual(AIPrompts.fill("翻译：{文本}", with: "hello"), "翻译：hello")
        XCTAssertEqual(AIPrompts.fill("{文本}\n再说一遍：{文本}", with: "好"), "好\n再说一遍：好")
        XCTAssertEqual(AIPrompts.fill("  前缀 {文本}  ", with: "  中间  "), "前缀 中间",
                       "文字和结果都去掉首尾空白")
    }

    func testFillWithoutPlaceholderAppendsAsNewParagraph() {
        XCTAssertEqual(AIPrompts.fill("帮我改成正式的语气", with: "明天不来了"), "帮我改成正式的语气\n\n明天不来了")
        XCTAssertEqual(AIPrompts.fill("帮我改成正式的语气", with: "   "), "帮我改成正式的语气",
                       "没有文字时只交出提示词")
        XCTAssertEqual(AIPrompts.fill("", with: "只有文字"), "只有文字")
    }

    func testOtherBracesAreLeftAlone() {
        XCTAssertEqual(AIPrompts.fill("{text} 和 {文本}", with: "x"), "{text} 和 x")
    }

    func testQuickActionsAllCarryThePlaceholder() {
        XCTAssertEqual(AIQuickAction.allCases.map(\.title), ["翻译", "总结", "润色", "解释"])
        for action in AIQuickAction.allCases {
            XCTAssertTrue(action.template.contains(AIPrompts.placeholder), action.title)
            let filled = AIPrompts.fill(action.template, with: "样例")
            XCTAssertTrue(filled.hasSuffix("样例"), action.title)
            XCTAssertFalse(filled.contains(AIPrompts.placeholder), action.title)
        }
    }

    // MARK: 文字从哪来

    func testDraftWinsOverClipboard() {
        XCTAssertEqual(AIPrompts.source(draft: " 输入框 ", clipboard: "剪贴板"), .draft("输入框"))
        XCTAssertEqual(AIPrompts.source(draft: "  \n", clipboard: " 剪贴板 "), .clipboard("剪贴板"))
        XCTAssertEqual(AIPrompts.source(draft: "", clipboard: nil), .none)
        XCTAssertEqual(AIPrompts.source(draft: "", clipboard: "  "), .none)
    }

    func testComposeUsesTheSource() {
        XCTAssertEqual(AIPrompts.compose("解释：{文本}", draft: "", clipboard: "闭包"), "解释：闭包")
        XCTAssertEqual(AIPrompts.compose("解释：{文本}", draft: "协程", clipboard: "闭包"), "解释：协程")
        XCTAssertNil(AIPrompts.compose("解释：{文本}", draft: " ", clipboard: nil))
    }

    // MARK: 常用提示词的编辑

    func testAddValidatesAndTrims() {
        var list: [AIPrompt] = []
        XCTAssertNil(AIPrompts.add(name: " 周报 ", content: " 把 {文本} 写成周报 ", id: "a", to: &list))
        XCTAssertEqual(list, [AIPrompt(id: "a", name: "周报", content: "把 {文本} 写成周报")])
        XCTAssertEqual(AIPrompts.add(name: "", content: "x", id: "b", to: &list), .emptyName)
        XCTAssertEqual(AIPrompts.add(name: "空", content: "  \n", id: "b", to: &list), .emptyContent)
        XCTAssertEqual(AIPrompts.add(name: "周报", content: "y", id: "b", to: &list), .duplicateName)
        XCTAssertEqual(AIPrompts.add(name: String(repeating: "长", count: AIPrompts.nameLimit + 1),
                                     content: "y", id: "b", to: &list), .nameTooLong)
        XCTAssertEqual(AIPrompts.add(name: "长内容", content: String(repeating: "字", count: AIPrompts.contentLimit + 1),
                                     id: "b", to: &list), .contentTooLong)
        XCTAssertEqual(list.count, 1, "出错时列表不变")
    }

    func testAddStopsAtTheLimit() {
        var list: [AIPrompt] = []
        for index in 0 ..< AIPrompts.maxCount {
            XCTAssertNil(AIPrompts.add(name: "第\(index)", content: "x", id: "\(index)", to: &list))
        }
        XCTAssertEqual(AIPrompts.add(name: "多一条", content: "x", id: "more", to: &list), .full)
        XCTAssertEqual(list.count, AIPrompts.maxCount)
    }

    func testUpdateKeepsPositionAndAllowsItsOwnName() {
        var list = [AIPrompt(id: "a", name: "甲", content: "1"), AIPrompt(id: "b", name: "乙", content: "2")]
        XCTAssertNil(AIPrompts.update("a", name: "甲", content: "改过 {文本}", in: &list), "保留自己的名字不算重名")
        XCTAssertEqual(list[0], AIPrompt(id: "a", name: "甲", content: "改过 {文本}"))
        XCTAssertEqual(AIPrompts.update("a", name: "乙", content: "x", in: &list), .duplicateName)
        XCTAssertNil(AIPrompts.update("missing", name: "丙", content: "x", in: &list))
        XCTAssertEqual(list.map(\.id), ["a", "b"])
    }

    func testRemoveAndMove() {
        var list = ["a", "b", "c"].map { AIPrompt(id: $0, name: $0, content: $0) }
        AIPrompts.move("c", by: -1, in: &list)
        XCTAssertEqual(list.map(\.id), ["a", "c", "b"])
        AIPrompts.move("a", by: -5, in: &list)
        XCTAssertEqual(list.map(\.id), ["a", "c", "b"], "到头了就停")
        AIPrompts.move("a", by: 9, in: &list)
        XCTAssertEqual(list.map(\.id), ["c", "b", "a"])
        AIPrompts.remove("b", from: &list)
        XCTAssertEqual(list.map(\.id), ["c", "a"])
    }

    func testSanitizedDropsBrokenEntries() {
        let list = [
            AIPrompt(id: "a", name: "好的", content: "内容"),
            AIPrompt(id: "", name: "没 id", content: "x"),
            AIPrompt(id: "b", name: "  ", content: "x"),
            AIPrompt(id: "c", name: "没内容", content: ""),
            AIPrompt(id: "a", name: "重复 id", content: "x"),
        ]
        XCTAssertEqual(AIPrompts.sanitized(list), [AIPrompt(id: "a", name: "好的", content: "内容")])
    }

    func testSettingsKeepPromptsAndOldFilesHaveNone() throws {
        let old = try JSONDecoder().decode(AINotchSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.prompts, [])

        var settings = AINotchSettings()
        settings.prompts = [AIPrompt(id: "a", name: "周报", content: "把 {文本} 写成周报")]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AINotchSettings.self, from: data), settings)

        let odd = #"{"prompts":[{"id":"x","name":"只有名字"},{"id":"y","name":"好","content":"内容","extra":1}]}"#
        let decoded = try JSONDecoder().decode(AINotchSettings.self, from: Data(odd.utf8))
        XCTAssertEqual(decoded.prompts, [AIPrompt(id: "y", name: "好", content: "内容")])

        let broken = #"{"enabled":false,"prompts":"不是列表"}"#
        let fallback = try JSONDecoder().decode(AINotchSettings.self, from: Data(broken.utf8))
        XCTAssertFalse(fallback.enabled, "提示词坏了不影响别的设置")
        XCTAssertEqual(fallback.prompts, [])
    }

    // MARK: 剪贴板

    func testClipboardPreviewCollapsesAndTruncates() {
        XCTAssertNil(AIClipboard.preview(nil))
        XCTAssertNil(AIClipboard.preview(" \n\t "))
        XCTAssertEqual(AIClipboard.preview("  第一行\n\n第二行  "), "第一行 第二行")
        XCTAssertEqual(AIClipboard.preview("一二三四五六", limit: 4), "一二三四…")
        XCTAssertEqual(AIClipboard.preview("一二三四", limit: 4), "一二三四")
        XCTAssertEqual(AIPrompts.preview("甲乙丙丁戊", limit: 2), "甲乙…")
    }

    func testClipboardInsert() {
        XCTAssertEqual(AIClipboard.insert(" 剪贴板 ", into: ""), "剪贴板")
        XCTAssertEqual(AIClipboard.insert("剪贴板", into: "  "), "剪贴板", "空白草稿直接换掉")
        XCTAssertEqual(AIClipboard.insert("剪贴板", into: "问题"), "问题\n剪贴板")
        XCTAssertEqual(AIClipboard.insert("剪贴板", into: "问题\n"), "问题\n剪贴板")
        XCTAssertEqual(AIClipboard.insert("   ", into: "问题"), "问题")
        XCTAssertEqual(AIClipboard.insert(nil, into: "问题"), "问题")
    }

    func testClipboardInsertIsCapped() {
        let long = String(repeating: "字", count: AIClipboard.insertLimit + 10)
        XCTAssertEqual(AIClipboard.insert(long, into: "").count, AIClipboard.insertLimit)
        XCTAssertTrue(AIClipboard.isTruncated(long))
        XCTAssertFalse(AIClipboard.isTruncated("短"))
        XCTAssertFalse(AIClipboard.isTruncated(nil))
    }

    // MARK: 输入法选字

    func testNoSubmitWhileComposing() {
        XCTAssertFalse(AIAsk.canSubmit("nihao", hasMarkedText: true))
        XCTAssertTrue(AIAsk.canSubmit("你好", hasMarkedText: false))
        XCTAssertFalse(AIAsk.canSubmit("  ", hasMarkedText: false))
    }

    // MARK: 面板回到哪块屏幕

    private let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testPanelReturnsToItsOwnScreen() {
        let screens = [left, right]
        let origin = CGPoint(x: 700, y: 120)
        let pointerOnRight = CGPoint(x: 2000, y: 500)
        XCTAssertTrue(AIPanelReturn.shouldAnswer(shelfScreen: left, origin: origin,
                                                 pointer: pointerOnRight, screens: screens),
                      "指针跑到右屏，左屏的扩展栏照样把面板开回来")
        XCTAssertFalse(AIPanelReturn.shouldAnswer(shelfScreen: right, origin: origin,
                                                  pointer: pointerOnRight, screens: screens))
    }

    func testWithoutOriginFollowsThePointer() {
        let screens = [left, right]
        let pointer = CGPoint(x: 2000, y: 500)
        XCTAssertFalse(AIPanelReturn.shouldAnswer(shelfScreen: left, origin: nil, pointer: pointer, screens: screens))
        XCTAssertTrue(AIPanelReturn.shouldAnswer(shelfScreen: right, origin: nil, pointer: pointer, screens: screens))
        XCTAssertTrue(AIPanelReturn.shouldAnswer(shelfScreen: left, origin: nil,
                                                 pointer: CGPoint(x: -50, y: -50), screens: screens),
                      "指针不在任何屏幕上时不挑")
        XCTAssertTrue(AIPanelReturn.shouldAnswer(shelfScreen: nil, origin: nil, pointer: pointer, screens: screens))
    }

    func testUnpluggedScreenFallsBackToThePointer() {
        let origin = CGPoint(x: 2000, y: 500)
        let pointer = CGPoint(x: 100, y: 100)
        XCTAssertTrue(AIPanelReturn.shouldAnswer(shelfScreen: left, origin: origin, pointer: pointer, screens: [left]))
    }
}
