import Foundation

// MARK: - 消息灵动岛：程序坞角标增量和横幅属性线索
//
// macOS 27 的通知横幅辅助说明只有「发件人, 内容」两段，没有 App 名，原来的认法认不出是谁。
// 这里补两条线索：一是程序坞角标，微信、信息、WhatsApp 来消息时自己的角标会加一，横幅
// 出现前后几秒里只有一个 App 的角标涨了，就是它；二是横幅元素上的 AXAttributedDescription、
// AXDescription、AXIdentifier、AXHelp 里有没有 App 名或 bundle id。只有纯逻辑，读程序坞和
// 读横幅都在 Services 那边。诊断里只写长度、命中与否和角标数字，不写消息内容。

/// 程序坞上一个 App 的角标。
public enum NotchDockBadge: Equatable, Sendable {
    /// 程序坞上没有这个 App（没开着、也没留在程序坞）。
    case missing
    /// 在程序坞上，没有角标。
    case none
    /// 数字角标（「99+」记 99）。
    case count(Int)
    /// 不是数字的角标（小红点、「•」）。
    case mark

    /// 读到的 AXStatusLabel 原文：nil 或空白是没有角标，数字是个数，别的算有标记。
    public static func parse(_ raw: String?) -> NotchDockBadge {
        guard let raw else { return .none }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        if trimmed.range(of: #"^\d+\+?$"#, options: .regularExpression) != nil {
            let digits = trimmed.filter(\.isNumber)
            return .count(Int(digits.prefix(6)) ?? 0)
        }
        return .mark
    }

    /// 比大小用的数：没有角标 0，标记 1，不在程序坞上的不比。
    public var level: Int? {
        switch self {
        case .missing: nil
        case .none: 0
        case .count(let n): n
        case .mark: 1
        }
    }

    /// 诊断里的写法：n/a、-、数字、yes。
    public var text: String {
        switch self {
        case .missing: "n/a"
        case .none: "-"
        case .count(let n): "\(n)"
        case .mark: "yes"
        }
    }
}

/// 某一刻程序坞上三个 App 的角标。
public struct NotchDockSample: Equatable, Sendable {
    public var at: Date
    public var badges: [NotchMessageApp: NotchDockBadge]

    public init(at: Date, badges: [NotchMessageApp: NotchDockBadge]) {
        self.at = at
        self.badges = badges
    }

    public func badge(_ app: NotchMessageApp) -> NotchDockBadge { badges[app] ?? .missing }

    /// 诊断里的一行：messages:n/a,whatsapp:n/a,wechat:2。
    public var summary: String {
        NotchMessageApp.allCases.map { "\($0.rawValue):\(badge($0).text)" }.joined(separator: ",")
    }
}

/// 一条横幅前后角标的变化，和据此认出的 App。
public struct NotchDockAttribution: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// 只有一个 App 的角标涨了。
        case single
        /// 不止一个 App 涨了，分不清。
        case multiple
        /// 都没涨。
        case unchanged
        /// 横幅前后的角标记录不够（刚开始观察、程序坞读不到），没法比。
        case noData = "no-data"
    }

    /// 各 App 角标涨了多少（只记涨了的）。
    public var rises: [NotchMessageApp: Int]
    /// 比较的起点和终点（横幅前最后一次、窗口里最后一次）。
    public var before: NotchDockSample?
    public var after: NotchDockSample?

    public init(rises: [NotchMessageApp: Int], before: NotchDockSample?, after: NotchDockSample?) {
        self.rises = rises.filter { $0.value > 0 }
        self.before = before
        self.after = after
    }

    /// 涨了的 App，按 `NotchMessageApp.allCases` 的顺序。
    public var rising: [NotchMessageApp] { NotchMessageApp.allCases.filter { (rises[$0] ?? 0) > 0 } }

    public var kind: Kind {
        guard before != nil, after != nil, before?.at != after?.at else { return .noData }
        switch rising.count {
        case 0: return .unchanged
        case 1: return .single
        default: return .multiple
        }
    }

    /// 只有一个 App 涨了时是它。
    public var app: NotchMessageApp? { kind == .single ? rising.first : nil }

    /// 别的横幅已经认走的个数从涨幅里扣掉：同一段时间里先来一条微信（已经认出来）、
    /// 再来一条认不出的，两个 App 都涨了一，扣掉微信那一条以后只剩信息涨了。
    public func excluding(_ claims: [NotchMessageApp: Int]) -> NotchDockAttribution {
        var left = rises
        for (app, count) in claims {
            guard let rise = left[app] else { continue }
            left[app] = rise - count
        }
        return NotchDockAttribution(rises: left, before: before, after: after)
    }

    /// 诊断里 matched 的写法：dock-badge(+1 wechat)、dock-badge(ambiguous:messages+wechat)。
    public var source: String {
        switch kind {
        case .single:
            let app = rising[0]
            return "dock-badge(+\(rises[app] ?? 0) \(app.rawValue))"
        case .multiple:
            return "dock-badge(ambiguous:\(rising.map(\.rawValue).joined(separator: "+")))"
        case .unchanged:
            return "dock-badge(no change)"
        case .noData:
            return "dock-badge(no data)"
        }
    }

    /// 诊断里的角标前后：在程序坞上的几个 App 各写「前->后」，形如 wechat:1->2。
    public var badgeLine: String {
        guard let before, let after else { return "none" }
        let parts = NotchMessageApp.allCases.compactMap { app -> String? in
            let a = before.badge(app), b = after.badge(app)
            if a == .missing, b == .missing { return nil }
            return "\(app.rawValue):\(a.text)->\(b.text)"
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }
}

/// 最近一段时间程序坞角标的记录（每秒记一次，横幅出现时再立刻记、补记），按时间排。
public struct NotchDockBadgeHistory: Equatable, Sendable {
    /// 横幅出现前后多少秒内的角标变化算它的。
    public static let window: TimeInterval = 3
    /// 记录留多久。
    public static let keep: TimeInterval = 20

    public private(set) var samples: [NotchDockSample] = []

    public init(samples: [NotchDockSample] = []) {
        for sample in samples { append(sample) }
    }

    /// 记一次（按时间插到该在的位置），太旧的扔掉。
    public mutating func append(_ sample: NotchDockSample) {
        let index = samples.lastIndex { $0.at <= sample.at }.map { $0 + 1 } ?? 0
        samples.insert(sample, at: index)
        guard let latest = samples.last?.at else { return }
        samples.removeAll { latest.timeIntervalSince($0.at) > Self.keep }
    }

    /// 最新一次记录。
    public var latest: NotchDockSample? { samples.last }

    /// 刚记的这次和上一次比，有没有哪个 App 的角标涨了（每秒记一次时用：有认不出的横幅在等，
    /// 角标一涨就再读一遍横幅）。
    public var lastStepRose: Bool {
        guard samples.count >= 2 else { return false }
        let a = samples[samples.count - 2], b = samples[samples.count - 1]
        return NotchMessageApp.allCases.contains { Self.rise(from: a.badge($0), to: b.badge($0)) > 0 }
    }

    /// `at` 那一刻出现的横幅前后 `window` 秒里各 App 角标涨了多少。起点是窗口开始前最后一次
    /// 记录（没有时用窗口里第一次），然后挨个比相邻两次，只把涨的加起来（中间被读掉清零、
    /// 又来了新消息也能算上）。
    public func attribution(at time: Date, window: TimeInterval = NotchDockBadgeHistory.window) -> NotchDockAttribution {
        let lower = time.addingTimeInterval(-window)
        let upper = time.addingTimeInterval(window)
        let inside = samples.filter { $0.at >= lower && $0.at <= upper }
        var sequence: [NotchDockSample] = []
        if let baseline = samples.last(where: { $0.at < lower }) { sequence.append(baseline) }
        sequence.append(contentsOf: inside)
        guard sequence.count >= 2 else {
            return NotchDockAttribution(rises: [:], before: sequence.first, after: sequence.first)
        }
        var rises: [NotchMessageApp: Int] = [:]
        for (a, b) in zip(sequence, sequence.dropFirst()) {
            for app in NotchMessageApp.allCases {
                let step = Self.rise(from: a.badge(app), to: b.badge(app))
                if step > 0 { rises[app, default: 0] += step }
            }
        }
        return NotchDockAttribution(rises: rises, before: sequence.first, after: sequence.last)
    }

    /// 相邻两次之间涨了多少。不在程序坞上的不算（App 刚打开时冒出来的角标不是新消息）。
    static func rise(from a: NotchDockBadge, to b: NotchDockBadge) -> Int {
        guard let x = a.level, let y = b.level, y > x else { return 0 }
        return y - x
    }
}

// MARK: - 横幅属性里的线索

/// 横幅元素上一段可能带 App 名或 bundle id 的字，和它从哪个属性来。
public struct NotchBannerClue: Equatable, Sendable {
    /// attr-desc（AXAttributedDescription 的字）、attr-values（它的属性值）、desc、id、help。
    public var source: String
    public var text: String

    public init(source: String, text: String) {
        self.source = source
        self.text = text
    }
}

/// 一条线索认出的 App。
public struct NotchClueHit: Equatable, Sendable {
    public var app: NotchMessageApp
    /// 从哪个属性、怎么认的：attr-desc:bundle、help:name、attr-desc:segment[0]。
    public var source: String
}

extension NotchBannerParser {
    /// 横幅属性里的线索认出的 App：bundle id 完整出现、整段字正好是 App 名，或
    /// AXAttributedDescription 按分隔符拆开后有一段是 App 名（和标题、内容一样的段、内容里
    /// 拆出来的段不算）。AXDescription 就是辅助说明，原来的认法比过名字，这里只找 bundle id。
    public static func clueHit(_ banner: NotchBanner, names: NotchAppNames = .builtIn) -> NotchClueHit? {
        for clue in banner.clues {
            if let hit = clueHit(clue, in: banner, names: names) { return hit }
        }
        return nil
    }

    static func clueHit(_ clue: NotchBannerClue, in banner: NotchBanner, names: NotchAppNames) -> NotchClueHit? {
        if let app = NotchMessageApp.match(bundleIDIn: clue.text) {
            return NotchClueHit(app: app, source: "\(clue.source):bundle")
        }
        // 辅助说明原文原来的认法已经比过；和辅助说明一样的 AXAttributedDescription 也不再比名字。
        if clue.source == "desc" { return nil }
        if clue.source == "attr-desc", let summary = cleaned(banner.summary),
           NotchAppNames.normalized(summary) == NotchAppNames.normalized(clue.text) { return nil }
        // 整段正好是 App 名；和标题、副标题、内容一样的不算（对方发来的字正好是「微信」）。
        let texts = [banner.title, banner.subtitle, banner.body].compactMap { cleaned($0) }.map(NotchAppNames.normalized)
        if let app = names.match(clue.text), !texts.contains(NotchAppNames.normalized(clue.text)) {
            return NotchClueHit(app: app, source: "\(clue.source):name")
        }
        guard clue.source == "attr-desc" else { return nil }
        var probe = banner
        probe.summary = clue.text
        if let hit = summaryApp(probe, names: names) {
            return NotchClueHit(app: hit.app, source: "\(clue.source):segment[\(hit.index)]")
        }
        return nil
    }

    /// 诊断里的线索一行：每条线索只写长度和命中（clues=[attr-desc:len18:none,help:len12:wechat-name]），
    /// 不写原文；AXAttributedDescription 的属性键名另写（只是键名，不含内容）。
    public static func clueReport(_ banner: NotchBanner, names: NotchAppNames = .builtIn) -> String {
        var parts = banner.clues.map { clue -> String in
            let hit = clueHit(clue, in: banner, names: names)
            let how = hit.map { "\($0.app.rawValue)-\($0.source.split(separator: ":").last.map(String.init) ?? "")" }
            return "\(clue.source):len\(clue.text.count):\(how ?? "none")"
        }
        if !banner.clues.contains(where: { $0.source == "attr-desc" }) { parts.insert("attr-desc:absent", at: 0) }
        var line = "clues=[\(parts.joined(separator: ","))]"
        if !banner.attributedKeys.isEmpty {
            line += " attr-keys=[\(banner.attributedKeys.prefix(10).map { reportWord($0) }.joined(separator: ","))]"
        }
        return line
    }

    /// 认横幅属于哪个 App，带上新线索：先用原来的认法（顶上的 App 名、辅助说明、图标、
    /// bundle id、标题）；认不出时看属性线索；还认不出时看程序坞角标，只有一个 App 涨了才认。
    /// 属性线索和角标都有、又不一致时信属性线索：那是横幅自己写的，角标涨可能是别的 App
    /// 同时来了消息。几个 App 同时涨、属性线索指着其中一个时，也按线索认。
    public static func resolve(_ banner: NotchBanner, names: NotchAppNames = .builtIn,
                               dock: NotchDockAttribution? = nil) -> Recognition? {
        if let recognised = recognise(banner, names: names) { return recognised }
        if let clue = clueHit(banner, names: names) {
            var recognition = Recognition(app: clue.app, source: clue.source)
            recognition.inferred = true
            return recognition
        }
        if let dock, let app = dock.app {
            var recognition = Recognition(app: app, source: dock.source)
            recognition.inferred = true
            return recognition
        }
        return nil
    }

    /// 发件人和内容（靠角标、属性线索认出 App 时用）：辅助说明第一段是发件人，后面整个是内容；
    /// 开头是时间的跳过，末尾「已堆叠」去掉。标题正好是辅助说明的开头时用标题（名字里带逗号
    /// 也不会拆错）。内容优先用横幅上的 body。
    public static func senderAndPreview(_ banner: NotchBanner) -> (sender: String?, preview: String?) {
        let title = cleaned(banner.title)
        var sender: String?
        var rest: String?
        if let summary = cleaned(banner.summary) {
            var text = stripStackedSuffix(summary)
            if let range = text.range(of: summarySeparatorPattern, options: .regularExpression),
               isTimeLike(String(text[..<range.lowerBound])) {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if let title, text.hasPrefix(title),
               let end = text.index(text.startIndex, offsetBy: title.count, limitedBy: text.endIndex),
               let range = text.range(of: summarySeparatorPattern, options: [.regularExpression, .anchored],
                                      range: end..<text.endIndex) {
                sender = title
                rest = String(text[range.upperBound...])
            } else if let range = text.range(of: summarySeparatorPattern, options: .regularExpression) {
                sender = String(text[..<range.lowerBound])
                rest = String(text[range.upperBound...])
            }
        }
        sender = cleaned(sender) ?? title
        var preview = cleaned(banner.body) ?? cleaned(banner.subtitle) ?? cleaned(rest)
        if let body = preview, isPlaceholder(body) { preview = nil }
        if sender == nil { preview = nil }
        return (sender, preview.map { singleLine($0) })
    }

    /// 末尾「, stacked」「，已堆叠」去掉（`senderAndPreview` 用）。
    static func stripStackedSuffix(_ summary: String) -> String {
        let whole = segmentSpans(summary).text
        return whole.trimmingCharacters(in: .whitespaces)
    }
}
