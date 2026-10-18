import Foundation

// 到点提醒的提示音：提醒事项、喝水、待办到点时轻轻响一声。
//
// 这里只放纯逻辑（选哪个音色、该不该响、短时间里几条合成一声、哪些提醒刚刚
// 到点），播放在 Services/ReminderSoundPlayer.swift，方便单独测试。

// MARK: - 三类提醒

public enum ReminderSoundKind: String, Codable, CaseIterable, Sendable {
    case reminders, water, todo

    public var title: String {
        switch self {
        case .reminders: tr("提醒事项")
        case .water: tr("喝水")
        case .todo: tr("待办")
        }
    }

    /// 本应用排的系统通知用哪一类的音色，按通知标识的前缀认。不是这三类的
    /// （股票到价、电量、姿势等）为 nil，照旧用系统默认提示音。
    public init?(notificationIdentifier id: String) {
        if id.hasPrefix("docket.water.") { self = .water; return }
        if id.hasPrefix("docket.reminder.") { self = .reminders; return }
        if id.hasPrefix("docket.todo.") { self = .todo; return }
        return nil
    }
}

// MARK: - 音色

/// 可选的音色，全是 macOS 自带的提示音（/System/Library/Sounds），不另外打包
/// 任何声音文件。`off`（菜单里叫“不响”）是这一类不响。
public enum ReminderTone: String, Codable, CaseIterable, Sendable {
    case off
    case glass, tink, pop, purr, ping, bottle, submarine, morse, hero, funk

    /// `NSSound(named:)` 用的名字，`off` 没有。
    public var soundName: String? {
        switch self {
        case .off: nil
        case .glass: "Glass"
        case .tink: "Tink"
        case .pop: "Pop"
        case .purr: "Purr"
        case .ping: "Ping"
        case .bottle: "Bottle"
        case .submarine: "Submarine"
        case .morse: "Morse"
        case .hero: "Hero"
        case .funk: "Funk"
        }
    }

    /// 菜单里显示的名字：系统提示音保留系统自己的英文名，和“声音”设置里一致。
    public var title: String {
        soundName ?? tr("不响")
    }

    /// 某个音色这台 Mac 上找不到时依次换用的，最后是 Tink。
    public var fallbacks: [String] {
        guard let soundName else { return [] }
        return [soundName, "Tink", "Pop"].reduce(into: [String]()) { list, name in
            if !list.contains(name) { list.append(name) }
        }
    }
}

// MARK: - 设置

/// 设置 ▸ 扩展栏 ▸ 音效 ▸ 提醒音效。音量和总开关跟着上面的统一音效设置走。
public struct ReminderSoundSettings: Codable, Hashable, Sendable {
    /// 提醒音效总开关，默认开。
    public var enabled: Bool = true
    public var reminders: ReminderTone = ReminderSoundSettings.defaultTone(.reminders)
    public var water: ReminderTone = ReminderSoundSettings.defaultTone(.water)
    public var todo: ReminderTone = ReminderSoundSettings.defaultTone(.todo)

    /// 默认分配：提醒事项 Glass（清亮、最像“到点了”），喝水 Pop（像一滴水），
    /// 待办 Tink（最轻的一下）。Purr 已经给了久坐提醒，这里不重复用。
    public static func defaultTone(_ kind: ReminderSoundKind) -> ReminderTone {
        switch kind {
        case .reminders: .glass
        case .water: .pop
        case .todo: .tink
        }
    }

    public init() {}

    public func tone(for kind: ReminderSoundKind) -> ReminderTone {
        switch kind {
        case .reminders: reminders
        case .water: water
        case .todo: todo
        }
    }

    public mutating func setTone(_ tone: ReminderTone, for kind: ReminderSoundKind) {
        switch kind {
        case .reminders: reminders = tone
        case .water: water = tone
        case .todo: todo = tone
        }
    }

    /// 宽松解码：旧的状态文件没有这一项，或者以后的版本加了这里不认识的音色，
    /// 都退回默认，而不是让整份设置读不出来。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        func tone(_ key: CodingKeys, _ kind: ReminderSoundKind) -> ReminderTone {
            let raw = try? c.decodeIfPresent(String.self, forKey: key)
            return raw.flatMap(ReminderTone.init(rawValue:)) ?? ReminderSoundSettings.defaultTone(kind)
        }
        reminders = tone(.reminders, .reminders)
        water = tone(.water, .water)
        todo = tone(.todo, .todo)
    }
}

// MARK: - 该不该响

/// 响之前要看的外部情况。nil 是这台 Mac 上判断不了，按“没有”处理。
public struct ReminderSoundEnvironment: Equatable, Sendable {
    /// 勿扰或任意专注模式开着。
    public var focusActive: Bool?
    /// 屏幕正被共享（屏幕共享、远程桌面）。
    public var screenShared: Bool?

    public init(focusActive: Bool? = nil, screenShared: Bool? = nil) {
        self.focusActive = focusActive
        self.screenShared = screenShared
    }
}

public enum ReminderSoundDecision {
    /// 设置允许这一类响的话是哪个音色：统一音效开关、统一音量大于 0、提醒音效
    /// 总开关、这一类没选“不响”，四个都满足才有。不看勿扰和屏幕共享。
    public static func tone(for kind: ReminderSoundKind, settings: ReminderSoundSettings,
                            master: WidgetSoundSettings) -> ReminderTone? {
        guard master.enabled, master.gain > 0, settings.enabled else { return nil }
        let tone = settings.tone(for: kind)
        return tone == .off ? nil : tone
    }

    /// 应用自己播放时用的判断：在上面的基础上，勿扰/专注模式和屏幕共享时不响。
    /// “减少动态效果”不在这里：它只管动画，不管声音。
    public static func toneToPlay(for kind: ReminderSoundKind, settings: ReminderSoundSettings,
                                  master: WidgetSoundSettings,
                                  environment: ReminderSoundEnvironment) -> ReminderTone? {
        guard environment.focusActive != true, environment.screenShared != true else { return nil }
        return tone(for: kind, settings: settings, master: master)
    }

    /// 系统通知要不要带声音。勿扰和专注由系统自己挡，这里只看设置。
    public static func notificationHasSound(_ kind: ReminderSoundKind, settings: ReminderSoundSettings,
                                            master: WidgetSoundSettings) -> Bool {
        tone(for: kind, settings: settings, master: master) != nil
    }

    // MARK: 刚到点的提醒事项

    /// 两次检查之间隔得太久（合盖睡眠、卡住）就不补响，免得一醒来叮一声说的是
    /// 几小时前的事。
    public static let maxGap: TimeInterval = 90

    /// 在 (`after`, `now`] 这段时间里到点的那些（只算带具体时刻的；只有日期的
    /// 全天提醒没有“到点”那一刻，不响）。返回它们的 id，按到点先后。
    public static func newlyDue(_ items: [(id: String, due: ReminderDue)],
                                after: Date, upTo now: Date) -> [String] {
        let gap = now.timeIntervalSince(after)
        guard gap > 0, gap <= maxGap else { return [] }
        return items
            .filter { $0.due.hasTime && $0.due.date > after && $0.due.date <= now }
            .sorted { $0.due.date == $1.due.date ? $0.id < $1.id : $0.due.date < $1.due.date }
            .map(\.id)
    }

    // MARK: 勿扰和屏幕共享

    /// 读 `~/Library/DoNotDisturb/DB/Assertions.json`：里面有正在生效的专注
    /// 记录就是开着。系统没有公开接口，这个文件要“完全磁盘访问权限”才读得到，
    /// 读不到或者格式变了都是 nil（判断不了）。
    public static func focusActive(assertionsJSON data: Data?) -> Bool? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        var sawRecords = false
        for entry in entries {
            guard let records = entry["storeAssertionRecords"] else { continue }
            sawRecords = true
            if let list = records as? [Any], !list.isEmpty { return true }
        }
        // 文件在、结构对、没有任何记录：确实没开。
        return sawRecords || entries.isEmpty ? false : nil
    }

    /// 读 `CGSessionCopyCurrentDictionary()` 里的 `CGSSessionScreenIsShared`：
    /// 系统“屏幕共享”和远程管理正在看这台 Mac 时为真。会议软件的共享屏幕不会
    /// 写这里，所以那种情况判断不了。
    public static func screenShared(sessionValue value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.intValue != 0
        case let number as Int: return number != 0
        default: return nil
        }
    }
}

// MARK: - 合并

/// 短时间里连着到点的几条只响一声。
///
/// 不分是哪一类：提醒事项和喝水恰好同一分钟到点，也只响第一声。几个卡片
/// 同时看到同一条提醒到点也一样只响一次。
public struct ReminderSoundGate: Sendable {
    public let window: TimeInterval
    private var last: Date?

    public static let defaultWindow: TimeInterval = 4

    public init(window: TimeInterval = ReminderSoundGate.defaultWindow) {
        self.window = window
    }

    public mutating func allow(at now: Date) -> Bool {
        if let last, now >= last, now.timeIntervalSince(last) < window {
            return false
        }
        last = now
        return true
    }
}
