import Foundation

// 专注时把收音机当背景音乐：选台的编码、该不该播、淡入淡出的曲线、按台记住的音量。
// 全是纯逻辑，播放器（`RadioPlayer`、`AmbientPlayer`）和专注驱动（`FocusAmbientDriver`）照着做。

/// 淡入淡出：音量系数从当前值走到目标值。
///
/// 时长按走的距离折算：从 0 到 1 是整段（淡入 1.5 秒、淡出 0.8 秒），淡出到一半
/// 又点播放，就从那一半往回升，只用剩下那段的时间，不会先跳回 0 或卡在 0。
/// 曲线是平滑阶梯（两头慢、中间快），起止都没有突变。
public struct AudioFade: Equatable, Sendable {
    public static let fadeIn: Double = 1.5
    public static let fadeOut: Double = 0.8
    /// 驱动淡入淡出的计时器间隔，约 30 帧每秒，耳朵听不出台阶。
    public static let tick: Double = 1.0 / 30

    public var from: Double
    public var to: Double
    public var start: Date
    public var duration: Double

    /// 从 `current` 走到 `target`，`full` 是走满 0 到 1 要的时间。
    public init(from current: Double, to target: Double, start: Date, full: Double) {
        let a = Self.clamp(current), b = Self.clamp(target)
        from = a
        to = b
        self.start = start
        duration = max(0, full) * abs(b - a)
    }

    /// 这一刻的系数。
    public func value(at now: Date) -> Double {
        let p = progress(at: now)
        return from + (to - from) * Self.curve(p)
    }

    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return Self.clamp(now.timeIntervalSince(start) / duration)
    }

    public func isDone(at now: Date) -> Bool { progress(at: now) >= 1 }

    /// 平滑阶梯 3p² - 2p³：0 到 1，两头切线为 0。
    public static func curve(_ p: Double) -> Double {
        let t = clamp(p)
        return t * t * (3 - 2 * t)
    }

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// 每个台记住用户调过的音量（0...100），按台 id 存。切台时套用，没记过就用面板上的音量。
///
/// 直播流做真正的响度分析代价太大，这里只是记住：哪个台偏响，调小一次，下次切到它还是那么大。
public enum RadioVolumeMemory {
    public static let key = "docket.radio.stationVolumes"
    /// 最多记这么多台，超出时丢掉最早记的（字典没有次序，按 id 排序丢，够用）。
    public static let limit = 200

    public static func volume(for id: String, in memory: [String: Int], fallback: Double) -> Double {
        guard let saved = memory[id] else { return min(max(fallback, 0), 100) }
        return Double(clamp(saved))
    }

    public static func remembering(_ volume: Double, for id: String, in memory: [String: Int]) -> [String: Int] {
        let clean = id.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, volume.isFinite else { return memory }
        var next = memory
        next[clean] = clamp(Int(volume.rounded()))
        if next.count > limit {
            for drop in next.keys.filter({ $0 != clean }).sorted().prefix(next.count - limit) {
                next[drop] = nil
            }
        }
        return next
    }

    /// UserDefaults 里读出来的字典，值不是整数的丢掉。
    public static func decode(_ raw: [String: Any]?) -> [String: Int] {
        var result: [String: Int] = [:]
        for (id, value) in raw ?? [:] {
            if let n = value as? Int { result[id] = clamp(n) }
            else if let d = value as? Double, d.isFinite { result[id] = clamp(Int(d.rounded())) }
        }
        return result
    }

    static func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }
}

/// 专注计时「环境音」一行的选择：原有的环境音，或收音机收藏里的一个台。
///
/// 存在 `TimerState.ambient` 里：环境音是 `AmbientSound` 的 rawValue（和原来一样），
/// 电台是 `radio:` 加电台的编码（`RadioStation.encoded`），收藏改了名或删了也还知道放哪个。
public enum FocusRadio {
    public static let prefix = "radio:"

    public enum Choice: Equatable, Sendable {
        case none
        case ambient(AmbientSound)
        case radio(RadioStation)
    }

    public static func raw(for station: RadioStation) -> String {
        prefix + station.encoded
    }

    public static func choice(_ raw: String) -> Choice {
        if raw.hasPrefix(prefix) {
            let body = String(raw.dropFirst(prefix.count))
            guard let station = RadioStation(decoding: body, fallbackID: "focus") else { return .none }
            return .radio(station)
        }
        if let sound = AmbientSound(rawValue: raw) { return .ambient(sound) }
        return .none
    }

    /// 选的电台；收藏里还有同一个 id（或同一条地址）的台时用收藏里那份，
    /// 备用地址、改过的名字都跟着收藏走。
    public static func station(_ raw: String, favourites: [RadioStation] = []) -> RadioStation? {
        guard case .radio(let stored) = choice(raw) else { return nil }
        return favourites.first { $0.id == stored.id } ?? favourites.first { $0.matches(stored) } ?? stored
    }

    /// 现在应该放哪个台，nil 是不放：规则和环境音一样（`FocusAmbient.wanted`），
    /// 专注在走才放，休息时开着「休息时声音停下」就不放，暂停、重置都不放。
    public static func wanted(_ state: TimerState, now: Date, favourites: [RadioStation] = []) -> RadioStation? {
        guard let station = station(state.ambient, favourites: favourites),
              FocusCycle.isRunning(state, now: now) else { return nil }
        if state.phase != .focus, state.quietOnBreak { return nil }
        return station
    }

    /// 所有收音机小组件的收藏合在一起，按小组件和收藏的顺序，同一个台只留第一次出现的。
    public static func favourites(_ configs: [WidgetConfig]) -> [RadioStation] {
        var result: [RadioStation] = []
        var ids = Set<String>()
        for config in configs {
            for station in RadioDial.stations(config) {
                guard !ids.contains(station.id), !result.contains(where: { $0.matches(station) }) else { continue }
                ids.insert(station.id)
                result.append(station)
            }
        }
        return result
    }

    /// 选的是不是这个台（面板上高亮用）。
    public static func isChosen(_ station: RadioStation, raw: String) -> Bool {
        guard case .radio(let stored) = choice(raw) else { return false }
        return stored.id == station.id || stored.matches(station)
    }

    /// 面板上的「换」：选的是电台时轮到下一个收藏的台，最后一个台之后回到第一种环境音；
    /// 选的是环境音或没选时照旧（`FocusAmbient.next`）。
    public static func next(after raw: String, favourites: [RadioStation]) -> String {
        if case .radio(let stored) = choice(raw),
           let index = favourites.firstIndex(where: { $0.id == stored.id || $0.matches(stored) }),
           index + 1 < favourites.count {
            return Self.raw(for: favourites[index + 1])
        }
        return FocusAmbient.next(after: raw).rawValue
    }
}

/// 专注驱动该不该播、该不该停：环境音和电台各一份，规则一样。
///
/// 只管自己放起来的声音：播放器正在放用户自己点的东西时不去抢；专注中用户手动停了
/// 或换了别的，这一轮让给用户，不再放回来，停的时候也不碰；专注停下（暂停、重置、
/// 开着「休息时声音停下」进了休息）就停掉自己放的，下一轮重新来。
public struct FocusPlayback: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case start(String)
        case switchTo(String)
        case stop
    }

    /// 我们放起来的那个（台 id 或环境音名）；nil 是现在没放，或这一轮让给了用户。
    public private(set) var started: String?
    /// 这一轮用户接管了，等专注停下再说。
    public private(set) var yielded = false

    public init() {}

    /// `wanted` 是现在该放的，nil 是不该放；`playing` 是播放器正在放的，nil 是没在放。
    public mutating func step(wanted: String?, playing: String?) -> Action {
        guard let wanted else {
            let action: Action = (started != nil && playing == started) ? .stop : .none
            started = nil
            yielded = false
            return action
        }
        if yielded { return .none }
        if let started {
            guard playing == started else {
                // 用户手动停了或换了别的：这一轮不再管。
                self.started = nil
                yielded = true
                return .none
            }
            guard started != wanted else { return .none }
            self.started = wanted
            return .switchTo(wanted)
        }
        // 播放器正在放用户自己的东西，不去抢。
        if playing != nil {
            yielded = true
            return .none
        }
        started = wanted
        return .start(wanted)
    }

    /// 放不起来（声音设备、地址不对）：这一轮不再每秒重试。
    public mutating func failed() {
        started = nil
        yielded = true
    }
}
