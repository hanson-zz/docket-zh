import XCTest

/// 消息灵动岛诊断：最近 5 条真实横幅和测试横幅分开记、按横幅计数、不写原文；
/// 辅助说明里 App 名在第二段、末尾都认，内容里夹着的 App 名不认。
final class NotchBannerLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func analysis(_ outcome: NotchBannerAnalysis.Outcome, at offset: TimeInterval = 0,
                          app: String? = nil) -> NotchBannerAnalysis {
        NotchBannerAnalysis(at: t0.addingTimeInterval(offset), path: [0, 0, 0, 0], stacked: false, app: app ?? "other",
                            has: ["title", "body", "summary"], summary: "summary parts=2 sep=[comma] chars=10 head=len:2",
                            matched: "none", bundleHint: "none", help: "present", actions: ["AXPress"], close: "none",
                            attributes: [], outcome: outcome, outcomeApp: app)
    }

    private func wechatBanner(summary: String?, title: String = "王姐", body: String = "今晚七点到店里对一下货",
                              id: String? = "6A1F2C3D-0000-4000-8000-00000000BEEF") -> NotchBanner {
        NotchBanner(identifier: id, title: title, body: body, summary: summary)
    }

    // MARK: 记录

    func testRealAndTestKeptApart() {
        var log = NotchBannerLog(build: "0.8.0 (13)")
        for index in 0..<7 { log.record(analysis(.notRecognised, at: Double(index)), key: "id:\(index)") }
        log.record(analysis(.test, at: 10), key: "id:probe")
        log.record(analysis(.notRecognised, at: 11), key: "id:7")
        XCTAssertEqual(log.real.count, NotchBannerLog.keep, "只留最近 5 条")
        XCTAssertEqual(log.real.last?.key, "id:7")
        XCTAssertEqual(log.test?.key, "id:probe", "测试横幅单独一条，后来的真实横幅不会盖掉它")
        XCTAssertEqual(log.realBanners, 8)
        XCTAssertEqual(log.rejected, 8)
        XCTAssertEqual(log.recognised, 0)
        XCTAssertEqual(log.countsLine, "realBanners=8 recognised=0 rejected=8 reasons=[not-recognised:8]")

        // 再来一条测试横幅：只换测试那条，不动真实横幅。
        log.record(analysis(.test, at: 12), key: "id:probe2")
        XCTAssertEqual(log.test?.key, "id:probe2")
        XCTAssertEqual(log.real.count, NotchBannerLog.keep)
        XCTAssertEqual(log.realBanners, 8)
    }

    func testSameBannerCountedOnceAndUpgraded() {
        var log = NotchBannerLog()
        // 第一次读时字还没填上，后来认出来了：算一条，按认出来算。
        log.record(analysis(.notRecognised), key: "id:A")
        log.record(analysis(.message, at: 1, app: "wechat"), key: "id:A")
        log.record(analysis(.message, at: 2, app: "wechat"), key: "id:A")
        XCTAssertEqual(log.realBanners, 1)
        XCTAssertEqual(log.recognised, 1)
        XCTAssertEqual(log.rejected, 0)
        XCTAssertEqual(log.reasons, ["message": 1])
        XCTAssertEqual(log.real.count, 1)
        XCTAssertEqual(log.real.first?.analysis.outcome, .message)
        // 快消失时空读一遍：计数改成后来的结果，但记录留认出来的那次。
        log.record(analysis(.notRecognised, at: 3), key: "id:A")
        XCTAssertEqual(log.real.first?.analysis.outcome, .message)
        XCTAssertEqual(log.realBanners, 1)
    }

    func testBannerFirstSeenAsRealThenAsTestMovesOut() {
        // 暗号设上之前就读到了自己的测试横幅：之后认成测试，从真实横幅里挪出来。
        var log = NotchBannerLog()
        log.record(analysis(.notRecognised), key: "id:P")
        log.record(analysis(.test, at: 1), key: "id:P")
        XCTAssertTrue(log.real.isEmpty)
        XCTAssertEqual(log.realBanners, 0)
        XCTAssertEqual(log.rejected, 0)
        XCTAssertEqual(log.reasons, [:])
        // 暗号清掉后又读到它：仍是测试那条，不算真实横幅。
        log.record(analysis(.notRecognised, at: 2), key: "id:P")
        XCTAssertTrue(log.real.isEmpty)
        XCTAssertEqual(log.realBanners, 0)
    }

    func testLogSurvivesEncoding() throws {
        var log = NotchBannerLog(build: "0.8.0 (13)")
        log.record(analysis(.appOff, app: "messages"), key: "id:1")
        log.record(analysis(.test, at: 1), key: "id:2")
        let back = try JSONDecoder().decode(NotchBannerLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(back, log)
        var next = back
        next.record(analysis(.appOff, at: 2, app: "messages"), key: "id:1")
        XCTAssertEqual(next.realBanners, 1, "存回来以后同一条仍只算一次")
    }

    func testReportHasSectionsAndNoContent() {
        let banner = wechatBanner(summary: "王姐，今晚七点到店里对一下货")
        var log = NotchBannerLog()
        let analysed = NotchBannerParser.analyse(banner, path: [0, 0, 0, 0], enabled: NotchMessageApp.allCases, at: t0)
        XCTAssertEqual(analysed.outcome, .notRecognised)
        log.record(analysed, key: NotchBannerParser.identityKey(banner))
        let text = log.report { _ in "T" }.joined(separator: "\n")
        XCTAssertTrue(text.contains("realBanners=1 recognised=0 rejected=1 reasons=[not-recognised:1]"))
        XCTAssertTrue(text.contains("--- last 5 real banners (newest first) ---"))
        XCTAssertTrue(text.contains("T banner path=[0, 0, 0, 0] stacked=false app=none has=[title,body,summary] -> app not recognised"))
        XCTAssertTrue(text.contains("summary parts=2 sep=[fullwidth-comma] chars=14 head=len:2"))
        XCTAssertTrue(text.contains("--- test banner ---\nnone"))
        XCTAssertFalse(text.contains("王姐"))
        XCTAssertFalse(text.contains("对一下货"))
    }

    // MARK: 测试横幅不认错

    func testTestTokenOnlyMarksUnrecognisedBanners() {
        // 真实微信消息里碰巧带着暗号：仍是微信消息。
        let wechat = wechatBanner(summary: "微信，王姐，订单 #0042 到了", body: "订单 #0042 到了")
        XCTAssertEqual(NotchBannerParser.analyse(wechat, path: [], enabled: NotchMessageApp.allCases,
                                                 testTokens: ["#0042"]).outcome, .message)
        // 码头自己的测试横幅：暗号还在等时、读到以后暗号清掉了（最近的暗号）都算测试。
        let probe = NotchBanner(identifier: "P", title: "消息灵动岛", body: NotchMessageProbe.body(token: "#0042"),
                                summary: "消息灵动岛, " + NotchMessageProbe.body(token: "#0042"))
        XCTAssertEqual(NotchBannerParser.analyse(probe, path: [], enabled: NotchMessageApp.allCases,
                                                 testTokens: ["#0042"]).outcome, .test)
        XCTAssertEqual(NotchBannerParser.analyse(probe, path: [], enabled: NotchMessageApp.allCases,
                                                 testTokens: ["#9999"]).outcome, .notRecognised)
        XCTAssertTrue(NotchBannerParser.report(NotchBannerNode(role: "AXWindow", children: [
            NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: "P",
                            description: probe.summary,
                            children: [NotchBannerNode(role: "AXStaticText", identifier: "title", value: probe.title),
                                       NotchBannerNode(role: "AXStaticText", identifier: "body", value: probe.body)]),
        ]), enabled: NotchMessageApp.allCases, testTokens: ["#0042"]).contains("-> test banner"))
    }

    func testOutcomes() {
        let enabledOff = NotchBannerParser.analyse(wechatBanner(summary: "微信，王姐，在吗"), path: [], enabled: [.messages])
        XCTAssertEqual(enabledOff.outcome, .appOff)
        XCTAssertEqual(enabledOff.verdict, "wechat is turned off")
        // 只有 bundle id、一个字都没有：认出了 App 但没字。
        let empty = NotchBanner(identifier: "X", hints: ["com.tencent.xinWeChat"])
        let analysed = NotchBannerParser.analyse(empty, path: [], enabled: NotchMessageApp.allCases)
        XCTAssertEqual(analysed.outcome, .noText)
        XCTAssertEqual(analysed.verdict, "wechat banner has no text")
        let message = NotchBannerParser.analyse(wechatBanner(summary: "王姐，微信，今晚七点到店里对一下货"), path: [],
                                                enabled: NotchMessageApp.allCases)
        XCTAssertEqual(message.outcome, .message)
        XCTAssertEqual(message.matched, "summary[1]")
        XCTAssertEqual(message.lines[0], "banner path=[] stacked=false app=wechat has=[title,body,summary] -> message from wechat")
    }

    func testIdentityKey() {
        XCTAssertEqual(NotchBannerParser.identityKey(wechatBanner(summary: "x", id: "ABC")), "id:ABC")
        let a = NotchBannerParser.identityKey(wechatBanner(summary: "王姐，在吗", id: nil))
        let b = NotchBannerParser.identityKey(wechatBanner(summary: "王姐，在吗", id: nil))
        let c = NotchBannerParser.identityKey(wechatBanner(summary: "王姐，在吗？", id: nil))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.hasPrefix("h:"))
        XCTAssertFalse(a.contains("王姐"))
    }

    // MARK: App 名在第二段、末尾

    func testAppNameInSecondOrLastSegment() {
        let enabled = NotchMessageApp.allCases
        let shapes: [(String, NotchMessageApp, Int)] = [
            ("王姐, 微信", .wechat, 1),
            ("王姐，微信，今晚七点到店里对一下货", .wechat, 1),
            ("王姐, 今晚七点到店里对一下货, WeChat", .wechat, 2),
            ("林小雨, 信息, 今晚七点到店里对一下货", .messages, 1),
            ("信息, 林小雨, 今晚七点到店里对一下货", .messages, 0),
        ]
        for (summary, app, index) in shapes {
            let banner = wechatBanner(summary: summary, title: summary.hasPrefix("林") || summary.hasPrefix("信") ? "林小雨" : "王姐")
            let hit = NotchBannerParser.recognise(banner)
            XCTAssertEqual(hit?.app, app, summary)
            XCTAssertEqual(hit?.source, "summary[\(index)]", summary)
            XCTAssertEqual(NotchBannerParser.incoming(banner, enabled: enabled)?.sender, banner.title, summary)
        }
    }

    func testAppNameInsideContentIsNotTaken() {
        // 内容里自己夹着「，微信，」：不是微信的横幅（比如 WhatsApp 的辅助说明里没写 App 名）。
        let inside = NotchBanner(identifier: "W", title: "Dan", body: "好的，微信，明天见", summary: "Dan，好的，微信，明天见")
        XCTAssertNil(NotchBannerParser.recognise(inside))
        // 内容太长被截断加了省略号，原文找不到：末尾几段连起来是内容的开头，也不认。
        let truncated = NotchBanner(identifier: "W", title: "Dan", body: "好的，微信，明天见，这是一段很长很长的话",
                                    summary: "Dan，好的，微信，明天见…")
        XCTAssertNil(NotchBannerParser.recognise(truncated))
        // 对方就发了「微信」两个字。
        let word = NotchBanner(identifier: "W", title: "Dan", body: "微信", summary: "Dan，微信")
        XCTAssertNil(NotchBannerParser.recognise(word))
        // 发件人就叫「信息」。
        let sender = NotchBanner(identifier: "W", title: "信息", body: "在吗", summary: "信息，在吗")
        XCTAssertNotEqual(NotchBannerParser.recognise(sender)?.source, "summary[0]")
        // 真的是微信、内容又以「微信」开头并被截断：App 名那段仍认。
        let leading = NotchBanner(identifier: "W", title: "王姐", body: "微信转账收到了，谢谢你这么快",
                                  summary: "微信，王姐，微信转账收到了…")
        XCTAssertEqual(NotchBannerParser.recognise(leading)?.app, .wechat)
        XCTAssertEqual(NotchBannerParser.recognise(leading)?.source, "summary[0]")
        // 群名里带逗号、App 名在后面。
        let group = NotchBanner(identifier: "W", title: "A, B", body: "开会", summary: "A, B, 开会, WhatsApp")
        XCTAssertEqual(NotchBannerParser.recognise(group)?.app, .whatsapp)
        // 系统「信息」在 macOS 27 若只写「发件人, 内容」：认不出，宁可不弹。
        let bare = NotchBanner(identifier: "M", title: "林小雨", body: "到楼下了", summary: "林小雨, 到楼下了")
        XCTAssertNil(NotchBannerParser.recognise(bare))
    }

    func testExtraAttributesAreListedNotRead() {
        let node = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: "U",
                                   description: "王姐，在吗",
                                   attributes: ["AXRole", "AXDescription", "AXBundleIdentifier"],
                                   children: [NotchBannerNode(role: "AXStaticText", identifier: "title", value: "王姐"),
                                              NotchBannerNode(role: "AXStaticText", identifier: "body", value: "在吗")])
        var withValue = node
        withValue.attributeTexts = ["com.tencent.xinWeChat"]
        let banner = NotchBannerParser.banner(from: withValue)
        XCTAssertEqual(banner.extraAttributes, ["AXBundleIdentifier"])
        XCTAssertEqual(NotchBannerParser.recognise(banner)?.source, "bundle", "不常见属性里的 bundle id 也认")
        let analysed = NotchBannerParser.analyse(banner, path: [], enabled: NotchMessageApp.allCases)
        XCTAssertTrue(analysed.lines[2].contains("attrs=[AXBundleIdentifier]"))
        XCTAssertFalse(analysed.lines.joined().contains("com.tencent"), "属性的值不写进诊断")
    }
}
