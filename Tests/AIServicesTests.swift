import XCTest

/// AI 助手的纯逻辑：内置服务、显示哪些、默认服务、自定义服务、提问方式和卡片尺寸。
final class AIServicesTests: XCTestCase {

    private func config(_ values: [String: WidgetConfig.Value] = [:]) -> WidgetConfig {
        WidgetConfig(values)
    }

    private func ids(_ config: WidgetConfig) -> [String] {
        AIServices.enabled(in: config).map(\.id)
    }

    // MARK: 内置服务

    func testBuiltInsAreTheElevenPlannedServices() {
        XCTAssertEqual(AIServices.builtIn.map(\.title),
                       ["豆包", "DeepSeek", "Kimi", "通义", "元宝", "文心", "智谱清言",
                        "ChatGPT", "Gemini", "Perplexity", "Grok"])
        XCTAssertEqual(AIServices.builtIn.filter { $0.region == .domestic }.count, 7)
        XCTAssertEqual(AIServices.builtIn.filter { $0.region == .overseas }.count, 4)
    }

    func testBuiltInsHaveUniqueIDsTitlesAndInitials() {
        let all = AIServices.builtIn
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.title)).count, all.count)
        XCTAssertEqual(Set(all.map(\.initial)).count, all.count, "两块字牌长得一样就分不清了")
        for service in all {
            XCTAssertFalse(service.isCustom, service.id)
            XCTAssertFalse(service.initial.isEmpty, service.id)
            XCTAssertLessThanOrEqual(service.initial.count, 2, service.id)
        }
    }

    func testEveryBuiltInHasAnHTTPSHomePage() {
        for service in AIServices.builtIn {
            let url = try? XCTUnwrap(service.homeURL, service.id)
            XCTAssertEqual(url?.scheme, "https", service.id)
        }
    }

    /// 只有核实过官方支持的两家带提问模板。
    func testOnlyVerifiedServicesCarryAnAskTemplate() {
        let asking = AIServices.builtIn.filter(\.supportsAsk).map(\.id)
        XCTAssertEqual(asking, ["chatgpt", "perplexity"])
        for service in AIServices.builtIn {
            if let template = service.askTemplate {
                XCTAssertTrue(template.hasPrefix("https://"), service.id)
                XCTAssertTrue(template.contains("%s"), service.id)
            }
        }
    }

    // MARK: 显示哪些

    func testANewWidgetShowsDeepSeekKimiAndDoubaoWithDeepSeekAsDefault() {
        let fresh = WidgetCatalog.make(.aiAssistant)!.config
        XCTAssertEqual(ids(fresh), ["deepseek", "kimi", "doubao"])
        XCTAssertEqual(AIServices.defaultService(in: fresh)?.id, "deepseek")
    }

    func testResolveDedupsSkipsUnknownAndKeepsOrder() {
        let resolved = AIServices.resolve(ids: ["kimi", "nope", "kimi", "grok", "custom-gone"], custom: [])
        XCTAssertEqual(resolved.map(\.id), ["kimi", "grok"])
    }

    func testResolveStopsAtTheMaximum() {
        var many = AIServices.builtIn.map(\.id)
        let extra = (0 ..< 5).map { i in
            AIService(id: "custom-\(i)", title: "自定义\(i)", initial: "\(i)", region: .domestic,
                      home: "https://example\(i).com")
        }
        many += extra.map(\.id)
        XCTAssertEqual(AIServices.resolve(ids: many, custom: extra).count, AIServices.maxCount)
    }

    func testCorruptOrWrongTypedConfigFallsBackToDefaults() {
        XCTAssertEqual(ids(config([AIServices.servicesKey: .string("deepseek,kimi")])), AIServices.defaultIDs)
        XCTAssertEqual(ids(config([AIServices.servicesKey: .number(3)])), AIServices.defaultIDs)
        XCTAssertEqual(ids(config([AIServices.servicesKey: .list([.number(1), .bool(true)])])), AIServices.defaultIDs)
        XCTAssertEqual(ids(config([AIServices.servicesKey: .list([.string("old-model")])])), AIServices.defaultIDs)
        XCTAssertEqual(AIServices.decode("{not json"), [])
        XCTAssertEqual(AIServices.decode(""), [])
    }

    func testHidingEverythingLeavesTheCardEmptyRatherThanRestoringDefaults() {
        var c = config()
        for id in AIServices.defaultIDs { AIServices.hide(id, in: &c) }
        XCTAssertEqual(ids(c), [])
        XCTAssertNil(AIServices.defaultService(in: c))
        XCTAssertEqual(AIServices.tileWidth(count: 0, square: false), 123)
    }

    func testToggleShowsAndHides() {
        var c = config()
        AIServices.toggle("chatgpt", in: &c)
        XCTAssertEqual(ids(c), ["deepseek", "kimi", "doubao", "chatgpt"])
        AIServices.toggle("kimi", in: &c)
        XCTAssertEqual(ids(c), ["deepseek", "doubao", "chatgpt"])
        AIServices.toggle("not-a-service", in: &c)
        XCTAssertEqual(ids(c), ["deepseek", "doubao", "chatgpt"])
    }

    func testShowStopsAtTheMaximum() {
        var c = config()
        for service in AIServices.builtIn { AIServices.show(service.id, in: &c) }
        XCTAssertEqual(ids(c).count, AIServices.builtIn.count)
        let extra = (0 ..< 3).compactMap { i -> AIService? in
            try? AIServices.custom(title: "站\(i)", address: "site\(i).example.com", id: "x\(i)").get()
        }
        for service in extra { AIServices.addCustom(service, in: &c) }
        XCTAssertEqual(ids(c).count, AIServices.maxCount)
        XCTAssertEqual(AIServices.custom(in: c).count, 3, "满了也照样保存，只是不上卡片")
    }

    // MARK: 默认服务

    func testSetDefaultAndMove() {
        var c = config()
        AIServices.setDefault("kimi", in: &c)
        XCTAssertEqual(AIServices.defaultService(in: c)?.id, "kimi")
        AIServices.move("kimi", by: -1, in: &c)
        XCTAssertEqual(ids(c), ["kimi", "deepseek", "doubao"])
        AIServices.move("kimi", by: -1, in: &c)
        XCTAssertEqual(ids(c), ["kimi", "deepseek", "doubao"], "到头了不动")
        XCTAssertFalse(AIServices.canMove("kimi", by: -1, in: c))
        XCTAssertTrue(AIServices.canMove("kimi", by: 1, in: c))
        AIServices.move("doubao", by: 1, in: &c)
        XCTAssertEqual(ids(c), ["kimi", "deepseek", "doubao"])
        AIServices.setDefault("grok", in: &c)
        XCTAssertEqual(AIServices.defaultService(in: c)?.id, "kimi", "不在卡片上的不能当默认")
    }

    func testHidingTheDefaultMovesItToTheFirstRemaining() {
        var c = config()
        AIServices.move("deepseek", by: 1, in: &c)
        XCTAssertEqual(ids(c), ["kimi", "deepseek", "doubao"])
        AIServices.hide("deepseek", in: &c)
        XCTAssertEqual(AIServices.defaultService(in: c)?.id, "kimi")
        XCTAssertEqual(c.string(AIServices.defaultKey), "kimi")
    }

    func testAStaleSavedDefaultFallsBackWithoutCrashing() {
        let c = config([AIServices.defaultKey: .string("gone"),
                        AIServices.servicesKey: .list([.string("kimi"), .string("grok")])])
        XCTAssertEqual(AIServices.defaultService(in: c)?.id, "kimi")
    }

    // MARK: 自定义服务

    func testCustomNeedsANameAndAValidAddressOrAnApp() {
        XCTAssertEqual(AIServices.custom(title: " ", address: "https://metaso.cn", id: "a"), .failure(.emptyName))
        XCTAssertEqual(AIServices.custom(title: "秘塔", address: "", id: "a"), .failure(.missingTarget))
        XCTAssertEqual(AIServices.custom(title: "秘塔", address: "ftp://metaso.cn", id: "a"), .failure(.invalidAddress))
        XCTAssertEqual(AIServices.custom(title: "秘塔", address: "meta so.cn", id: "a"), .failure(.invalidAddress))
        XCTAssertEqual(AIServices.custom(title: "秘塔", address: "notahost", id: "a"), .failure(.invalidAddress))

        let site = try? AIServices.custom(title: "秘塔", address: "metaso.cn", id: "a1").get()
        XCTAssertEqual(site?.id, "custom-a1")
        XCTAssertEqual(site?.home, "https://metaso.cn")
        XCTAssertEqual(site?.initial, "秘")
        XCTAssertNil(site?.askTemplate, "自定义服务不带提问模板，一律复制再打开")

        let app = try? AIServices.custom(title: "Claude", address: "", appPath: "/Applications/Claude.app",
                                         appBundleID: "com.example.claude", id: "b1").get()
        XCTAssertEqual(app?.appPath, "/Applications/Claude.app")
        XCTAssertEqual(app?.home, "")
        XCTAssertEqual(app?.initial, "C")
    }

    func testCustomRejectsDuplicates() {
        XCTAssertEqual(AIServices.custom(title: "kimi", address: "https://k.example.com", id: "a"),
                       .failure(.duplicateName))
        XCTAssertEqual(AIServices.custom(title: "我的 DS", address: "http://chat.deepseek.com", id: "a"),
                       .failure(.duplicateAddress))
        XCTAssertEqual(AIServices.custom(title: "豆包二号", address: "doubao.com/chat", id: "a"),
                       .failure(.duplicateAddress), "不看协议、www. 和末尾的斜杠")

        var c = config()
        let first = try! AIServices.custom(title: "秘塔", address: "metaso.cn", id: "a1").get()
        XCTAssertNil(AIServices.addCustom(first, in: &c))
        XCTAssertEqual(ids(c).last, "custom-a1")
        let again = try! AIServices.custom(title: "秘塔搜索", address: "https://metaso.cn/", id: "a2").get()
        XCTAssertEqual(AIServices.addCustom(again, in: &c), .duplicateAddress)
        XCTAssertEqual(AIServices.custom(title: "秘塔", address: "other.example.com", id: "a3",
                                         existing: AIServices.all(in: c)), .failure(.duplicateName))
    }

    func testCustomServicesRoundTripThroughTheConfig() throws {
        var c = config()
        let site = try AIServices.custom(title: "秘塔", address: "metaso.cn", id: "a1").get()
        AIServices.addCustom(site, in: &c)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(WidgetConfig.self, from: data)
        XCTAssertEqual(AIServices.custom(in: back), [site])
        XCTAssertEqual(ids(back), ["deepseek", "kimi", "doubao", "custom-a1"])

        AIServices.removeCustom("custom-a1", in: &c)
        XCTAssertEqual(AIServices.custom(in: c), [])
        XCTAssertEqual(ids(c), ["deepseek", "kimi", "doubao"])
        AIServices.removeCustom("kimi", in: &c)
        XCTAssertEqual(ids(c), ["deepseek", "kimi", "doubao"], "内置的只能隐藏，不能删")
    }

    func testABrokenCustomListIsKeptBeforeItIsOverwritten() throws {
        var c = config([AIServices.customKey: .string("{broken")])
        XCTAssertEqual(AIServices.custom(in: c), [])
        let site = try AIServices.custom(title: "秘塔", address: "metaso.cn", id: "a1").get()
        AIServices.addCustom(site, in: &c)
        XCTAssertEqual(c.string(AIServices.brokenCustomKey), "{broken")
        XCTAssertEqual(AIServices.custom(in: c), [site])
    }

    func testDecodeDropsBuiltInLookalikesAndDuplicates() {
        let fake = AIService(id: "deepseek", title: "假", initial: "假", region: .domestic, home: "https://x.example.com")
        let ok = AIService(id: "custom-1", title: "一", initial: "一", region: .domestic, home: "https://one.example.com")
        let empty = AIService(id: "custom-2", title: "空", initial: "空", region: .domestic, home: "")
        XCTAssertEqual(AIServices.decode(AIServices.encode([fake, ok, ok, empty])), [ok])
    }

    // MARK: 提问

    func testReturnKey() {
        XCTAssertEqual(AIAsk.returnAction(shift: false, hasMarkedText: false), .submit)
        XCTAssertEqual(AIAsk.returnAction(shift: true, hasMarkedText: false), .newline)
        XCTAssertEqual(AIAsk.returnAction(shift: false, option: true, hasMarkedText: false), .newline)
        XCTAssertEqual(AIAsk.returnAction(shift: false, hasMarkedText: true), .passThrough,
                       "中文输入法选字时的回车只确认选字")
        XCTAssertEqual(AIAsk.returnAction(shift: true, hasMarkedText: true), .passThrough)
    }

    func testBlankQuestionsAreBlocked() {
        let deepseek = AIServices.builtIn("deepseek")!
        XCTAssertNil(AIAsk.question("  \n\t "))
        XCTAssertEqual(AIAsk.plan("   ", service: deepseek), .blocked)
        XCTAssertEqual(AIAsk.question("  你好 \n"), "你好")
    }

    func testServicesWithATemplateOpenWithTheQuestion() throws {
        let chatgpt = try XCTUnwrap(AIServices.builtIn("chatgpt"))
        guard case .openWithQuestion(let url) = AIAsk.plan(" 什么是 a&b?\n第二行 ", service: chatgpt) else {
            return XCTFail("ChatGPT 应该带问题打开")
        }
        XCTAssertTrue(url.absoluteString.hasPrefix("https://chatgpt.com/?q="))
        XCTAssertFalse(url.absoluteString.contains("&b"), "& 要编码，不然问题被截断")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }
        XCTAssertEqual(query?.value, "什么是 a&b?\n第二行")
        XCTAssertEqual(AIAsk.buttonTitle(for: chatgpt), "打开并提问")

        let perplexity = try XCTUnwrap(AIServices.builtIn("perplexity"))
        guard case .openWithQuestion(let p) = AIAsk.plan("swift", service: perplexity) else {
            return XCTFail("Perplexity 应该带问题打开")
        }
        XCTAssertEqual(p.absoluteString, "https://www.perplexity.ai/search?q=swift")
    }

    func testServicesWithoutATemplateCopyThenOpen() throws {
        let deepseek = try XCTUnwrap(AIServices.builtIn("deepseek"))
        XCTAssertEqual(AIAsk.plan("  你好  ", service: deepseek), .copyThenOpen("你好"))
        XCTAssertEqual(AIAsk.buttonTitle(for: deepseek), "复制问题并打开")
        XCTAssertEqual(AIAsk.buttonTitle(for: nil), "复制问题并打开")
        XCTAssertEqual(AIAsk.hint(after: .copyThenOpen("你好"), service: deepseek), "已复制，到 DeepSeek 里粘贴即可。")
    }

    func testAVeryLongQuestionIsCopiedInsteadOfStuffedIntoAURL() throws {
        let chatgpt = try XCTUnwrap(AIServices.builtIn("chatgpt"))
        let long = String(repeating: "很长的问题", count: 400)
        XCTAssertEqual(AIAsk.plan(long, service: chatgpt), .copyThenOpen(long))
    }

    func testHintsNeverClaimTheQuestionWasSentOrAnswered() {
        let services = AIServices.builtIn
        for service in services {
            let plans: [AIAsk.Plan] = [.blocked, .copyThenOpen("x"),
                                       .openWithQuestion(URL(string: "https://example.com")!)]
            for plan in plans {
                let hint = AIAsk.hint(after: plan, service: service) ?? ""
                XCTAssertFalse(hint.contains("已发送"), hint)
                XCTAssertFalse(hint.contains("已回答"), hint)
                XCTAssertFalse(hint.contains("回答如下"), hint)
            }
        }
    }

    // MARK: 卡片

    func testTheCardGrowsWithTheServices() {
        XCTAssertEqual(AIServices.tileWidth(count: 1, square: false), 124)
        XCTAssertEqual(AIServices.tileWidth(count: 3, square: false), 182)
        XCTAssertLessThan(AIServices.tileWidth(count: 3, square: false), AIServices.tileWidth(count: 5, square: false))
        XCTAssertEqual(AIServices.tileWidth(count: 40, square: false),
                       AIServices.tileWidth(count: AIServices.maxCount, square: false))
        XCTAssertEqual(AIServices.tileWidth(count: 1, square: true), AIServices.tileWidth(count: 9, square: true))
        XCTAssertEqual(AIServices.visibleCount(9, square: true, vertical: false), AIServices.squareVisible)
    }

    func testCatalogSizesFollowTheConfig() {
        var widget = WidgetCatalog.make(.aiAssistant)!
        let three = WidgetCatalog.naturalSize(widget).width
        AIServices.show("chatgpt", in: &widget.config)
        AIServices.show("gemini", in: &widget.config)
        XCTAssertGreaterThan(WidgetCatalog.naturalSize(widget).width, three)
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(widget), 76)

        var square = WidgetCatalog.make(.aiAssistant, overrides: ["layout": .string(AIServices.squareLayout)])!
        XCTAssertEqual(WidgetCatalog.naturalSize(square).width, 108)
        AIServices.show("grok", in: &square.config)
        XCTAssertEqual(WidgetCatalog.naturalSize(square).width, 108)
    }

    func testCatalogEntry() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.aiAssistant))
        XCTAssertEqual(entry.name, "AI 助手")
        XCTAssertEqual(entry.category, .tools)
        XCTAssertEqual(WidgetKind.aiAssistant.rawValue, "ai-assistant")
        XCTAssertNil(WidgetCatalog.openTarget(.aiAssistant), "点卡片打开面板")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.aiAssistant), [], "字牌在卡片和面板里管，不进设置页")
        for query in ["AI 助手", "ai", "deepseek", "豆包", "提问", "zhushou"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: [entry.name], kind: "ai-assistant"), query)
        }
    }
}
