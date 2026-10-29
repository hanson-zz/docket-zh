import XCTest

/// 消息灵动岛：中文系统的辅助说明（全角逗号）、设置里的状态自查、测试通知。
final class NotchMessageDiagnosisTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(_ banners: [NotchBannerNode]) -> NotchBannerNode {
        NotchBannerNode(role: "AXWindow", children: [NotchBannerNode(role: "AXGroup", children: banners)])
    }

    // MARK: 辅助说明的拆法

    func testSummaryPartsEnglishAndChinese() {
        XCTAssertEqual(NotchBannerParser.summaryParts("Messages, John, Hello, how are you"),
                       ["Messages", "John", "Hello, how are you"])
        XCTAssertEqual(NotchBannerParser.summaryParts("信息，林小雨，晚上七点，三里屯见"),
                       ["信息", "林小雨", "晚上七点，三里屯见"], "内容里的逗号原样留着")
        XCTAssertEqual(NotchBannerParser.summaryParts("微信、王姐、在吗"), ["微信", "王姐", "在吗"])
        XCTAssertEqual(NotchBannerParser.summaryParts("微信，王姐，在吗，已堆叠"), ["微信", "王姐", "在吗"])
        XCTAssertEqual(NotchBannerParser.summaryParts("WhatsApp, Dan, ok, stacked"), ["WhatsApp", "Dan", "ok"])
        XCTAssertEqual(NotchBannerParser.summaryParts("信息"), ["信息"])
        XCTAssertEqual(NotchBannerParser.summaryParts("  "), [])
    }

    func testChineseSummaryWithFullWidthCommasIsRecognised() {
        // 中文系统的横幅：字没有标识，辅助说明用全角逗号。以前只按「, 」拆，认不出 App，一条都不弹。
        let node = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: "C1",
                                   description: "信息，林小雨，到楼下了",
                                   children: [NotchBannerNode(role: "AXStaticText", value: "林小雨"),
                                              NotchBannerNode(role: "AXStaticText", value: "到楼下了")])
        let found = NotchBannerParser.incoming(in: window([node]), enabled: NotchMessageApp.allCases)
        XCTAssertEqual(found.first?.app, .messages)
        XCTAssertEqual(found.first?.sender, "林小雨")
        XCTAssertEqual(found.first?.preview, "到楼下了")

        let onlySummary = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterAlertStack",
                                          description: "微信，王姐，下午三点开会，别迟到，已堆叠")
        let wechat = NotchBannerParser.incoming(in: window([onlySummary]), enabled: NotchMessageApp.allCases).first
        XCTAssertEqual(wechat?.app, .wechat)
        XCTAssertEqual(wechat?.sender, "王姐")
        XCTAssertEqual(wechat?.preview, "下午三点开会，别迟到")
    }

    func testAppLabelNeverUsesSenderOrBody() {
        XCTAssertEqual(NotchBannerParser.appLabel(NotchBanner(header: "微信", title: "王姐", body: "在吗")), "微信")
        XCTAssertEqual(NotchBannerParser.appLabel(NotchBanner(title: "王姐", body: "在吗", summary: "信息，王姐，在吗")), "信息")
        XCTAssertEqual(NotchBannerParser.appLabel(NotchBanner(title: "王姐", imageNames: ["Slack"])), "Slack")
        XCTAssertNil(NotchBannerParser.appLabel(NotchBanner(title: "王姐", body: "在吗")))
    }

    // MARK: 状态几行

    func testAccessibilityLine() {
        let ok = NotchMessageDiagnosis.accessibility(.init(trusted: true))
        XCTAssertEqual(ok.level, .ok)
        XCTAssertNil(ok.hint)

        let never = NotchMessageDiagnosis.accessibility(.init(trusted: false, lastTrustedBuild: nil, currentBuild: "0.8 (9)"))
        XCTAssertEqual(never.level, .warning)
        XCTAssertEqual(never.value, tr("未授权"))
        XCTAssertTrue(never.hint?.contains(NotchMessageDiagnosis.reAddHint) == true, "没授权时总说怎么移除再添加")

        let lost = NotchMessageDiagnosis.Snapshot(trusted: false, lastTrustedBuild: "0.8 (8)", currentBuild: "0.8 (9)")
        XCTAssertTrue(lost.trustLostAfterUpdate)
        XCTAssertEqual(NotchMessageDiagnosis.accessibility(lost).value, tr("更新后授权失效"))

        let sameBuild = NotchMessageDiagnosis.Snapshot(trusted: false, lastTrustedBuild: "0.8 (9)", currentBuild: "0.8 (9)")
        XCTAssertFalse(sameBuild.trustLostAfterUpdate, "同一个版本里被关掉的不算更新失效")
    }

    func testNotificationCenterLine() {
        XCTAssertEqual(NotchMessageDiagnosis.notificationCenter(.init(trusted: false)).level, .idle)
        XCTAssertEqual(NotchMessageDiagnosis.notificationCenter(.init(trusted: true, notificationCenterRunning: false)).level,
                       .warning)
        XCTAssertEqual(NotchMessageDiagnosis.notificationCenter(.init(trusted: true, connected: false)).value, tr("正在连接"))
        let connected = NotchMessageDiagnosis.notificationCenter(.init(trusted: true, connected: true))
        XCTAssertEqual(connected.level, .ok)
        XCTAssertEqual(connected.value, tr("已连接"))
    }

    func testLastBannerLine() {
        let never = NotchMessageDiagnosis.lastBanner(.init(trusted: true), now: now)
        XCTAssertEqual(never.value, tr("从未"))
        XCTAssertNotNil(never.hint)
        let recent = NotchMessageDiagnosis.lastBanner(.init(trusted: true, lastBanner: now.addingTimeInterval(-10),
                                                            lastBannerApp: "微信"), now: now)
        XCTAssertEqual(recent.level, .ok)
        XCTAssertEqual(recent.value, "\(tr("刚刚")) · 微信")
        XCTAssertEqual(NotchMessageDiagnosis.lines(.init(trusted: true), now: now).count, 3)
    }

    // MARK: 测试通知

    func testProbeTokenAndMatching() {
        XCTAssertEqual(NotchMessageProbe.makeToken(42), "#0042")
        XCTAssertEqual(NotchMessageProbe.makeToken(123_456), "#3456")
        XCTAssertEqual(NotchMessageProbe.makeToken(-7), "#0007")
        let token = "#0042"
        let body = NotchMessageProbe.body(token: token)
        XCTAssertTrue(body.contains(token))
        XCTAssertTrue(NotchMessageProbe.matches(NotchBanner(header: "码头", title: "消息灵动岛", body: body), token: token))
        XCTAssertTrue(NotchMessageProbe.matches(NotchBanner(summary: "码头，消息灵动岛，\(body)"), token: token))
        XCTAssertFalse(NotchMessageProbe.matches(NotchBanner(header: "码头", body: "#0043"), token: token))
        XCTAssertFalse(NotchMessageProbe.matches(NotchBanner(body: body), token: ""))

        let incoming = NotchMessageProbe.incoming(NotchBanner(header: "码头", body: body), token: token)
        XCTAssertEqual(incoming?.isTest, true)
        XCTAssertEqual(incoming?.key, "probe:#0042")
        XCTAssertNotNil(incoming?.sender)
        let message = NotchMessage(incoming!, date: now)
        XCTAssertTrue(message.isTest)
        XCTAssertFalse(message.canReplyInline, "测试那条不能回复")
        XCTAssertNil(NotchMessageProbe.incoming(NotchBanner(header: "信息", body: "在吗"), token: token))
    }

    func testProbeStates() {
        var probe = NotchMessageProbe()
        XCTAssertNil(probe.line(.init(trusted: true)))
        probe.sent(token: "#0001", at: now)
        XCTAssertEqual(probe.token, "#0001")
        XCTAssertEqual(probe.line(.init(trusted: true))?.level, .idle)
        XCTAssertFalse(probe.tick(now: now.addingTimeInterval(5)))
        XCTAssertTrue(probe.tick(now: now.addingTimeInterval(NotchMessageProbe.timeout)))
        XCTAssertNil(probe.token)
        XCTAssertEqual(probe.state, .missed(at: now.addingTimeInterval(NotchMessageProbe.timeout)))
        XCTAssertFalse(probe.tick(now: now.addingTimeInterval(100)), "没读到之后不再变")

        // 没读到时的说明按现状给。
        let untrusted = probe.line(.init(trusted: false))
        XCTAssertEqual(untrusted?.level, .warning)
        XCTAssertTrue(untrusted?.hint?.contains(NotchMessageDiagnosis.reAddHint) == true)
        let noBanner = probe.line(.init(trusted: true))?.hint
        let someBanner = probe.line(.init(trusted: true, lastBanner: now))?.hint
        XCTAssertNotNil(noBanner)
        XCTAssertNotEqual(noBanner, someBanner)

        probe.sent(token: "#0002", at: now)
        probe.received(at: now.addingTimeInterval(1))
        XCTAssertEqual(probe.line(.init(trusted: true))?.level, .ok)
        XCTAssertFalse(probe.tick(now: now.addingTimeInterval(60)))

        probe.notificationsOff()
        XCTAssertEqual(probe.line(.init(trusted: true))?.level, .warning)
        probe.inactive()
        XCTAssertEqual(probe.line(.init(trusted: true))?.level, .warning)
    }

    func testInboxClearsTestMessages() {
        var inbox = NotchMessageInbox()
        let real = NotchMessage(app: .wechat, sender: "王姐", preview: "在吗", date: now)
        let test = NotchMessage(app: .messages, sender: "码头", preview: "测试", date: now, isTest: true)
        inbox.receive(real)
        inbox.receive(test)
        XCTAssertEqual(inbox.current?.id, test.id)
        XCTAssertTrue(inbox.clearTests())
        XCTAssertEqual(inbox.messages.map(\.id), [real.id])
        XCTAssertEqual(inbox.current?.id, real.id)
        XCTAssertEqual(inbox.unreadCounts.map { $0.app }, [.wechat], "测试那条不留未读数")

        var onlyTest = NotchMessageInbox()
        onlyTest.receive(test)
        XCTAssertFalse(onlyTest.clearTests())
        XCTAssertTrue(onlyTest.isEmpty)
        XCTAssertNil(onlyTest.current)
    }
}
