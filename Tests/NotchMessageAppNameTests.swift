import XCTest

/// 消息灵动岛：macOS 27 上微信 4.x（4.1.15.55）的横幅没有 header、没有图标，只有 title / body
/// 和辅助说明，App 名得从辅助说明里找。夹具照用户真机诊断的那棵 8 节点树搭：
/// AXWindow(AXSystemDialog) ▸ AXGroup(AXHostingView) ▸ AXGroup ▸ AXScrollArea ▸
/// AXGroup(AXNotificationCenterBanner, uuid) ▸ title / body，旁边一个 widgets-overlay-view。
final class NotchMessageAppNameTests: XCTestCase {
    private let uuid = "6A1F2C3D-0000-4000-8000-00000000BEEF"

    private func realTree(summary: String?, title: String = "王姐", body: String = "今晚七点到店里对一下货",
                          actions: [String] = [], help: String? = nil,
                          extraChildren: [NotchBannerNode] = []) -> NotchBannerNode {
        let banner = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: uuid,
                                     description: summary, help: help, actions: actions,
                                     children: [NotchBannerNode(role: "AXStaticText", identifier: "title", value: title),
                                                NotchBannerNode(role: "AXStaticText", identifier: "body", value: body)]
                                         + extraChildren)
        return NotchBannerNode(role: "AXWindow", subrole: "AXSystemDialog", children: [
            NotchBannerNode(role: "AXGroup", subrole: "AXHostingView", children: [
                NotchBannerNode(role: "AXGroup", children: [
                    NotchBannerNode(role: "AXScrollArea", children: [banner]),
                ]),
                NotchBannerNode(role: "AXGroup", identifier: "widgets-overlay-view"),
            ]),
        ])
    }

    private func first(_ tree: NotchBannerNode, names: NotchAppNames = .builtIn,
                       enabled: [NotchMessageApp] = NotchMessageApp.allCases) -> NotchLocatedIncoming? {
        NotchBannerParser.located(incomingIn: tree, enabled: enabled, names: names).first
    }

    func testFixtureMatchesTheRealDiagnosis() {
        let tree = realTree(summary: "微信，王姐，今晚七点到店里对一下货")
        let report = NotchBannerParser.report(tree, enabled: NotchMessageApp.allCases)
        XCTAssertTrue(report.contains("nodes=8"))
        XCTAssertTrue(report.contains("roles=[AXGroup:4, AXScrollArea:1, AXStaticText:2, AXWindow:1]"))
        XCTAssertTrue(report.contains("subroles=[AXHostingView:1, AXNotificationCenterBanner:1, AXSystemDialog:1]"))
        XCTAssertTrue(report.contains("ids=[body:1, title:1, uuid:1, widgets-overlay-view:1]"))
        XCTAssertTrue(report.contains("banner path=[0, 0, 0, 0]"))
        XCTAssertEqual(first(tree)?.path, [0, 0, 0, 0])
    }

    func testSummaryShapes() {
        let shapes: [(String, String)] = [
            ("微信，王姐，今晚七点到店里对一下货", "中文全角逗号"),
            ("WeChat, 王姐, 今晚七点到店里对一下货", "英文"),
            ("Weixin, 王姐, 今晚七点到店里对一下货", "海外版名字"),
            ("下午10:31，微信，王姐，今晚七点到店里对一下货", "带时间前缀"),
            ("22:31, WeChat, 王姐, 今晚七点到店里对一下货", "带 24 小时制时间"),
            ("王姐，微信，今晚七点到店里对一下货", "App 名在第二段"),
            ("微信: 王姐", "冒号"),
            ("微信：王姐，今晚七点到店里对一下货", "全角冒号"),
            ("WeChat,王姐,今晚七点到店里对一下货", "逗号没空格"),
            ("\u{200E}微信\u{200F}，王姐，今晚七点到店里对一下货", "夹着方向控制符"),
            ("微信 WeChat，王姐，今晚七点到店里对一下货", "中英并列"),
            ("WeChat（微信）, 王姐, 今晚七点到店里对一下货", "全角括号"),
            ("WeChat(微信), 王姐, 今晚七点到店里对一下货", "括号前没空格"),
            ("微信，王姐，今晚七点到店里对一下货，已堆叠", "末尾已堆叠"),
        ]
        for (summary, label) in shapes {
            let found = first(realTree(summary: summary))
            XCTAssertEqual(found?.incoming.app, .wechat, label)
            XCTAssertEqual(found?.incoming.sender, "王姐", label)
            XCTAssertEqual(found?.incoming.preview, "今晚七点到店里对一下货", label)
            XCTAssertEqual(found?.incoming.key, "id:\(uuid)", label)
            XCTAssertEqual(found?.pressable, true, label)
        }
    }

    func testRecognitionSourceIsReported() {
        let tree = realTree(summary: "下午10:31，微信，王姐，今晚七点到店里对一下货")
        let report = NotchBannerParser.report(tree, enabled: NotchMessageApp.allCases)
        XCTAssertTrue(report.contains("app=wechat"))
        XCTAssertTrue(report.contains("message from wechat"))
        XCTAssertTrue(report.contains("matched=summary[1]"))
        XCTAssertTrue(report.contains("summary parts=4 sep=[fullwidth-comma]"))
        XCTAssertFalse(report.contains("王姐"))
        XCTAssertFalse(report.contains("对一下货"))
    }

    func testUnknownAppIsNotMisread() {
        // 别的 App：不认，也不因为内容或发件人正好叫「信息」「微信」而认错。
        XCTAssertNil(first(realTree(summary: "钉钉，王姐，今晚七点到店里对一下货")))
        XCTAssertNil(first(realTree(summary: "Slack，王姐，信息", body: "信息")), "内容就是「信息」")
        XCTAssertNil(first(realTree(summary: "Slack，微信群，今晚", title: "微信群", body: "今晚")))
        let hidden = first(realTree(summary: "微信，你收到了一条消息", title: "微信", body: "你收到了一条消息"))
        XCTAssertEqual(hidden?.incoming.app, .wechat, "微信自己关了预览：标题就是 App 名")
        XCTAssertNil(hidden?.incoming.sender, "标题是 App 名时不当发件人")
        XCTAssertNil(first(realTree(summary: "微信支付，收款到账", title: "收款", body: "到账")), "只认完全一样的名字")
        XCTAssertNil(first(realTree(summary: nil)))
        // 认出来但没启用。
        XCTAssertNil(first(realTree(summary: "微信，王姐，在吗"), enabled: [.messages]))
    }

    func testOtherLanguagesAndApps() {
        XCTAssertEqual(first(realTree(summary: "Nachrichten, Anna, Hallo", title: "Anna", body: "Hallo"))?.incoming.app, .messages)
        XCTAssertEqual(first(realTree(summary: "訊息，林小雨，到了", title: "林小雨", body: "到了"))?.incoming.app, .messages)
        XCTAssertEqual(first(realTree(summary: "メッセージ、田中、了解", title: "田中", body: "了解"))?.incoming.app, .messages)
        XCTAssertEqual(first(realTree(summary: "WhatsApp Beta, Dan, ok", title: "Dan", body: "ok"))?.incoming.app, .whatsapp)
    }

    func testExtraNamesFromInstalledApps() {
        // 内置表里没有的本地化名字，由 Services 从 App 的 Info.plist 读出来传进来。
        let tree = realTree(summary: "微信测试版，王姐，今晚七点到店里对一下货")
        XCTAssertNil(first(tree))
        let names = NotchAppNames(extra: [.wechat: ["微信测试版", "  "], .messages: ["微信"]])
        XCTAssertEqual(first(tree, names: names)?.incoming.app, .wechat)
        XCTAssertEqual(names.extra[.wechat], ["微信测试版"], "空的不收")
        XCTAssertNil(names.extra[.messages], "和别的 App 内置名字撞了的不收")
        XCTAssertEqual(names.summary, "wechat:微信测试版")
        XCTAssertEqual(NotchAppNames.builtIn.summary, "none")
        let long = NotchAppNames(extra: [.wechat: [String(repeating: "长", count: 41)]])
        XCTAssertNil(long.extra[.wechat])
    }

    func testBundleIDHints() {
        XCTAssertEqual(NotchMessageApp.match(bundleIDIn: "com.tencent.xinWeChat"), .wechat)
        XCTAssertEqual(NotchMessageApp.match(bundleIDIn: "app:com.tencent.xinWeChat/notification"), .wechat)
        XCTAssertNil(NotchMessageApp.match(bundleIDIn: "com.tencent.xinWeChat2"), "改过 bundle id 的副本不算")
        XCTAssertEqual(NotchMessageApp.match(bundleIDIn: "net.whatsapp.WhatsApp"), .whatsapp)
        XCTAssertNil(NotchMessageApp.match(bundleIDIn: nil))
        // 辅助说明认不出，横幅元素的帮助里带着 bundle id。
        let tree = realTree(summary: "王姐，今晚七点到店里对一下货", help: "com.tencent.xinWeChat")
        let found = first(tree)
        XCTAssertEqual(found?.incoming.app, .wechat)
        XCTAssertEqual(found?.incoming.sender, "王姐")
        XCTAssertTrue(NotchBannerParser.report(tree, enabled: NotchMessageApp.allCases).contains("matched=bundle"))
    }

    func testReportWhenNotRecognised() {
        // 第一段像 App 名：原文写出来，好补名字表。
        let unknown = NotchBannerParser.report(realTree(summary: "WeChat Work，王姐，今晚七点到店里对一下货"),
                                               enabled: NotchMessageApp.allCases)
        XCTAssertTrue(unknown.contains("app not recognised"))
        XCTAssertTrue(unknown.contains("head=\"WeChat Work\""))
        XCTAssertTrue(unknown.contains("summary parts=3 sep=[fullwidth-comma]"))
        XCTAssertTrue(unknown.contains("matched=none"))
        XCTAssertFalse(unknown.contains("王姐"))
        XCTAssertFalse(unknown.contains("对一下货"))

        // 第一段是发件人（「发件人，内容」那种）：不写原文，只写长度。
        let senderFirst = NotchBannerParser.report(realTree(summary: "王姐，今晚七点到店里对一下货"),
                                                   enabled: NotchMessageApp.allCases)
        XCTAssertTrue(senderFirst.contains("head=len:2"))
        XCTAssertTrue(senderFirst.contains("summary parts=2"))
        XCTAssertFalse(senderFirst.contains("王姐"))
        // 发件人带后缀、和标题互相包含：也不写。
        let group = NotchBannerParser.report(realTree(summary: "家人群 (5)，在吗", title: "家人群", body: "在吗"),
                                             enabled: NotchMessageApp.allCases)
        XCTAssertFalse(group.contains("家人群"))
        // 太长的第一段只写长度。
        let long = NotchBannerParser.report(realTree(summary: String(repeating: "长", count: 30)),
                                            enabled: NotchMessageApp.allCases)
        XCTAssertTrue(long.contains("head=len:30"))
        XCTAssertTrue(long.contains("sep=[none]"))
        // 不可见字符标出来。
        let marks = NotchBannerParser.report(realTree(summary: "\u{200E}钉钉，王姐，在吗"), enabled: NotchMessageApp.allCases)
        XCTAssertTrue(marks.contains("invisible=yes"))
        // 没有辅助说明。
        XCTAssertTrue(NotchBannerParser.report(realTree(summary: nil), enabled: NotchMessageApp.allCases)
            .contains("summary=none"))
    }

    func testAppLabelSkipsSender() {
        let senderFirst = NotchBanner(title: "王姐", body: "在吗", summary: "王姐，在吗")
        XCTAssertNil(NotchBannerParser.appLabel(senderFirst))
        let second = NotchBanner(title: "王姐", body: "在吗", summary: "王姐，微信，在吗")
        XCTAssertEqual(NotchBannerParser.appLabel(second), "微信")
    }

    func testSummarySegmentsAndTime() {
        let split = NotchBannerParser.summarySegments("下午10:31，微信，王姐，在吗, 好")
        XCTAssertEqual(split.parts, ["下午10:31", "微信", "王姐", "在吗", "好"])
        XCTAssertEqual(split.separators, ["fullwidth-comma", "comma"])
        XCTAssertTrue(NotchBannerParser.isTimeLike("22:31"))
        XCTAssertTrue(NotchBannerParser.isTimeLike("10:30 PM"))
        XCTAssertTrue(NotchBannerParser.isTimeLike("下午10:31"))
        XCTAssertTrue(NotchBannerParser.isTimeLike("现在"))
        XCTAssertFalse(NotchBannerParser.isTimeLike("王姐"))
        XCTAssertEqual(NotchBannerParser.summaryParts("下午10:31，微信，王姐，在吗，好"), ["微信", "王姐", "在吗，好"])
        XCTAssertEqual(NotchBannerParser.summaryParts("22:31"), ["22:31"])
        XCTAssertEqual(NotchAppNames.normalized(" \u{200E}WeChat（微信）\u{00A0}: "), "wechat (微信)")
    }

    func testSummaryOnlyBannerWithTimePrefix() {
        // 只有辅助说明、开头带时间：时间跳过，App、发件人、内容照常拆。
        let stack = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterBanner",
                                    description: "下午10:31，微信，王姐，今晚七点，到店里")
        let tree = NotchBannerNode(role: "AXWindow", children: [stack])
        let found = NotchBannerParser.incoming(in: tree, enabled: NotchMessageApp.allCases).first
        XCTAssertEqual(found?.app, .wechat)
        XCTAssertEqual(found?.sender, "王姐")
        XCTAssertEqual(found?.preview, "今晚七点，到店里")
    }

    // MARK: 关掉系统横幅

    func testCloseMethod() {
        let closeAction = "Name:Close\nTarget:0x0\nSelector:(null)"
        XCTAssertEqual(NotchBannerParser.actionDisplayName(closeAction), "Close")
        XCTAssertEqual(NotchBannerParser.actionDisplayName("AXPress"), "AXPress")

        let withAction = realTree(summary: "微信，王姐，在吗", actions: ["AXPress", "Name:显示详细信息\nTarget:0x0", "Name:关闭\nTarget:0x0"])
        let banner = NotchBannerParser.located(in: withAction).first?.banner
        XCTAssertEqual(banner?.close, .action("Name:关闭\nTarget:0x0"), "动作名原样存着，执行时原样传回")
        XCTAssertEqual(banner?.actionNames, ["AXPress", "显示详细信息", "关闭"])
        let report = NotchBannerParser.report(withAction, enabled: NotchMessageApp.allCases)
        XCTAssertTrue(report.contains("close=action"))
        XCTAssertTrue(report.contains("actions=[AXPress,显示详细信息,关闭]"))

        let withButton = realTree(summary: "微信，王姐，在吗", extraChildren: [
            NotchBannerNode(role: "AXButton", subrole: "AXCloseButton", description: "关闭"),
        ])
        XCTAssertEqual(NotchBannerParser.located(in: withButton).first?.banner.close, .button(path: [2]))

        // 只有「清除」、只有 AXPress：不关。
        let clearOnly = realTree(summary: "微信，王姐，在吗", actions: ["AXPress", "Name:Clear\nTarget:0x0"])
        XCTAssertNil(NotchBannerParser.located(in: clearOnly).first?.banner.close)
        XCTAssertTrue(NotchBannerParser.report(clearOnly, enabled: NotchMessageApp.allCases).contains("close=none"))
        // 一摞的不关。
        let stack = NotchBannerNode(role: "AXGroup", subrole: "AXNotificationCenterAlertStack",
                                    description: "微信，王姐，在吗", actions: ["Name:Close\nTarget:0x0"])
        XCTAssertNil(NotchBannerParser.closeMethod(stack))
    }

    func testCloseSettingDefaultsOffAndDecodes() throws {
        XCTAssertFalse(NotchMessageSettings().closeSystemBanner)
        let old = try JSONDecoder().decode(NotchMessageSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertFalse(old.closeSystemBanner, "老状态文件没有这一项时按关读")
        var on = NotchMessageSettings()
        on.closeSystemBanner = true
        let back = try JSONDecoder().decode(NotchMessageSettings.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.closeSystemBanner)
    }
}
