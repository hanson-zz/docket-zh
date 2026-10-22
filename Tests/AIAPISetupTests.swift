import XCTest

/// 设置里 API 那一段的纯逻辑：缺什么、点 API 之后怎么办、校验结果怎么落到
/// 打开方式上、密钥怎么清洗、各服务的默认接口和获取密钥的链接。
final class AIAPISetupTests: XCTestCase {

    // MARK: 缺什么

    func testReadinessChecksKeyThenAddressThenModel() {
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "deepseek", override: nil, hasKey: false), .missing(.key))
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "deepseek", override: nil, hasKey: true), .ready)
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "doubao", override: nil, hasKey: true), .missing(.model),
                       "豆包要填接入点 ID")
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "doubao", override: AIEndpoint(model: "ep-1"), hasKey: true), .ready)
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "custom-x", override: nil, hasKey: true), .missing(.baseURL),
                       "自定义服务没有默认地址")
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "custom-x", override: AIEndpoint(baseURL: "http://api.example.com", model: "m"),
                                            hasKey: true), .badURL, "外网只收 https")
        XCTAssertEqual(AIAPISetup.readiness(serviceID: "custom-x", override: AIEndpoint(baseURL: "https://api.example.com/v1"),
                                            hasKey: true), .missing(.model))
    }

    func testReadinessAgreesWithResolvedEndpoints() {
        for id in AIServices.builtIn.map(\.id) + ["custom-x"] {
            let ready = AIAPISetup.readiness(serviceID: id, override: nil, hasKey: true) == .ready
            XCTAssertEqual(ready, AIEndpoints.resolved(id, override: nil) != nil, id)
        }
    }

    func testEveryBuiltInHasADefaultAddress() {
        for service in AIServices.builtIn {
            let base = AIEndpoints.defaults[service.id]?.baseURL ?? ""
            XCTAssertNotNil(AIEndpoints.chatURL(base: base), "\(service.id) 要有默认接口地址")
        }
    }

    func testRetiredDefaultModelsAreGone() {
        let models = AIEndpoints.defaults.values.map(\.model)
        for retired in ["deepseek-chat", "moonshot-v1-8k", "glm-4-flash", "gpt-4o-mini"] {
            XCTAssertFalse(models.contains(retired), "\(retired) 已下线或即将下线")
        }
    }

    // MARK: 点 API

    func testTappingAPIAlwaysWorks() {
        XCTAssertEqual(AIAPISetup.tapAPI(.ready), .select)
        XCTAssertEqual(AIAPISetup.tapAPI(.missing(.key)), .expand(focus: .key))
        XCTAssertEqual(AIAPISetup.tapAPI(.missing(.model)), .expand(focus: .model))
        XCTAssertEqual(AIAPISetup.tapAPI(.badURL), .expand(focus: .baseURL))
    }

    func testPendingHints() {
        XCTAssertEqual(AIAPISetup.pendingHint(.missing(.key), serviceID: "deepseek"), "填入密钥后生效")
        XCTAssertEqual(AIAPISetup.pendingHint(.missing(.model), serviceID: "doubao"), "填入接入点 ID 后生效")
        XCTAssertEqual(AIAPISetup.pendingHint(.missing(.model), serviceID: "gemini"), "填入模型名后生效")
        XCTAssertNil(AIAPISetup.pendingHint(.ready, serviceID: "deepseek"))
    }

    func testChoosingAPIWithoutAKeyIsRememberedAndFallsBackToWeb() {
        var settings = AINotchSettings()
        let deepseek = AIServices.builtIn("deepseek")!
        settings.modes["deepseek"] = .api
        let effective = AIOpenModes.mode(for: deepseek, settings: settings, hasKey: false)
        XCTAssertEqual(effective, .web)
        XCTAssertEqual(AIAPISetup.segment(.api, saved: .api, effective: effective, hasWeb: true), .pending)
        XCTAssertEqual(AIAPISetup.segment(.web, saved: .api, effective: effective, hasWeb: true), .current)
        XCTAssertEqual(AIAPISetup.segment(.jump, saved: .api, effective: effective, hasWeb: true), .normal)
        // 密钥填好后不用再点一次就生效。
        XCTAssertEqual(AIOpenModes.mode(for: deepseek, settings: settings, hasKey: true), .api)
    }

    func testSegmentsWhenNothingIsPending() {
        XCTAssertEqual(AIAPISetup.segment(.api, saved: .web, effective: .web, hasWeb: true), .normal,
                       "没填密钥时 API 段也能点")
        XCTAssertEqual(AIAPISetup.segment(.web, saved: .jump, effective: .jump, hasWeb: false), .unavailable)
        XCTAssertEqual(AIAPISetup.segment(.jump, saved: .jump, effective: .jump, hasWeb: false), .current)
    }

    // MARK: 校验

    func testVerdictFromStatus() {
        XCTAssertEqual(AIAPISetup.verdict(status: 200), .ok)
        XCTAssertEqual(AIAPISetup.verdict(status: 429), .ok, "太频繁说明密钥有效")
        if case .rejected = AIAPISetup.verdict(status: 401) {} else { XCTFail("401 是密钥不对") }
        if case .rejected = AIAPISetup.verdict(status: 404) {} else { XCTFail("404 是地址或模型不对") }
        if case .unverified = AIAPISetup.verdict(status: 503) {} else { XCTFail("5xx 没法确认") }
    }

    func testVerdictFromFailures() {
        if case .unverified = AIAPISetup.verdict(failure: .offline) {} else { XCTFail() }
        if case .unverified = AIAPISetup.verdict(failure: .timeout) {} else { XCTFail() }
        if case .rejected = AIAPISetup.verdict(failure: .badURL) {} else { XCTFail() }
        if case .rejected(let text) = AIAPISetup.verdict(failure: .http(status: 401, message: nil)) {
            XCTAssertTrue(text.contains("401"))
        } else { XCTFail() }
    }

    func testModeAfterCheck() {
        XCTAssertEqual(AIAPISetup.modeAfterCheck(.ok, intent: .api), .api, "存好密钥校验通过就切到 API")
        XCTAssertNil(AIAPISetup.modeAfterCheck(.rejected("x"), intent: .api), "被拒绝时回到网页")
        XCTAssertEqual(AIAPISetup.modeAfterCheck(.unverified("x"), intent: .api), .api)
        XCTAssertEqual(AIAPISetup.modeAfterCheck(.ok, intent: .web), .web, "只是测试连接不改方式")
        XCTAssertEqual(AIAPISetup.modeAfterCheck(.rejected("x"), intent: .jump), .jump)
        XCTAssertEqual(AIAPISetup.checkNote(.ok, mode: .api), "连接成功，已改用 API。")
    }

    func testDeletingTheKeyFallsBackToWeb() {
        XCTAssertNil(AIAPISetup.modeAfterKeyDeleted(.api))
        XCTAssertEqual(AIAPISetup.modeAfterKeyDeleted(.jump), .jump)
        XCTAssertNil(AIAPISetup.modeAfterKeyDeleted(nil))
    }

    // MARK: 密钥

    func testKeyNormalization() {
        XCTAssertEqual(AIAPISetup.normalizedKey("  sk-abc\n"), .ok("sk-abc"))
        XCTAssertEqual(AIAPISetup.normalizedKey("Bearer sk-abc"), .ok("sk-abc"), "从文档连着复制的 Bearer 去掉")
        XCTAssertEqual(AIAPISetup.normalizedKey("bearer  sk-abc "), .ok("sk-abc"))
        XCTAssertEqual(AIAPISetup.normalizedKey("   "), .empty)
        XCTAssertEqual(AIAPISetup.normalizedKey("sk-a sk-b"), .hasSpaces)
        XCTAssertNotNil(AIAPISetup.KeyInput.hasSpaces.message)
    }

    // MARK: 链接和说明

    func testKeyPagesAreHTTPSAndOnlyForBuiltIns() {
        for service in AIServices.builtIn {
            let page = AIAPISetup.keyPage(service.id)
            XCTAssertNotNil(page, service.id)
            XCTAssertEqual(page?.scheme, "https", service.id)
        }
        XCTAssertNil(AIAPISetup.keyPage("custom-x"))
    }

    func testModeNotesAreShortOneLiners() {
        for mode in AIOpenMode.allCases {
            let note = AIAPISetup.modeNote(mode)
            XCTAssertFalse(note.isEmpty)
            XCTAssertLessThanOrEqual(note.count, 32, "每种方式一行短说明：\(note)")
        }
        XCTAssertEqual(AIAPISetup.modeNote(.jump), "打开 Mac App，没装就用浏览器。")
        XCTAssertNotNil(AIAPISetup.providerNote("doubao"))
        XCTAssertNil(AIAPISetup.providerNote("deepseek"))
    }
}
