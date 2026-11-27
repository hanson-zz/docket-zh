import Foundation

// MARK: - 时间洞察 · 领域模型
//
// 时间洞察记的是「哪个 App 在前台、你真的在用」的时间段。采集器（Services 里的
// `TimeInsightsTracker`）把系统事件喂给 `TimeInsightsRecorder`，它切出一段段
// `ActivitySession`，写进本机的 SQLite（`TimeInsightsDatabase`）。这里的东西都是
// 纯逻辑，测试直接编译：分类、按天拆分、去重、汇总、CSV 导出、设置和 Pro 范围。
//
// 隐私约定：
// - 只记前台 App 的 bundle ID 和显示名，不读按键内容，不截图，不做 OCR。
// - 窗口标题和网站域名两项（Pro）在阶段 A 只有接口，「待接通」，不采集；即使将来接通，
//   也要用户逐项单独同意，购买 Pro 不等于同意（见 `TimeInsightsSettings`）。
// - 网址只留域名，路径、查询串、锚点一律丢掉（`TimeInsightsDomain.sanitize`）。
// - 暂停、排除、清空、基础导出都免费。

/// 一段活动的分类。默认全部是未分类，只有内置的少量 bundle ID 规则会给出别的分类；
/// 认不出来的保持未分类，不硬猜（浏览器不等于工作）。
public enum TimeInsightsCategory: String, CaseIterable, Codable, Sendable {
    case development
    case design
    case learning
    case communication
    case entertainment
    case other
    case uncategorized

    public var title: String {
        switch self {
        case .development: tr("开发", context: "category")
        case .design: tr("设计")
        case .learning: tr("学习")
        case .communication: tr("沟通")
        case .entertainment: tr("娱乐", context: "category")
        case .other: tr("其他")
        case .uncategorized: tr("未分类")
        }
    }

    public var symbol: String {
        switch self {
        case .development: "chevron.left.forwardslash.chevron.right"
        case .design: "paintpalette"
        case .learning: "book"
        case .communication: "bubble.left.and.bubble.right"
        case .entertainment: "play.rectangle"
        case .other: "square.grid.2x2"
        case .uncategorized: "questionmark.circle"
        }
    }

    /// 今日总览里算「工作」的分类。娱乐和其他算「其他」，未分类单独一格，
    /// 不并进工作，免得工作占比虚高。
    public var countsAsWork: Bool {
        switch self {
        case .development, .design, .learning, .communication: true
        case .entertainment, .other, .uncategorized: false
        }
    }

    /// 存进数据库的值认不出来时（新版本写的分类）按未分类读。
    public init(stored raw: String) {
        self = TimeInsightsCategory(rawValue: raw) ?? .uncategorized
    }
}

/// 一段记录从哪来。
public enum ActivitySource: String, Codable, Sendable, CaseIterable {
    /// 前台 App 且有键盘鼠标操作：算「有效活跃」。
    case foreground
    /// App 在前台，但超过空闲门槛没有任何输入（看视频、离开座位但没锁屏）：
    /// 只算「前台停留」，不算活跃。
    case idleForeground = "idle-foreground"
    /// 浏览器扩展传来的网站段（阶段 B，待接通）。
    case browserBridge = "browser-bridge"

    public init(stored raw: String) {
        self = ActivitySource(rawValue: raw) ?? .foreground
    }

    /// 这一段算不算有效活跃。
    public var isActive: Bool { self != .idleForeground }
}

/// 一段记录带的隐私标记（存成整数）。
public struct ActivityPrivacyFlags: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// 窗口标题已按规则抹掉（阶段 B）。
    public static let titleRedacted = ActivityPrivacyFlags(rawValue: 1 << 0)
    /// 网址只留了域名。
    public static let domainOnly = ActivityPrivacyFlags(rawValue: 1 << 1)
    /// 私密浏览窗口：不记标题和域名（阶段 B）。
    public static let privateBrowsing = ActivityPrivacyFlags(rawValue: 1 << 2)
    /// 命中敏感 App 或排除站点规则（阶段 B）。
    public static let sensitive = ActivityPrivacyFlags(rawValue: 1 << 3)
}

/// 一段连续的前台活动。时间是绝对时刻（存成 Unix 秒），显示和按天拆分时才用本地日历。
public struct ActivitySession: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    /// 窗口标题：Pro 且单独同意后才会有（阶段 B），阶段 A 永远是 nil。
    public var windowTitle: String?
    /// 网站域名：Pro 且单独同意、浏览器扩展接通后才会有（阶段 B），阶段 A 永远是 nil。
    public var domain: String?
    public var classification: TimeInsightsCategory
    public var source: ActivitySource
    public var privacyFlags: ActivityPrivacyFlags

    public init(id: String = UUID().uuidString, start: Date, end: Date, bundleID: String, appName: String,
                windowTitle: String? = nil, domain: String? = nil,
                classification: TimeInsightsCategory = .uncategorized,
                source: ActivitySource = .foreground, privacyFlags: ActivityPrivacyFlags = []) {
        self.id = id
        self.start = start
        self.end = end
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.domain = domain
        self.classification = classification
        self.source = source
        self.privacyFlags = privacyFlags
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

// MARK: - 分类规则

/// 一条分类规则：按 bundle ID、窗口标题关键词或网站域名匹配，`priority` 大的先比。
/// 自定义规则的编辑是 Pro（阶段 B）；阶段 A 只有内置的 bundle ID 规则在用。
public struct TimeInsightsRule: Codable, Equatable, Hashable, Sendable {
    public enum Match: Codable, Equatable, Hashable, Sendable {
        case bundleID(String)
        case titleKeyword(String)
        case domain(String)
    }

    public var match: Match
    public var category: TimeInsightsCategory
    public var priority: Int

    public init(_ match: Match, category: TimeInsightsCategory, priority: Int = 0) {
        self.match = match
        self.category = category
        self.priority = priority
    }

    /// 这条规则认不认这一段。标题和域名为 nil 时，对应的规则不命中。
    public func matches(bundleID: String, windowTitle: String?, domain: String?) -> Bool {
        switch match {
        case .bundleID(let id):
            return id.caseInsensitiveCompare(bundleID) == .orderedSame
        case .titleKeyword(let keyword):
            guard let windowTitle, !keyword.isEmpty else { return false }
            return windowTitle.localizedCaseInsensitiveContains(keyword)
        case .domain(let rule):
            guard let domain, !rule.isEmpty else { return false }
            let host = domain.lowercased()
            let wanted = rule.lowercased()
            return host == wanted || host.hasSuffix("." + wanted)
        }
    }
}

public enum TimeInsightsClassifier {
    /// 内置的少量规则：只收确定的 bundle ID。浏览器、终端以外的通用工具、
    /// 认不出的 App 都不在这里，保持未分类。
    public static let builtIn: [String: TimeInsightsCategory] = [
        "com.apple.dt.Xcode": .development,
        "com.microsoft.VSCode": .development,
        "com.apple.Terminal": .development,
        "com.googlecode.iterm2": .development,
        "com.jetbrains.intellij": .development,
        "com.github.GitHubClient": .development,
        "com.figma.Desktop": .design,
        "com.bohemiancoding.sketch3": .design,
        "com.adobe.Photoshop": .design,
        "com.adobe.illustrator": .design,
        "com.apple.mail": .communication,
        "com.tinyspeck.slackmacgap": .communication,
        "com.tencent.xinWeChat": .communication,
        "com.tencent.WeWorkMac": .communication,
        "com.alibaba.DingTalkMac": .communication,
        "com.electron.lark": .communication,
        "us.zoom.xos": .communication,
        "com.apple.iChat": .communication,
        "com.apple.Music": .entertainment,
        "com.spotify.client": .entertainment,
        "com.apple.TV": .entertainment,
        "com.netease.163music": .entertainment,
    ]

    /// 用户规则按优先级（大的先）比，同优先级按给的顺序；都不中再看内置规则；
    /// 再不中就是未分类。
    public static func classify(bundleID: String, windowTitle: String? = nil, domain: String? = nil,
                                rules: [TimeInsightsRule] = []) -> TimeInsightsCategory {
        let ordered = rules.enumerated().sorted {
            $0.element.priority != $1.element.priority
                ? $0.element.priority > $1.element.priority
                : $0.offset < $1.offset
        }
        for (_, rule) in ordered where rule.matches(bundleID: bundleID, windowTitle: windowTitle, domain: domain) {
            return rule.category
        }
        return builtIn[bundleID] ?? .uncategorized
    }

    /// 规则改了以后重算分类：只换 `classification`，时间、App 和来源一律不动。
    public static func reclassify(_ sessions: [ActivitySession], rules: [TimeInsightsRule]) -> [ActivitySession] {
        sessions.map { session in
            var copy = session
            copy.classification = classify(bundleID: session.bundleID, windowTitle: session.windowTitle,
                                           domain: session.domain, rules: rules)
            return copy
        }
    }
}

// MARK: - 设置

/// 时间洞察的设置：存在 UserDefaults（`TimeInsightsSettings.defaultsKey`），全局一份，
/// 不跟着某张卡片。窗口标题和网站两项默认关，要用户自己打开；阶段 A 打开了也不采集
/// （`TimeInsightsPro.collectsWindowTitles` 等恒为假）。
public struct TimeInsightsSettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "timeInsights.settings"
    /// 空闲判定可选的分钟数。
    public static let idleChoices: [Int] = [1, 2, 3, 5, 10, 15, 30]
    public static let defaultIdleMinutes = 5
    /// 保留多少天的记录，超出的在启动和每天第一次写入时删掉。
    public static let defaultRetentionDays = 90

    public var paused: Bool
    public var idleMinutes: Int
    public var excludedBundleIDs: [String]
    /// 窗口标题统计（Pro，阶段 B）的单独同意。
    public var windowTitlesOptIn: Bool
    /// 网站域名统计（Pro，阶段 B）的单独同意。
    public var websitesOptIn: Bool
    public var retentionDays: Int

    public init(paused: Bool = false, idleMinutes: Int = defaultIdleMinutes, excludedBundleIDs: [String] = [],
                windowTitlesOptIn: Bool = false, websitesOptIn: Bool = false,
                retentionDays: Int = defaultRetentionDays) {
        self.paused = paused
        self.idleMinutes = idleMinutes
        self.excludedBundleIDs = excludedBundleIDs
        self.windowTitlesOptIn = windowTitlesOptIn
        self.websitesOptIn = websitesOptIn
        self.retentionDays = retentionDays
    }

    /// 少了键（旧版本存的）按默认补，空闲分钟数夹在 1 到 60 之间。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        let idle = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? Self.defaultIdleMinutes
        idleMinutes = min(60, max(1, idle))
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
        windowTitlesOptIn = try c.decodeIfPresent(Bool.self, forKey: .windowTitlesOptIn) ?? false
        websitesOptIn = try c.decodeIfPresent(Bool.self, forKey: .websitesOptIn) ?? false
        let keep = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? Self.defaultRetentionDays
        retentionDays = max(1, keep)
    }

    public var idleThreshold: TimeInterval { TimeInterval(idleMinutes * 60) }

    public func isExcluded(_ bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }

    public mutating func exclude(_ bundleID: String) {
        guard !bundleID.isEmpty, !isExcluded(bundleID) else { return }
        excludedBundleIDs.append(bundleID)
    }

    public mutating func include(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    public static func decode(_ data: Data?) -> TimeInsightsSettings {
        guard let data, let settings = try? JSONDecoder().decode(TimeInsightsSettings.self, from: data) else {
            return TimeInsightsSettings()
        }
        return settings
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

/// 自带的、默认不记的 App：码头自己、登录窗口和屏保这类系统界面。
public enum TimeInsightsDefaults {
    /// 码头自己的 bundle ID（project.yml 的 PRODUCT_BUNDLE_IDENTIFIER）。点面板、开设置时
    /// 码头会到前台，这段时间不算用了别的 App，也不算用了码头。
    public static let ownBundleID = "com.docket-zh.app"

    public static let alwaysSkipped: Set<String> = [
        ownBundleID,
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.SecurityAgent",
    ]
}

// MARK: - 计算

public enum TimeInsightsMath {
    /// 在本地午夜切开：跨天的一段拆成每天一段，id 加上 `#1`、`#2` 后缀（第一段保留原 id）。
    public static func splitByDay(_ session: ActivitySession, calendar: Calendar = .current) -> [ActivitySession] {
        guard session.end > session.start else { return [] }
        var parts: [ActivitySession] = []
        var cursor = session.start
        var index = 0
        while cursor < session.end {
            let dayStart = calendar.startOfDay(for: cursor)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? session.end
            let end = min(dayEnd, session.end)
            var part = session
            part.id = index == 0 ? session.id : "\(session.id)#\(index)"
            part.start = cursor
            part.end = end
            parts.append(part)
            cursor = end
            index += 1
        }
        return parts
    }

    /// 去重并消除重叠：同 id 只留一份；按开始时间排好后，后一段和前一段重叠的部分剪掉，
    /// 剪完没有长度的丢掉。保证任何时刻最多算一次，不双计。
    public static func normalized(_ sessions: [ActivitySession]) -> [ActivitySession] {
        var seen = Set<String>()
        let unique = sessions.filter { seen.insert($0.id).inserted && $0.end > $0.start }
        let sorted = unique.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        var out: [ActivitySession] = []
        var reach: Date?
        for var session in sorted {
            if let reach, session.start < reach {
                session.start = reach
            }
            guard session.end > session.start else { continue }
            out.append(session)
            reach = max(reach ?? session.end, session.end)
        }
        return out
    }

    /// 只留 `interval` 里面的部分。
    public static func clipped(_ sessions: [ActivitySession], to interval: DateInterval) -> [ActivitySession] {
        sessions.compactMap { session in
            let start = max(session.start, interval.start)
            let end = min(session.end, interval.end)
            guard end > start else { return nil }
            var copy = session
            copy.start = start
            copy.end = end
            return copy
        }
    }

    /// `day` 所在那一天（本地日历）的区间。
    public static func dayInterval(_ day: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }
}

/// 一个 App 今天用了多久。
public struct TimeInsightsAppUsage: Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var appName: String
    public var category: TimeInsightsCategory
    public var active: TimeInterval
    /// 有效活跃的段数（切换回来、空闲回来都是新的一段）。
    public var segments: Int
    public var id: String { bundleID }

    public init(bundleID: String, appName: String, category: TimeInsightsCategory, active: TimeInterval,
                segments: Int = 0) {
        self.bundleID = bundleID
        self.appName = appName
        self.category = category
        self.active = active
        self.segments = segments
    }
}

/// 一天的汇总。三种口径分开算：前台停留（含无操作的那段）、有效活跃、已分类工作。
public struct TimeInsightsDay: Equatable, Sendable {
    /// 有效活跃：前台且有输入的时间。
    public var active: TimeInterval
    /// 前台停留：有效活跃加上 App 在前台但没有输入的时间（不含锁屏、休眠）。
    public var foreground: TimeInterval
    /// 已分类为工作（开发、设计、学习、沟通）的有效活跃。
    public var work: TimeInterval
    /// 娱乐和其他的有效活跃。
    public var other: TimeInterval
    /// 未分类的有效活跃。
    public var uncategorized: TimeInterval
    /// 按有效活跃从多到少排好的 App。
    public var apps: [TimeInsightsAppUsage]
    /// 每小时的有效活跃秒数，24 格（详细时间轴是 Pro，阶段 C 再画）。
    public var hours: [TimeInterval]
    /// 有效活跃的段数（每次切换 App 或从空闲回来都是新的一段）。
    public var segments: Int
    /// 最长的一段连续活跃（同一个 App，不被切换或空闲打断）。
    public var longest: TimeInsightsAppUsage?
    /// 每个分类的有效活跃秒数（没有的分类不在里面）。
    public var categories: [TimeInsightsCategory: TimeInterval] = [:]
    /// 每个分类在 24 个小时里各有多少有效活跃秒数，按小时分类堆叠的柱状图用。
    public var hourCategories: [TimeInsightsCategory: [TimeInterval]] = [:]
    /// 每个 App（bundle ID）在 24 个小时里各有多少有效活跃秒数，按应用切换时用。
    public var hourApps: [String: [TimeInterval]] = [:]

    public static let empty = TimeInsightsDay(active: 0, foreground: 0, work: 0, other: 0, uncategorized: 0,
                                              apps: [], hours: Array(repeating: 0, count: 24),
                                              segments: 0, longest: nil)

    /// 免费层的 Top 5。
    public static let freeTopCount = 5

    public func top(_ count: Int = freeTopCount) -> [TimeInsightsAppUsage] { Array(apps.prefix(count)) }

    public var isEmpty: Bool { foreground <= 0 }

    /// 前台停留里没有输入、不算活跃的那部分。
    public var idleForeground: TimeInterval { max(0, foreground - active) }

    /// 一天的汇总。码头自己、登录窗口这类默认不记的 App（`TimeInsightsDefaults.alwaysSkipped`）
    /// 即使库里有（旧版本记过），也不计入。
    public static func make(_ sessions: [ActivitySession], day: Date, calendar: Calendar = .current) -> TimeInsightsDay {
        let interval = TimeInsightsMath.dayInterval(day, calendar: calendar)
        let counted = sessions.filter { !TimeInsightsDefaults.alwaysSkipped.contains($0.bundleID) }
        let clean = TimeInsightsMath.clipped(TimeInsightsMath.normalized(counted), to: interval)
        var result = TimeInsightsDay.empty
        var byApp: [String: TimeInsightsAppUsage] = [:]
        for session in clean {
            let length = session.duration
            result.foreground += length
            guard session.source.isActive else { continue }
            result.active += length
            result.segments += 1
            if session.classification.countsAsWork {
                result.work += length
            } else if session.classification == .uncategorized {
                result.uncategorized += length
            } else {
                result.other += length
            }
            var usage = byApp[session.bundleID]
                ?? TimeInsightsAppUsage(bundleID: session.bundleID, appName: session.appName,
                                        category: session.classification, active: 0)
            usage.active += length
            usage.segments += 1
            // 名字和分类用最近的一段（App 改名或规则改了以后，显示新的）。
            usage.appName = session.appName
            usage.category = session.classification
            byApp[session.bundleID] = usage
            if length > (result.longest?.active ?? 0) {
                result.longest = TimeInsightsAppUsage(bundleID: session.bundleID, appName: session.appName,
                                                      category: session.classification, active: length)
            }
            result.categories[session.classification, default: 0] += length
            for (hour, seconds) in hourParts(session, calendar: calendar) {
                result.hours[hour] += seconds
                result.hourCategories[session.classification, default: Array(repeating: 0, count: 24)][hour] += seconds
                result.hourApps[session.bundleID, default: Array(repeating: 0, count: 24)][hour] += seconds
            }
        }
        result.apps = byApp.values.sorted {
            $0.active != $1.active ? $0.active > $1.active : $0.appName < $1.appName
        }
        return result
    }

    /// 一段在每个整点小时里各占多少秒（本地日历的小时，0 到 23）。
    static func hourParts(_ session: ActivitySession, calendar: Calendar) -> [(Int, TimeInterval)] {
        var parts: [(Int, TimeInterval)] = []
        var cursor = session.start
        while cursor < session.end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let hourEnd = hourStart.addingTimeInterval(3600)
            let end = min(hourEnd, session.end)
            guard end > cursor else { break }
            if (0..<24).contains(hour) { parts.append((hour, end.timeIntervalSince(cursor))) }
            cursor = end
        }
        return parts
    }
}

// MARK: - 导出

public enum TimeInsightsCSV {
    /// 基础导出（免费）的列。窗口标题和域名属于完整导出（Pro，阶段 C），这里不带。
    public static let header = "start,end,duration_seconds,bundle_id,app_name,category,source"

    public static func make(_ sessions: [ActivitySession]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [header]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            lines.append([
                formatter.string(from: s.start),
                formatter.string(from: s.end),
                String(Int(s.duration.rounded())),
                escape(s.bundleID),
                escape(s.appName),
                s.classification.rawValue,
                s.source.rawValue,
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 带逗号、引号或换行的字段加引号，里面的引号写两遍。开头是 = + - @ 的加一个
    /// 单引号，免得表格软件把 App 名当公式。
    public static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - 显示

public enum TimeInsightsFormat {
    /// 「3 小时 12 分」「45 分」「不到 1 分」。
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        if minutes < 1 { return tr("不到 1 分") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(rest) 分") }
        if rest == 0 { return tr("\(hours) 小时") }
        return tr("\(hours) 小时 \(rest) 分")
    }

    /// 展开面板顶部大数字的紧凑写法（例如「6h 32m」），避免 440pt 面板挤压环形图。
    /// 0 显示 0m；已有正时长但不足一分钟显示 <1m。
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        let minutes = Int((value / 60).rounded(.down))
        if minutes == 0 { return value > 0 ? "<1m" : "0m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    /// 竖排卡片上的短写法「3:12」。
    public static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        return String(format: "%ld:%02ld", minutes / 60, minutes % 60)
    }

    /// 卡片进度条的满格：8 小时。只是参照，不是目标。
    public static let barFull: TimeInterval = 8 * 3600

    public static func barFraction(_ active: TimeInterval) -> Double {
        min(1, max(0, active / barFull))
    }
}

// MARK: - 采集状态

/// 卡片和面板上的状态。
public enum TimeInsightsStatus: Equatable, Sendable {
    /// 正在记前台 App。
    case recording
    /// 超过空闲门槛没有输入：AFK，不计活跃。
    case idle
    /// 用户在面板或设置里暂停了。
    case paused
    /// 锁屏、休眠、屏保、显示器睡眠或切换了用户。
    case away
    /// 前台是排除的 App。
    case excluded
    /// 前台是码头自己（在看面板、设置或完整统计）：不计时。
    case ownApp
    /// 还没开始（刚启动、还不知道前台是谁）。
    case starting
    /// 本机数据库打不开：不记，也不用假数据补。
    case storageError

    public var title: String {
        switch self {
        case .recording: tr("正在记录")
        case .idle: tr("暂时离开，不计时")
        case .paused: tr("已暂停记录")
        case .away: tr("锁屏或休眠中，不计时")
        case .excluded: tr("排除的应用，不计时")
        case .ownApp: tr("码头在前台，不计时")
        case .starting: tr("准备中")
        case .storageError: tr("本机数据打不开，暂停记录")
        }
    }

    /// 卡片上那一行放得下的短说法。
    public var shortTitle: String {
        switch self {
        case .recording: tr("正在记录")
        case .idle: tr("暂时离开")
        case .paused: tr("已暂停")
        case .away: tr("未在使用")
        case .excluded: tr("排除的应用")
        case .ownApp: tr("码头自身")
        case .starting: tr("准备中")
        case .storageError: tr("数据打不开")
        }
    }

    public var symbol: String {
        switch self {
        case .recording: "hourglass"
        case .idle: "moon.zzz"
        case .paused: "pause.circle"
        case .away: "lock"
        case .excluded: "eye.slash"
        case .ownApp: "pause.circle"
        case .starting: "hourglass"
        case .storageError: "exclamationmark.triangle"
        }
    }
}

// MARK: - Pro 范围（阶段 A 只占位）

/// 时间洞察的 Pro 功能。阶段 A 全部「待接通」：界面只写说明，不采集、不伪造数据。
public enum TimeInsightsProFeature: String, CaseIterable, Sendable {
    case windowTitles
    case websites
    case customRules
    case detailedTimeline
    case trends
    case fullExport

    public var title: String {
        switch self {
        case .windowTitles: tr("窗口标题统计")
        case .websites: tr("网站域名统计")
        case .customRules: tr("自定义分类规则")
        case .detailedTimeline: tr("详细时间轴")
        case .trends: tr("周、月趋势")
        case .fullExport: tr("完整数据导出")
        }
    }

    public var detail: String {
        switch self {
        case .windowTitles: tr("单独同意后才读取当前窗口的标题，可随时撤销。")
        case .websites: tr("通过浏览器扩展只记域名，不记网址路径和查询内容。")
        case .customRules: tr("按应用、标题关键词或域名设置分类和优先级。")
        case .detailedTimeline: tr("按时间段查看每一段活动。")
        case .trends: tr("按日、周、月对比活跃和工作时长。")
        case .fullExport: tr("导出包括窗口标题和域名在内的全部字段。")
        }
    }

    public var symbol: String {
        switch self {
        case .windowTitles: "macwindow"
        case .websites: "globe"
        case .customRules: "slider.horizontal.3"
        case .detailedTimeline: "chart.bar.xaxis"
        case .trends: "chart.line.uptrend.xyaxis"
        case .fullExport: "square.and.arrow.up.on.square"
        }
    }

    /// 这一项现在接通了没有。阶段 A 全部没有。
    public var isConnected: Bool { false }

    /// 要不要用户单独同意采集（和买没买 Pro 无关）。
    public var needsConsent: Bool {
        switch self {
        case .windowTitles, .websites: true
        default: false
        }
    }
}

public enum TimeInsightsPro {
    /// Pro 是否解锁，只决定「能不能打开」，不决定「打开了没有」。
    public static func isActive(unlocked: Bool) -> Bool { unlocked }

    /// 现在采不采窗口标题：Pro、用户单独同意、功能接通，三样都要。阶段 A 没接通，恒为假。
    public static func collectsWindowTitles(_ settings: TimeInsightsSettings, unlocked: Bool) -> Bool {
        unlocked && settings.windowTitlesOptIn && TimeInsightsProFeature.windowTitles.isConnected
    }

    /// 现在采不采网站域名：同上，阶段 A 恒为假。
    public static func collectsWebsites(_ settings: TimeInsightsSettings, unlocked: Bool) -> Bool {
        unlocked && settings.websitesOptIn && TimeInsightsProFeature.websites.isConnected
    }

    /// 免费层能看几个 App。
    public static func topLimit(unlocked: Bool) -> Int {
        unlocked ? Int.max : TimeInsightsDay.freeTopCount
    }

    /// 暂停、排除、清空、基础导出：任何时候都能用，不看 Pro。降级后也能查看、导出、删除自己的数据。
    public static func canControlPrivacy(unlocked: Bool) -> Bool { true }
}

// MARK: - 浏览器和窗口标题接口（阶段 B 待接通）

/// 浏览器扩展传来的一条当前标签页。只带域名，标题要另外同意。
public struct BrowserTabSample: Equatable, Sendable {
    public var browserBundleID: String
    public var domain: String
    public var title: String?
    public var isPrivate: Bool

    public init(browserBundleID: String, domain: String, title: String? = nil, isPrivate: Bool = false) {
        self.browserBundleID = browserBundleID
        self.domain = domain
        self.title = title
        self.isPrivate = isPrivate
    }
}

/// 浏览器通讯的连接状态。
public enum BrowserBridgeState: Equatable, Sendable {
    /// 还没有接通任何浏览器扩展（阶段 A 永远是这个）。
    case notConnected
    case connected
    /// 扩展曾经连过，现在没有心跳。
    case offline
}

/// 浏览器扩展通讯协议。阶段 A 只有协议和没接通的实现，阶段 B 写 Safari / Chrome 等适配。
public protocol TimeInsightsBrowserBridge: Sendable {
    var state: BrowserBridgeState { get }
    /// `bundleID` 这个浏览器现在前台的标签页；没接通、没有或是私密窗口时 nil。
    func currentTab(for bundleID: String) -> BrowserTabSample?
}

/// 没接通的浏览器通讯：什么都不给。
public struct UnconnectedBrowserBridge: TimeInsightsBrowserBridge {
    public init() {}
    public var state: BrowserBridgeState { .notConnected }
    public func currentTab(for bundleID: String) -> BrowserTabSample? { nil }
}

/// 窗口标题来源。阶段 A 只有没接通的实现，不读任何窗口内容。
public protocol TimeInsightsWindowTitleSource: Sendable {
    var isConnected: Bool { get }
    func title(forProcess pid: Int32) -> String?
}

public struct UnconnectedWindowTitleSource: TimeInsightsWindowTitleSource {
    public init() {}
    public var isConnected: Bool { false }
    public func title(forProcess pid: Int32) -> String? { nil }
}

public enum TimeInsightsDomain {
    /// 从网址里只取域名：小写，去掉开头的 www.，路径、查询串、锚点、端口、用户名一律丢。
    /// 不是 http(s) 的（file:、about:、chrome:）不记，返回 nil。
    public static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
