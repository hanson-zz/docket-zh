import Foundation

// MARK: - 动态图标：消息未读（信息、微信、邮件）
//
// 未读数只取 Apple 程序坞上这个 App 自己的角标（AXStatusLabel，读法在 Services 的
// LiveBadgeMonitor），不读聊天内容、不截屏、不拿通知条数冒充未读数。读不到角标时就是
// 「未知」，图标保持原样，不画假的数字。这里只有纯逻辑：分级、配色、开关、角标文字、
// 新消息弹一下的合并规则，全部能在测试里跑。

/// 按未读数变化的三个消息 App。
public enum LiveBadgeApp: String, CaseIterable, Equatable, Sendable {
    case messages
    case wechat
    case mail

    public var bundleID: String {
        switch self {
        case .messages: "com.apple.MobileSMS"
        case .wechat: "com.tencent.xinWeChat"
        case .mail: "com.apple.mail"
        }
    }

    public init?(bundleID: String) {
        let id = bundleID.lowercased()
        guard let app = Self.allCases.first(where: { $0.bundleID.lowercased() == id }) else { return nil }
        self = app
    }

    /// 设置里这个 App 的子开关，默认开。
    public var toggleKey: String { "liveIcons.badge.\(rawValue)" }

    /// 原图标的主色色相（度）：信息、微信是绿，邮件是蓝。趣味模式按它算要转多少度。
    public var baseHue: Double {
        switch self {
        case .messages, .wechat: 130
        case .mail: 212
        }
    }
}

/// 两种风格：简洁（默认）只弹角标，不改图标颜色；趣味按未读数分级换色、加闪光火焰液滴。
public enum LiveBadgeStyle: String, CaseIterable, Equatable, Sendable {
    case subtle
    case playful

    public static let key = "liveIcons.badgeStyle"
    public static let `default` = LiveBadgeStyle.subtle

    public init(stored: String?) {
        self = stored.flatMap(LiveBadgeStyle.init(rawValue:)) ?? .default
    }
}

/// 未读分级：0、1、2 到 3、4 到 6、7 到 8、9 及以上。
public enum LiveBadgeTier: Int, CaseIterable, Comparable, Sendable {
    case idle
    case one
    case few
    case several
    case many
    case lots

    public init(count: Int) {
        switch count {
        case ..<1: self = .idle
        case 1: self = .one
        case 2...3: self = .few
        case 4...6: self = .several
        case 7...8: self = .many
        default: self = .lots
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// 趣味模式下图标要转到的色相（度）：蓝、紫、紫粉、红粉、红。0 和 1 条保持原色，返回 nil。
    public var targetHue: Double? {
        switch self {
        case .idle, .one: nil
        case .few: 205
        case .several: 285
        case .many: 330
        case .lots: 352
        }
    }

    /// 角标旁边的装饰（只在趣味模式）。
    public var accent: LiveBadgeAccent {
        switch self {
        case .idle, .one: .none
        case .few: .sparkle
        case .several: .flame
        case .many, .lots: .drip
        }
    }
}

/// 角标旁边的装饰：闪光、火焰、液滴。都是静态挂件，只有新消息那一下弹一次。
public enum LiveBadgeAccent: Equatable, Sendable {
    case none
    case sparkle
    case flame
    case drip
}

/// 一个 App 此刻的未读读数。
public enum LiveBadgeReading: Equatable, Sendable {
    /// 读不到（没给辅助功能权限、程序坞上没有它、读失败）：图标保持原样。
    case unknown
    /// 有数字角标。
    case count(Int)
    /// 有角标但不是数字（小红点）：只当「有新消息」，不分级。
    case mark

    /// 和刘海消息共用的程序坞角标解析。
    public init(_ badge: NotchDockBadge) {
        switch badge {
        case .missing: self = .unknown
        case .none: self = .count(0)
        case .count(let n): self = .count(max(0, n))
        case .mark: self = .mark
        }
    }

    /// 能拿来分级的未读数：只有数字角标算，小红点和未知都是 nil。
    public var reliableCount: Int? {
        if case .count(let n) = self { return n }
        return nil
    }

    /// 比大小用的数：未知不比，小红点算 1。
    public var level: Int? {
        switch self {
        case .unknown: nil
        case .count(let n): n
        case .mark: 1
        }
    }
}

/// 某个风格、某个读数下图标该怎么画。
public struct LiveBadgeLook: Equatable, Sendable {
    /// 角标上的字；nil 是不画角标。小红点角标是空字符串（画一个小圆点）。
    public var badgeText: String?
    /// 图标要转的色相角度（度），0 是不转。
    public var hueRotation: Double
    public var accent: LiveBadgeAccent
    public var tier: LiveBadgeTier

    public static let plain = LiveBadgeLook(badgeText: nil, hueRotation: 0, accent: .none, tier: .idle)

    public static func of(_ app: LiveBadgeApp, reading: LiveBadgeReading, style: LiveBadgeStyle) -> LiveBadgeLook {
        switch reading {
        case .unknown, .count(0):
            return .plain
        case .mark:
            return LiveBadgeLook(badgeText: "", hueRotation: 0, accent: .none, tier: .one)
        case .count(let n):
            let tier = LiveBadgeTier(count: n)
            let text = LiveBadgeLook.text(n)
            guard style == .playful, let hue = tier.targetHue else {
                return LiveBadgeLook(badgeText: text, hueRotation: 0, accent: style == .playful ? tier.accent : .none,
                                     tier: tier)
            }
            return LiveBadgeLook(badgeText: text, hueRotation: rotation(from: app.baseHue, to: hue),
                                 accent: tier.accent, tier: tier)
        }
    }

    /// 角标文字：1 到 99，再多写「99+」。
    public static func text(_ count: Int) -> String {
        count > 99 ? "99+" : "\(max(0, count))"
    }

    /// 从 a 转到 b 走近的那一边，结果在 -180...180。
    public static func rotation(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// 新消息弹一下：未读数涨了才弹，1 秒内连着涨的合并成一次；从未知变成有数（刚打开码头、
/// 刚给权限）不算新消息，不弹。
public struct LiveBadgePulse: Equatable, Sendable {
    public static let coalesce: TimeInterval = 1

    public private(set) var last: LiveBadgeReading = .unknown
    public private(set) var lastPulse: Date?
    /// 每弹一次加一，视图拿它当动画触发。
    public private(set) var generation = 0

    public init() {}

    /// 喂一次新读数，返回这次要不要弹。
    @discardableResult
    public mutating func update(_ reading: LiveBadgeReading, now: Date) -> Bool {
        defer { last = reading }
        guard let old = last.level, let new = reading.level, new > old else { return false }
        if let lastPulse, now.timeIntervalSince(lastPulse) < Self.coalesce { return false }
        lastPulse = now
        generation += 1
        return true
    }
}

/// 设置里「预览」用的演示读数：0 到 9 条，不碰真实消息。
public enum LiveBadgeDemo {
    public static let range = 0...9
}

// MARK: - 邮件：撰写中、发送中

/// 邮件图标右下角的活动：有写信窗口开着时挂铅笔，发件箱里有信没发出去时挂一圈转动的小环。
/// 读不到（没权限、邮件没开）时两样都是 false，什么都不挂。新邮件的闪光跟未读数的轻弹同一次触发。
public struct LiveMailActivity: Equatable, Sendable {
    public var composing = false
    public var sending = false

    public init(composing: Bool = false, sending: Bool = false) {
        self.composing = composing
        self.sending = sending
    }

    public enum Corner: Equatable, Sendable { case composing, sending }

    /// 一次只挂一个，发送中优先。
    public var corner: Corner? {
        if sending { return .sending }
        return composing ? .composing : nil
    }

    static let sendWords = ["send", "发送", "傳送", "寄送"]

    /// 写信窗口工具栏上的「发送」按钮（只认按钮名字整句，不读信的内容）。
    public static func isSendButton(_ texts: [String]) -> Bool {
        texts.contains { text in
            let t = text.trimmingCharacters(in: .whitespaces).lowercased()
            return sendWords.contains(t) || sendWords.contains { t.hasPrefix($0 + " message") || t == $0 + "邮件" }
        }
    }
}
