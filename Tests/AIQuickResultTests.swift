import XCTest

/// Dock 提问后刘海下方的快捷结果卡片：设置默认值和旧存档、要不要弹、弹在哪、卡片多高、
/// 什么时候自动收起、标题怎么拆、字数上限、主按钮的小熊猫橙。
final class AIQuickResultTests: XCTestCase {
    // MARK: 设置

    func testSettingsDefaults() {
        let settings = AINotchSettings()
        XCTAssertEqual(settings.answerPlacement, .notch, "默认刘海优先")
        XCTAssertTrue(settings.autoShowResult, "默认提交后自动展开结果")
        XCTAssertEqual(settings.afterAnswer, .manual, "默认保持显示、手动收起")
    }

    func testOldSaveDecodesWithDefaults() throws {
        let old = try JSONDecoder().decode(AINotchSettings.self,
                                           from: Data(#"{"enabled":true,"modes":{"deepseek":"api"}}"#.utf8))
        XCTAssertEqual(old.answerPlacement, .notch)
        XCTAssertTrue(old.autoShowResult)
        XCTAssertEqual(old.afterAnswer, .manual)
        XCTAssertEqual(old.modes["deepseek"], .api, "旧的打开方式照常读")
    }

    func testUnknownValuesFallBackToDefaults() throws {
        let json = #"{"answerPlacement":"sidebar","autoShowResult":"yes","afterAnswer":"after60"}"#
        let settings = try JSONDecoder().decode(AINotchSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.answerPlacement, .notch)
        XCTAssertTrue(settings.autoShowResult)
        XCTAssertEqual(settings.afterAnswer, .manual)
    }

    func testSettingsRoundTrip() throws {
        var settings = AINotchSettings()
        settings.answerPlacement = .panel
        settings.autoShowResult = false
        settings.afterAnswer = .after30
        let back = try JSONDecoder().decode(AINotchSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back, settings)
    }

    // MARK: 自动收起

    func testCollapseSeconds() {
        XCTAssertNil(AIAutoCollapse.manual.seconds)
        XCTAssertEqual(AIAutoCollapse.after15.seconds, 15)
        XCTAssertEqual(AIAutoCollapse.after30.seconds, 30)
        XCTAssertEqual(AIAutoCollapse.allCases.count, 3)
    }

    func testCollapseOnlyCountsDownWhenDoneAndNotHeld() {
        XCTAssertEqual(AIQuickResult.collapseDelay(.after15, phase: .done, pinned: false, hovering: false), 15)
        XCTAssertNil(AIQuickResult.collapseDelay(.after15, phase: .done, pinned: false, hovering: true), "悬停时不倒计时")
        XCTAssertNil(AIQuickResult.collapseDelay(.after30, phase: .done, pinned: true, hovering: false), "固定后不收")
        XCTAssertNil(AIQuickResult.collapseDelay(.manual, phase: .done, pinned: false, hovering: false))
        XCTAssertNil(AIQuickResult.collapseDelay(.after15, phase: .answering, pinned: false, hovering: false))
        XCTAssertNil(AIQuickResult.collapseDelay(.after15, phase: .thinking, pinned: false, hovering: false))
        XCTAssertNil(AIQuickResult.collapseDelay(.after15, phase: .failed("x"), pinned: false, hovering: false),
                     "失败留着给用户重试")
    }

    func testOutsideClick() {
        XCTAssertTrue(AIQuickResult.closesOnOutsideClick(phase: .done, pinned: false))
        XCTAssertTrue(AIQuickResult.closesOnOutsideClick(phase: .failed("x"), pinned: false))
        XCTAssertFalse(AIQuickResult.closesOnOutsideClick(phase: .done, pinned: true))
        XCTAssertFalse(AIQuickResult.closesOnOutsideClick(phase: .answering, pinned: false))
        XCTAssertFalse(AIQuickResult.closesOnOutsideClick(phase: .thinking, pinned: false))
    }

    // MARK: 高度

    func testCardHeightIsClamped() {
        XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: 0), 180)
        XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: 20), 180)
        XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: 5000), 300)
        XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: .infinity), 180, "量不出来按最矮")
        XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: -10), 180)
        let mid = AIQuickResult.cardHeight(bodyHeight: 100)
        XCTAssertGreaterThan(mid, 180)
        XCTAssertLessThan(mid, 300)
        XCTAssertGreaterThan(AIQuickResult.cardHeight(bodyHeight: 100, withMascot: true), mid, "探头时头部往下让")
        XCTAssertEqual(AIQuickResult.width, 420)
    }

    func testBodyLimitFillsTheTallestCard() {
        for mascot in [false, true] {
            let limit = AIQuickResult.bodyLimit(withMascot: mascot)
            XCTAssertEqual(AIQuickResult.cardHeight(bodyHeight: limit, withMascot: mascot), 300)
            XCTAssertLessThan(AIQuickResult.cardHeight(bodyHeight: limit - 20, withMascot: mascot), 300)
        }
    }

    // MARK: 要不要弹、弹在哪

    func testOnlyAPIPopsTheCard() {
        for mode in [AIOpenMode.web, .jump] {
            XCTAssertEqual(AIQuickResult.target(mode: mode, unlocked: true, placement: .notch, autoShow: true,
                                                notchOccupied: false), .none, "\(mode) 拿不到回答，不弹")
        }
    }

    func testLockedFallsBack() {
        XCTAssertEqual(AIQuickResult.target(mode: .api, unlocked: false, placement: .notch, autoShow: true,
                                            notchOccupied: false), .none)
    }

    func testPlacementAndOccupancy() {
        XCTAssertEqual(AIQuickResult.target(mode: .api, unlocked: true, placement: .notch, autoShow: true,
                                            notchOccupied: false), .notchCard)
        XCTAssertEqual(AIQuickResult.target(mode: .api, unlocked: true, placement: .notch, autoShow: true,
                                            notchOccupied: true), .floating)
        XCTAssertEqual(AIQuickResult.target(mode: .api, unlocked: true, placement: .panel, autoShow: true,
                                            notchOccupied: false), .fullPanel, "小组件面板保持原来的做法")
        XCTAssertEqual(AIQuickResult.target(mode: .api, unlocked: true, placement: .notch, autoShow: false,
                                            notchOccupied: false), .quiet)
    }

    func testRelocateKeepsTheResult() {
        XCTAssertEqual(AIQuickResult.relocated(.notchCard, notchOccupied: true), .floating)
        XCTAssertEqual(AIQuickResult.relocated(.floating, notchOccupied: false), .notchCard)
        XCTAssertEqual(AIQuickResult.relocated(.floating, notchOccupied: true), .floating)
        XCTAssertEqual(AIQuickResult.relocated(.fullPanel, notchOccupied: true), .fullPanel)
    }

    // MARK: 阶段

    func testPhase() {
        XCTAssertEqual(AIQuickResult.phase(status: nil, text: ""), .thinking)
        XCTAssertEqual(AIQuickResult.phase(status: .streaming, text: ""), .thinking)
        XCTAssertEqual(AIQuickResult.phase(status: .streaming, text: "你"), .answering)
        XCTAssertEqual(AIQuickResult.phase(status: .done, text: "你好"), .done)
        XCTAssertEqual(AIQuickResult.phase(status: .stopped, text: "你好"), .done, "停止后留下的字算答完")
        XCTAssertEqual(AIQuickResult.phase(status: .failed("超时"), text: ""), .failed("超时"))
        if case .failed = AIQuickResult.phase(status: .stopped, text: "") {} else { XCTFail("没出字就停了算失败") }
        XCTAssertEqual(AIQuickResultPhase.done.title, "已完成")
        XCTAssertEqual(AIQuickResultPhase.thinking.title, "正在思考")
        XCTAssertEqual(AIQuickResultPhase.answering.title, "正在回答")
        XCTAssertEqual(AIQuickResultPhase.failed("x").title, "失败")
    }

    // MARK: 标题

    func testSplitTitle() {
        XCTAssertEqual(AIQuickResult.splitTitle("# 产品介绍优化结果\n让复杂的工作变简单。").title, "产品介绍优化结果")
        XCTAssertEqual(AIQuickResult.splitTitle("**产品介绍优化结果**\n让复杂的工作变简单。").title, "产品介绍优化结果")
        let plain = AIQuickResult.splitTitle("产品介绍优化结果\n让复杂的工作变简单。")
        XCTAssertEqual(plain.title, "产品介绍优化结果")
        XCTAssertEqual(plain.body, "让复杂的工作变简单。")
        XCTAssertNil(AIQuickResult.splitTitle("只有一行。").title)
        XCTAssertNil(AIQuickResult.splitTitle("第一句话就结束了。\n第二段").title, "带句号的不当标题")
        XCTAssertNil(AIQuickResult.splitTitle("- 列表一\n- 列表二").title)
        XCTAssertNil(AIQuickResult.splitTitle("```swift\nlet a = 1\n```").title)
        XCTAssertNil(AIQuickResult.splitTitle(String(repeating: "长", count: 40) + "\n正文").title)
    }

    // MARK: 位置

    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let bar = CGRect(x: 0, y: 950, width: 1512, height: 32)
    private let notchEntry = CGRect(x: 663, y: 950, width: 185, height: 32)

    func testNotchCardHangsUnderTheNotchCentered() {
        let card = AIQuickResult.notchFrame(below: notchEntry, screen: laptop, height: 200, avoiding: [])
        XCTAssertEqual(card.size, CGSize(width: 420, height: 200))
        XCTAssertEqual(card.midX, notchEntry.midX, accuracy: 0.5, "顶部居中对着刘海")
        XCTAssertLessThanOrEqual(card.maxY, bar.minY, "不盖菜单栏")
        let window = AIQuickResult.windowFrame(card: card, withMascot: true)
        XCTAssertEqual(window.maxY, bar.minY, accuracy: 0.5, "探头那一截正好接到刘海下沿")
        XCTAssertEqual(AIQuickResult.windowFrame(card: card, withMascot: false), card)
    }

    func testNotchCardClearsAnIsland() {
        let island = CGRect(x: 600, y: 860, width: 312, height: 122)
        let card = AIQuickResult.notchFrame(below: notchEntry, screen: laptop, height: 220, avoiding: [island])
        XCTAssertLessThanOrEqual(card.maxY, island.minY, "不盖住小岛")
    }

    func testFloatingGoesTopRightOrUnderTheIsland() {
        let corner = AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200, blockers: [])
        XCTAssertEqual(corner.maxX, laptop.maxX - AIQuickResult.margin, "右上角")
        XCTAssertLessThanOrEqual(corner.maxY, bar.minY)
        XCTAssertGreaterThan(corner.minX, notchEntry.maxX, "不盖刘海那一段")
        let island = CGRect(x: 600, y: 860, width: 312, height: 122)
        let under = AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200,
                                                blockers: [island])
        XCTAssertLessThanOrEqual(under.maxY, island.minY, "小岛下方")
        let elsewhere = CGRect(x: 3000, y: 860, width: 312, height: 122)
        XCTAssertEqual(AIQuickResult.floatingFrame(screen: laptop, menuBar: bar, entry: notchEntry, height: 200,
                                                   blockers: [elsewhere]), corner, "别的屏幕上的小岛不管")
    }

    // MARK: 字数

    func testAskLimit() {
        XCTAssertEqual(AIAskLimit.label("帮我优化一下这段产品介绍，让它更有吸引力。"), "21 / 2000")
        XCTAssertTrue(AIAskLimit.withinLimit(String(repeating: "字", count: 2000)))
        XCTAssertFalse(AIAskLimit.withinLimit(String(repeating: "字", count: 2001)))
        XCTAssertEqual(AIAskLimit.label(""), "0 / 2000")
    }

    // MARK: 小组件底栏

    func testShortChipAndButtonTitles() {
        XCTAssertEqual(AIDockChip.clipboardSummary.title, "剪贴板")
        XCTAssertEqual(AIAsk.buttonTitle(mode: .api, service: nil, appInstalled: false), "提问")
        XCTAssertEqual(AIAnswerPlacement.notch.shortTitle, "刘海")
    }

    /// 主按钮的小熊猫橙：原色白字不到 4.5，按 `PanelButtonLook.solid` 同色相加深后白字够 4.5，不改深色字。
    func testRedPandaButtonIsReadable() throws {
        let orange = try XCTUnwrap(ColorCode(hex: ShelfColor.redPanda.hex))
        let look = PanelButtonLook.solid(for: orange)
        XCTAssertGreaterThanOrEqual(look.contrast, 4.5)
        XCTAssertFalse(look.inkIsDark, "白字")
        XCTAssertGreaterThanOrEqual(look.pressedContrast, 4.5)
    }
}
