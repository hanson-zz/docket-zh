import XCTest

/// 「App」打开方式找 Mac App 的纯逻辑：候选 bundle id、按 App 名模糊匹配、
/// 带问题时装了 App 就复制再开 App。
final class AIAppMatchTests: XCTestCase {

    private func service(_ id: String) -> AIService { AIServices.builtIn(id)! }

    func testBundleIDCandidates() {
        XCTAssertEqual(AIAppMatch.bundleIDs(for: service("doubao")).first, "com.bot.pc.doubao")
        XCTAssertTrue(AIAppMatch.bundleIDs(for: service("doubao")).contains("com.volcengine.doubao"), "旧 id 留作候选")
        XCTAssertEqual(AIAppMatch.bundleIDs(for: service("chatgpt")), ["com.openai.chat"])
        XCTAssertEqual(AIAppMatch.bundleIDs(for: service("yuanbao")), ["com.tencent.yuanbao"])
        XCTAssertEqual(AIAppMatch.bundleIDs(for: service("kimi")), ["com.moonshot.kimichat"])
        XCTAssertTrue(AIAppMatch.bundleIDs(for: service("deepseek")).isEmpty, "DeepSeek 没有官方对话 Mac App")
        let custom = AIService(id: "custom-c", title: "Claude", initial: "C", region: .overseas, home: "",
                               appBundleID: "com.anthropic.claudefordesktop", appPath: "/Applications/Claude.app")
        XCTAssertEqual(AIAppMatch.bundleIDs(for: custom), ["com.anthropic.claudefordesktop"])
    }

    func testEveryBuiltInHasNames() {
        for item in AIServices.builtIn {
            XCTAssertFalse(AIAppMatch.names(for: item).isEmpty, item.id)
        }
    }

    func testNormalization() {
        XCTAssertEqual(AIAppMatch.normalized("Doubao.app"), "doubao")
        XCTAssertEqual(AIAppMatch.normalized(" Google Gemini.APP"), "googlegemini")
        XCTAssertEqual(AIAppMatch.normalized("元宝.app"), "元宝")
        XCTAssertEqual(AIAppMatch.normalized("Kimi-智能助手"), "kimi智能助手")
    }

    func testFuzzyNameMatching() {
        let doubao = service("doubao")
        XCTAssertEqual(AIAppMatch.bestMatch(for: doubao, among: ["Safari.app", "Doubao.app"]), "Doubao.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: doubao, among: ["豆包.app"]), "豆包.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: doubao, among: ["doubao.app"]), "doubao.app", "不分大小写")
        XCTAssertNil(AIAppMatch.bestMatch(for: doubao, among: ["Doubao Browser.app"]), "豆包浏览器不是对话 App")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("kimi"), among: ["Kimi.app"]), "Kimi.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("tongyi"), among: ["Qianwen.app"]), "Qianwen.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("tongyi"), among: ["千问.app"]), "千问.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("yuanbao"), among: ["元宝.app"]), "元宝.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("wenxin"), among: ["文小言.app"]), "文小言.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: service("zhipu"), among: ["智谱清言.app"]), "智谱清言.app")
        XCTAssertNil(AIAppMatch.bestMatch(for: service("grok"), among: ["Grok Bot.app"]), "Grok Bot 是别的产品")
        XCTAssertNil(AIAppMatch.bestMatch(for: service("deepseek"), among: ["DeepSeek Harness.app"]),
                     "写代码的 Harness 不是对话 App")
        XCTAssertNil(AIAppMatch.bestMatch(for: service("kimi"), among: ["Kimi"]), "只看 .app")
    }

    func testGenericSuffixesAndExactWins() {
        let gemini = service("gemini")
        XCTAssertEqual(AIAppMatch.bestMatch(for: gemini, among: ["Gemini Desktop.app"]), "Gemini Desktop.app")
        XCTAssertEqual(AIAppMatch.bestMatch(for: gemini, among: ["Gemini Desktop.app", "Gemini.app"]), "Gemini.app",
                       "完全同名优先")
        XCTAssertEqual(AIAppMatch.quality(of: "Kimi AI.app", names: ["Kimi"]), .suffix)
        XCTAssertEqual(AIAppMatch.quality(of: "Kimi.app", names: ["Kimi"]), .exact)
        XCTAssertNil(AIAppMatch.quality(of: "Kimix.app", names: ["Kimi"]))
    }

    func testCustomServiceMatchesByItsOwnTitle() {
        let custom = AIService(id: "custom-m", title: "秘塔", initial: "秘", region: .domestic, home: "https://metaso.cn")
        XCTAssertEqual(AIAppMatch.bestMatch(for: custom, among: ["秘塔.app"]), "秘塔.app")
    }

    func testDescriptions() {
        XCTAssertEqual(AIAppMatch.displayName("/Applications/元宝.app"), "元宝")
        XCTAssertEqual(AIAppMatch.describe(.found(name: "Doubao")), "会打开 Doubao")
        XCTAssertEqual(AIAppMatch.describe(.chosen(name: "Kimi")), "会打开你选的 Kimi")
        XCTAssertTrue(AIAppMatch.describe(.web).contains("浏览器"))
    }

    func testAskPlanPrefersTheInstalledApp() {
        let chatgpt = service("chatgpt")
        XCTAssertEqual(AIAsk.plan("你好", service: chatgpt, appInstalled: true), .copyThenOpen("你好"),
                       "装了 App 时复制问题再开 App")
        if case .openWithQuestion = AIAsk.plan("你好", service: chatgpt, appInstalled: false) {} else {
            XCTFail("没装 App 时照旧带问题开浏览器")
        }
        XCTAssertEqual(AIAsk.plan("  ", service: chatgpt, appInstalled: true), .blocked)
    }
}
