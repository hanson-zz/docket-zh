import XCTest

/// 刘海对话的纯逻辑：打开方式、接口地址、请求体、SSE 解析、出错提示、
/// 上下文裁剪、回答排版、网页模式的小判断和设置的读写。
final class AIChatTests: XCTestCase {

    private func service(_ id: String) -> AIService { AIServices.builtIn(id)! }

    private let custom = AIService(id: "custom-abc", title: "秘塔", initial: "秘", region: .domestic,
                                   home: "https://metaso.cn")
    private let customAppOnly = AIService(id: "custom-app", title: "某 App", initial: "某", region: .domestic,
                                          home: "", appPath: "/Applications/X.app")

    // MARK: 打开方式

    func testBuiltInsDefaultToWebAndCustomToJump() {
        for item in AIServices.builtIn {
            XCTAssertEqual(AIOpenModes.defaultMode(item), .web, item.id)
            XCTAssertEqual(AIOpenModes.mode(for: item, settings: AINotchSettings(), hasKey: false), .web, item.id)
        }
        XCTAssertEqual(AIOpenModes.defaultMode(custom), .jump)
        XCTAssertEqual(AIOpenModes.mode(for: customAppOnly, settings: AINotchSettings(), hasKey: false), .jump)
    }

    func testAPIOnlyWithAKeyAndACompleteEndpoint() {
        var settings = AINotchSettings()
        settings.modes["deepseek"] = .api
        XCTAssertEqual(AIOpenModes.mode(for: service("deepseek"), settings: settings, hasKey: false), .web,
                       "没填密钥时退回网页")
        XCTAssertEqual(AIOpenModes.mode(for: service("deepseek"), settings: settings, hasKey: true), .api)

        settings.modes["doubao"] = .api
        XCTAssertEqual(AIOpenModes.mode(for: service("doubao"), settings: settings, hasKey: true), .web,
                       "豆包没填接入点 ID 不能用 API")
        settings.endpoints["doubao"] = AIEndpoint(model: "ep-2026")
        XCTAssertEqual(AIOpenModes.mode(for: service("doubao"), settings: settings, hasKey: true), .api)

        settings.modes["gemini"] = .api
        XCTAssertEqual(AIOpenModes.mode(for: service("gemini"), settings: settings, hasKey: true), .web,
                       "没有默认接口的服务要自己填地址和模型")
    }

    func testCustomServiceCanUseItsOwnChatEndpoint() {
        var settings = AINotchSettings()
        settings.modes[custom.id] = .api
        settings.endpoints[custom.id] = AIEndpoint(baseURL: "https://api.example.com/v1", model: "m1")
        XCTAssertEqual(AIOpenModes.mode(for: custom, settings: settings, hasKey: true), .api)
        XCTAssertTrue(AIOpenModes.available(for: custom, settings: settings, hasKey: true).contains(.api))
        XCTAssertEqual(AIOpenModes.available(for: customAppOnly, settings: AINotchSettings(), hasKey: false), [.jump])
    }

    func testWebWithoutAnAddressFallsBackToJump() {
        var settings = AINotchSettings()
        settings.modes[customAppOnly.id] = .web
        XCTAssertEqual(AIOpenModes.mode(for: customAppOnly, settings: settings, hasKey: false), .jump)
    }

    func testModeLabels() {
        XCTAssertEqual(AIOpenModes.label(.api, model: "deepseek-chat"), "API · deepseek-chat")
        XCTAssertEqual(AIOpenModes.label(.api, model: " "), "API")
        XCTAssertEqual(AIOpenModes.label(.web), "网页 · 你的账号")
        XCTAssertTrue(AIOpenModes.label(.jump).hasPrefix("App"))
        XCTAssertEqual(AIOpenMode.jump.title, "App", "原来的「跳转」改名 App，存的值仍是 jump")
    }

    // MARK: 接口

    func testDefaultEndpoints() {
        XCTAssertEqual(AIEndpoints.resolved("deepseek", override: nil),
                       AIEndpoint(baseURL: "https://api.deepseek.com", model: "deepseek-flash"))
        XCTAssertEqual(AIEndpoints.resolved("tongyi", override: nil)?.model, "qwen-plus")
        XCTAssertEqual(AIEndpoints.resolved("zhipu", override: nil)?.model, "glm-4.7-flash")
        XCTAssertEqual(AIEndpoints.resolved("kimi", override: nil)?.model, "kimi-k2.6", "moonshot-v1 已下线")
        XCTAssertEqual(AIEndpoints.resolved("chatgpt", override: nil)?.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(AIEndpoints.resolved("kimi", override: nil)?.baseURL, "https://api.moonshot.cn/v1")
        XCTAssertNil(AIEndpoints.resolved("doubao", override: nil))
        XCTAssertTrue(AIEndpoints.requiresModel("doubao"))
    }

    func testOverridesWinAndBlankFieldsKeepTheDefault() {
        let resolved = AIEndpoints.resolved("deepseek", override: AIEndpoint(baseURL: "  ", model: "deepseek-reasoner"))
        XCTAssertEqual(resolved, AIEndpoint(baseURL: "https://api.deepseek.com", model: "deepseek-reasoner"))
        XCTAssertNil(AIEndpoints.resolved("deepseek", override: AIEndpoint(baseURL: "ftp://x.com", model: "")))
    }

    func testChatURL() {
        XCTAssertEqual(AIEndpoints.chatURL(base: "https://api.deepseek.com")?.absoluteString,
                       "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(AIEndpoints.chatURL(base: "https://api.openai.com/v1/")?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(AIEndpoints.chatURL(base: "https://x.com/v1/chat/completions")?.absoluteString,
                       "https://x.com/v1/chat/completions")
        XCTAssertEqual(AIEndpoints.chatURL(base: "http://localhost:11434/v1")?.absoluteString,
                       "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(AIEndpoints.chatURL(base: "http://api.example.com/v1"), "外网只收 https")
        XCTAssertNil(AIEndpoints.chatURL(base: "javascript:alert(1)"))
        XCTAssertNil(AIEndpoints.chatURL(base: "https://user@x.com/v1"))
        XCTAssertNil(AIEndpoints.chatURL(base: ""))
    }

    // MARK: 请求

    func testRequestBodyIsOpenAICompatibleAndStreams() throws {
        let history = [AIChatMessage(role: .user, text: "你好"),
                       AIChatMessage(role: .assistant, text: "你好！"),
                       AIChatMessage(role: .user, text: "再说一句")]
        let data = AIChatRequest.body(model: "deepseek-chat", history: history)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "deepseek-chat")
        XCTAssertEqual(object["stream"] as? Bool, true)
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "你好"],
                                  ["role": "assistant", "content": "你好！"],
                                  ["role": "user", "content": "再说一句"]])
    }

    func testURLRequestCarriesTheKeyOnlyInTheHeader() throws {
        let request = try XCTUnwrap(AIChatRequest.urlRequest(
            endpoint: AIEndpoint(baseURL: "https://api.deepseek.com", model: "deepseek-chat"),
            key: " sk-secret \n", history: [AIChatMessage(role: .user, text: "hi")]))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertFalse(request.url!.absoluteString.contains("sk-secret"))
        XCTAssertFalse(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("sk-secret"))
        XCTAssertNil(AIChatRequest.urlRequest(endpoint: AIEndpoint(baseURL: "nope", model: "m"), key: "k", history: []))
    }

    // MARK: SSE

    func testParsesDeltasCommentsAndDone() {
        var parser = AISSEParser()
        var events: [AISSEEvent] = []
        events += parser.feed(line: ": keep-alive")
        events += parser.feed(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#)
        events += parser.feed(line: "")
        events += parser.feed(line: #"data: {"choices":[{"delta":{"content":"你"}}]}"#)
        events += parser.feed(line: #"data:{"choices":[{"delta":{"content":"好"}}]}"#)
        events += parser.feed(line: "event: message")
        events += parser.feed(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
        events += parser.feed(line: "data: [DONE]")
        XCTAssertEqual(events, [.delta("你"), .delta("好"), .done])
    }

    func testChunksSplitAnywhereAndCRLF() {
        let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"**粗\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"体**\"}}]}\r\n\r\ndata: [DONE]\r\n\r\n"
        var parser = AISSEParser()
        var events: [AISSEEvent] = []
        var index = stream.startIndex
        // 每次喂 7 个字符，把 JSON 和换行都切开。
        while index < stream.endIndex {
            let end = stream.index(index, offsetBy: 7, limitedBy: stream.endIndex) ?? stream.endIndex
            events += parser.feed(chunk: String(stream[index ..< end]))
            index = end
        }
        events += parser.finish()
        XCTAssertEqual(events, [.delta("**粗"), .delta("体**"), .done])
    }

    func testMultiLineDataIsJoinedAtTheBlankLine() {
        var parser = AISSEParser()
        var events = parser.feed(line: #"data: {"choices":[{"delta":"#)
        events += parser.feed(line: #"data: {"content":"拼起来"}}]}"#)
        events += parser.feed(line: "")
        XCTAssertEqual(events, [.delta("拼起来")])
    }

    func testErrorInsideTheStream() {
        var parser = AISSEParser()
        let events = parser.feed(line: #"data: {"error":{"message":"Insufficient Balance","type":"x"}}"#)
        XCTAssertEqual(events, [.failure("Insufficient Balance")])
    }

    func testWholeJSONReplyWhenTheServerDoesNotStream() {
        let body = Data(#"{"choices":[{"message":{"role":"assistant","content":"整段回答"}}]}"#.utf8)
        XCTAssertEqual(AISSEParser.completeReply(body), "整段回答")
        XCTAssertNil(AISSEParser.completeReply(Data("{}".utf8)))
    }

    // MARK: 出错

    func testStatusCodesMapToChineseHints() {
        XCTAssertTrue(AIChatFailure.http(status: 401, message: nil).message.contains("密钥"))
        XCTAssertTrue(AIChatFailure.http(status: 429, message: nil).message.contains("太频繁"))
        XCTAssertTrue(AIChatFailure.http(status: 402, message: nil).message.contains("余额"))
        XCTAssertTrue(AIChatFailure.http(status: 404, message: nil).message.contains("模型名"))
        XCTAssertTrue(AIChatFailure.http(status: 503, message: nil).message.contains("503"))
        let rejected = AIChatFailure.http(status: 400, body: Data(#"{"error":{"message":"bad model"}}"#.utf8))
        XCTAssertEqual(rejected, .http(status: 400, message: "bad model"))
        XCTAssertTrue(rejected.message.contains("bad model"))
        XCTAssertEqual(AIChatFailure.http(status: 500, body: Data("<html>".utf8)), .http(status: 500, message: nil))
    }

    func testNetworkErrors() {
        XCTAssertEqual(AIChatFailure.network(code: URLError.Code.timedOut.rawValue), .timeout)
        XCTAssertTrue(AIChatFailure.timeout.message.contains("60 秒"))
        XCTAssertEqual(AIChatFailure.network(code: URLError.Code.notConnectedToInternet.rawValue), .offline)
        XCTAssertEqual(AIChatFailure.network(code: URLError.Code.cannotFindHost.rawValue), .cannotConnect)
        XCTAssertEqual(AIChatFailure.network(code: URLError.Code.secureConnectionFailed.rawValue), .secureConnection)
        XCTAssertNil(AIChatFailure.network(code: URLError.Code.cancelled.rawValue), "停止生成不算出错")
    }

    func testLongServerMessagesAreShortened() {
        let long = String(repeating: "错", count: 500)
        XCTAssertLessThan(AIChatFailure.stream(long).message.count, 200)
    }

    // MARK: 上下文

    func testHistoryKeepsTheLastTwentyAndStartsWithAQuestion() {
        var messages: [AIChatMessage] = []
        for index in 0 ..< 15 {
            messages.append(AIChatMessage(role: .user, text: "问\(index)"))
            messages.append(AIChatMessage(role: .assistant, text: "答\(index)"))
        }
        messages.append(AIChatMessage(role: .user, text: "最后一问"))
        let history = AIChatContext.history(messages)
        XCTAssertLessThanOrEqual(history.count, 20)
        XCTAssertEqual(history.first?.role, .user)
        XCTAssertEqual(history.last?.text, "最后一问")
    }

    func testHistoryDropsFailedAndEmptyAnswers() {
        let messages = [AIChatMessage(role: .user, text: "一"),
                        AIChatMessage(role: .assistant, text: "", status: .failed("401")),
                        AIChatMessage(role: .assistant, text: "半句", status: .failed("超时")),
                        AIChatMessage(role: .user, text: "二"),
                        AIChatMessage(role: .assistant, text: "  ", status: .stopped)]
        XCTAssertEqual(AIChatContext.history(messages).map(\.text), ["一", "二"])
    }

    // MARK: 排版

    func testMarkdownBlocks() {
        let text = "看这个：\n**重点**\n```swift\nlet a = 1\n  let b = 2\n```\n完了"
        XCTAssertEqual(AIMarkdown.blocks(text), [
            .text("看这个：\n**重点**"),
            .code(language: "swift", body: "let a = 1\n  let b = 2"),
            .text("完了"),
        ])
    }

    func testUnfinishedFenceWhileStreamingIsStillCode() {
        XCTAssertEqual(AIMarkdown.blocks("代码：\n```\nprint(1)"),
                       [.text("代码："), .code(language: "", body: "print(1)")])
        XCTAssertEqual(AIMarkdown.blocks(""), [])
    }

    // MARK: 网页

    func testGoogleSignInIsDetected() {
        XCTAssertTrue(AIWeb.isGoogleSignIn(URL(string: "https://accounts.google.com/v3/signin/identifier?x=1")))
        XCTAssertFalse(AIWeb.isGoogleSignIn(URL(string: "https://gemini.google.com/app")))
        XCTAssertFalse(AIWeb.isGoogleSignIn(nil))
        XCTAssertTrue(AIWeb.googleWarning.contains("用浏览器打开"))
    }

    func testNewWindowsStayOnTheSameSiteOrGoToTheBrowser() {
        let home = URL(string: "https://chatgpt.com/")
        XCTAssertEqual(AIWeb.newWindowTarget(URL(string: "https://auth.openai.com/log-in"), home: home), .sameView)
        XCTAssertEqual(AIWeb.newWindowTarget(URL(string: "https://cdn.chatgpt.com/x"), home: home), .sameView)
        XCTAssertEqual(AIWeb.newWindowTarget(URL(string: "https://en.wikipedia.org/wiki/X"), home: home), .browser)
        XCTAssertEqual(AIWeb.newWindowTarget(URL(string: "mailto:a@b.com"), home: home), .ignore)
        XCTAssertEqual(AIWeb.newWindowTarget(URL(string: "https://passport.baidu.com/"),
                                             home: URL(string: "https://wenxin.baidu.com/")), .sameView)
        XCTAssertEqual(AIWeb.siteKey("www.doubao.com.cn"), "doubao.com.cn")
    }

    func testUserAgentIsDesktopSafari() {
        XCTAssertTrue(AIWeb.userAgent.contains("Macintosh"))
        XCTAssertTrue(AIWeb.userAgent.contains("Safari/"))
        XCTAssertTrue(AIWeb.userAgent.contains("Version/"))
        XCTAssertEqual(AIWeb.credit(URL(string: "https://www.kimi.com/")), "网页内容由 kimi.com 提供")
    }

    // MARK: 快捷键和钥匙串

    func testHotKeyWarnings() {
        let optionSpace = KeyCombo(keyCode: 49, modifiers: KeyCombo.Modifier.option)
        XCTAssertNotNil(AIHotKeyAdvice.warning(for: optionSpace))
        XCTAssertTrue(AIHotKeyAdvice.warning(for: optionSpace)!.contains("ChatGPT"))
        XCTAssertNotNil(AIHotKeyAdvice.warning(for: KeyCombo(keyCode: 49, modifiers: KeyCombo.Modifier.command)))
        XCTAssertNil(AIHotKeyAdvice.warning(for: KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.option)))
        XCTAssertNil(AIHotKeyAdvice.warning(for: nil))
    }

    func testKeychainServiceName() {
        XCTAssertEqual(AIKeyNaming.service(bundleID: "com.docket-zh.app", serviceID: "deepseek"),
                       "com.docket-zh.app.ai.deepseek")
    }

    // MARK: 设置

    func testSettingsDefaultsAndLenientDecoding() throws {
        let defaults = AINotchSettings()
        XCTAssertTrue(defaults.enabled)
        XCTAssertFalse(defaults.mainScreenOnly)
        XCTAssertNil(defaults.hotKey, "快捷键默认不设")

        let old = try JSONDecoder().decode(AINotchSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old, defaults)

        let odd = #"{"enabled":false,"modes":{"kimi":"api","doubao":"teleport"},"future":1}"#
        let decoded = try JSONDecoder().decode(AINotchSettings.self, from: Data(odd.utf8))
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.modes, ["kimi": .api], "认不出的打开方式跳过")
    }

    func testSettingsRoundTripAndShiftOnlyHotKeyIsNotUsable() throws {
        var settings = AINotchSettings()
        settings.mainScreenOnly = true
        settings.hotKey = KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.shift)
        settings.modes = ["deepseek": .api, "kimi": .jump]
        settings.endpoints = ["doubao": AIEndpoint(model: "ep-1")]
        settings.lastServiceID = "kimi"
        settings.appPaths = ["kimi": "/Applications/Kimi.app"]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AINotchSettings.self, from: data), settings)
        XCTAssertNil(settings.usableHotKey)
        settings.hotKey = KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.control | KeyCombo.Modifier.option)
        XCTAssertNotNil(settings.usableHotKey)
    }

    func testPersistedStateWithoutTheKeyStillLoads() throws {
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.aiNotch.enabled)
        let data = try JSONEncoder().encode(state)
        XCTAssertTrue(try JSONDecoder().decode(PersistedState.self, from: data).aiNotch.enabled)
    }
}
