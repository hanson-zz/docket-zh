import Foundation

// 「Codex 用量」的提示音：等你确认、一轮完成、额度快用完。
//
// 声音跟着系统通知走（通知内容带上选的 macOS 提示音），勿扰和专注模式由系统
// 自己挡，这里不另外判断。这里只放纯逻辑：哪些状态变化该出声、额度过线、
// 一次变化只响一次的防抖，以及卡片上小喇叭画不画。发通知在 CodexService。

/// 设置 ▸ 小组件 ▸ Codex 用量 ▸ 声音。
public struct CodexChimeSettings: Equatable, Sendable {
    public static let waitingKey = "soundWaiting"
    public static let doneKey = "soundDone"
    public static let quotaKey = "soundQuota"
    public static let toneKey = "tone"

    /// 等你确认：默认开。
    public var waiting: Bool
    /// 一轮完成：默认关。
    public var done: Bool
    /// 额度快用完（过 90%）：默认关。
    public var quota: Bool
    /// macOS 自带提示音的名字（/System/Library/Sounds）。
    public var tone: String

    public static let defaultTone = "Glass"
    /// 设置里可选的提示音，都是系统自带的，不另外打包声音文件。
    public static let tones = ["Glass", "Ping", "Tink", "Pop", "Hero", "Purr", "Submarine", "Funk", "Bottle", "Morse"]

    public init(waiting: Bool = true, done: Bool = false, quota: Bool = false, tone: String = CodexChimeSettings.defaultTone) {
        self.waiting = waiting
        self.done = done
        self.quota = quota
        self.tone = Self.tones.contains(tone) ? tone : Self.defaultTone
    }

    public init(config: WidgetConfig) {
        self.init(waiting: config.bool(Self.waitingKey, default: true),
                  done: config.bool(Self.doneKey, default: false),
                  quota: config.bool(Self.quotaKey, default: false),
                  tone: config.string(Self.toneKey, default: Self.defaultTone))
    }

    /// 有任何一项会出声。
    public var anyOn: Bool { waiting || done || quota }
}

public enum CodexChime {
    public enum Event: String, Sendable, Equatable {
        case waiting, done, quota
    }

    /// 额度快用完：用掉 90% 时响一下。
    public static let quotaLevel = 0.9

    /// 这一种事件出不出声。
    public static func sounds(_ event: Event, settings: CodexChimeSettings) -> Bool {
        switch event {
        case .waiting: settings.waiting
        case .done: settings.done
        case .quota: settings.quota
        }
    }

    /// 状态变化发不发通知、带不带声音。`banner` 是原来的「任务完成时通知」
    /// 「发送通知」开关：横幅开、声音关就发一条不出声的；横幅关、声音开也要发
    /// （系统通知才能带声音、才能被勿扰挡住）；两个都关不发。
    public static func delivery(_ event: Event, banner: Bool,
                                settings: CodexChimeSettings) -> (post: Bool, sound: Bool) {
        let sound = sounds(event, settings: settings)
        return (banner || sound, sound)
    }

    /// 两次扫描之间各个会话的状态变化里，哪些该提醒。
    ///
    /// `previous` 为 nil 是刚开始看（启动、刚放上卡片）：只记下状态，不响，免得
    /// 一启动就把十分钟前完成的那一轮再报一遍。一个会话新进入「等你确认」算一次；
    /// 从工作中或等你确认变成「已完成」算一次；停在同一个状态不再算。
    public static func events(previous: [String: CodexActivity]?,
                              current: [String: CodexActivity]) -> [(session: String, event: Event)] {
        guard let previous else { return [] }
        return current.keys.sorted().compactMap { id in
            let now = current[id] ?? .idle
            let before = previous[id] ?? .idle
            guard now != before else { return nil }
            switch now {
            case .waiting: return (id, .waiting)
            case .done where before == .working || before == .waiting: return (id, .done)
            default: return nil
            }
        }
    }

    /// 额度这一次刚升过 90%：上一次还在线下、这一次到了线上才算，停在 95% 不再
    /// 响，重置回落后再升上来会再响一次。没有上一次读数时不算。
    public static func quotaCrossed(previous: Double?, current: Double, level: Double = quotaLevel) -> Bool {
        guard let previous else { return false }
        return previous < level && current >= level
    }

    /// 额度提醒：横幅按原来的「首次提醒阈值」几档发，声音只在升过 90% 那一次带。
    /// 返回 nil 是这次不用提醒；hit 是通知标题里说的那一档。
    public static func quota(previous: Double?, current: Double, bannerOn: Bool, alertAt: Int,
                             soundOn: Bool) -> (hit: Double, sound: Bool)? {
        let bannerHit = bannerOn
            ? CodexAlert.crossed(previous: previous, current: current, thresholds: CodexAlert.thresholds(first: alertAt))
            : nil
        let sound = soundOn && quotaCrossed(previous: previous, current: current)
        if let bannerHit { return (bannerHit, sound) }
        guard sound else { return nil }
        return (current >= 1 ? 1 : quotaLevel, true)
    }

    /// 卡片和面板标题上的小喇叭。
    public enum Speaker: Equatable, Sendable {
        /// 这个状态会响。
        case on
        /// 这个状态有声音开关，但关着。
        case off
        /// 这个状态本来不出声（工作中、空闲）。
        case hidden
    }

    public static func speaker(for activity: CodexActivity, settings: CodexChimeSettings) -> Speaker {
        switch activity {
        case .waiting: settings.waiting ? .on : .off
        case .done: settings.done ? .on : .off
        case .working, .idle: .hidden
        }
    }

    /// 点面板标题上的小喇叭开关的是哪一项（工作中、空闲没有）。
    public static func toggleKey(for activity: CodexActivity) -> String? {
        switch activity {
        case .waiting: CodexChimeSettings.waitingKey
        case .done: CodexChimeSettings.doneKey
        case .working, .idle: nil
        }
    }
}

/// 防抖：同一个会话的同一种提醒在一段时间里只发一次（状态在等你确认和工作中
/// 之间来回跳也只响一声）；不同会话几乎同时触发时，只有第一条带声音。
public struct CodexChimeGate: Sendable {
    public let repeatWindow: TimeInterval
    public let soundWindow: TimeInterval
    private var lastByKey: [String: Date] = [:]
    private var lastSound: Date?

    public init(repeatWindow: TimeInterval = 30, soundWindow: TimeInterval = 3) {
        self.repeatWindow = repeatWindow
        self.soundWindow = soundWindow
    }

    /// 这一条要不要发。发了就记下时间。
    public mutating func allow(_ key: String, at now: Date) -> Bool {
        if let last = lastByKey[key], now >= last, now.timeIntervalSince(last) < repeatWindow {
            return false
        }
        lastByKey[key] = now
        // 只留最近的，免得一直长。
        if lastByKey.count > 64 {
            lastByKey = lastByKey.filter { now.timeIntervalSince($0.value) < repeatWindow }
        }
        return true
    }

    /// 这一条带不带声音（短时间里已经响过就不再响）。
    public mutating func allowSound(at now: Date) -> Bool {
        if let lastSound, now >= lastSound, now.timeIntervalSince(lastSound) < soundWindow {
            return false
        }
        lastSound = now
        return true
    }
}
