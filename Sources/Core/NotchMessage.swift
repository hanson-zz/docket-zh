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

    /// 横幅上可能写的 App 名（小写比较）：中英文界面、繁体，以及老名字。
    public var bannerNames: [String] {
        switch self {
        case .messages: ["信息", "messages", "imessage", "訊息", "短信", "message"]
        case .whatsapp: ["whatsapp", "whatsapp messenger"]
        case .wechat: ["微信", "wechat", "weixin"]
        }
    }

    /// 能不能在刘海里直接回复。只有「信息」有可用的 AppleScript；WhatsApp、微信只跳转。
    public var canReplyInline: Bool { self == .messages }

    /// 认横幅上写的 App 名，认不出时为 nil。
    public static func match(name raw: String?) -> NotchMessageApp? {
        guard let raw else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        return allCases.first { $0.bannerNames.contains(name) }
    }

    /// 按 bundle id 认，大小写不敏感。
    public static func match(bundleID raw: String?) -> NotchMessageApp? {
        guard let id = raw?.lowercased(), !id.isEmpty else { return nil }
        return allCases.first { app in app.bundleIDs.contains { $0.lowercased() == id } }
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

    private enum CodingKeys: String, CodingKey { case enabled, apps, position, seconds }

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
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(apps.map(\.rawValue), forKey: .apps)
        try c.encode(position.rawValue, forKey: .position)
        try c.encode(seconds, forKey: .seconds)
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
    public var children: [NotchBannerNode]

    public init(role: String? = nil, subrole: String? = nil, identifier: String? = nil,
                description: String? = nil, title: String? = nil, value: String? = nil,
                children: [NotchBannerNode] = []) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.description = description
        self.title = title
        self.value = value
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

    public init(identifier: String? = nil, header: String? = nil, title: String? = nil,
                subtitle: String? = nil, body: String? = nil, summary: String? = nil,
                imageNames: [String] = [], stacked: Bool = false) {
        self.identifier = identifier
        self.header = header
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.summary = summary
        self.imageNames = imageNames
        self.stacked = stacked
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
        return found
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

    /// 这条横幅是不是要的 App 的一条消息。认不出 App、App 没启用、什么字都没有时为 nil。
    public static func incoming(_ banner: NotchBanner, enabled: [NotchMessageApp]) -> NotchIncoming? {
        let summaryHead = banner.summary.flatMap { summaryParts($0).first }
        let candidates: [String?] = [banner.header, summaryHead] + banner.imageNames.map { Optional($0) }
        var app = candidates.lazy.compactMap { NotchMessageApp.match(name: $0) }.first
        var titleIsApp = false
        if app == nil, let fromTitle = NotchMessageApp.match(name: banner.title) {
            app = fromTitle
            titleIsApp = true
        }
        guard let app, enabled.contains(app) else { return nil }

        var sender = titleIsApp ? nil : cleaned(banner.title)
        if let name = sender, NotchMessageApp.match(name: name) == app { sender = nil }
        var preview = cleaned(banner.body) ?? cleaned(banner.subtitle)
        if let body = preview, isPlaceholder(body) { preview = nil }
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
    public static func incoming(in window: NotchBannerNode, enabled: [NotchMessageApp]) -> [NotchIncoming] {
        located(incomingIn: window, enabled: enabled).map(\.incoming)
    }

    /// 同上，带横幅的位置和能不能替用户点它（一摞点下去只是展开，不点）。
    public static func located(incomingIn window: NotchBannerNode,
                               enabled: [NotchMessageApp]) -> [NotchLocatedIncoming] {
        located(in: window).compactMap { entry in
            incoming(entry.banner, enabled: enabled).map {
                NotchLocatedIncoming(path: entry.path, incoming: $0, pressable: !entry.banner.stacked)
            }
        }
    }

    /// 横幅上的 App 名，设置里「最近一次读到横幅」用：顶上的 App 名，没有时取辅助说明的
    /// 第一段，再没有取图标的说明。不取发件人和内容。
    public static func appLabel(_ banner: NotchBanner) -> String? {
        cleaned(banner.header) ?? banner.summary.flatMap { summaryParts($0).first } ?? banner.imageNames.first
    }

    /// 拆横幅的辅助说明：App 名、发件人、内容。英文系统用「, 」分开，中文系统用全角
    /// 「，」（有时是「、」），只按前两个分隔拆，内容里的逗号原样留着；末尾的「已堆叠」
    /// 去掉。最多三段。
    public static func summaryParts(_ summary: String) -> [String] {
        var rest = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        // 末尾「, stacked」「，已堆叠」。
        if let range = rest.range(of: #"\s*(, |,|，|、)\s*([^,，、]+)$"#, options: .regularExpression) {
            let tail = rest[range].trimmingCharacters(in: CharacterSet(charactersIn: ",，、 "))
            if stackedWords.contains(tail.lowercased()) { rest = String(rest[..<range.lowerBound]) }
        }
        var parts: [String] = []
        while parts.count < 2,
              let range = rest.range(of: #"(, |，|、)"#, options: .regularExpression) {
            parts.append(String(rest[..<range.lowerBound]))
            rest = String(rest[range.upperBound...])
        }
        parts.append(rest)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
