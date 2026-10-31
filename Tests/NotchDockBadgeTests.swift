import XCTest

/// 消息灵动岛：macOS 27 横幅上没有 App 名时，靠程序坞角标增量和横幅属性线索认 App；
/// 辅助说明「发件人, 内容」拆成标题和正文；诊断只写长度、命中和角标数字。
final class NotchDockBadgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ offset: TimeInterval, wechat: NotchDockBadge = .missing,
                        messages: NotchDockBadge = .missing, whatsapp: NotchDockBadge = .missing) -> NotchDockSample {
        NotchDockSample(at: t0.addingTimeInterval(offset),
                        badges: [.wechat: wechat, .messages: messages, .whatsapp: whatsapp])
    }

    /// 真机 beta.14 上读到的那种横幅：标题、内容两段静态文字，辅助说明「发件人, 内容」。
    private func macOS27Node(title: String = "王姐", body: String = "今晚七点到店里对一下货",
                             summary: String? = nil, attributed: String? = nil, help: String? = nil) -> NotchBannerNode {
        var node = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner",
                                   description: summary ?? "\(title), \(body)", help: help,
                                   actions: ["AXPress", "Name:关闭\nTarget:0x0\nSelector:(null)"],
                                   attributes: ["AXAttributedDescription", "AXImageData"],
                                   children: [NotchBannerNode(role: "AXStaticText", value: title),
                                              NotchBannerNode(role: "AXStaticText", value: body)])
        node.attributedDescription = attributed ?? node.description
        node.attributedKeys = ["AXFont", "AXForegroundColor"]
        return node
    }

    private func macOS27Banner(title: String = "王姐", body: String = "今晚七点到店里对一下货",
                               attributed: String? = nil, help: String? = nil) -> NotchBanner {
        NotchBannerParser.banner(from: macOS27Node(title: title, body: body, attributed: attributed, help: help))
    }

    // MARK: 角标读法

    func testBadgeParsing() {
        XCTAssertEqual(NotchDockBadge.parse(nil), .none)
        XCTAssertEqual(NotchDockBadge.parse("  "), .none)
        XCTAssertEqual(NotchDockBadge.parse("3"), .count(3))
        XCTAssertEqual(NotchDockBadge.parse("99+"), .count(99))
        XCTAssertEqual(NotchDockBadge.parse("•"), .mark)
        XCTAssertNil(NotchDockBadge.missing.level, "不在程序坞上的不比")
        XCTAssertEqual(NotchDockBadge.none.level, 0)
        XCTAssertEqual(NotchDockBadge.mark.level, 1)
        XCTAssertEqual(sample(0, wechat: .count(2)).summary, "messages:n/a,whatsapp:n/a,wechat:2")
    }

    // MARK: 角标增量判定

    func testSingleRiseAfterBanner() {
        let history = NotchDockBadgeHistory(samples: [sample(-2, wechat: .count(1)), sample(-1, wechat: .count(1)),
                                                      sample(0.5, wechat: .count(2))])
        let result = history.attribution(at: t0)
        XCTAssertEqual(result.kind, .single)
        XCTAssertEqual(result.app, .wechat)
        XCTAssertEqual(result.rises, [.wechat: 1])
        XCTAssertEqual(result.source, "dock-badge(+1 wechat)")
        XCTAssertEqual(result.badgeLine, "wechat:1->2", "不在程序坞上的信息、WhatsApp 不写")
    }

    func testRiseJustBeforeBannerCountsFromBaselineOutsideWindow() {
        // 微信先改角标、横幅后出来：起点是窗口开始前最后一次记录。
        let history = NotchDockBadgeHistory(samples: [sample(-4, wechat: .none), sample(-0.8, wechat: .count(1))])
        let result = history.attribution(at: t0)
        XCTAssertEqual(result.app, .wechat)
        XCTAssertEqual(result.badgeLine, "wechat:-->1")
    }

    func testRiseOutsideWindowIgnored() {
        let history = NotchDockBadgeHistory(samples: [sample(-6, wechat: .count(1)), sample(-5, wechat: .count(2)),
                                                      sample(-1, wechat: .count(2)), sample(1, wechat: .count(2))])
        let result = history.attribution(at: t0)
        XCTAssertEqual(result.kind, .unchanged)
        XCTAssertNil(result.app)
        XCTAssertEqual(result.source, "dock-badge(no change)")
    }

    func testReadThenNewMessageStillRises() {
        // 中间被读掉清零、又来一条：只把涨的加起来。
        let history = NotchDockBadgeHistory(samples: [sample(-2, wechat: .count(3)), sample(-1, wechat: .none),
                                                      sample(1, wechat: .count(1))])
        XCTAssertEqual(history.attribution(at: t0).rises, [.wechat: 1])
    }

    func testAppAppearingInDockIsNotARise() {
        let history = NotchDockBadgeHistory(samples: [sample(-1, wechat: .missing), sample(1, wechat: .count(5))])
        XCTAssertEqual(history.attribution(at: t0).kind, .unchanged, "App 刚打开冒出来的角标不算新消息")
    }

    func testNotEnoughSamples() {
        XCTAssertEqual(NotchDockBadgeHistory().attribution(at: t0).kind, .noData)
        let one = NotchDockBadgeHistory(samples: [sample(0, wechat: .count(1))])
        XCTAssertEqual(one.attribution(at: t0).kind, .noData)
        XCTAssertEqual(one.attribution(at: t0).source, "dock-badge(no data)")
    }

    func testMarkBadgeRise() {
        let history = NotchDockBadgeHistory(samples: [sample(-1, messages: .none), sample(0.5, messages: .mark)])
        XCTAssertEqual(history.attribution(at: t0).app, .messages)
    }

    // MARK: 多候选消歧

    func testTwoAppsRisingIsAmbiguous() {
        let history = NotchDockBadgeHistory(samples: [
            sample(-1, wechat: .count(1), messages: .none),
            sample(1, wechat: .count(2), messages: .count(1)),
        ])
        let result = history.attribution(at: t0)
        XCTAssertEqual(result.kind, .multiple)
        XCTAssertNil(result.app)
        XCTAssertEqual(result.source, "dock-badge(ambiguous:messages+wechat)")
    }

    func testClaimedRiseIsSubtracted() {
        let history = NotchDockBadgeHistory(samples: [
            sample(-1, wechat: .count(1), messages: .none),
            sample(1, wechat: .count(2), messages: .count(1)),
        ])
        // 同一段时间里另一条横幅已经认成微信：剩下的只有信息涨了。
        let result = history.attribution(at: t0).excluding([.wechat: 1])
        XCTAssertEqual(result.app, .messages)
        XCTAssertEqual(result.source, "dock-badge(+1 messages)")
        // 微信涨了二、只认走一条：两个都还在涨，仍然分不清。
        let twice = NotchDockBadgeHistory(samples: [
            sample(-1, wechat: .count(1), messages: .none),
            sample(1, wechat: .count(3), messages: .count(1)),
        ])
        XCTAssertEqual(twice.attribution(at: t0).excluding([.wechat: 1]).kind, .multiple)
    }

    func testHistoryKeepsOrderPrunesAndSeesLastStep() {
        var history = NotchDockBadgeHistory()
        history.append(sample(0, wechat: .count(1)))
        history.append(sample(-1, wechat: .count(1)))
        XCTAssertEqual(history.samples.map(\.at), [t0.addingTimeInterval(-1), t0], "按时间插")
        XCTAssertFalse(history.lastStepRose)
        history.append(sample(1, wechat: .count(2)))
        XCTAssertTrue(history.lastStepRose)
        history.append(sample(30, wechat: .count(2)))
        XCTAssertEqual(history.samples.count, 1, "20 秒前的扔掉")
    }

    // MARK: 认 App 和拆发件人

    func testDockBadgeRecognisesMacOS27Banner() {
        let banner = macOS27Banner()
        XCTAssertNil(NotchBannerParser.recognise(banner), "辅助说明里没有 App 名，原来的认法认不出")
        let dock = NotchDockBadgeHistory(samples: [sample(-1, wechat: .count(1)), sample(0.5, wechat: .count(2))])
            .attribution(at: t0)
        let incoming = NotchBannerParser.incoming(banner, enabled: NotchMessageApp.allCases, dock: dock)
        XCTAssertEqual(incoming?.app, .wechat)
        XCTAssertEqual(incoming?.sender, "王姐")
        XCTAssertEqual(incoming?.preview, "今晚七点到店里对一下货")

        let analysis = NotchBannerParser.analyse(banner, path: [0, 0, 0, 0], enabled: NotchMessageApp.allCases,
                                                 dock: dock, at: t0)
        XCTAssertEqual(analysis.outcome, .message)
        XCTAssertEqual(analysis.matched, "dock-badge(+1 wechat)")
        XCTAssertEqual(analysis.badge, "wechat:1->2")
        XCTAssertEqual(analysis.app, "wechat")
        let text = analysis.lines.joined(separator: "\n")
        XCTAssertTrue(text.contains("badge=[wechat:1->2]"))
        XCTAssertTrue(text.contains("clues=[attr-desc:len"))
        XCTAssertFalse(text.contains("王姐"), "诊断不写发件人")
        XCTAssertFalse(text.contains("今晚"), "诊断不写内容")
    }

    func testDockBadgeAppTurnedOff() {
        let dock = NotchDockBadgeHistory(samples: [sample(-1, wechat: .count(1)), sample(0.5, wechat: .count(2))])
            .attribution(at: t0)
        let banner = macOS27Banner()
        XCTAssertNil(NotchBannerParser.incoming(banner, enabled: [.messages], dock: dock))
        let analysis = NotchBannerParser.analyse(banner, path: [0], enabled: [.messages], dock: dock, at: t0)
        XCTAssertEqual(analysis.outcome, .appOff)
    }

    func testAmbiguousOrUnchangedDockStaysUnrecognised() {
        let banner = macOS27Banner()
        let ambiguous = NotchDockBadgeHistory(samples: [
            sample(-1, wechat: .count(1), messages: .none), sample(1, wechat: .count(2), messages: .count(1)),
        ]).attribution(at: t0)
        XCTAssertNil(NotchBannerParser.incoming(banner, enabled: NotchMessageApp.allCases, dock: ambiguous))
        let analysis = NotchBannerParser.analyse(banner, path: [0], enabled: NotchMessageApp.allCases,
                                                 dock: ambiguous, at: t0)
        XCTAssertEqual(analysis.outcome, .notRecognised)
        XCTAssertEqual(analysis.matched, "dock-badge(ambiguous:messages+wechat)")
        XCTAssertNil(NotchBannerParser.incoming(banner, enabled: NotchMessageApp.allCases))
    }

    func testExplicitRecognitionIgnoresDock() {
        // 辅助说明里有 App 名时照旧认，角标说别的 App 涨了也不管。
        let node = macOS27Node(summary: "微信, 王姐, 今晚七点到店里对一下货")
        let banner = NotchBannerParser.banner(from: node)
        let dock = NotchDockBadgeHistory(samples: [sample(-1, messages: .none), sample(1, messages: .count(1))])
            .attribution(at: t0)
        let analysis = NotchBannerParser.analyse(banner, path: [0], enabled: NotchMessageApp.allCases, dock: dock, at: t0)
        XCTAssertEqual(analysis.outcomeApp, "wechat")
        XCTAssertNil(analysis.badge)
        XCTAssertNil(analysis.clues)
    }

    // MARK: 属性线索

    func testAttributedDescriptionBundleIDWinsAndDisambiguates() {
        let banner = macOS27Banner(attributed: "com.tencent.xinWeChat 王姐, 今晚七点到店里对一下货")
        let ambiguous = NotchDockBadgeHistory(samples: [
            sample(-1, wechat: .count(1), messages: .none), sample(1, wechat: .count(2), messages: .count(1)),
        ]).attribution(at: t0)
        let hit = NotchBannerParser.resolve(banner, dock: ambiguous)
        XCTAssertEqual(hit?.app, .wechat)
        XCTAssertEqual(hit?.source, "attr-desc:bundle")
        XCTAssertEqual(hit?.inferred, true)
        // 角标说是信息、线索说是微信：信线索。
        let otherApp = NotchDockBadgeHistory(samples: [sample(-1, messages: .none), sample(1, messages: .count(1))])
            .attribution(at: t0)
        XCTAssertEqual(NotchBannerParser.resolve(banner, dock: otherApp)?.app, .wechat)
        let analysis = NotchBannerParser.analyse(banner, path: [0], enabled: NotchMessageApp.allCases,
                                                 dock: otherApp, at: t0)
        XCTAssertEqual(analysis.matched, "attr-desc:bundle (dock-badge(+1 messages))")
        XCTAssertTrue(analysis.clues?.contains("attr-desc:len") == true)
        XCTAssertTrue(analysis.clues?.contains(":wechat-bundle") == true)
    }

    func testAttributedDescriptionSegmentAndHelpName() {
        let segment = macOS27Banner(attributed: "微信, 王姐, 今晚七点到店里对一下货")
        XCTAssertEqual(NotchBannerParser.clueHit(segment)?.source, "attr-desc:segment[0]")
        let help = macOS27Banner(help: "WeChat")
        XCTAssertEqual(NotchBannerParser.clueHit(help)?.app, .wechat)
        XCTAssertEqual(NotchBannerParser.clueHit(help)?.source, "help:name")
    }

    func testCluesIgnoreContentThatLooksLikeAppName() {
        // AXAttributedDescription 和辅助说明一样、内容正好是「微信」：不认。
        let same = macOS27Banner(body: "微信")
        XCTAssertNil(NotchBannerParser.clueHit(same))
        // 帮助文字正好等于对方发来的内容：不认。
        let echoed = macOS27Banner(body: "WhatsApp", help: "WhatsApp")
        XCTAssertNil(NotchBannerParser.clueHit(echoed))
        let report = NotchBannerParser.clueReport(macOS27Banner())
        XCTAssertTrue(report.hasPrefix("clues=[attr-desc:len15:none,desc:len15:none"), report)
        XCTAssertTrue(report.contains("attr-keys=[AXFont,AXForegroundColor]"))
        XCTAssertFalse(report.contains("王姐"))
    }

    // MARK: 辅助说明拆分

    func testSenderAndPreviewSplit() {
        // 只有辅助说明：第一段是发件人，后面整个是内容（内容里的逗号原样留着）。
        let summaryOnly = NotchBanner(summary: "王姐, 今晚七点, 到店里对一下货")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(summaryOnly).sender, "王姐")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(summaryOnly).preview, "今晚七点, 到店里对一下货")
        // 群名里带逗号：标题正好是开头时用标题。
        let group = NotchBanner(title: "张三, 李四", summary: "张三, 李四, 好的")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(group).sender, "张三, 李四")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(group).preview, "好的")
        // 开头是时间的跳过，末尾「已堆叠」去掉。
        let timed = NotchBanner(summary: "下午3:20，王姐，收到，已堆叠")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(timed).sender, "王姐")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(timed).preview, "收到")
        // 内容优先用 body；占位话当没有预览。
        let withBody = NotchBanner(title: "王姐", body: "今晚七点到店里对一下货", summary: "王姐, 今晚七点到店里…")
        XCTAssertEqual(NotchBannerParser.senderAndPreview(withBody).preview, "今晚七点到店里对一下货")
        let hidden = NotchBanner(summary: "王姐, 收到 3 条新消息")
        XCTAssertNil(NotchBannerParser.senderAndPreview(hidden).preview)
        // 没有分隔符也没有标题：没有发件人，也不给内容。
        let bare = NotchBanner(summary: "一段话")
        XCTAssertNil(NotchBannerParser.senderAndPreview(bare).sender)
        XCTAssertNil(NotchBannerParser.senderAndPreview(bare).preview)
    }
}
