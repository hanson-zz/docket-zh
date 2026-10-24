import XCTest

/// 消息灵动岛：设置、横幅解析（认不出就静默）、去重、消息堆叠、自动收起、
/// 和码头自己刘海内容的优先级、信息快速回复的脚本。
final class NotchMessageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 设置

    func testSettingsDefaultOffWithAllAppsAndAutoYield() {
        let settings = NotchMessageSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.apps, [.messages, .whatsapp, .wechat])
        XCTAssertEqual(settings.position, .auto)
        XCTAssertEqual(settings.dismissSeconds, 6)
    }

    func testSettingsDecodeLeniently() throws {
        let old = try JSONDecoder().decode(NotchMessageSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old, NotchMessageSettings())
        let odd = try JSONDecoder().decode(NotchMessageSettings.self, from: Data(
            #"{"enabled":true,"apps":["wechat","telegram","messages"],"position":"floating","seconds":7}"#.utf8))
        XCTAssertTrue(odd.enabled)
        XCTAssertEqual(odd.apps, [.messages, .wechat], "认不出的 App 丢掉，按固定顺序")
        XCTAssertEqual(odd.position, .auto, "认不出的位置按默认")
        XCTAssertEqual(odd.dismissSeconds, 6, "不在选项里的秒数按默认")
    }

    func testSettingsRoundTripAndToggleKeepsOrder() throws {
        var settings = NotchMessageSettings()
        settings.enabled = true
        settings.set(.messages, false)
        settings.set(.messages, true)
        XCTAssertEqual(settings.apps, [.messages, .whatsapp, .wechat])
        settings.set(.whatsapp, false)
        settings.position = .capsule
        settings.seconds = 10
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(NotchMessageSettings.self, from: data), settings)
    }

    func testPersistedStateCarriesSettings() throws {
        var state = PersistedState()
        state.notchMessage.enabled = true
        state.notchMessage.position = .belowNotch
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(back.notchMessage, state.notchMessage)
        // 老状态文件没有这一组：默认关。
        let legacy = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.notchMessage.enabled)
    }

    func testProGate() {
        var settings = NotchMessageSettings()
        XCTAssertFalse(ProLicenseGate.notchMessageActive(settings, unlocked: true), "默认关")
        settings.enabled = true
        XCTAssertTrue(ProLicenseGate.notchMessageActive(settings, unlocked: true))
        XCTAssertFalse(ProLicenseGate.notchMessageActive(settings, unlocked: false), "没解锁不生效，设置留着")
        XCTAssertTrue(settings.enabled)
        settings.apps = []
        XCTAssertFalse(ProLicenseGate.notchMessageActive(settings, unlocked: true), "一个 App 都没选也不观察")
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.notchMessage))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.notchMessage)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.notchMessage)), "消息灵动岛")
    }

    // MARK: 认 App

    func testAppMatching() {
        XCTAssertEqual(NotchMessageApp.match(name: "信息"), .messages)
        XCTAssertEqual(NotchMessageApp.match(name: " Messages "), .messages)
        XCTAssertEqual(NotchMessageApp.match(name: "WhatsApp"), .whatsapp)
        XCTAssertEqual(NotchMessageApp.match(name: "微信"), .wechat)
        XCTAssertEqual(NotchMessageApp.match(name: "WeChat"), .wechat)
        XCTAssertNil(NotchMessageApp.match(name: "Slack"))
        XCTAssertNil(NotchMessageApp.match(name: ""))
        XCTAssertNil(NotchMessageApp.match(name: nil))
        XCTAssertEqual(NotchMessageApp.match(bundleID: "com.apple.mobilesms"), .messages)
        XCTAssertEqual(NotchMessageApp.match(bundleID: "net.whatsapp.WhatsApp"), .whatsapp)
        XCTAssertEqual(NotchMessageApp.match(bundleID: "desktop.WhatsApp"), .whatsapp)
        XCTAssertEqual(NotchMessageApp.match(bundleID: "com.tencent.xinWeChat"), .wechat)
        XCTAssertNil(NotchMessageApp.match(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(NotchMessageApp.messages.canReplyInline)
        XCTAssertFalse(NotchMessageApp.whatsapp.canReplyInline)
        XCTAssertFalse(NotchMessageApp.wechat.canReplyInline)
    }

    // MARK: 横幅解析

    private func text(_ id: String?, _ value: String) -> NotchBannerNode {
        NotchBannerNode(role: "AXStaticText", identifier: id, value: value)
    }

    /// macOS 26 一条横幅的样子：窗口 ▸ 宿主 ▸ 组 ▸ 滚动区 ▸ 组 ▸ 横幅，横幅里
    /// header / title / body 三段字。
    private func window(_ banners: [NotchBannerNode]) -> NotchBannerNode {
        NotchBannerNode(role: "AXWindow", subrole: "AXSystemDialog", title: "Notification Center", children: [
            NotchBannerNode(role: "AXGroup", subrole: "AXHostingView", children: [
                NotchBannerNode(role: "AXGroup", children: [
                    NotchBannerNode(role: "AXScrollArea", identifier: "AXNotificationListItems", children: [
                        NotchBannerNode(role: "AXGroup", children: banners),
                    ]),
                ]),
            ]),
        ])
    }

    private func banner(id: String? = "8F0C", subrole: String = "AXNotificationCenterBanner",
                        header: String?, title: String?, body: String?, summary: String? = nil) -> NotchBannerNode {
        var children: [NotchBannerNode] = [NotchBannerNode(role: "AXImage", description: nil)]
        if let header { children.append(text("header", header)) }
        if let title { children.append(text("title", title)) }
        if let body { children.append(text("body", body)) }
        return NotchBannerNode(role: "AXGroup", subrole: subrole, identifier: id, description: summary,
                               children: children)
    }

    func testParsesMessagesBanner() {
        let tree = window([banner(header: "信息", title: "林小雨", body: "晚上七点三里屯见吗？\n我订了靠窗的位置")])
        let found = NotchBannerParser.incoming(in: tree, enabled: NotchMessageApp.allCases)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.app, .messages)
        XCTAssertEqual(found.first?.sender, "林小雨")
        XCTAssertEqual(found.first?.preview, "晚上七点三里屯见吗？ 我订了靠窗的位置", "换行并成空格")
        XCTAssertEqual(found.first?.key, "id:8F0C")
        XCTAssertEqual(found.first?.previewHidden, false)
    }

    func testLocatedPathsPointAtTheBanner() {
        let tree = window([banner(header: "信息", title: "林小雨", body: "在吗")])
        let located = NotchBannerParser.located(incomingIn: tree, enabled: NotchMessageApp.allCases)
        XCTAssertEqual(located.first?.path, [0, 0, 0, 0, 0])
        XCTAssertEqual(located.first?.pressable, true)
        var node = tree
        for index in located.first?.path ?? [] { node = node.children[index] }
        XCTAssertEqual(node.subrole, "AXNotificationCenterBanner")
        let stack = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterAlertStack",
                                    description: "微信, 王姐, 在吗, stacked")
        XCTAssertEqual(NotchBannerParser.located(incomingIn: window([stack]), enabled: [.wechat]).first?.pressable,
                       false, "一摞点下去只是展开，不替用户点")
    }

    func testDisabledAppAndUnknownAppAreSilent() {
        let tree = window([banner(header: "WhatsApp", title: "Daniel Wu", body: "Flight lands at 6:20")])
        XCTAssertTrue(NotchBannerParser.incoming(in: tree, enabled: [.messages, .wechat]).isEmpty)
        let slack = window([banner(header: "Slack", title: "#general", body: "lunch?")])
        XCTAssertTrue(NotchBannerParser.incoming(in: slack, enabled: NotchMessageApp.allCases).isEmpty)
    }

    func testUnrecognisedStructureIsSilent() {
        // 没有横幅 subrole、什么字都没有、空窗口、乱七八糟的树：都不弹，也不崩。
        XCTAssertTrue(NotchBannerParser.incoming(in: NotchBannerNode(), enabled: NotchMessageApp.allCases).isEmpty)
        let noBanner = window([NotchBannerNode(role: "AXGroup", children: [text("title", "信息")])])
        XCTAssertTrue(NotchBannerParser.incoming(in: noBanner, enabled: NotchMessageApp.allCases).isEmpty)
        let empty = window([NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner")])
        XCTAssertTrue(NotchBannerParser.incoming(in: empty, enabled: NotchMessageApp.allCases).isEmpty)
        // 非常深的树不会无限往下找。
        var deep = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner",
                                   children: [text("header", "微信"), text("title", "王姐"), text("body", "在吗")])
        for _ in 0..<40 { deep = NotchBannerNode(role: "AXGroup", children: [deep]) }
        XCTAssertTrue(NotchBannerParser.incoming(in: deep, enabled: NotchMessageApp.allCases).isEmpty)
    }

    func testFallsBackToTextOrderWithoutIdentifiers() {
        let node = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterAlert", children: [
            NotchBannerNode(role: "AXStaticText", value: "微信"),
            NotchBannerNode(role: "AXStaticText", value: "王姐"),
            NotchBannerNode(role: "AXStaticText", value: "下午的会改到三点"),
        ])
        let found = NotchBannerParser.incoming(in: window([node]), enabled: NotchMessageApp.allCases)
        XCTAssertEqual(found.first?.app, .wechat)
        XCTAssertEqual(found.first?.sender, "王姐")
        XCTAssertEqual(found.first?.preview, "下午的会改到三点")
        XCTAssertEqual(found.first?.key, "text:wechat|王姐|下午的会改到三点", "没有系统标识时按内容去重")
    }

    func testFallsBackToSummary() {
        let stack = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterAlertStack", identifier: nil,
                                    description: "WhatsApp, Daniel Wu, Flight lands at 6:20, can you grab me?, stacked")
        let found = NotchBannerParser.incoming(in: window([stack]), enabled: NotchMessageApp.allCases)
        XCTAssertEqual(found.first?.app, .whatsapp)
        XCTAssertEqual(found.first?.sender, "Daniel Wu")
        XCTAssertEqual(found.first?.preview, "Flight lands at 6:20, can you grab me?", "内容里的逗号保留，末尾的 stacked 去掉")
    }

    func testAppNameFromSummaryWhenHeaderMissing() {
        let node = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: "A1",
                                   description: "信息, 林小雨, 好的", children: [text("title", "林小雨"), text("body", "好的")])
        let found = NotchBannerParser.incoming(in: window([node]), enabled: NotchMessageApp.allCases)
        XCTAssertEqual(found.first?.app, .messages)
        XCTAssertEqual(found.first?.sender, "林小雨")
    }

    func testHiddenPreviews() {
        // 系统关了预览：标题写 App 名，内容写「通知」。
        let system = window([banner(header: "信息", title: "信息", body: "通知")])
        let a = NotchBannerParser.incoming(in: system, enabled: NotchMessageApp.allCases).first
        XCTAssertEqual(a?.app, .messages)
        XCTAssertNil(a?.sender)
        XCTAssertNil(a?.preview)
        XCTAssertEqual(a?.previewHidden, true)
        // 微信自己关了预览。
        let wechat = window([banner(header: nil, title: "微信", body: "你收到了一条消息。")])
        let b = NotchBannerParser.incoming(in: wechat, enabled: NotchMessageApp.allCases).first
        XCTAssertEqual(b?.app, .wechat, "标题就是 App 名时也认得出")
        XCTAssertNil(b?.sender)
        XCTAssertEqual(b?.previewHidden, true)
        // 有发件人但内容是占位话。
        let counted = window([banner(header: "微信", title: "王姐", body: "[3条]")])
        XCTAssertEqual(NotchBannerParser.incoming(in: counted, enabled: NotchMessageApp.allCases).first?.preview, nil)
        XCTAssertTrue(NotchBannerParser.isPlaceholder("收到 3 条新消息"))
        XCTAssertTrue(NotchBannerParser.isPlaceholder("New message."))
        XCTAssertFalse(NotchBannerParser.isPlaceholder("新消息到了吗"))
    }

    func testNotificationCenterListIsIgnored() {
        // 打开通知中心那一栏：带桌面小组件，或一下子很多条，都不当新消息。
        let widgets = window([banner(header: "信息", title: "林小雨", body: "在吗"),
                              NotchBannerNode(role: "AXGroup", identifier: "widget-local:com.apple.weather")])
        XCTAssertTrue(NotchBannerParser.isListPanel(widgets))
        XCTAssertTrue(NotchBannerParser.incoming(in: widgets, enabled: NotchMessageApp.allCases).isEmpty)
        let many = window((0..<6).map { banner(id: "B\($0)", header: "信息", title: "人\($0)", body: "嗨") })
        XCTAssertTrue(NotchBannerParser.incoming(in: many, enabled: NotchMessageApp.allCases).isEmpty)
        let two = window((0..<2).map { banner(id: "B\($0)", header: "信息", title: "人\($0)", body: "嗨") })
        XCTAssertEqual(NotchBannerParser.incoming(in: two, enabled: NotchMessageApp.allCases).count, 2)
    }

    // MARK: 去重

    func testDeduperById() {
        var dedupe = NotchMessageDeduper()
        XCTAssertTrue(dedupe.isNew("id:A", now: now))
        XCTAssertFalse(dedupe.isNew("id:A", now: now.addingTimeInterval(1)), "排版变化又报一次")
        XCTAssertFalse(dedupe.isNew("id:A", now: now.addingTimeInterval(200)))
        XCTAssertTrue(dedupe.isNew("id:B", now: now.addingTimeInterval(2)))
        XCTAssertTrue(dedupe.isNew("id:A", now: now.addingTimeInterval(200 + NotchMessageDeduper.idWindow)), "很久以后的同一个标识算新的")
    }

    func testDeduperByTextExpiresQuickly() {
        var dedupe = NotchMessageDeduper()
        XCTAssertTrue(dedupe.isNew("text:wechat|王姐|好", now: now))
        XCTAssertFalse(dedupe.isNew("text:wechat|王姐|好", now: now.addingTimeInterval(2)))
        XCTAssertTrue(dedupe.isNew("text:wechat|王姐|好", now: now.addingTimeInterval(2 + NotchMessageDeduper.textWindow)),
                      "对方隔一会儿又发同一句，照样弹")
    }

    func testDeduperRememberPrimesWithoutShowing() {
        var dedupe = NotchMessageDeduper()
        dedupe.remember("id:old", now: now)
        XCTAssertFalse(dedupe.isNew("id:old", now: now.addingTimeInterval(1)), "开始观察前就在屏幕上的不弹")
    }

    // MARK: 堆叠

    private func message(_ app: NotchMessageApp, _ sender: String?, _ minutesAgo: Double = 0) -> NotchMessage {
        NotchMessage(app: app, sender: sender, preview: sender == nil ? nil : "内容",
                     date: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testInboxStacksNewestFirst() {
        var inbox = NotchMessageInbox()
        XCTAssertNil(inbox.current)
        XCTAssertEqual(inbox.remainingCount, 0)
        let wang = message(.wechat, "王姐", 9)
        let lin = message(.messages, "林小雨", 2)
        let daniel = message(.whatsapp, "Daniel Wu")
        inbox.receive(wang)
        inbox.receive(lin)
        inbox.receive(daniel)
        XCTAssertEqual(inbox.current?.id, daniel.id, "最新的在最上面")
        XCTAssertEqual(inbox.remainingCount, 2)
        XCTAssertEqual(NotchMessageText.remaining(inbox.remainingCount), "还有 2 条")
        XCTAssertNil(NotchMessageText.remaining(0))
        XCTAssertEqual(inbox.next?.id, lin.id)
        XCTAssertEqual(inbox.unreadCounts.map(\.app), [.messages, .whatsapp, .wechat])
        XCTAssertEqual(inbox.unreadCounts.map(\.count), [1, 1, 1])
    }

    func testLaterKeepsUnreadAndMovesOn() {
        var inbox = NotchMessageInbox()
        let a = message(.wechat, "王姐", 3)
        let b = message(.messages, "林小雨")
        inbox.receive(a)
        inbox.receive(b)
        XCTAssertTrue(inbox.later(), "还有一条没点过稍后")
        XCTAssertEqual(inbox.current?.id, a.id)
        XCTAssertFalse(inbox.later(), "都点过稍后：收起")
        XCTAssertEqual(inbox.messages.count, 2, "稍后的还算未读")
        XCTAssertTrue(inbox.focus(.messages))
        XCTAssertEqual(inbox.current?.id, b.id)
    }

    func testHandledRemovesWholeConversation() {
        var inbox = NotchMessageInbox()
        inbox.receive(message(.messages, "林小雨", 5))
        inbox.receive(message(.wechat, "王姐", 4))
        inbox.receive(message(.messages, "林小雨", 1))
        XCTAssertEqual(inbox.current?.sender, "林小雨")
        XCTAssertTrue(inbox.handleCurrent())
        XCTAssertEqual(inbox.messages.map(\.sender), ["王姐"], "同一个人的几条一起处理掉")
        XCTAssertEqual(inbox.current?.sender, "王姐")
        XCTAssertFalse(inbox.handleCurrent())
        XCTAssertTrue(inbox.isEmpty)
        XCTAssertNil(inbox.current)
        XCTAssertFalse(inbox.handleCurrent(), "空的时候不出错")
        XCTAssertFalse(inbox.later())
    }

    func testReceiveWhileReplyingKeepsTheCard() {
        var inbox = NotchMessageInbox()
        let lin = message(.messages, "林小雨", 1)
        inbox.receive(lin)
        let wang = message(.wechat, "王姐")
        inbox.receive(wang, makeCurrent: false)
        XCTAssertEqual(inbox.current?.id, lin.id, "正在回复时不换人")
        XCTAssertEqual(inbox.remainingCount, 1)
        XCTAssertTrue(inbox.handle(lin.id))
        XCTAssertEqual(inbox.current?.id, wang.id)
        XCTAssertTrue(inbox.handle(UUID()), "找不到的那条不动，current 还在")
        var empty = NotchMessageInbox()
        empty.receive(wang, makeCurrent: false)
        XCTAssertEqual(empty.current?.id, wang.id, "没有 current 时照样显示")
    }

    func testLimitNeverDropsTheCurrentCard() {
        var inbox = NotchMessageInbox()
        let first = message(.messages, "第一位")
        inbox.receive(first)
        for index in 0..<(NotchMessageInbox.limit + 3) {
            inbox.receive(message(.wechat, "人\(index)"), makeCurrent: false)
        }
        XCTAssertEqual(inbox.current?.id, first.id)
        XCTAssertLessThanOrEqual(inbox.messages.count, NotchMessageInbox.limit + 1)
    }

    func testHiddenSenderMessagesAreTheirOwnConversation() {
        var inbox = NotchMessageInbox()
        inbox.receive(message(.wechat, nil, 2))
        inbox.receive(message(.wechat, nil))
        inbox.handleCurrent()
        XCTAssertEqual(inbox.messages.count, 1, "不知道是谁的，各算各的")
    }

    func testClearAppAndLimit() {
        var inbox = NotchMessageInbox()
        for index in 0..<(NotchMessageInbox.limit + 5) {
            inbox.receive(message(index.isMultiple(of: 2) ? .wechat : .messages, "人\(index)"))
        }
        XCTAssertEqual(inbox.messages.count, NotchMessageInbox.limit)
        inbox.clear(.wechat)
        XCTAssertTrue(inbox.messages.allSatisfy { $0.app == .messages })
        XCTAssertNotNil(inbox.current)
        XCTAssertEqual(inbox.unreadCounts.map(\.app), [.messages])
        inbox.clearAll()
        XCTAssertTrue(inbox.isEmpty)
        XCTAssertFalse(inbox.focus())
    }

    func testMessageHelpers() {
        let lin = message(.messages, "林小雨")
        XCTAssertEqual(lin.initial, "林")
        XCTAssertEqual(message(.whatsapp, "daniel Wu").initial, "D")
        XCTAssertEqual(message(.whatsapp, "+86 138").initial, "8")
        XCTAssertNil(message(.wechat, nil).initial)
        XCTAssertTrue(lin.canReplyInline)
        XCTAssertFalse(message(.wechat, "王姐").canReplyInline)
        XCTAssertFalse(message(.messages, nil).canReplyInline, "不知道发给谁不能回复")
        XCTAssertEqual(lin.avatarHue, message(.messages, "林小雨").avatarHue, "同一个名字同一种颜色")
        XCTAssertTrue((0..<6).contains(lin.avatarHue))
    }

    // MARK: 卡片上的字

    func testTexts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9, minute: 40))!
        XCTAssertEqual(NotchMessageText.time(base.addingTimeInterval(-20), now: base, calendar: calendar), "刚刚")
        XCTAssertEqual(NotchMessageText.time(base.addingTimeInterval(-120), now: base, calendar: calendar), "09:38")
        XCTAssertEqual(NotchMessageText.time(base.addingTimeInterval(-86_400), now: base, calendar: calendar), "10/23")
        let next = NotchMessage(app: .wechat, sender: "王姐", preview: "x", date: base.addingTimeInterval(-540))
        XCTAssertEqual(NotchMessageText.clock(next.date, calendar: calendar), "09:31")
        XCTAssertTrue(NotchMessageText.nextLine(next).hasPrefix("下一条：微信 · 王姐 · "))
        XCTAssertEqual(NotchMessageText.hiddenDetail(.wechat), "微信关闭了通知预览，打开微信查看内容")
        XCTAssertEqual(NotchMessageText.hiddenHint(.wechat), "在微信设置里打开预览后可显示内容")
        XCTAssertEqual(NotchMessageText.jump("打开"), "打开 ↗")
    }

    // MARK: 自动收起

    func testCountdownPausesWhileHovering() {
        var countdown = NotchMessageCountdown()
        XCTAssertFalse(countdown.expired(at: now))
        countdown.start(6, at: now)
        XCTAssertFalse(countdown.expired(at: now.addingTimeInterval(5.9)))
        XCTAssertTrue(countdown.expired(at: now.addingTimeInterval(6)))
        countdown.start(6, at: now)
        countdown.pause(at: now.addingTimeInterval(5))
        XCTAssertTrue(countdown.isPaused)
        XCTAssertFalse(countdown.expired(at: now.addingTimeInterval(60)), "悬停时不收")
        countdown.resume(at: now.addingTimeInterval(60))
        XCTAssertFalse(countdown.expired(at: now.addingTimeInterval(62)), "离开后至少再给 3 秒")
        XCTAssertTrue(countdown.expired(at: now.addingTimeInterval(63)))
        countdown.stop()
        XCTAssertFalse(countdown.isRunning)
        countdown.resume(at: now)
        XCTAssertFalse(countdown.isRunning, "没暂停过的恢复不做事")
    }

    // MARK: 优先级

    func testPriorityOrder() {
        typealias P = NotchMessagePriority
        XCTAssertEqual(P.stage(.init(), waited: 0), .show)
        XCTAssertEqual(P.stage(.init(fullscreen: true, aiPanelOpen: true, reminderShowing: true), waited: 0), .suppressed,
                       "全屏最先")
        XCTAssertEqual(P.stage(.init(aiPanelOpen: true, reminderShowing: true), waited: 0), .indicatorOnly,
                       "AI 对话开着只显示未读数")
        XCTAssertEqual(P.stage(.init(reminderShowing: true), waited: 1), .hold)
        XCTAssertEqual(P.stage(.init(reminderShowing: true), waited: P.maxWait), .indicatorOnly, "等太久就只留未读数")
        XCTAssertTrue(P.expandsAfterWait(arrival: now.addingTimeInterval(-5), now: now))
        XCTAssertFalse(P.expandsAfterWait(arrival: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(P.expandsAfterWait(arrival: nil, now: now))
        XCTAssertTrue(P.islandYields(cardExpanded: true))
        XCTAssertFalse(P.islandYields(cardExpanded: false))
        XCTAssertTrue(P.aiEntryVisible(enabled: true, islandShowing: false, cardExpanded: false))
        XCTAssertFalse(P.aiEntryVisible(enabled: true, islandShowing: false, cardExpanded: true))
        XCTAssertFalse(P.aiEntryVisible(enabled: true, islandShowing: true, cardExpanded: false))
        XCTAssertFalse(P.aiEntryVisible(enabled: false, islandShowing: false, cardExpanded: false))
    }

    // MARK: 快速回复

    func testReplyQuotingAndScript() {
        XCTAssertEqual(NotchMessageReply.quoted("他说\"好\""), #""他说\"好\"""#)
        XCTAssertEqual(NotchMessageReply.quoted("第一行\n第二行"), #""第一行" & return & "第二行""#)
        XCTAssertEqual(NotchMessageReply.quoted(#"a\b"#), #""a\\b""#)
        let script = NotchMessageReply.script(text: "好的，七点前到", recipient: #"林"小雨"#)
        XCTAssertTrue(script.contains(#"set targetName to "林\"小雨""#))
        XCTAssertTrue(script.contains(#"send "好的，七点前到" to item 1 of hits"#))
        XCTAssertTrue(script.contains("if (count of hits) > 1 then return \"ambiguous\""), "重名不发")
        XCTAssertNil(NotchMessageReply.normalized("  \n "))
        XCTAssertEqual(NotchMessageReply.normalized("  好的 "), "好的")
        XCTAssertEqual(NotchMessageReply.normalized(String(repeating: "a", count: 3000))?.count, NotchMessageReply.maxLength)
    }

    func testReplyOutcome() {
        XCTAssertEqual(NotchMessageReply.outcome(result: "sent", errorNumber: nil), .sent)
        XCTAssertEqual(NotchMessageReply.outcome(result: "notfound", errorNumber: nil), .notFound)
        XCTAssertEqual(NotchMessageReply.outcome(result: "ambiguous", errorNumber: nil), .ambiguous)
        XCTAssertEqual(NotchMessageReply.outcome(result: nil, errorNumber: -1743), .denied)
        XCTAssertEqual(NotchMessageReply.outcome(result: nil, errorNumber: -1744), .denied)
        XCTAssertEqual(NotchMessageReply.outcome(result: nil, errorNumber: -1728), .failed)
        XCTAssertEqual(NotchMessageReply.outcome(result: "什么", errorNumber: nil), .failed)
        XCTAssertNil(NotchMessageReply.message(.sent))
        XCTAssertNotNil(NotchMessageReply.message(.denied))
        XCTAssertTrue(NotchMessageReply.message(.denied)!.contains("自动化"))
    }
}
