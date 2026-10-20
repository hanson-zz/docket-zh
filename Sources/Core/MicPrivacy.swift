import Foundation

/// 麦克风与摄像头面板（隐私指示）的纯逻辑，放在 Core 方便测试。
///
/// - 谁在用：每秒拿到一份「现在在用的」清单（App 用麦克风、摄像头开着），
///   `MicUsageLog.update` 跟上次比，开始的记一条，停了的写上结束时间。摄像头
///   系统不说是哪个 App 在用，只记「摄像头开着」，不猜 App。
/// - 今天谁用过：记录只存在本机（Application Support），按天汇总成每个 App 一行。
///   免费只看今天；码头 Pro 可以往前翻 30 天（`MicUsageLog.keptDays`）。记录
///   本身总是留 30 天，没解锁只是不显示今天以前的，解锁或试用时自动回来。
/// - 全局静音：输入音量拉到 0，记下原来的音量，解除时恢复（`MicMute`）。
/// - 提醒：有 App 开始用麦克风、摄像头亮起时发通知（`MicAlertTracker`）。
public enum MicSource: String, Codable, Hashable, Sendable {
    case microphone
    case camera
}

/// 现在正在用的一项：哪个 App 在用麦克风，或者摄像头开着。
public struct MicActiveUse: Hashable, Sendable {
    /// 稳定的标识：App 的 bundle id，没有时用进程名；摄像头固定是 `MicActiveUse.cameraID`。
    public var app: String
    /// 显示的名字。
    public var name: String
    public var source: MicSource

    public init(app: String, name: String, source: MicSource) {
        self.app = app
        self.name = name
        self.source = source
    }

    public static let cameraID = "camera"

    /// 摄像头开着（不说是哪个 App）。
    public static var camera: MicActiveUse {
        MicActiveUse(app: cameraID, name: tr("摄像头"), source: .camera)
    }

    var key: String { "\(source.rawValue)|\(app)" }
}

/// 一段使用：从开始到结束；结束是 nil 表示还在用。
public struct MicUsageSession: Codable, Hashable, Sendable {
    public var app: String
    public var name: String
    public var source: MicSource
    public var start: Date
    public var end: Date?

    public init(app: String, name: String, source: MicSource, start: Date, end: Date? = nil) {
        self.app = app
        self.name = name
        self.source = source
        self.start = start
        self.end = end
    }

    var key: String { "\(source.rawValue)|\(app)" }

    /// 和 [from, to) 重叠了多少秒；还在用的算到 `now`。
    func overlap(from: Date, to: Date, now: Date) -> TimeInterval {
        let stop = min(end ?? now, to)
        let begin = max(start, from)
        return max(0, stop.timeIntervalSince(begin))
    }
}

/// 面板「今天谁用过」里的一行：某天某个 App 一共用了多久。
public struct MicUsageRow: Hashable, Sendable, Identifiable {
    public var app: String
    public var name: String
    public var source: MicSource
    /// 那天最近一次开始用的时刻。
    public var lastStart: Date
    /// 那天一共用了多少秒。
    public var total: TimeInterval
    /// 现在还在用。
    public var active: Bool

    public var id: String { "\(source.rawValue)|\(app)" }
}

/// 只存在本机的使用记录。
public struct MicUsageLog: Codable, Equatable, Sendable {
    public var sessions: [MicUsageSession]
    /// 最后一次存盘的时刻：上次退出（或崩溃）时还开着的那几段按它收尾。
    public var savedAt: Date?

    /// 记录留 30 天（含今天）。
    public static let keptDays = 30
    /// 记录条数上限，超过时丢最老的。一个 App 一天反复开关几百次也不会撑爆文件。
    public static let maxSessions = 4000
    /// 同一个 App 停下后这么多秒内又开始，接着算上一段，不另起一行，也不再提醒。
    public static let rejoinGap: TimeInterval = 5

    public init(sessions: [MicUsageSession] = [], savedAt: Date? = nil) {
        self.sessions = sessions
        self.savedAt = savedAt
    }

    /// 还开着的段。
    public var open: [MicUsageSession] { sessions.filter { $0.end == nil } }

    /// 读回来时把上次没收尾的段收尾：结束时间取上次存盘的时刻（不早于开始）。
    public mutating func closeDangling() {
        for index in sessions.indices where sessions[index].end == nil {
            let start = sessions[index].start
            sessions[index].end = max(start, savedAt ?? start)
        }
    }

    /// 跟上一次比：新开始的记一条（返回它们，提醒用），停了的写上结束时间。
    ///
    /// 同一个 App 停下不到 `rejoinGap` 秒又开始，算接着上一段，不返回。
    @discardableResult
    public mutating func update(active: [MicActiveUse], now: Date) -> [MicActiveUse] {
        var seen = Set<String>()
        let wanted = active.filter { seen.insert($0.key).inserted }
        let wantedKeys = Set(wanted.map(\.key))

        // 停了的收尾。
        for index in sessions.indices where sessions[index].end == nil && !wantedKeys.contains(sessions[index].key) {
            sessions[index].end = max(sessions[index].start, now)
        }

        var started: [MicActiveUse] = []
        let openKeys = Set(open.map(\.key))
        for use in wanted where !openKeys.contains(use.key) {
            // 刚停没多久的接回去。
            if let index = sessions.lastIndex(where: { $0.key == use.key }),
               let end = sessions[index].end, now.timeIntervalSince(end) <= Self.rejoinGap,
               now >= end {
                sessions[index].end = nil
                sessions[index].name = use.name
                continue
            }
            sessions.append(MicUsageSession(app: use.app, name: use.name, source: use.source, start: now))
            started.append(use)
        }
        return started
    }

    /// 丢掉 30 天以前的和超出上限的。
    public mutating func prune(now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: today) ?? today
        sessions.removeAll { ($0.end ?? now) < cutoff }
        if sessions.count > Self.maxSessions {
            // 还开着的不丢。
            let overflow = sessions.count - Self.maxSessions
            var dropped = 0
            sessions.removeAll { session in
                guard dropped < overflow, session.end != nil else { return false }
                dropped += 1
                return true
            }
        }
    }

    /// 某一天的汇总：每个 App 一行，用得久的在前；摄像头单独一行。
    public func rows(on day: Date, now: Date, calendar: Calendar = .current) -> [MicUsageRow] {
        let from = calendar.startOfDay(for: day)
        guard let to = calendar.date(byAdding: .day, value: 1, to: from) else { return [] }
        var rows: [String: MicUsageRow] = [:]
        var order: [String] = []
        for session in sessions {
            let seconds = session.overlap(from: from, to: to, now: now)
            let active = session.end == nil && from <= now && now < to
            guard seconds > 0 || active else { continue }
            let start = max(session.start, from)
            if var row = rows[session.key] {
                row.total += seconds
                if start > row.lastStart { row.lastStart = start; row.name = session.name }
                row.active = row.active || active
                rows[session.key] = row
            } else {
                rows[session.key] = MicUsageRow(app: session.app, name: session.name, source: session.source,
                                                lastStart: start, total: seconds, active: active)
                order.append(session.key)
            }
        }
        return order.compactMap { rows[$0] }.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.lastStart > $1.lastStart
        }
    }

    /// 能看的那几天，新的在前，今天总在第一个。免费只有今天；Pro 是 30 天里有记录的日子。
    public func days(now: Date, unlocked: Bool, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard unlocked else { return [today] }
        let cutoff = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: today) ?? today
        var days = Set<Date>([today])
        for session in sessions {
            var day = calendar.startOfDay(for: max(session.start, cutoff))
            let last = calendar.startOfDay(for: session.end ?? now)
            // 跨过半夜的段两天都算；最多走 30 步。
            var steps = 0
            while day <= last, steps <= Self.keptDays {
                if day >= cutoff, day <= today { days.insert(day) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                steps += 1
            }
        }
        return days.sorted(by: >)
    }

    /// 还开着的某一项从什么时候开始用的，面板写已用时长。
    public func startOfOpen(app: String, source: MicSource) -> Date? {
        sessions.last { $0.app == app && $0.source == source && $0.end == nil }?.start
    }
}

// MARK: - 全局静音

/// 全局静音 = 把输入音量拉到 0，记下原来的音量；解除时恢复原值。
///
/// 音量是 0 到 1。快速开关里的「麦克风静音」也走这一份，两边看到的一样。
public enum MicMute {
    /// 记下的音量没有或是 0 时恢复到一半，免得「解除静音」以后还是听不到。
    public static let fallbackVolume = 0.5
    /// 低于这个就算 0。
    public static let silent = 0.005

    /// 要静音时记下哪个音量：现在不是 0 就记现在的，是 0 就留着上次记的。
    public static func remembered(current: Double?, previous: Double?) -> Double {
        if let current, current > silent { return min(1, current) }
        if let previous, previous > silent { return min(1, previous) }
        return fallbackVolume
    }

    /// 解除静音时恢复到多少。
    public static func restored(_ saved: Double?) -> Double {
        guard let saved, saved > silent else { return fallbackVolume }
        return min(1, saved)
    }

    /// 记着「已静音」时，现在还算不算静音：有人把音量调上去了就不算了。
    /// 读不到音量（设备没有音量可调）时照记着的算。
    public static func stillMuted(flag: Bool, volume: Double?) -> Bool {
        guard flag else { return false }
        guard let volume else { return true }
        return volume <= silent
    }
}

// MARK: - 提醒

/// 要发的一条提醒。
public struct MicAlert: Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

/// 有 App 开始用麦克风、摄像头亮起时提醒，同一项一分钟内只提醒一次。
///
/// 码头刚启动的第一轮不提醒：那时已经在开会的不算「开始用」。
public struct MicAlertTracker: Sendable {
    public static let quietInterval: TimeInterval = 60

    private var primed = false
    private var lastAlert: [String: Date] = [:]

    public init() {}

    public mutating func alerts(started: [MicActiveUse], notifyMic: Bool, notifyCamera: Bool,
                                now: Date) -> [MicAlert] {
        defer { primed = true }
        guard primed else { return [] }
        var result: [MicAlert] = []
        for use in started {
            switch use.source {
            case .microphone where !notifyMic: continue
            case .camera where !notifyCamera: continue
            default: break
            }
            if let last = lastAlert[use.key], now.timeIntervalSince(last) < Self.quietInterval { continue }
            lastAlert[use.key] = now
            switch use.source {
            case .microphone:
                result.append(MicAlert(id: "docket.mic.\(use.app)",
                                       title: tr("\(use.name) 开始用麦克风"),
                                       body: tr("在码头的麦克风面板里可以一键静音。")))
            case .camera:
                result.append(MicAlert(id: "docket.mic.camera",
                                       title: tr("摄像头亮起了"),
                                       body: tr("有 App 打开了摄像头。")))
            }
        }
        return result
    }
}

// MARK: - 电平

public enum MicLevel {
    /// 电平表一共几格，前几格是绿的。
    public static let segments = 24
    public static let greenSegments = 10
    /// 显示范围：-60 dB 到 0 dB。
    public static let floor: Double = -60

    /// 分贝换成 0 到 1。
    public static func normalized(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels - floor) / -floor))
    }

    /// 亮几格。
    public static func lit(_ level: Double, segments: Int = segments) -> Int {
        guard level.isFinite, segments > 0 else { return 0 }
        return Int((min(1, max(0, level)) * Double(segments)).rounded())
    }
}

// MARK: - 设置

/// 麦克风卡片存在配置里的几项。
public struct MicPrivacySettings: Equatable, Sendable {
    public static let notifyMicKey = "notifyMic"
    public static let notifyCameraKey = "notifyCamera"
    public static let redWhenMutedKey = "redWhenMuted"
    public static let muteKeyKey = "muteKey"

    /// 默认快捷键 ⌥⌘M（M 的键码是 46）。
    public static let defaultMuteKey = KeyCombo(keyCode: 46,
                                                modifiers: KeyCombo.Modifier.option | KeyCombo.Modifier.command)
    public static var defaultMuteKeyText: String { encode(defaultMuteKey) }

    public var notifyMic: Bool
    public var notifyCamera: Bool
    public var redWhenMuted: Bool
    public var muteKey: KeyCombo?

    public init(config: WidgetConfig) {
        notifyMic = config.bool(Self.notifyMicKey, default: true)
        notifyCamera = config.bool(Self.notifyCameraKey, default: true)
        redWhenMuted = config.bool(Self.redWhenMutedKey, default: true)
        muteKey = Self.decode(config.string(Self.muteKeyKey, default: Self.defaultMuteKeyText))
    }

    /// 「键码:修饰键」，没有快捷键时是空字符串。
    public static func encode(_ combo: KeyCombo?) -> String {
        guard let combo else { return "" }
        return "\(combo.keyCode):\(combo.modifiers)"
    }

    /// 读不懂的、不带 ⌃⌥⌘ 的都当没有。
    public static func decode(_ text: String) -> KeyCombo? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let code = UInt32(parts[0]), let modifiers = UInt32(parts[1]),
              code < 512 else { return nil }
        let combo = KeyCombo(keyCode: code, modifiers: modifiers)
        return combo.hasRequiredModifier ? combo : nil
    }
}

// MARK: - 文案

public enum MicPrivacyText {
    /// 面板头上那一行。
    public static func subtitle(micApps: Int, camera: Bool, muted: Bool) -> String {
        if muted { return tr("静音中") }
        switch (micApps, camera) {
        case (0, false): return tr("现在没有 App 在用")
        case (0, true): return tr("摄像头开着")
        case (let n, false): return tr("\(n) 个 App 正在用")
        case (let n, true): return tr("\(n) 个 App 正在用 · 摄像头开着")
        }
    }

    /// 已用时长，像秒表：「03:10」，满一小时「1:02:03」。
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 「09:30」，24 小时制。
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 一天一共用了多久：「不到 1 分钟」「48 分钟」「1 小时 5 分钟」。
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds.isFinite ? seconds : 0) / 60))
        if minutes < 1 { return tr("不到 1 分钟") }
        if minutes < 60 { return tr("\(minutes) 分钟") }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? tr("\(h) 小时") : tr("\(h) 小时 \(m) 分钟")
    }

    /// 静音时提示「谁在用麦克风，听不到你」：一个就写名字，多个写「等 N 个 App」。
    public static func mutedNote(names: [String]) -> String? {
        guard let first = names.first else { return nil }
        if names.count == 1 { return tr("\(first) 在用麦克风，听不到你") }
        return tr("\(first) 等 \(names.count) 个 App 在用麦克风，听不到你")
    }

    /// 没有图标时的首字。
    public static func initial(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    /// 首字方块的颜色，按名字固定从几种里挑。
    public static let initialColors = ["#3E8ED0", "#E0A23A", "#2FAE7A", "#9B6BDF", "#D9534F", "#3BB3B3"]

    public static func initialColor(_ name: String) -> String {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return initialColors[sum % initialColors.count]
    }

    /// 记录里某天的标题：今天、昨天，其余「10月18日 周日」。
    public static func dayTitle(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return tr("今天") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return tr("昨天") }
        let month = calendar.component(.month, from: day)
        let date = calendar.component(.day, from: day)
        let weekdays = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
        let weekday = weekdays[(calendar.component(.weekday, from: day) - 1 + 7) % 7]
        return tr("\(month)月\(date)日 \(weekday)")
    }
}
