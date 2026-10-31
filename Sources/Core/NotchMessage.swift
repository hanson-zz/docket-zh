import Foundation

// MARK: - 消息灵动岛（码头 Pro）
//
// 信息、WhatsApp、微信的通知到达时，在刘海下方展开一张液态玻璃消息卡。消息从
// 系统通知横幅读来：辅助功能（AX）观察「通知中心」进程里的横幅，把读到的那一小
// 棵树抄成 `NotchBannerNode`，交给这里解析。横幅的结构不是公开接口，每个 macOS
// 版本都可能变，所以解析一律宽松：认不出就返回 nil，界面静默不弹，绝不崩溃。
// 码头只读横幅，不拦截、不修改系统通知。
//
// 这里只有纯逻辑（设置、解析、去重、消息堆叠、收起倒计时、和码头自己刘海内容的
// 优先级），AX 读取、窗口和 AppleScript 都在 App / Services 那边。

/// 支持的三个 App。
public enum NotchMessageApp: String, Codable, CaseIterable, Sendable {
    case messages
    case whatsapp
    case wechat

    /// 设置和卡片上的名字。
    public var title: String {
        switch self {
        case .messages: tr("信息", context: "app")
        case .whatsapp: "WhatsApp"
        case .wechat: tr("微信")
        }
    }

    /// 打开、取图标用的 bundle id，第一个是首选。WhatsApp 新版是 Catalyst 的
    /// net.whatsapp.WhatsApp，老的 Electron 版是 desktop.WhatsApp。
    public var bundleIDs: [String] {
        switch self {
        case .messages: ["com.apple.MobileSMS"]
        case .whatsapp: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]
        case .wechat: ["com.tencent.xinWeChat"]
        }
    }

    /// 横幅上可能写的 App 名（按 `NotchAppNames.normalized` 整理后比较：小写、去掉
    /// 方向控制符、全角括号和空格换成半角）：各语言界面、繁体，以及老名字。微信 4.x
    /// （bundle id 仍是 com.tencent.xinWeChat，App 包叫 WeChat.app）中文界面显示「微信」，
    /// 英文界面显示「WeChat」，海外版官网改叫「Weixin」；装机时本地化名字再由
    /// `NotchAppNameCatalog` 从 App 自己的 Info.plist 动态补。
    public var bannerNames: [String] {
        switch self {
        case .messages:
            ["信息", "messages", "imessage", "訊息", "短信", "message",
             "メッセージ", "메시지", "nachrichten", "mensajes", "messaggi", "mensagens", "сообщения",
             "berichten", "meddelanden", "beskeder", "meldinger", "viestit", "wiadomości", "mesajlar",
             "zprávy", "üzenetek", "повідомлення", "tin nhắn", "pesan", "ข้อความ", "الرسائل", "הודעות"]
        case .whatsapp:
            ["whatsapp", "whatsapp messenger", "whatsapp desktop", "whatsapp beta", "واتساب", "וואטסאפ"]
        case .wechat:
            ["微信", "wechat", "weixin", "微信 wechat", "wechat 微信", "微信 weixin", "weixin 微信",
             "wechat (微信)", "微信 (wechat)", "weixin (微信)", "微信 (weixin)",
             "wechat for mac", "weixin for mac", "微信 mac 版", "微信mac版", "微信 for mac", "위챗"]
        }
    }

    /// 能不能在刘海里直接回复。只有「信息」有可用的 AppleScript；WhatsApp、微信只跳转。
    public var canReplyInline: Bool { self == .messages }

    /// 认横幅上写的 App 名（只认内置名字表里完全一样的），认不出时为 nil。
    public static func match(name raw: String?) -> NotchMessageApp? {
        NotchAppNames.builtIn.match(raw)
    }

    /// 按 bundle id 认，大小写不敏感。
    public static func match(bundleID raw: String?) -> NotchMessageApp? {
        guard let id = raw?.lowercased(), !id.isEmpty else { return nil }
        return allCases.first { app in app.bundleIDs.contains { $0.lowercased() == id } }
    }

    /// 一段字里带着哪个 App 的 bundle id（横幅元素的标识、帮助等属性有时会带出来）。
    /// 要在字里完整出现、前后不是字母数字，免得 com.tencent.xinWeChat2 这类改过的副本也算。
    public static func match(bundleIDIn raw: String?) -> NotchMessageApp? {
        guard let text = raw?.lowercased(), !text.isEmpty else { return nil }
        for app in allCases {
            for id in app.bundleIDs {
                var searchRange = text.startIndex..<text.endIndex
                let needle = id.lowercased()
                while let range = text.range(of: needle, range: searchRange) {
                    let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                    let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                    let edge: (Character?) -> Bool = { c in
                        guard let c else { return true }
                        return !(c.isLetter || c.isNumber)
                    }
                    if edge(before), edge(after) { return app }
                    searchRange = range.upperBound..<text.endIndex
                }
            }
        }
        return nil
    }
}

/// 认 App 名用的名字表：内置的 `bannerNames`，加上装机时从 App 自己的 Info.plist 读到的
/// 本地化显示名（`NotchAppNameCatalog` 在 Services 读，这里只收字，方便测试）。只认整理后
/// 完全一样的名字，不做包含、不做模糊匹配，认不出宁可不弹也不认错。
public struct NotchAppNames: Equatable, Sendable {
    /// 额外的名字，已整理。
    public private(set) var extra: [NotchMessageApp: [String]]

    public static let builtIn = NotchAppNames()

    /// 额外名字最长多少字，再长的不像 App 名，不收。
    public static let maxExtraLength = 40

    public init(extra: [NotchMessageApp: [String]] = [:]) {
        var cleaned: [NotchMessageApp: [String]] = [:]
        for app in NotchMessageApp.allCases {
            var seen = Self.builtInNormalized[app] ?? []
            var list: [String] = []
            for raw in extra[app] ?? [] {
                let name = Self.normalized(raw)
                guard !name.isEmpty, name.count <= Self.maxExtraLength, !seen.contains(name) else { continue }
                // 和别的 App 的内置名字撞了的不收，免得一个 App 的本地化名把另一个顶掉。
                guard !NotchMessageApp.allCases.contains(where: { other in
                    other != app && Self.builtInNormalized[other]?.contains(name) == true
                }) else { continue }
                seen.insert(name)
                list.append(name)
            }
            if !list.isEmpty { cleaned[app] = list }
        }
        self.extra = cleaned
    }

    /// 内置名字先比，再比额外的。
    public func match(_ raw: String?) -> NotchMessageApp? {
        guard let raw else { return nil }
        let name = Self.normalized(raw)
        guard !name.isEmpty else { return nil }
        if let app = NotchMessageApp.allCases.first(where: { Self.builtInNormalized[$0]?.contains(name) == true }) {
            return app
        }
        return NotchMessageApp.allCases.first { extra[$0]?.contains(name) == true }
    }

    /// 额外名字的一行摘要，诊断信息用（只是 App 名，不涉及消息）。
    public var summary: String {
        let parts = NotchMessageApp.allCases.compactMap { app -> String? in
            guard let names = extra[app], !names.isEmpty else { return nil }
            return "\(app.rawValue):\(names.prefix(6).joined(separator: "|"))"
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    /// 内置名字整理后的样子，只算一次。
    static let builtInNormalized: [NotchMessageApp: Set<String>] = Dictionary(
        uniqueKeysWithValues: NotchMessageApp.allCases.map { ($0, Set($0.bannerNames.map(normalized))) })

    /// 横幅文字里可能夹着的不可见字符：方向控制符、零宽字符。
    static let invisible: Set<Unicode.Scalar> = Set(
        [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
         0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF, 0x061C].compactMap(Unicode.Scalar.init))

    static func hasInvisible(_ text: String) -> Bool {
        text.unicodeScalars.contains { invisible.contains($0) }
    }

    /// 整理一个名字：去掉不可见字符，各种空格换成普通空格并合并，全角括号换成半角，
    /// 去掉首尾空白和末尾的冒号，小写。
    public static func normalized(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where !invisible.contains(scalar) {
            switch scalar.value {
            case 0x00A0, 0x2007, 0x202F, 0x3000, 0x2009, 0x200A: scalars.append(" ")
            case 0xFF08: scalars.append("(")
            case 0xFF09: scalars.append(")")
            default: scalars.append(scalar)
            }
        }
        var text = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // 括号前后的空格统一成「名字 (别名)」，「WeChat(微信)」「WeChat （微信）」都算同一个。
        text = text.replacingOccurrences(of: #"\s*\(\s*"#, with: " (", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\)"#, with: ")", options: .regularExpression)
        while let last = text.last, last == ":" || last == "：" { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// 消息卡放在哪。
public enum NotchMessagePosition: String, Codable, CaseIterable, Sendable {
    /// 默认：看拾掇等刘海 App 在不在刘海附近，让开它们。见 `NotchMessagePlacement`。
    case auto
    /// 总在刘海正下方，不管别的刘海 App。
    case belowNotch
    /// 刘海旁边的小胶囊，完全不占刘海中间，点开才展开卡片。
    case capsule

    public var title: String {
        switch self {
        case .auto: tr("自动让位")
        case .belowNotch: tr("刘海下方")
        case .capsule: tr("刘海旁小胶囊")
        }
    }
}

/// 设置 ▸ 通用 ▸ 消息灵动岛。默认关；码头 Pro。
public struct NotchMessageSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    /// 启用哪几个 App，默认三个都开。
    public var apps: [NotchMessageApp] = NotchMessageApp.allCases
    public var position: NotchMessagePosition = .auto
    /// 展开后几秒自动收起（指针停在卡片上时暂停）。
    public var seconds: Int = NotchMessageSettings.defaultSeconds
    /// 卡片弹出后替用户关掉那条系统横幅（只在横幅自己带「关闭」动作或关闭按钮时），默认关。
    public var closeSystemBanner: Bool = false

    public static let defaultSeconds = 6
    public static let secondChoices: [Int] = [4, 6, 10]

    public init() {}

    public func isOn(_ app: NotchMessageApp) -> Bool { apps.contains(app) }

    public mutating func set(_ app: NotchMessageApp, _ on: Bool) {
        var next = Set(apps)
        if on { next.insert(app) } else { next.remove(app) }
        // 按固定顺序存，设置文件不会因为点的先后不同而变。
        apps = NotchMessageApp.allCases.filter { next.contains($0) }
    }

    /// 存着的秒数不在选项里时按默认读，免得选择器上一行都没选中。
    public var dismissSeconds: Int {
        NotchMessageSettings.secondChoices.contains(seconds) ? seconds : NotchMessageSettings.defaultSeconds
    }

    private enum CodingKeys: String, CodingKey { case enabled, apps, position, seconds, closeSystemBanner }

    /// 宽松解码：老状态文件没有这一组、或以后多了认不出的 App 和位置，都照常读。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        if let raw = try? c.decodeIfPresent([String].self, forKey: .apps) {
            let known = Set(raw.compactMap(NotchMessageApp.init(rawValue:)))
            apps = NotchMessageApp.allCases.filter { known.contains($0) }
        }
        if let raw = try? c.decodeIfPresent(String.self, forKey: .position),
           let value = NotchMessagePosition(rawValue: raw) {
            position = value
        }
        seconds = (try? c.decodeIfPresent(Int.self, forKey: .seconds)) ?? NotchMessageSettings.defaultSeconds
        closeSystemBanner = (try? c.decodeIfPresent(Bool.self, forKey: .closeSystemBanner)) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(apps.map(\.rawValue), forKey: .apps)
        try c.encode(position.rawValue, forKey: .position)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(closeSystemBanner, forKey: .closeSystemBanner)
    }
}

// MARK: - 横幅：AX 树的快照

/// 从「通知中心」进程读到的一个 AX 元素，只抄解析要用的几个属性。读的那边限制
/// 了深度和个数，这里不再担心树太大。
public struct NotchBannerNode: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var description: String?
    public var title: String?
    public var value: String?
    /// AXHelp（提示文字），有的版本会带出 App 名或 bundle id。
    public var help: String?
    /// 元素支持的 AX 动作名（只给横幅元素读）。自定义动作形如「Name:Close\nTarget:…」。
    public var actions: [String]
    /// 元素上有哪些 AX 属性（只给横幅元素读，只要名字），诊断用。
    public var attributes: [String]
    /// 不常见属性里读到的字（只给横幅元素读）：只用来找 bundle id，不写进诊断。
    public var attributeTexts: [String] = []
    /// AXAttributedDescription 的字（只给横幅元素读）：找 App 名、bundle id 用，诊断里只写长度。
    public var attributedDescription: String?
    /// AXAttributedDescription 里出现过的属性键名（诊断用，不含内容）。
    public var attributedKeys: [String] = []
    /// AXAttributedDescription 里字体、颜色以外的属性值（链接之类）：只用来找 bundle id、App 名。
    public var attributedValues: [String] = []
    public var children: [NotchBannerNode]

    public init(role: String? = nil, subrole: String? = nil, identifier: String? = nil,
                description: String? = nil, title: String? = nil, value: String? = nil,
                help: String? = nil, actions: [String] = [], attributes: [String] = [],
                children: [NotchBannerNode] = []) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.description = description
        self.title = title
        self.value = value
        self.help = help
        self.actions = actions
        self.attributes = attributes
        self.children = children
    }

    /// 这个元素上能读的文字：静态文字的值，没有时用标题。
    var text: String? {
        let raw = value ?? title
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// 一条横幅上读到的字。字段都可能是 nil。
public struct NotchBanner: Equatable, Sendable {
    /// 系统给每条通知的标识（macOS 26 上是 UUID），读不到时为 nil。
    public var identifier: String?
    /// 横幅顶上的 App 名（`header`）。
    public var header: String?
    /// 发件人或群名（`title`）。
    public var title: String?
    public var subtitle: String?
    /// 消息内容（`body`）。
    public var body: String?
    /// 横幅整体的辅助说明，形如「信息, 林小雨, 晚上七点…」。
    public var summary: String?
    /// App 图标这类图片元素上的说明，有时就是 App 名。
    public var imageNames: [String]
    /// 是几条叠在一起的那一摞（`AXNotificationCenterAlertStack`）。
    public var stacked: Bool
    /// 横幅元素自己的标识、帮助、标题、值：只用来找里面有没有 bundle id，不写进诊断。
    public var hints: [String]
    /// 横幅元素的动作名（自定义动作取「Name:」那一段），诊断和关横幅用。
    public var actionNames: [String]
    /// 能怎么关掉这条横幅；没有安全的关法时为 nil。
    public var close: NotchBannerClose?
    /// 横幅元素上不常见的 AX 属性名（常见的几个去掉），诊断用：看新系统有没有带 App 的属性。
    public var extraAttributes: [String] = []
    /// 横幅元素属性里可能带 App 名或 bundle id 的字（`NotchBannerClue`），认不出 App 时用；
    /// 诊断里只写长度和命中。
    public var clues: [NotchBannerClue] = []
    /// AXAttributedDescription 里的属性键名，诊断用。
    public var attributedKeys: [String] = []

    public init(identifier: String? = nil, header: String? = nil, title: String? = nil,
                subtitle: String? = nil, body: String? = nil, summary: String? = nil,
                imageNames: [String] = [], stacked: Bool = false, hints: [String] = [],
                actionNames: [String] = [], close: NotchBannerClose? = nil) {
        self.identifier = identifier
        self.header = header
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.summary = summary
        self.imageNames = imageNames
        self.stacked = stacked
        self.hints = hints
        self.actionNames = actionNames
        self.close = close
    }
}

/// 关掉一条系统横幅的办法：执行横幅元素上名为「关闭」的动作，或者按一下横幅里的关闭按钮。
public enum NotchBannerClose: Equatable, Sendable {
    /// 横幅元素上的动作，原样存 AX 给的动作名（执行时要原样传回去）。
    case action(String)
    /// 横幅里的关闭按钮，路径从横幅元素往下算。
    case button(path: [Int])

    /// 诊断里写的种类。
    public var kind: String {
        switch self {
        case .action: "action"
        case .button: "button"
        }
    }
}

/// 解析出来的一条新消息，还没进堆叠。
public struct NotchIncoming: Equatable, Sendable {
    public var app: NotchMessageApp
    /// 发件人；对方关了预览、或认不出时为 nil。
    public var sender: String?
    /// 消息内容；关了预览时为 nil。
    public var preview: String?
    /// 去重用的键：有系统标识用标识，没有时用内容。
    public var key: String
    /// 设置里「发一条测试通知」读回来的那条（`NotchMessageProbe`）：不能回复、不留未读。
    public var isTest: Bool

    public var previewHidden: Bool { preview == nil }

    public init(app: NotchMessageApp, sender: String?, preview: String?, key: String, isTest: Bool = false) {
        self.app = app
        self.sender = sender
        self.preview = preview
        self.key = key
        self.isTest = isTest
    }
}

/// 一条新消息和它的横幅在树里的位置。
public struct NotchLocatedIncoming: Equatable, Sendable {
    public var path: [Int]
    public var incoming: NotchIncoming
    /// 能不能替用户点这条横幅打开对应的聊天。
    public var pressable: Bool

    public init(path: [Int], incoming: NotchIncoming, pressable: Bool) {
        self.path = path
        self.incoming = incoming
        self.pressable = pressable
    }
}

public enum NotchBannerParser {
    /// 通知中心的 bundle id。
    public static let notificationCenterBundleID = "com.apple.notificationcenterui"

    /// 横幅元素的 subrole：Sonoma 起的单条横幅、提醒，macOS 26 几条叠在一起时的
    /// 那一摞，以及老版本的名字。
    public static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner", "AXNotificationCenterAlert",
        "AXNotificationCenterAlertStack", "AXNotificationCenterNotification",
    ]
    static let stackSubrole = "AXNotificationCenterAlertStack"

    /// 「几条叠在一起」时辅助说明末尾多出来的词。
    static let stackedWords: Set<String> = ["stacked", "已堆叠", "堆叠", "已堆疊"]

    /// 关了预览时横幅上写的占位话（去掉句末标点、小写比较）。系统关预览是标题写
    /// App 名、内容写「通知」；微信、WhatsApp 自己关预览时写的是下面这些。
    static let placeholderBodies: Set<String> = [
        "通知", "notification", "通知内容已隐藏",
        "你收到了一条消息", "您收到了一条消息", "你收到了一条新消息", "您收到了一条新消息",
        "你有一条新消息", "您有一条新消息", "收到一条新消息", "收到一条消息", "[1条]",
        "new message", "you have a new message", "you received a new message", "message", "消息", "新消息",
    ]

    /// 树里最多看多深，防一个反常的树。
    static let maxDepth = 14

    /// 是不是通知中心的整个列表（点菜单栏时间打开的那一栏）。那里是以前的通知，
    /// 不能当新消息弹出来：带桌面小组件，或者一下子有好几条横幅，就当是列表。
    public static func isListPanel(_ window: NotchBannerNode) -> Bool {
        var banners = 0
        var widgets = false
        walk(window, depth: 0) { node in
            if let id = node.identifier, id.hasPrefix("widget-local:") || id == "widget-editor-button" {
                widgets = true
            }
            if let subrole = node.subrole, bannerSubroles.contains(subrole) { banners += 1 }
        }
        return widgets || banners > 4
    }

    /// 一个窗口里的所有横幅。认不出结构时是空的。
    public static func banners(in window: NotchBannerNode) -> [NotchBanner] {
        located(in: window).map(\.banner)
    }

    /// 同 `banners(in:)`，带上每条横幅在树里的位置（从窗口往下每一层是第几个孩子），
    /// 读树的那边按位置找回横幅元素，点「打开」时替用户点一下那条横幅。
    public static func located(in window: NotchBannerNode) -> [(path: [Int], banner: NotchBanner)] {
        guard !isListPanel(window) else { return [] }
        var found: [(path: [Int], banner: NotchBanner)] = []
        collect(window, path: [], into: &found)
        // 没有认得的 subrole（系统换了名字）：退一步按「孩子里有 body 和 title / header 标识的字」认。
        if found.isEmpty { collectByTexts(window, path: [], into: &found) }
        return found
    }

    /// 桌面小组件（也挂在通知中心进程里）：读树时不往里走，省得把预算花在它们身上。
    public static func isDesktopWidget(identifier: String?) -> Bool {
        identifier?.hasPrefix("widget-local:") == true
    }

    static let textIdentifiers: Set<String> = ["title", "body", "subtitle", "header"]

    private static func collectByTexts(_ node: NotchBannerNode, path: [Int],
                                       into found: inout [(path: [Int], banner: NotchBanner)]) {
        guard path.count <= maxDepth, node.role != "AXStaticText" else { return }
        let marked = node.children.filter { child in
            child.role == "AXStaticText" && textIdentifiers.contains(child.identifier?.lowercased() ?? "")
        }
        // 要同时有内容（body）和标题或 App 名（title / header），只有一段带标识的字不算。
        let marks = Set(marked.compactMap { $0.identifier?.lowercased() })
        if marks.contains("body"), marks.contains("title") || marks.contains("header") {
            found.append((path, banner(from: node)))
            return
        }
        for (index, child) in node.children.enumerated() { collectByTexts(child, path: path + [index], into: &found) }
    }

    // MARK: 诊断信息

    /// 一个窗口的结构摘要，给设置里「复制诊断信息」用：角色、subrole、标识的统计，认没
    /// 认成通知列表，每条横幅认成哪个 App、为什么没弹。不抄发件人和消息内容（只写有没有），
    /// App 名只写认出来的；`probeToken` 出现在哪条横幅上也标出来。
    public static func report(_ window: NotchBannerNode, enabled: [NotchMessageApp], probeToken: String? = nil,
                              testTokens: [String] = [], names: NotchAppNames = .builtIn) -> String {
        var nodes = 0
        var roles: [String: Int] = [:]
        var subroles: [String: Int] = [:]
        var ids: [String: Int] = [:]
        walk(window, depth: 0) { node in
            nodes += 1
            if let role = node.role { roles[role, default: 0] += 1 }
            if let subrole = node.subrole { subroles[subrole, default: 0] += 1 }
            if let id = node.identifier, !id.isEmpty { ids[reportIdentifier(id), default: 0] += 1 }
        }
        func list(_ counts: [String: Int]) -> String {
            counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        }
        var lines = ["window role=\(window.role ?? "-") subrole=\(window.subrole ?? "-") nodes=\(nodes)",
                     "  roles=[\(list(roles))]",
                     "  subroles=[\(list(subroles))]",
                     "  ids=[\(list(ids))]"]
        if isListPanel(window) {
            lines.append("  -> notification list or desktop widget, skipped")
            return lines.joined(separator: "\n")
        }
        let banners = located(in: window)
        if banners.isEmpty { lines.append("  -> no banner found") }
        for entry in banners {
            let analysis = analyse(entry.banner, path: entry.path, enabled: enabled,
                                   testTokens: [probeToken].compactMap { $0 } + testTokens, names: names)
            lines.append(contentsOf: analysis.lines.map { "  " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    /// 诊断里 summary 那一行：拆成几段、用的什么分隔符、有没有不可见字符；认不出 App 时
    /// 再写第一段（App 名通常在的位置），但只在它像 App 名时写原文，否则只写长度。
    /// 发件人和内容的原文绝不写：第一段和标题、内容一样或互相包含时也只写长度。
    static func summaryReport(_ banner: NotchBanner, recognised: Recognition?) -> String {
        guard let summary = banner.summary else { return "summary=none" }
        let split = summarySegments(summary)
        var parts = ["summary parts=\(split.parts.count)",
                     "sep=[\(split.separators.isEmpty ? "none" : split.separators.joined(separator: ","))]",
                     "chars=\(summary.count)"]
        if NotchAppNames.hasInvisible(summary) { parts.append("invisible=yes") }
        if recognised == nil, let head = split.parts.first {
            if looksLikeAppName(head, in: banner) {
                parts.append("head=\"\(head)\"")
            } else {
                parts.append("head=len:\(head.count)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// 动作名在诊断里的写法：太长截断、去掉换行。
    static func reportWord(_ raw: String) -> String {
        let flat = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 24 ? String(flat.prefix(24)) + "…" : flat
    }

    /// 一段字像不像 App 名：不长（≤24 字），不是空的，和横幅的标题、副标题、内容既不一样也不
    /// 互相包含（防止把发件人或内容写进诊断、当成 App 名）。
    static func looksLikeAppName(_ raw: String, in banner: NotchBanner) -> Bool {
        let name = NotchAppNames.normalized(raw)
        guard !name.isEmpty, raw.count <= 24 else { return false }
        for other in [banner.title, banner.subtitle, banner.body].compactMap({ $0 }) {
            let text = NotchAppNames.normalized(other)
            guard !text.isEmpty else { continue }
            if text == name || text.contains(name) || name.contains(text) { return false }
        }
        return true
    }

    /// 标识里 UUID 那种一条一个的写成 uuid，小组件只留前缀，免得摘要又长又带内容。
    static func reportIdentifier(_ id: String) -> String {
        if UUID(uuidString: id) != nil { return "uuid" }
        if isDesktopWidget(identifier: id) { return "widget-local:*" }
        return id.count > 40 ? String(id.prefix(40)) + "…" : id
    }

    private static func collect(_ node: NotchBannerNode, path: [Int],
                                into found: inout [(path: [Int], banner: NotchBanner)]) {
        guard path.count <= maxDepth else { return }
        if let subrole = node.subrole, bannerSubroles.contains(subrole) {
            found.append((path, banner(from: node)))
            // 一摞里面单条的横幅也可能挂在下面：接着往里找，靠去重合并。
            if subrole == stackSubrole {
                for (index, child) in node.children.enumerated() { collect(child, path: path + [index], into: &found) }
            }
            return
        }
        for (index, child) in node.children.enumerated() { collect(child, path: path + [index], into: &found) }
    }

    /// 一条横幅元素上的字：先按标识（header / title / subtitle / body）认，认不出
    /// 时按静态文字的先后，再不行拆辅助说明。
    public static func banner(from node: NotchBannerNode) -> NotchBanner {
        var result = NotchBanner(identifier: cleaned(node.identifier), summary: cleaned(node.description),
                                 stacked: node.subrole == stackSubrole)
        result.hints = ([node.identifier, node.help, node.title, node.value] + node.attributeTexts.map(Optional.some))
            .compactMap { cleaned($0) }
        result.actionNames = node.actions.map(actionDisplayName)
        result.close = closeMethod(node)
        result.extraAttributes = node.attributes.filter { !commonAttributes.contains($0) }
        result.attributedKeys = node.attributedKeys
        let clueSources: [(String, String?)] = [
            ("attr-desc", node.attributedDescription),
            ("attr-values", node.attributedValues.isEmpty ? nil : node.attributedValues.joined(separator: "\n")),
            ("desc", node.description), ("id", node.identifier), ("help", node.help),
        ]
        result.clues = clueSources.compactMap { source, text in
            cleaned(text).map { NotchBannerClue(source: source, text: $0) }
        }
        var loose: [String] = []
        var images: [String] = []
        func visit(_ child: NotchBannerNode, depth: Int) {
            guard depth <= maxDepth else { return }
            // 里面再套一条横幅（一摞）时只看最上面这条自己的字。
            if depth > 0, let subrole = child.subrole, bannerSubroles.contains(subrole) { return }
            let role = child.role ?? ""
            if role == "AXImage", let name = cleaned(child.description) ?? cleaned(child.title) {
                images.append(name)
            }
            if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField", let text = child.text {
                switch child.identifier?.lowercased() {
                case "header", "app", "appname", "app-name": result.header = result.header ?? text
                case "title": result.title = result.title ?? text
                case "subtitle": result.subtitle = result.subtitle ?? text
                case "body", "message", "messagebody": result.body = result.body ?? text
                default: loose.append(text)
                }
            }
            for grand in child.children { visit(grand, depth: depth + 1) }
        }
        visit(node, depth: 0)
        result.imageNames = images

        let named = result.header != nil || result.title != nil || result.body != nil
        if !named, !loose.isEmpty {
            switch loose.count {
            case 1: result.body = loose[0]
            case 2: result.title = loose[0]; result.body = loose[1]
            default:
                result.header = loose[0]
                result.title = loose[1]
                result.body = loose[2...].joined(separator: " ")
            }
        } else if named, result.body == nil, let first = loose.first {
            // 有标题没有内容标识：剩下的第一段字当内容。
            result.body = first
        }

        if result.header == nil, result.title == nil, result.body == nil, let summary = result.summary {
            let parts = summaryParts(summary)
            if parts.count >= 3 {
                result.header = parts[0]
                result.title = parts[1]
                result.body = parts[2]
            } else if parts.count == 2 {
                result.header = parts[0]
                result.body = parts[1]
            }
        }
        return result
    }

    /// 横幅元素上常见的 AX 属性，诊断里不列。
    static let commonAttributes: Set<String> = [
        "AXRole", "AXSubrole", "AXRoleDescription", "AXIdentifier", "AXDescription", "AXTitle", "AXValue",
        "AXHelp", "AXChildren", "AXChildrenInNavigationOrder", "AXParent", "AXWindow", "AXTopLevelUIElement",
        "AXPosition", "AXSize", "AXFrame", "AXEnabled", "AXFocused", "AXSelected", "AXCustomActions",
        "AXActivationPoint", "AXTraits",
    ]

    public static func isCommonAttribute(_ name: String) -> Bool { commonAttributes.contains(name) }

    /// 认出来的 App 和从哪认的（诊断用：header、summary[段号]、image、bundle、title）。
    public struct Recognition: Equatable, Sendable {
        public var app: NotchMessageApp
        public var source: String
        /// 是靠程序坞角标或属性线索推断的（`resolve`），这时发件人、内容按辅助说明拆。
        public var inferred = false
        /// 是从标题认的（标题就是 App 名，比如关了预览），这时标题不当发件人。
        public var fromTitle: Bool { source == "title" }
    }

    /// 认横幅属于哪个 App。顺序：顶上的 App 名，辅助说明里的某一段（只认名字表里完全一样
    /// 的，跳过和标题、内容一样的段），图标说明，横幅属性里带的 bundle id，最后才是标题。
    public static func recognise(_ banner: NotchBanner, names: NotchAppNames = .builtIn) -> Recognition? {
        if let app = names.match(banner.header) { return Recognition(app: app, source: "header") }
        if let hit = summaryApp(banner, names: names) {
            return Recognition(app: hit.app, source: "summary[\(hit.index)]")
        }
        if let app = banner.imageNames.lazy.compactMap({ names.match($0) }).first {
            return Recognition(app: app, source: "image")
        }
        if let app = bundleHint(banner) { return Recognition(app: app, source: "bundle") }
        if let app = names.match(banner.title) { return Recognition(app: app, source: "title") }
        return nil
    }

    /// 辅助说明里哪一段是 App 名。按所有分隔符拆开逐段比（App 名在第一段、第二段、
    /// 末尾都认），只比 `appCandidates` 留下的段：和标题、内容一样的段，内容自己拆出来
    /// 的段都跳过（对方发来的字正好是「信息」、或内容里夹着「，微信，」时不认错）。
    static func summaryApp(_ banner: NotchBanner, names: NotchAppNames) -> (app: NotchMessageApp, index: Int)? {
        for candidate in appCandidates(banner) {
            if let app = names.match(candidate.text) { return (app, candidate.index) }
        }
        return nil
    }

    /// 横幅元素的属性（标识、帮助、标题、值）和辅助说明里带着的 bundle id。
    static func bundleHint(_ banner: NotchBanner) -> NotchMessageApp? {
        (banner.hints + [banner.summary].compactMap { $0 }).lazy
            .compactMap { NotchMessageApp.match(bundleIDIn: $0) }.first
    }

    /// 这条横幅是不是要的 App 的一条消息。认不出 App、App 没启用、什么字都没有时为 nil。
    /// `dock` 是这条横幅前后的程序坞角标变化，原来的认法认不出时用（见 `resolve`）。
    public static func incoming(_ banner: NotchBanner, enabled: [NotchMessageApp],
                                names: NotchAppNames = .builtIn,
                                dock: NotchDockAttribution? = nil) -> NotchIncoming? {
        guard let recognised = resolve(banner, names: names, dock: dock), enabled.contains(recognised.app) else {
            return nil
        }
        let app = recognised.app

        var sender: String?
        var preview: String?
        if recognised.inferred {
            // 辅助说明里没有 App 名（macOS 27 只有「发件人, 内容」）：第一段是发件人。
            (sender, preview) = senderAndPreview(banner)
        } else {
            sender = recognised.fromTitle ? nil : cleaned(banner.title)
            if let name = sender, names.match(name) == app { sender = nil }
            preview = cleaned(banner.body) ?? cleaned(banner.subtitle)
            if let body = preview, isPlaceholder(body) { preview = nil }
        }
        // 有内容却没有发件人：多半是关了预览只写了一句话，或者结构没认对，都按没预览处理。
        if sender == nil { preview = nil }
        guard sender != nil || banner.body != nil || banner.title != nil || banner.summary != nil else { return nil }

        let key: String
        if let id = banner.identifier, !id.isEmpty {
            key = "id:\(id)"
        } else {
            key = "text:\(app.rawValue)|\(sender ?? "")|\(preview ?? banner.body ?? "")"
        }
        return NotchIncoming(app: app, sender: sender, preview: preview.map { singleLine($0) }, key: key)
    }

    /// 一个窗口里所有要弹的新消息（还没去重）。
    public static func incoming(in window: NotchBannerNode, enabled: [NotchMessageApp],
                                names: NotchAppNames = .builtIn) -> [NotchIncoming] {
        located(incomingIn: window, enabled: enabled, names: names).map(\.incoming)
    }

    /// 同上，带横幅的位置和能不能替用户点它（一摞点下去只是展开，不点）。
    public static func located(incomingIn window: NotchBannerNode, enabled: [NotchMessageApp],
                               names: NotchAppNames = .builtIn) -> [NotchLocatedIncoming] {
        located(in: window).compactMap { entry in
            incoming(entry.banner, enabled: enabled, names: names).map {
                NotchLocatedIncoming(path: entry.path, incoming: $0, pressable: !entry.banner.stacked)
            }
        }
    }

    /// 横幅上的 App 名，设置里「最近一次读到横幅」用：顶上的 App 名；没有时取辅助说明里
    /// 认出来的那一段，认不出时取第一段（只在它像 App 名时，见 `looksLikeAppName`）；再没有
    /// 取图标的说明。不取发件人和内容。
    public static func appLabel(_ banner: NotchBanner, names: NotchAppNames = .builtIn) -> String? {
        if let header = cleaned(banner.header) { return header }
        if let summary = banner.summary {
            let parts = summarySegments(summary).parts
            if let hit = summaryApp(banner, names: names), hit.index < parts.count { return parts[hit.index] }
            if let head = parts.first, looksLikeAppName(head, in: banner) { return head }
        }
        return banner.imageNames.first
    }

    /// 拆横幅的辅助说明：App 名、发件人、内容。英文系统用「, 」分开，中文系统用全角
    /// 「，」（有时是「、」），也认没有空格的「,」和「App: 标题」那样的冒号；只按前两个分隔
    /// 拆，内容里的逗号原样留着；末尾的「已堆叠」去掉；开头是时间（「22:31」「下午10:30」
    /// 「现在」）时跳过那一段。最多三段。
    public static func summaryParts(_ summary: String) -> [String] {
        let rest = stripStacked(summary)
        var parts = splitLeading(rest, limit: 2)
        if parts.count > 1, isTimeLike(parts[0]) { parts = splitLeading(afterFirst(rest), limit: 2) }
        return parts
    }

    /// 去掉开头那一段（和它后面的分隔符）之后剩下的字。
    private static func afterFirst(_ text: String) -> String {
        guard let range = text.range(of: summarySeparatorPattern, options: .regularExpression) else { return "" }
        return String(text[range.upperBound...])
    }

    /// 按分隔符拆出前 `limit` 段，剩下的整个作最后一段。
    private static func splitLeading(_ text: String, limit: Int) -> [String] {
        var rest = text
        var parts: [String] = []
        while parts.count < limit,
              let range = rest.range(of: summarySeparatorPattern, options: .regularExpression) {
            parts.append(String(rest[..<range.lowerBound]))
            rest = String(rest[range.upperBound...])
        }
        parts.append(rest)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 末尾「, stacked」「，已堆叠」去掉。
    private static func stripStacked(_ summary: String) -> String {
        var rest = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = rest.range(of: #"\s*(, |,|，|、)\s*([^,，、]+)$"#, options: .regularExpression) {
            let tail = rest[range].trimmingCharacters(in: CharacterSet(charactersIn: ",，、 "))
            if stackedWords.contains(tail.lowercased()) { rest = String(rest[..<range.lowerBound]) }
        }
        return rest
    }

    /// 辅助说明里认的分隔符：「, 」「,」「，」「、」「: 」「：」「；」「; 」「 · 」「 - 」。
    /// 时间「22:31」里的冒号后面没有空格，不算分隔。
    static let summarySeparatorPattern = #"(, ?|，|、|: |：|; ?|；| · | - )"#

    /// 分隔符的名字，诊断用。
    static func separatorName(_ raw: String) -> String {
        switch raw {
        case ", ": "comma"
        case ",": "comma-nospace"
        case "，": "fullwidth-comma"
        case "、": "ideographic-comma"
        case ": ": "colon"
        case "：": "fullwidth-colon"
        case "; ", ";", "；": "semicolon"
        case " · ": "middle-dot"
        case " - ": "dash"
        default: "other"
        }
    }

    /// 把辅助说明按所有分隔符拆成段（不限段数，找 App 名用），带上出现过的分隔符种类。
    public static func summarySegments(_ summary: String) -> (parts: [String], separators: [String]) {
        let split = segmentSpans(summary)
        return (split.spans.map(\.text), split.separators)
    }

    /// 同上，带每段在（去掉末尾「已堆叠」后的）辅助说明里的位置，和那段字本身。
    static func segmentSpans(_ summary: String)
        -> (text: String, spans: [(text: String, range: Range<String.Index>)], separators: [String]) {
        let whole = stripStacked(summary)
        var spans: [(text: String, range: Range<String.Index>)] = []
        var kinds: [String] = []
        var start = whole.startIndex
        func add(_ range: Range<String.Index>) {
            let raw = whole[range]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let inner = raw.range(of: trimmed) else { return }
            spans.append((trimmed, inner))
        }
        while start < whole.endIndex,
              let range = whole.range(of: summarySeparatorPattern, options: .regularExpression, range: start..<whole.endIndex) {
            add(start..<range.lowerBound)
            let kind = separatorName(String(whole[range]))
            if !kinds.contains(kind) { kinds.append(kind) }
            start = range.upperBound
        }
        add(start..<whole.endIndex)
        return (whole, spans, kinds)
    }

    /// 辅助说明里哪几段可能是 App 名（段号, 字）：去掉和标题、副标题、内容一样的段，
    /// 落在标题、副标题、内容原文范围里的段（内容里本身带逗号时，「好的，微信，明天见」
    /// 拆出来的「微信」不算），以及末尾组成内容的那几段（系统把长内容截断加省略号时
    /// 内容不能原样找到，按「末尾几段连起来是内容的开头」认）。
    static func appCandidates(_ banner: NotchBanner) -> [(index: Int, text: String)] {
        guard let summary = banner.summary else { return [] }
        let split = segmentSpans(summary)
        let spans = split.spans
        let texts = [banner.body, banner.subtitle, banner.title].compactMap { cleaned($0) }
        let excluded = Set(texts.map(NotchAppNames.normalized).filter { !$0.isEmpty })
        var blocked = Set<Int>()
        // 原文范围：标题、内容在辅助说明里原样出现的每一处，整段落在里面的段都不算。
        for text in texts {
            var from = split.text.startIndex
            while from < split.text.endIndex, let hit = split.text.range(of: text, range: from..<split.text.endIndex) {
                for (index, span) in spans.enumerated()
                where span.range.lowerBound >= hit.lowerBound && span.range.upperBound <= hit.upperBound {
                    blocked.insert(index)
                }
                from = hit.upperBound
            }
        }
        // 末尾几段：连起来（去掉分隔符、空白、末尾省略号）是内容去掉分隔符后的开头。
        if let body = cleaned(banner.body) {
            let bodyCompact = compact(body)
            if !bodyCompact.isEmpty {
                for start in spans.indices {
                    let tail = compact(spans[start...].map(\.text).joined())
                    guard !tail.isEmpty, bodyCompact.hasPrefix(tail) else { continue }
                    for index in start..<spans.count { blocked.insert(index) }
                    break
                }
            }
        }
        return spans.enumerated().compactMap { index, span in
            guard !blocked.contains(index), !excluded.contains(NotchAppNames.normalized(span.text)) else { return nil }
            return (index, span.text)
        }
    }

    /// 比较内容用：去掉分隔符、空白和末尾省略号，小写。
    static func compact(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: summarySeparatorPattern, with: "", options: .regularExpression)
        text = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0)
            && !NotchAppNames.invisible.contains($0) }.map(Character.init))
        while let last = text.last, last == "…" || last == "." { text.removeLast() }
        return text.lowercased()
    }

    /// 像不像通知上的时间：「22:31」「10:30 PM」「下午10:30」「现在」「now」「昨天」。
    static func isTimeLike(_ raw: String) -> Bool {
        let text = NotchAppNames.normalized(raw)
        if ["现在", "刚刚", "now", "just now", "昨天", "yesterday", "現在", "剛剛"].contains(text) { return true }
        let pattern = #"^((上午|下午|晚上|凌晨|中午|早上|今天)\s*)?\d{1,2}[:：]\d{2}(\s*(am|pm|a\.m\.|p\.m\.))?$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: 关掉系统横幅

    /// 「关闭」在各语言里的写法（整理后比较）。只认关闭，不认「清除」（一摞时会清掉整摞）。
    static let closeWords: Set<String> = ["close", "关闭", "關閉", "閉じる", "닫기", "schließen", "fermer",
                                          "cerrar", "chiudi", "fechar", "закрыть", "sluiten", "stäng"]

    /// AX 动作的显示名：自定义动作「Name:Close\nTarget:0x0\nSelector:(null)」取「Close」。
    public static func actionDisplayName(_ raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return raw }
        let body = raw.dropFirst("Name:".count)
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? String(body)
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// 能怎么安全地关掉这条横幅：一摞的不关；横幅元素上有名为「关闭」的动作就用它；否则
    /// 找横幅里 subrole 是 AXCloseButton（或标识是 close）的按钮；都没有时为 nil，不关。
    public static func closeMethod(_ node: NotchBannerNode) -> NotchBannerClose? {
        guard node.subrole != stackSubrole else { return nil }
        if let action = node.actions.first(where: { closeWords.contains(NotchAppNames.normalized(actionDisplayName($0))) }) {
            return .action(action)
        }
        func find(_ current: NotchBannerNode, path: [Int]) -> [Int]? {
            guard path.count <= 4 else { return nil }
            for (index, child) in current.children.enumerated() {
                // 里面再套一条横幅的不算这条的按钮。
                if let subrole = child.subrole, bannerSubroles.contains(subrole) { continue }
                let id = child.identifier?.lowercased()
                if child.subrole == "AXCloseButton"
                    || (child.role == "AXButton" && ["close", "closebutton", "close-button", "close_button"].contains(id ?? "")) {
                    return path + [index]
                }
                if let hit = find(child, path: path + [index]) { return hit }
            }
            return nil
        }
        return find(node, path: []).map { .button(path: $0) }
    }

    static func isPlaceholder(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = trimmed.last, "。.!！…".contains(last) { trimmed.removeLast() }
        if placeholderBodies.contains(trimmed) { return true }
        // 微信关预览：「收到 3 条新消息」「[3条]」。
        if trimmed.range(of: #"^收到\s*\d+\s*条新?消息$"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^\[\d+条\]$"#, options: .regularExpression) != nil { return true }
        return false
    }

    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 预览只画两行：换行并成空格。
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func walk(_ node: NotchBannerNode, depth: Int, _ body: (NotchBannerNode) -> Void) {
        guard depth <= maxDepth else { return }
        body(node)
        for child in node.children { walk(child, depth: depth + 1, body) }
    }
}

// MARK: - 去重

/// 同一条横幅会被报好几次（出现、排版变化、叠成一摞），按键去重。
public struct NotchMessageDeduper: Sendable {
    /// 有系统标识的键记多久。
    public static let idWindow: TimeInterval = 300
    /// 只按内容认的键记多久：太长会把对方连发两次的同一句话吞掉。
    public static let textWindow: TimeInterval = 8

    private var seen: [String: Date] = [:]

    public init() {}

    /// 第一次见到这个键返回 true，并记下来。
    public mutating func isNew(_ key: String, now: Date) -> Bool {
        prune(now)
        if seen[key] != nil {
            seen[key] = now
            return false
        }
        seen[key] = now
        return true
    }

    /// 只记不弹：刚开始观察时屏幕上已经有的横幅。
    public mutating func remember(_ key: String, now: Date) {
        prune(now)
        seen[key] = now
    }

    private mutating func prune(_ now: Date) {
        seen = seen.filter { key, date in
            let window = key.hasPrefix("id:") ? Self.idWindow : Self.textWindow
            return now.timeIntervalSince(date) < window
        }
    }
}

// MARK: - 消息堆叠

/// 卡片上的一条消息。
public struct NotchMessage: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var app: NotchMessageApp
    public var sender: String?
    public var preview: String?
    public var date: Date
    /// 测试通知读回来的（见 `NotchIncoming.isTest`）。
    public var isTest: Bool

    public init(id: UUID = UUID(), app: NotchMessageApp, sender: String?, preview: String?, date: Date,
                isTest: Bool = false) {
        self.id = id
        self.app = app
        self.sender = sender
        self.preview = preview
        self.date = date
        self.isTest = isTest
    }

    public init(_ incoming: NotchIncoming, date: Date, id: UUID = UUID()) {
        self.init(id: id, app: incoming.app, sender: incoming.sender, preview: incoming.preview, date: date,
                  isTest: incoming.isTest)
    }

    public var previewHidden: Bool { preview == nil || sender == nil }

    /// 同一个会话（同一个 App 的同一个人或群）。没发件人的各算各的。
    public func sameConversation(as other: NotchMessage) -> Bool {
        guard let sender, let otherSender = other.sender else { return id == other.id }
        return app == other.app && sender == otherSender
    }

    /// 能不能在刘海里直接回复：「信息」、知道发给谁。
    public var canReplyInline: Bool { app.canReplyInline && !previewHidden && !isTest }

    /// 头像上的字：名字的第一个字（英文取首字母大写），没名字时为 nil（画 App 图标）。
    public var initial: String? {
        guard let sender else { return nil }
        let letters = sender.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
        guard let first = letters.first else { return sender.first.map { String($0) } }
        return String(first).uppercased()
    }

    /// 头像底色的序号（0 到 5），同一个名字总是同一种颜色。
    public var avatarHue: Int {
        let source = sender ?? app.rawValue
        let sum = source.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return sum % 6
    }
}

/// 收到的消息：最新的在最前。卡片显示 `current`，「还有 N 条」是其余的条数，
/// 「下一条」是排在 current 后面的那条。收起时刘海旁边按 App 显示未读数。
public struct NotchMessageInbox: Equatable, Sendable {
    /// 最多留多少条，再多就丢最旧的。
    public static let limit = 30

    public private(set) var messages: [NotchMessage] = []
    public private(set) var currentID: UUID?
    /// 点过「稍后」的：还算未读，但不再自动轮到它。
    public private(set) var deferred: Set<UUID> = []

    public init() {}

    public var isEmpty: Bool { messages.isEmpty }
    public var current: NotchMessage? { messages.first { $0.id == currentID } }

    /// current 以外还有几条。
    public var remainingCount: Int { max(0, messages.count - (current == nil ? 0 : 1)) }

    /// 卡片底下「下一条」的那条：current 后面第一条，没有就从头找。
    public var next: NotchMessage? {
        guard let currentID, let index = messages.firstIndex(where: { $0.id == currentID }) else {
            return messages.first
        }
        let rest = messages[(index + 1)...] + messages[..<index]
        return rest.first { !deferred.contains($0.id) } ?? rest.first
    }

    /// 收到一条：放到最前并显示它。`makeCurrent` 为 false 时（正在回复别人）只放进来，
    /// 卡片上还是原来那条，免得回复框底下突然换了人。
    public mutating func receive(_ message: NotchMessage, makeCurrent: Bool = true) {
        messages.insert(message, at: 0)
        if messages.count > Self.limit {
            let keep = Set(messages.prefix(Self.limit).map(\.id)).union(currentID.map { [$0] } ?? [])
            let dropped = messages.filter { !keep.contains($0.id) }.map(\.id)
            messages.removeAll { dropped.contains($0.id) }
            deferred.subtract(dropped)
        }
        if makeCurrent || current == nil { currentID = message.id }
    }

    /// 「稍后」：这条留着算未读，换到下一条没点过稍后的；没有了返回 false（收起）。
    @discardableResult
    public mutating func later() -> Bool {
        guard let currentID else { return false }
        deferred.insert(currentID)
        if let next = messages.first(where: { !deferred.contains($0.id) }) {
            self.currentID = next.id
            return true
        }
        return false
    }

    /// 打开了或回复了 current：这个会话的消息都算处理完，移走，换到下一条；没有了
    /// 返回 false（收起）。
    @discardableResult
    public mutating func handleCurrent() -> Bool {
        guard let currentID else { return false }
        return handle(currentID)
    }

    /// 同上，指定哪一条（回复发出去时卡片上的那条）。找不到这条时返回有没有 current。
    @discardableResult
    public mutating func handle(_ id: UUID) -> Bool {
        guard let target = messages.first(where: { $0.id == id }) else { return current != nil }
        let gone = messages.filter { $0.sameConversation(as: target) }.map(\.id)
        messages.removeAll { gone.contains($0.id) }
        deferred.subtract(gone)
        if let next = messages.first(where: { !deferred.contains($0.id) }) {
            currentID = next.id
            return true
        }
        currentID = messages.first?.id
        return false
    }

    /// 用户自己打开了这个 App：它的消息都清掉。
    public mutating func clear(_ app: NotchMessageApp) {
        let gone = messages.filter { $0.app == app }.map(\.id)
        messages.removeAll { $0.app == app }
        deferred.subtract(gone)
        if let currentID, gone.contains(currentID) { self.currentID = messages.first?.id }
    }

    /// 测试通知那条看完就走，不在刘海旁边留未读数。还有消息时返回 true。
    @discardableResult
    public mutating func clearTests() -> Bool {
        let gone = messages.filter(\.isTest).map(\.id)
        if !gone.isEmpty {
            messages.removeAll { $0.isTest }
            deferred.subtract(gone)
            if let currentID, gone.contains(currentID) { self.currentID = messages.first?.id }
        }
        return !messages.isEmpty
    }

    public mutating func clearAll() {
        messages.removeAll()
        deferred.removeAll()
        currentID = nil
    }

    /// 从收起态点开：显示这个 App 最新的一条（不给 App 就是最新的一条）。
    @discardableResult
    public mutating func focus(_ app: NotchMessageApp? = nil) -> Bool {
        guard let target = messages.first(where: { app == nil || $0.app == app }) else { return false }
        currentID = target.id
        return true
    }

    /// 收起态每个 App 的未读数，按 App 的固定顺序，没有的不列。
    public var unreadCounts: [(app: NotchMessageApp, count: Int)] {
        NotchMessageApp.allCases.compactMap { app in
            let count = messages.filter { $0.app == app }.count
            return count > 0 ? (app, count) : nil
        }
    }

    public static func == (lhs: NotchMessageInbox, rhs: NotchMessageInbox) -> Bool {
        lhs.messages == rhs.messages && lhs.currentID == rhs.currentID && lhs.deferred == rhs.deferred
    }
}

// MARK: - 卡片上的字

public enum NotchMessageText {
    /// 右上角「还有 2 条」。
    public static func remaining(_ count: Int) -> String? {
        count > 0 ? tr("还有 \(count) 条") : nil
    }

    /// 时间：一分钟内写「刚刚」，今天写 09:40，更早写 10/23。
    public static func time(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds >= 0, seconds < 60 { return tr("刚刚") }
        let parts = calendar.dateComponents([.hour, .minute, .month, .day], from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        return "\(parts.month ?? 1)/\(parts.day ?? 1)"
    }

    /// 时刻：09:31，「下一条」用。
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 底下一行「下一条：微信 · 王姐 · 09:31」。
    public static func nextLine(_ message: NotchMessage) -> String {
        let who = message.sender ?? tr("收到一条消息")
        return tr("下一条：\(message.app.title) · \(who) · \(clock(message.date))")
    }

    /// 关了预览时的标题和说明。
    public static let hiddenTitle = tr("收到一条消息")

    public static func hiddenDetail(_ app: NotchMessageApp) -> String {
        tr("\(app.title)关闭了通知预览，打开\(app.title)查看内容")
    }

    public static func hiddenHint(_ app: NotchMessageApp) -> String {
        tr("在\(app.title)设置里打开预览后可显示内容")
    }

    /// 跳转类按钮的字带「↗」。
    public static func jump(_ label: String) -> String { "\(label) ↗" }
}

// MARK: - 自动收起

/// 展开后几秒自动收起，指针停在卡片上时暂停，离开后至少再给 `minimumAfterHover` 秒。
public struct NotchMessageCountdown: Equatable, Sendable {
    public static let minimumAfterHover: TimeInterval = 3

    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval?

    public init() {}

    public var isRunning: Bool { deadline != nil }
    public var isPaused: Bool { pausedRemaining != nil }

    public mutating func start(_ duration: TimeInterval, at now: Date) {
        pausedRemaining = nil
        deadline = now.addingTimeInterval(max(0, duration))
    }

    public mutating func pause(at now: Date) {
        guard let deadline else { return }
        pausedRemaining = max(0, deadline.timeIntervalSince(now))
        self.deadline = nil
    }

    public mutating func resume(at now: Date) {
        guard let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        deadline = now.addingTimeInterval(max(remaining, Self.minimumAfterHover))
    }

    public mutating func stop() {
        deadline = nil
        pausedRemaining = nil
    }

    /// 到点了（暂停中永远不到点）。
    public func expired(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }
}

// MARK: - 和码头自己刘海内容的优先级

/// 码头自己也在刘海上放东西：AI 刘海对话（入口和展开的面板）、灵动提示的小胶囊
/// （音量、亮度、会议倒计时）、提醒弹窗（喝水、待办、提醒事项）。消息卡和它们的
/// 规则，从高到低：
///
/// 1. 全屏 App 或演示：什么都不画，消息留着，退出全屏后只显示收起态的未读数。
/// 2. AI 刘海对话面板开着（用户正在用）：不展开卡片，只在刘海两侧显示未读数；面板
///    收起后，最近 `freshWindow` 秒内到的消息再展开。
/// 3. 码头的提醒弹窗正显示：排队等它收起，最多等 `maxWait` 秒，之后只显示未读数。
/// 4. 消息卡高于灵动提示：卡片展开时灵动提示的小胶囊让位（音量、亮度只闪一下，会议
///    倒计时等卡片收起后回来），AI 刘海入口也暂时让位，免得下沿提示条压在卡片上。
///
/// 别的刘海 App（拾掇等）的让位见 `NotchMessagePlacement`。
public enum NotchMessagePriority {
    /// 排队最多等多久。
    public static let maxWait: TimeInterval = 8
    /// 被挡住期间到的消息，挡的东西走开后多久以内的还展开。
    public static let freshWindow: TimeInterval = 20

    public enum Stage: Equatable, Sendable {
        /// 什么都不画。
        case suppressed
        /// 只画收起态（未读数）。
        case indicatorOnly
        /// 先等一等，`maxWait` 内挡的东西走开就展开。
        case hold
        /// 可以展开（位置再看 `NotchMessagePlacement`）。
        case show
    }

    public struct Context: Equatable, Sendable {
        public var fullscreen: Bool
        public var aiPanelOpen: Bool
        public var reminderShowing: Bool

        public init(fullscreen: Bool = false, aiPanelOpen: Bool = false, reminderShowing: Bool = false) {
            self.fullscreen = fullscreen
            self.aiPanelOpen = aiPanelOpen
            self.reminderShowing = reminderShowing
        }
    }

    public static func stage(_ context: Context, waited: TimeInterval) -> Stage {
        if context.fullscreen { return .suppressed }
        if context.aiPanelOpen { return .indicatorOnly }
        if context.reminderShowing { return waited < maxWait ? .hold : .indicatorOnly }
        return .show
    }

    /// 挡的东西走开后要不要补一次展开：最新那条到得够近才展开，太久以前的只留未读数。
    public static func expandsAfterWait(arrival: Date?, now: Date) -> Bool {
        guard let arrival else { return false }
        let age = now.timeIntervalSince(arrival)
        return age >= 0 && age <= freshWindow
    }

    /// 灵动提示要不要让位：消息卡展开着就让。
    public static func islandYields(cardExpanded: Bool) -> Bool { cardExpanded }

    /// AI 刘海入口画不画：原来的规则再加一条，消息卡展开着时让位。
    public static func aiEntryVisible(enabled: Bool, islandShowing: Bool, cardExpanded: Bool) -> Bool {
        AINotchLayout.isVisible(enabled: enabled, islandShowing: islandShowing) && !cardExpanded
    }
}

// MARK: - 信息的快速回复

/// 刘海里回复「信息」用的 AppleScript。横幅上只有显示名，没有电话或邮箱：按名字
/// 找联系人，找不到再按群聊名，再按号码；有重名、找不到都不发，打开「信息」让用户
/// 自己发，绝不发错人。
public enum NotchMessageReply {
    /// 发送结果，AppleScript 返回的字。
    public static let sentToken = "sent"
    public static let notFoundToken = "notfound"
    public static let ambiguousToken = "ambiguous"

    /// 回复最长多少字，超过的截掉（刘海里的输入框本来就是一两句话）。
    public static let maxLength = 2000

    /// AppleScript 字符串字面量的转义：反斜杠、双引号，换行写成 return 拼接。
    public static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lines = escaped.components(separatedBy: CharacterSet.newlines)
        return lines.map { "\"\($0)\"" }.joined(separator: " & return & ")
    }

    /// 整理要发的字：去掉首尾空白，太长截断；空的返回 nil（不发）。
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > maxLength ? String(trimmed.prefix(maxLength)) : trimmed
    }

    /// 发给 `recipient`（横幅上的显示名）的脚本。
    public static func script(text: String, recipient: String) -> String {
        let body = quoted(text)
        let name = quoted(recipient)
        return """
        tell application "Messages"
            set targetName to \(name)
            set hits to {}
            try
                set hits to (every participant whose name is targetName)
            end try
            if (count of hits) is 0 then
                try
                    set hits to (every chat whose name is targetName)
                end try
            end if
            if (count of hits) is 0 then
                try
                    set hits to (every participant whose handle is targetName)
                end try
            end if
            if (count of hits) is 0 then return "\(notFoundToken)"
            if (count of hits) > 1 then return "\(ambiguousToken)"
            send \(body) to item 1 of hits
            return "\(sentToken)"
        end tell
        """
    }

    public enum Outcome: Equatable, Sendable {
        case sent
        /// 没找到这个人或群。
        case notFound
        /// 有重名，不知道发给谁。
        case ambiguous
        /// 没给自动化权限（AppleScript 错误 -1743 / -1744）。
        case denied
        case failed
    }

    /// 把 AppleScript 的返回值和错误号翻成结果。
    public static func outcome(result: String?, errorNumber: Int?) -> Outcome {
        if let errorNumber {
            return errorNumber == -1743 || errorNumber == -1744 ? .denied : .failed
        }
        switch result {
        case sentToken: return .sent
        case notFoundToken: return .notFound
        case ambiguousToken: return .ambiguous
        default: return .failed
        }
    }

    /// 结果写在卡片底下的一句话（发出去了不写，卡片直接收起）。
    public static func message(_ outcome: Outcome) -> String? {
        switch outcome {
        case .sent: nil
        case .notFound: tr("在「信息」里没找到这个联系人，已为你打开「信息」")
        case .ambiguous: tr("有同名的联系人，为免发错人，已为你打开「信息」")
        case .denied: tr("需要允许码头控制「信息」：系统设置 ▸ 隐私与安全性 ▸ 自动化")
        case .failed: tr("没发出去，已为你打开「信息」")
        }
    }

    /// 第一次回复前的说明。
    public static let permissionHint = tr("第一次发送时 macOS 会问是否允许码头控制「信息」，允许后才能在刘海里回复")
}
