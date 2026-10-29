import Foundation

// MARK: - 消息灵动岛：自查

/// 设置 ▸ 消息灵动岛里的「状态」几行：辅助功能、通知中心、最近一次读到横幅、测试
/// 通知。用户说「打开了还是不弹」时，看这几行就知道卡在哪一步。只有纯逻辑，读权限、
/// 读横幅、发通知都在 App 那边。
public enum NotchMessageDiagnosis {
    public enum Level: Equatable, Sendable {
        /// 正常（绿点）。
        case ok
        /// 要用户处理（橙点）。
        case warning
        /// 还没有结果、在等（灰点）。
        case idle
    }

    public struct Line: Equatable, Sendable {
        public var title: String
        public var value: String
        public var level: Level
        /// 值下面的一句说明（怎么处理），没有时为 nil。
        public var hint: String?

        public init(title: String, value: String, level: Level, hint: String? = nil) {
            self.title = title
            self.value = value
            self.level = level
            self.hint = hint
        }
    }

    /// 读到的现状。
    public struct Snapshot: Equatable, Sendable {
        /// `AXIsProcessTrusted()`。
        public var trusted: Bool
        /// 上次读到「已授权」时码头的版本（版本号加构建号），从没授权过时为 nil。
        public var lastTrustedBuild: String?
        public var currentBuild: String
        /// 通知中心进程在不在。
        public var notificationCenterRunning: Bool
        /// 观察器接上了通知中心（至少一个事件挂上了）。
        public var connected: Bool
        /// 最近一次读到任意一条横幅（不管是不是要的 App）的时间，和横幅上的 App 名。
        public var lastBanner: Date?
        public var lastBannerApp: String?
        /// 最近一次读到要的 App 的消息的时间。
        public var lastMessage: Date?

        public init(trusted: Bool, lastTrustedBuild: String? = nil, currentBuild: String = "",
                    notificationCenterRunning: Bool = true, connected: Bool = false,
                    lastBanner: Date? = nil, lastBannerApp: String? = nil, lastMessage: Date? = nil) {
            self.trusted = trusted
            self.lastTrustedBuild = lastTrustedBuild
            self.currentBuild = currentBuild
            self.notificationCenterRunning = notificationCenterRunning
            self.connected = connected
            self.lastBanner = lastBanner
            self.lastBannerApp = lastBannerApp
            self.lastMessage = lastMessage
        }

        /// 以前授权过、换了版本后读不到授权：多半是自签名更新后系统设置里留着旧的那一条。
        public var trustLostAfterUpdate: Bool {
            guard !trusted, let last = lastTrustedBuild, !last.isEmpty else { return false }
            return last != currentBuild
        }
    }

    /// 没授权时的处理办法。自签名版本每次更新签名都变，系统设置里码头看着还勾着，
    /// 其实是旧版本的那一条，勾掉再勾上也没用，要移除再添加。
    public static let reAddHint = tr("如果系统设置里码头已经勾着，那是更新前的旧授权：在 隐私与安全性 ▸ 辅助功能 里选中码头点「−」移除，再点「+」重新添加，或点「去授权」后打开开关。")

    public static func accessibility(_ s: Snapshot) -> Line {
        let title = tr("辅助功能")
        if s.trusted { return Line(title: title, value: tr("已授权"), level: .ok) }
        let value = s.trustLostAfterUpdate ? tr("更新后授权失效") : tr("未授权")
        return Line(title: title, value: value, level: .warning,
                    hint: tr("消息灵动岛要的是辅助功能权限，不是通知权限。") + reAddHint)
    }

    public static func notificationCenter(_ s: Snapshot) -> Line {
        let title = tr("通知中心")
        guard s.trusted else {
            return Line(title: title, value: tr("等辅助功能授权"), level: .idle)
        }
        guard s.notificationCenterRunning else {
            return Line(title: title, value: tr("未找到"), level: .warning,
                        hint: tr("系统的通知中心没有在运行，等几秒会自动重连；一直这样可以重启 Mac。"))
        }
        if s.connected { return Line(title: title, value: tr("已连接"), level: .ok) }
        return Line(title: title, value: tr("正在连接"), level: .idle)
    }

    public static func lastBanner(_ s: Snapshot, now: Date, calendar: Calendar = .current) -> Line {
        let title = tr("最近一次读到横幅")
        guard let date = s.lastBanner else {
            return Line(title: title, value: tr("从未"), level: .idle,
                        hint: tr("让别人给你发一条消息，或点下面的「发一条测试通知」。横幅没出现时码头读不到：通知样式要选「横幅」或「提醒」，专注模式、勿扰时不出现，正在看那个 App 时系统也不弹横幅。"))
        }
        var value = NotchMessageText.time(date, now: now, calendar: calendar)
        if let app = s.lastBannerApp, !app.isEmpty { value = "\(value) · \(app)" }
        return Line(title: title, value: value, level: .ok)
    }

    public static func lines(_ s: Snapshot, now: Date, calendar: Calendar = .current) -> [Line] {
        [accessibility(s), notificationCenter(s), lastBanner(s, now: now, calendar: calendar)]
    }
}

// MARK: - 测试通知

/// 「发一条测试通知」：码头自己发一条本地通知，看能不能从横幅上读到并弹出消息卡。
/// 正文里带一段每次不同的暗号，读横幅的那边按暗号认出它。
public struct NotchMessageProbe: Equatable, Sendable {
    /// 发出去后等多久还没读到就算没读到。
    public static let timeout: TimeInterval = 12
    /// 通知的标识前缀。
    public static let identifierPrefix = "docket.notchmessage.probe."

    public enum State: Equatable, Sendable {
        case idle
        /// 已发出，等横幅。
        case waiting(token: String, since: Date)
        /// 读到了。
        case received(at: Date)
        /// 等了 `timeout` 秒没读到。
        case missed(at: Date)
        /// 码头自己的通知被关了，横幅出不来。
        case notificationsOff
        /// 消息灵动岛没在运行（没打开、没选任何 App）。
        case inactive
    }

    public private(set) var state: State = .idle

    public init() {}

    /// 暗号：四位数字，前面加 # 好认。
    public static func makeToken(_ number: Int) -> String {
        "#" + String(format: "%04d", abs(number) % 10000)
    }

    public static func body(token: String) -> String {
        tr("测试消息灵动岛能不能读到横幅 \(token)")
    }

    /// 横幅上的字里有没有这个暗号。
    public static func matches(_ banner: NotchBanner, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let texts = [banner.header, banner.title, banner.subtitle, banner.body, banner.summary]
        return texts.contains { $0?.contains(token) == true }
    }

    /// 认出测试横幅时交给消息卡的那条。用「信息」的样式画，不能回复。
    public static func incoming(_ banner: NotchBanner, token: String) -> NotchIncoming? {
        guard matches(banner, token: token) else { return nil }
        return NotchIncoming(app: .messages, sender: tr("码头"),
                             preview: tr("测试成功：码头读到了通知横幅，消息灵动岛工作正常"),
                             key: "probe:\(token)", isTest: true)
    }

    public var token: String? {
        if case .waiting(let token, _) = state { return token }
        return nil
    }

    public mutating func sent(token: String, at now: Date) { state = .waiting(token: token, since: now) }
    public mutating func received(at now: Date) { state = .received(at: now) }
    public mutating func notificationsOff() { state = .notificationsOff }
    public mutating func inactive() { state = .inactive }

    /// 定时看一下：等太久就算没读到。状态变了返回 true。
    @discardableResult
    public mutating func tick(now: Date) -> Bool {
        guard case .waiting(_, let since) = state, now.timeIntervalSince(since) >= Self.timeout else { return false }
        state = .missed(at: now)
        return true
    }

    /// 按钮下面的一句话。没发过时为 nil。
    public func line(_ snapshot: NotchMessageDiagnosis.Snapshot) -> NotchMessageDiagnosis.Line? {
        let title = tr("测试通知")
        switch state {
        case .idle:
            return nil
        case .waiting:
            return .init(title: title, value: tr("已发出，等横幅…"), level: .idle)
        case .received:
            return .init(title: title, value: tr("读到了，消息卡已弹出"), level: .ok)
        case .missed:
            let hint: String
            if !snapshot.trusted {
                hint = tr("先给码头辅助功能权限。") + NotchMessageDiagnosis.reAddHint
            } else if snapshot.lastBanner == nil {
                hint = tr("一条横幅都没读到：看看屏幕右上角刚才有没有出现码头的横幅。没出现就到 系统设置 ▸ 通知 ▸ 码头，把样式改成「横幅」，并关掉专注模式；出现了却读不到，请在系统设置里把码头从辅助功能移除再重新添加。")
            } else {
                hint = tr("别的横幅能读到，这条没读到：确认刚才出现了码头的横幅，再试一次。")
            }
            return .init(title: title, value: tr("没读到"), level: .warning, hint: hint)
        case .notificationsOff:
            return .init(title: title, value: tr("码头的通知被关了"), level: .warning,
                         hint: tr("到 系统设置 ▸ 通知 ▸ 码头 打开「允许通知」，样式选「横幅」，再点一次测试。"))
        case .inactive:
            return .init(title: title, value: tr("消息灵动岛没在运行"), level: .warning,
                         hint: tr("打开上面的开关，并至少选一个 App。"))
        }
    }
}
