import Foundation

// 动态图标第二版的纯逻辑：哪个 App 用哪种动态、开关怎么叠、AI 额度水位读多少、
// 流光什么时候亮、Chrome 图标怎么转和怎么缓停、多久问一次 Chrome、画多快。
// 不碰 AppKit、不碰 CodexService，全部能在测试里跑。

/// 动态图标认得的 App。
public enum LiveIconApp: Equatable, Sendable {
    case finder
    case chrome
    /// ChatGPT 桌面 App：蓝色水位加流光，额度读的是 Codex 的（两者共用一份 OpenAI 额度数据）。
    case chatGPT
    /// Codex 桌面 App：紫色水位加流光。
    case codex
    /// Claude 桌面 App：橙色水位，没有流光（没有可靠的「正在干活」信号）。
    case claude

    public static let finderBundleID = "com.apple.finder"
    public static let chromeBundleID = "com.google.Chrome"
    public static let chatGPTBundleID = "com.openai.chat"
    /// Codex 桌面 App 的 bundle id 取自仓库里 CodexTerminal.codexApps，
    /// 尚未在真机安装包上核对过（未验证）。
    public static let codexBundleIDs = ["com.openai.codex"]
    /// Claude 桌面 App 的 bundle id，取自公开资料，尚未在真机安装包上核对过（未验证）。
    public static let claudeBundleID = "com.anthropic.claudefordesktop"

    public init?(bundleID: String) {
        switch bundleID {
        case Self.finderBundleID: self = .finder
        case Self.chromeBundleID: self = .chrome
        case Self.chatGPTBundleID: self = .chatGPT
        case Self.claudeBundleID: self = .claude
        default:
            guard Self.codexBundleIDs.contains(bundleID) else { return nil }
            self = .codex
        }
    }

    /// 画额度水位的三个 AI App。
    public var isAI: Bool {
        switch self {
        case .chatGPT, .codex, .claude: return true
        case .finder, .chrome: return false
        }
    }
}

/// 设置 ▸ 扩展栏的动态图标开关。总开关默认关，各 App 的子开关默认开；
/// 「AI 额度水位」管三个 AI 图标里的水位、百分比和悬停倒计时，默认开。
public struct LiveIconToggles: Equatable, Sendable {
    public static let masterKey = "liveIcons.enabled"
    public static let finderKey = "liveIcons.finder"
    public static let chromeKey = "liveIcons.chrome"
    /// 历史原因叫 ai：以前 ChatGPT 和 Codex 共用这一个开关，现在只管 ChatGPT。
    public static let openAIKey = "liveIcons.ai"
    public static let codexKey = "liveIcons.codex"
    public static let claudeKey = "liveIcons.claude"
    /// 「AI 额度水位」总开关。
    public static let quotaKey = "liveIcons.aiQuota"
    /// 水位左下角的百分比大字，默认显示。
    public static let percentKey = "liveIcons.aiPercent"

    public var master: Bool
    public var finder: Bool
    public var chrome: Bool
    public var chatGPT: Bool
    public var codex: Bool
    public var claude: Bool
    public var quota: Bool

    public init(master: Bool = false, finder: Bool = true, chrome: Bool = true, chatGPT: Bool = true,
                codex: Bool = true, claude: Bool = true, quota: Bool = true) {
        self.master = master
        self.finder = finder
        self.chrome = chrome
        self.chatGPT = chatGPT
        self.codex = codex
        self.claude = claude
        self.quota = quota
    }

    /// 从设置里读；没存过的键用各自的默认值。
    public init(defaults: UserDefaults) {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        self.init(master: flag(Self.masterKey, false), finder: flag(Self.finderKey, true),
                  chrome: flag(Self.chromeKey, true), chatGPT: flag(Self.openAIKey, true),
                  codex: flag(Self.codexKey, true), claude: flag(Self.claudeKey, true),
                  quota: flag(Self.quotaKey, true))
    }

    /// 这个 App 的动态图标开没开（AI App 开着时至少有流光）。
    public func isOn(_ app: LiveIconApp) -> Bool {
        guard master else { return false }
        switch app {
        case .finder: return finder
        case .chrome: return chrome
        case .chatGPT: return chatGPT
        case .codex: return codex
        case .claude: return claude
        }
    }

    /// 这个 App 的图标里画不画额度水位（连同百分比和悬停倒计时）。
    public func showsQuota(_ app: LiveIconApp) -> Bool {
        app.isAI && quota && isOn(app)
    }

    /// Codex 拆出自己的开关之前，ChatGPT/Codex 共用 `liveIcons.ai`。
    /// 升级上来还没有 Codex 开关的，照搬原来那个开关的值，不让关掉的 Codex 突然动起来。
    public static func migrateCodexToggle(_ defaults: UserDefaults) {
        guard defaults.object(forKey: codexKey) == nil,
              let shared = defaults.object(forKey: openAIKey) as? Bool else { return }
        defaults.set(shared, forKey: codexKey)
    }
}

/// AI 图标里的水位读的是哪个额度窗口。
public enum LiveQuotaWindow: Equatable, Sendable {
    /// 5 小时窗口。
    case session
    /// 每周窗口。
    case weekly
}

/// 水位要画的额度：还剩多少、来自哪个窗口、什么时候重置。
public struct LiveQuota: Equatable, Sendable {
    /// 剩余比例，0...1。
    public var remaining: Double
    public var window: LiveQuotaWindow
    public var resetsAt: Date?

    public init(remaining: Double, window: LiveQuotaWindow, resetsAt: Date?) {
        self.remaining = min(1, max(0, remaining))
        self.window = window
        self.resetsAt = resetsAt
    }
}

/// 设置里「显示：」选的额度窗口。
public enum LiveQuotaPreference: String, CaseIterable, Equatable, Sendable {
    /// 固定看 5 小时窗口。
    case session
    /// 固定看每周窗口。
    case weekly
    /// 两个里取更紧的（默认）。
    case tighter

    public static let key = "liveIcons.aiWindow"
    public static let `default` = LiveQuotaPreference.tighter

    /// 存的值读不懂或没存时用默认。
    public init(stored: String?) {
        self = stored.flatMap(LiveQuotaPreference.init(rawValue:)) ?? .default
    }
}

/// ChatGPT、Codex 和 Claude 图标里的水位和流光。
public enum LiveIconUsage {
    /// 水位 = 剩余额度（1 - 已用）：水越少越接近用完，像油箱。
    ///
    /// 默认（`.tighter`）5 小时和每周两个窗口取更紧的那个（剩余更少的）：哪个先卡住你，
    /// 就看哪个。某个窗口缺失、数值不对，或者它的重置时间已经过了（读数是上一轮的，
    /// 不再可信），就只看另一个；剩余一样多时取 5 小时窗口（它先重置，倒计时更有用）。
    /// 设置里固定成 5 小时或每周时只看那一个，它用不了就是未知，不拿另一个顶上。
    /// 报告没有或已过期（默认 30 分钟）时是 nil，即「未知」，图标里不画水位，绝不拿猜的数顶上。
    public static func quota(session: CodexLimitWindow?, weekly: CodexLimitWindow?,
                             fetchedAt: Date?, now: Date,
                             preference: LiveQuotaPreference = .tighter,
                             staleAfter: TimeInterval = 30 * 60) -> LiveQuota? {
        guard let fetchedAt, now.timeIntervalSince(fetchedAt) <= staleAfter else { return nil }
        func usable(_ w: CodexLimitWindow?, _ kind: LiveQuotaWindow) -> LiveQuota? {
            guard let w, w.usedFraction.isFinite else { return nil }
            if let resets = w.resetsAt, resets <= now { return nil }
            return LiveQuota(remaining: 1 - w.usedFraction, window: kind, resetsAt: w.resetsAt)
        }
        switch preference {
        case .session: return usable(session, .session)
        case .weekly: return usable(weekly, .weekly)
        case .tighter:
            let candidates = [usable(session, .session), usable(weekly, .weekly)].compactMap { $0 }
            return candidates.min { $0.remaining < $1.remaining }
        }
    }

    /// 报告里的 5 小时和每周窗口（Codex、Claude 共用一种报告）。
    public static func quota(_ report: CodexUsageReport?, now: Date,
                             preference: LiveQuotaPreference = .tighter,
                             staleAfter: TimeInterval = 30 * 60) -> LiveQuota? {
        guard let report else { return nil }
        return quota(session: report.primary, weekly: report.weekly,
                     fetchedAt: report.fetchedAt, now: now, preference: preference, staleAfter: staleAfter)
    }

    /// 重置倒计时的紧凑写法，只用 ASCII：不到 1 小时「42m」，
    /// 不到 1 天「19h 0m」，再长「1d 18h」。分钟向下取整，还剩不到 1 分钟时是「0m」；
    /// 已经过了或数值不对时也是「0m」。
    public static func resetCountdown(_ seconds: TimeInterval) -> String {
        let p = countdownParts(seconds)
        if p.hours < 1 && p.days < 1 { return "\(p.minutes)m" }
        if p.days < 1 { return "\(p.hours)h \(p.minutes)m" }
        return "\(p.days)d \(p.hours)h"
    }

    /// 离 resetsAt 还有多久的紧凑倒计时；没有重置时间时是 nil。
    public static func resetCountdown(_ quota: LiveQuota, now: Date) -> String? {
        quota.resetsAt.map { resetCountdown($0.timeIntervalSince(now)) }
    }

    /// 悬停胶囊里的整句：「1天 18小时后重置」「19小时 0分后重置」「42分后重置」，
    /// 英文界面是「Resets in 1d 18h」这类（走 Localizable.xcstrings）。分段规则同 `resetCountdown`。
    public static func resetSentence(_ seconds: TimeInterval) -> String {
        let p = countdownParts(seconds)
        if p.hours < 1 && p.days < 1 { return tr("\(p.minutes)分后重置") }
        if p.days < 1 { return tr("\(p.hours)小时 \(p.minutes)分后重置") }
        return tr("\(p.days)天 \(p.hours)小时后重置")
    }

    /// 离 resetsAt 还有多久的整句；没有重置时间时是 nil（悬停时不显示胶囊）。
    public static func resetSentence(_ quota: LiveQuota?, now: Date) -> String? {
        guard let resetsAt = quota?.resetsAt else { return nil }
        return resetSentence(resetsAt.timeIntervalSince(now))
    }

    /// 天、余下的小时（不到 1 天时是总小时）、余下的分钟。
    static func countdownParts(_ seconds: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        guard seconds.isFinite, seconds > 0 else { return (0, 0, 0) }
        let s = Int(min(seconds, 9_999 * 86_400))
        let days = s / 86_400
        return (days, days > 0 ? (s / 3600) % 24 : s / 3600, (s / 60) % 60)
    }

    /// 左下角百分比大字的字号：跟图标一起缩放，约为图标边长的 23%，但不小于 11pt。
    public static func percentFontSize(side: Double) -> Double {
        guard side.isFinite, side > 0 else { return 11 }
        return max(11, side * 0.2)
    }

    /// 流光只在 Codex 真在干活时绕圈：工作中，或者一轮做到一半停下来等你批准。
    /// 空闲和刚做完都不亮。
    public static func isWorking(_ activity: CodexActivity) -> Bool {
        switch activity {
        case .working, .waiting: return true
        case .idle, .done: return false
        }
    }

    /// 左下角的百分比大字（显示剩余），四舍五入到整数。
    public static func percentText(_ level: Double) -> String {
        guard level.isFinite else { return "" }
        return "\(Int((min(1, max(0, level)) * 100).rounded()))%"
    }

    /// 液面在内容区里的高度（从底往上，0...1），level 是剩余比例。按效果图只占图标下半截：
    /// 满额也只到约一半高，上半截的 App 标志始终露出来，一眼认得是哪个 App；几乎用完也露一条水线。
    public static func surfaceFraction(_ level: Double) -> Double {
        guard level.isFinite else { return 0 }
        let l = min(1, max(0, level))
        return 0.06 + l * 0.42
    }
}

/// macOS 图标的绘制区域：内容区约占边长 80%，居中；圆角约为内容边长的 22.37%。
public enum LiveIconGeometry {
    public static let contentFraction = 0.805
    public static let cornerFraction = 0.2237

    /// 边长为 side 的图标格里，内容区的边长和圆角半径。
    public static func content(side: Double) -> (inset: Double, length: Double, corner: Double) {
        let s = max(0, side)
        let length = s * contentFraction
        return ((s - length) / 2, length, length * cornerFraction)
    }
}

/// 动画节奏：一个图标一条 TimelineView，没东西动时暂停，不另起定时器。
public enum LiveIconMotion {
    public enum Kind: Equatable, Sendable {
        /// Chrome 图标转动，要顺。
        case spin
        /// 流光绕边，比水面快一点。
        case flow
        /// 只有水面轻轻晃。
        case water
    }

    /// 两帧之间至少隔多久。低电量模式明显降频；减弱动态效果时不该走到这里（直接静态）。
    public static func frameInterval(_ kind: Kind, lowPower: Bool) -> Double {
        switch (kind, lowPower) {
        case (.spin, false): return 1.0 / 60
        case (.flow, false): return 1.0 / 30
        case (.water, false): return 1.0 / 15
        case (.spin, true): return 1.0 / 24
        case (.flow, true): return 1.0 / 10
        case (.water, true): return 1.0 / 8
        }
    }

    /// 问 Chrome 当前标签页在不在加载的间隔：Chrome 在前台 0.5 秒，
    /// 在后台或低电量 1.5 秒，连着读不到时再放慢到 5 秒。
    public static func chromePollInterval(chromeFrontmost: Bool, lowPower: Bool, failures: Int = 0) -> Double {
        if failures > 0 { return 5 }
        return chromeFrontmost && !lowPower ? 0.5 : 1.5
    }
}

/// 问 Chrome「front window 的 active tab 在不在 loading」的结果。
public enum LiveChromeReading: Equatable, Sendable {
    case loading
    case idle
    /// 用户拒绝了自动化权限（-1743），或系统还没问过（-1744）。
    case denied
    /// 别的原因读不到（没装 Chrome、脚本出错）。
    case failed

    public init(loading: Bool?, errorCode: Int?) {
        if let errorCode {
            self = (errorCode == -1743 || errorCode == -1744) ? .denied : .failed
        } else if let loading {
            self = loading ? .loading : .idle
        } else {
            self = .failed
        }
    }
}

/// Chrome 读数是否可信：连着读到才转图标；拒绝或读不到时退回启动转一圈，绝不显示假进度。
public struct LiveChromeAvailability: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case unknown, available, unavailable }

    public private(set) var status: Status = .unknown
    public private(set) var failures = 0
    /// 拒绝之后不再问，免得每秒白跑一个必失败的脚本。
    public private(set) var stopped = false
    public static let failureLimit = 3

    public init() {}

    /// 记下一次读数，返回这次之后图标该不该转。
    @discardableResult
    public mutating func record(_ reading: LiveChromeReading) -> Bool {
        switch reading {
        case .loading, .idle:
            status = .available
            failures = 0
            return reading == .loading
        case .denied:
            status = .unavailable
            stopped = true
            return false
        case .failed:
            failures += 1
            if failures >= Self.failureLimit { status = .unavailable }
            return false
        }
    }

    /// 重新开始（开关重开、Chrome 重新启动）。
    public mutating func reset() { self = LiveChromeAvailability() }
}

/// Chrome 图标本身的转动：加载时匀速转，停下时用缓动减速回到原角度，
/// 退回方案是启动那一下转一圈。角度单位是度，只在 0..<360 里存，时间由调用方给。
public struct LiveIconSpin: Equatable, Sendable {
    /// 匀速：一圈约 1.1 秒。
    public static let degreesPerSecond = 360.0 / 1.1
    /// 减速至少再转这么多度，太短会像急刹。
    public static let minimumSettle = 120.0
    /// 启动转一圈用的时长。
    public static let oneTurnDuration = 0.9

    public enum Phase: Equatable, Sendable {
        case resting
        case spinning(since: Date, from: Double)
        /// 二次缓出：起始角速度等于匀速，结束时为 0，正好停在 360 的整数倍。
        case settling(since: Date, from: Double, distance: Double, duration: Double)
        /// 慢起慢停转满一圈。
        case oneTurn(since: Date, from: Double)
    }

    public private(set) var phase: Phase = .resting

    public init() {}

    public var isSpinning: Bool {
        if case .spinning = phase { return true }
        return false
    }

    /// 当前角度（0..<360）。
    public func angle(at now: Date) -> Double {
        switch phase {
        case .resting:
            return 0
        case let .spinning(since, from):
            return Self.wrap(from + Self.degreesPerSecond * max(0, now.timeIntervalSince(since)))
        case let .settling(since, from, distance, duration):
            let u = min(1, max(0, now.timeIntervalSince(since) / max(duration, 0.001)))
            let eased = 1 - (1 - u) * (1 - u)
            return Self.wrap(from + distance * eased)
        case let .oneTurn(since, from):
            let u = min(1, max(0, now.timeIntervalSince(since) / Self.oneTurnDuration))
            let eased = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
            return Self.wrap(from + (360 - from) * eased)
        }
    }

    /// 动画什么时候结束；匀速转时没有结束时间（nil），静止时是 since 之前。
    public func endDate(at now: Date) -> Date? {
        switch phase {
        case .resting: return now
        case .spinning: return nil
        case let .settling(since, _, _, duration): return since.addingTimeInterval(duration)
        case let .oneTurn(since, _): return since.addingTimeInterval(Self.oneTurnDuration)
        }
    }

    public func isAnimating(at now: Date) -> Bool {
        guard let end = endDate(at: now) else { return true }
        return end > now
    }

    /// 开始匀速转，从当前角度接着转，不跳。
    public mutating func start(at now: Date) {
        if isSpinning { return }
        let from = isAnimating(at: now) ? angle(at: now) : 0
        phase = .spinning(since: now, from: from)
    }

    /// 加载完：减速停到下一个 360 的整数倍（原角度）。
    public mutating func stop(at now: Date) {
        guard isSpinning else { return }
        let from = angle(at: now)
        var distance = 360 - from
        if distance < Self.minimumSettle { distance += 360 }
        // 二次缓出的初速度是 2·distance/duration，令它等于匀速，衔接不顿。
        let duration = 2 * distance / Self.degreesPerSecond
        phase = .settling(since: now, from: from, distance: distance, duration: duration)
    }

    /// 退回方案：启动那一下转一圈。正在转或正在减速时不打断。
    public mutating func turnOnce(at now: Date) {
        guard !isAnimating(at: now) else { return }
        phase = .oneTurn(since: now, from: 0)
    }

    /// 结束后归位，角度回到 0。
    public mutating func settleIfDone(at now: Date) {
        if !isAnimating(at: now) { phase = .resting }
    }

    static func wrap(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let r = degrees.truncatingRemainder(dividingBy: 360)
        let v = r < 0 ? r + 360 : r
        return v >= 359.9999 ? 0 : v
    }
}
