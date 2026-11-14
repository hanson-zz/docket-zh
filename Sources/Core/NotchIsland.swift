import CoreGraphics
import Foundation

// MARK: - 刘海小岛（码头 Pro）
//
// 从刘海两侧「长出」的黑色小岛，和刘海连成一体，显示码头自己正在进行的事：下载、
// 专注计时和倒计时卡片、快开始的会议、收音机、刚插上电源。没有刘海的屏幕在顶部居中
// 画一个同样形状的假刘海。
//
// 这里只有纯逻辑：设置、活动、优先级、三种形态（compact / split / expanded）、
// 什么时候不显示、几何和计时。窗口、动画和数据来源在 App 的 `NotchIslandController`。

/// 小岛能显示的五种活动，`allCases` 的顺序就是优先级（前面的先显示）：
/// 插电提示 > 下载 > 计时器 > 会议 > 收音机。
public enum NotchIslandKind: String, CaseIterable, Codable, Hashable, Sendable {
    case charging
    case download
    case timer
    case meeting
    case radio

    /// 越小越先显示。
    public var priority: Int { NotchIslandKind.allCases.firstIndex(of: self) ?? NotchIslandKind.allCases.count }

    /// 设置里勾选时的名字。
    public var title: String {
        switch self {
        case .charging: tr("充电")
        case .download: tr("下载")
        case .timer: tr("计时器")
        case .meeting: tr("会议")
        case .radio: tr("收音机")
        }
    }

    /// 设置里那一行的说明。
    public var detail: String {
        switch self {
        case .charging: tr("插上电源时显示闪电和电量，约 4 秒后收起。")
        case .download: tr("「下载」文件夹里有文件正在下载时显示进度，下好后打勾。")
        case .timer: tr("专注计时或倒计时卡片在跑或暂停时，在刘海下方显示剩余时间；同时有几个时显示最先结束的。")
        case .meeting: tr("「灵动提示」的会议倒计时打开时，会议快开始时在刘海旁显示还有几分钟，不再另起一个胶囊。")
        case .radio: tr("收音机正在播放时显示音波，悬停可暂停、换台、调音量。")
        }
    }

    /// 设置里显示的顺序（和效果图一致）：下载、计时器、会议、收音机、充电。
    public static let settingsOrder: [NotchIslandKind] = [.download, .timer, .meeting, .radio, .charging]

    /// 最早一版就有的四种。老状态文件没记 `known` 时按这四种算，后来加的（会议）默认勾上。
    public static let original: [NotchIslandKind] = [.charging, .download, .timer, .radio]
}

/// 设置 ▸ 消息灵动岛与刘海小岛 ▸「刘海小岛」：总开关默认关，每种活动默认都勾上。
public struct NotchIslandSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    /// 显示哪几种活动，按 `NotchIslandKind.allCases` 的顺序存。
    public var kinds: [NotchIslandKind] = NotchIslandKind.allCases

    public init() {}

    public func isOn(_ kind: NotchIslandKind) -> Bool { kinds.contains(kind) }

    public mutating func set(_ kind: NotchIslandKind, _ on: Bool) {
        var next = Set(kinds)
        if on { next.insert(kind) } else { next.remove(kind) }
        kinds = NotchIslandKind.allCases.filter { next.contains($0) }
    }

    private enum CodingKeys: String, CodingKey { case enabled, kinds, known }

    /// 宽松解码：老状态文件没有这一组、以后多了认不出的活动，都照常读。
    ///
    /// `known` 记存盘时认识哪几种：存盘时还没有的活动（这次新加的会议）当作默认勾上，
    /// 只有用户自己取消勾选的才是关着的。没有 `known` 的老文件按最早的四种算。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        if let raw = try? c.decodeIfPresent([String].self, forKey: .kinds) {
            let on = Set(raw.compactMap(NotchIslandKind.init(rawValue:)))
            let knownRaw = (try? c.decodeIfPresent([String].self, forKey: .known)) ?? nil
            let known = knownRaw.map { Set($0.compactMap(NotchIslandKind.init(rawValue:))) }
                ?? Set(NotchIslandKind.original)
            kinds = NotchIslandKind.allCases.filter { on.contains($0) || !known.contains($0) }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(kinds.map(\.rawValue), forKey: .kinds)
        try c.encode(NotchIslandKind.allCases.map(\.rawValue), forKey: .known)
    }
}

// MARK: - 活动

/// 计时器活动来自哪里：卡片上的「暂停 / 继续」「结束」按这个找回那一个计时器。
public enum NotchIslandTimerSource: Hashable, Sendable {
    /// 专注计时（`TimerState`）。
    case focus
    /// 扩展栏上某张倒计时卡片里的某个计时器（`CountdownList`，第一个的 id 是 `main`）。
    case countdown(widget: UUID, timer: String)
}

/// 一件正在进行的事。值只在内容真的变了时才变（计时器存结束时刻，不存每秒的剩余），
/// 窗口不会每秒重排。
public enum NotchIslandActivity: Equatable, Sendable {
    /// 刚插上电源：电量百分比。
    case charging(percent: Int)
    /// 下载：`fraction` 是 0...1，拿不到进度时 nil（只转圈）；`done` 是刚下好（打勾 2 秒）。
    case download(fraction: Double?, done: Bool)
    /// 计时器（专注计时或倒计时卡片）：在跑时有 `deadline`，暂停时有 `pausedLeft`；`total`
    /// 是这一段的总长（秒）。专注计时的 `focus` 为 false 是休息环节；倒计时的 `name` 是
    /// 卡片上起的名字（没起是空的）。
    case timer(deadline: Date?, pausedLeft: TimeInterval?, total: TimeInterval, focus: Bool,
               source: NotchIslandTimerSource = .focus, name: String = "")
    /// 快开始的会议（「灵动提示」的会议倒计时找到的那一个）：标题和开始时刻。
    case meeting(title: String, start: Date)
    /// 收音机：电台名和在不在播（刚在小岛上按了暂停时还留一会儿，方便继续）。
    case radio(station: String, playing: Bool)

    public var kind: NotchIslandKind {
        switch self {
        case .charging: .charging
        case .download: .download
        case .timer: .timer
        case .meeting: .meeting
        case .radio: .radio
        }
    }
}

/// 小岛的三种形态。
public enum NotchIslandForm: Equatable, Sendable {
    /// 一个活动：刘海左右两侧各一块。
    case compact(NotchIslandActivity)
    /// 两个活动：第一个照 compact，第二个是右边单独的小圆岛。
    case split(NotchIslandActivity, NotchIslandActivity)
    /// 指针悬停：向下展开成圆角卡片，`secondary` 在卡片底下一行。
    case expanded(NotchIslandActivity, secondary: NotchIslandActivity?)

    public var primary: NotchIslandActivity {
        switch self {
        case .compact(let primary), .split(let primary, _), .expanded(let primary, _): primary
        }
    }

    public var secondary: NotchIslandActivity? {
        switch self {
        case .compact: nil
        case .split(_, let secondary): secondary
        case .expanded(_, let secondary): secondary
        }
    }

    public var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }
}

/// 活动栈：按设置筛、按优先级排、同一种只留一个，再决定形态。
public enum NotchIslandStack {
    /// 最多同时显示几个活动（一个主的加一个小圆岛）。
    public static let maxShown = 2

    /// 设置里勾上的、按优先级排好的活动；同一种出现两次时留先来的那个，计时器例外：
    /// 专注计时和几张倒计时卡片同时在跑时留最先结束的那个（`NotchIslandTimer.endsBefore`）。
    public static func ordered(_ activities: [NotchIslandActivity], settings: NotchIslandSettings) -> [NotchIslandActivity] {
        var slot: [NotchIslandKind: Int] = [:]
        var kept: [NotchIslandActivity] = []
        for activity in activities where settings.isOn(activity.kind) {
            if let index = slot[activity.kind] {
                if activity.kind == .timer, NotchIslandTimer.endsBefore(activity, kept[index]) {
                    kept[index] = activity
                }
                continue
            }
            slot[activity.kind] = kept.count
            kept.append(activity)
        }
        // 稳定排序：同优先级（不会有）保持原顺序。
        return kept.enumerated()
            .sorted { ($0.element.kind.priority, $0.offset) < ($1.element.kind.priority, $1.offset) }
            .map(\.element)
    }

    /// 现在画哪种形态；没有活动时 nil。悬停时展开第一个活动的卡片。
    public static func form(_ ordered: [NotchIslandActivity], hovering: Bool) -> NotchIslandForm? {
        guard let primary = ordered.first else { return nil }
        let secondary = ordered.count > 1 ? ordered[1] : nil
        if hovering { return .expanded(primary, secondary: secondary) }
        if let secondary { return .split(primary, secondary) }
        return .compact(primary)
    }

    /// 一步到位：筛、排、选形态。
    public static func form(_ activities: [NotchIslandActivity], settings: NotchIslandSettings,
                            hovering: Bool) -> NotchIslandForm? {
        form(ordered(activities, settings: settings), hovering: hovering)
    }
}

// MARK: - 什么时候不显示

public enum NotchIslandGate {
    /// 当下的环境。
    public struct Context: Equatable, Sendable {
        /// 设置里打开、至少勾了一种活动、Pro 已解锁（见 `ProLicenseGate.notchIslandActive`）。
        public var active: Bool
        /// 码头的演示模式（快速开关）开着。
        public var presenting: Bool
        /// 有全屏 App 或演示（`NotchFullscreen`）。
        public var fullscreen: Bool
        /// 消息灵动岛的卡片正展开着：小岛让位，卡片收起后回来。
        public var messageCard: Bool
        /// 插电霓虹动画正在播：它自己在刘海旁放电量胶囊，小岛先让开。
        public var plugAnimation: Bool
        /// 「灵动提示」的音量或亮度胶囊正闪着（刘海正下方）：小岛先收起，胶囊消失后回来，
        /// 两个不叠在一起。
        public var levelFlash: Bool

        public init(active: Bool, presenting: Bool = false, fullscreen: Bool = false,
                    messageCard: Bool = false, plugAnimation: Bool = false, levelFlash: Bool = false) {
            self.active = active
            self.presenting = presenting
            self.fullscreen = fullscreen
            self.messageCard = messageCard
            self.plugAnimation = plugAnimation
            self.levelFlash = levelFlash
        }
    }

    /// 小岛现在能不能出现（有没有活动另算）。
    public static func visible(_ context: Context) -> Bool {
        context.active && !context.presenting && !context.fullscreen && !context.messageCard
            && !context.plugAnimation && !context.levelFlash
    }
}

// MARK: - 和「灵动提示」胶囊分开

/// 「灵动提示」的小胶囊也在刘海正下方。两者不叠：
///
/// - 音量、亮度一闪时胶囊照常出现，小岛这一会儿收起（`NotchIslandGate.Context.levelFlash`）；
/// - 会议倒计时：小岛显示着的时候交给小岛（勾了「会议」就是小岛的一个活动，没勾就
///   先不显示），胶囊不再另起；小岛不在（没打开、全屏、演示模式、没别的事）时照旧由
///   胶囊显示。
public enum NotchIslandCapsule {
    /// 胶囊这一刻显示什么。
    public static func content(flash: IslandContent?, meeting: IslandContent?, islandShown: Bool) -> IslandContent? {
        IslandContent.resolve(flash: flash, meeting: islandShown ? nil : meeting)
    }

    /// 小岛的会议活动：「灵动提示」找到的那一个会议（`IslandContent.meeting`），别的是 nil。
    public static func meetingActivity(_ content: IslandContent?) -> NotchIslandActivity? {
        guard case .meeting(let title, let start)? = content else { return nil }
        return .meeting(title: title, start: start)
    }
}

// MARK: - 计时

public enum NotchIslandTiming {
    /// 插电提示显示多久。
    public static let chargeLinger: TimeInterval = 4
    /// 下载完成的勾显示多久。
    public static let downloadDoneLinger: TimeInterval = 2
    /// 未完成的文件刚消失、还没确认下好（大小 2 秒不变才算）时，先留着转圈等这么久。
    public static let downloadSettleGrace: TimeInterval = 6
    /// 在小岛上按了暂停的收音机还留多久（方便马上继续）。
    public static let radioPauseLinger: TimeInterval = 8
    /// 指针停在小岛上多久才展开（扫过菜单栏时不乱弹）。
    public static let hoverDelay: TimeInterval = 0.15
    /// 指针离开卡片多久才收起。
    public static let leaveDelay: TimeInterval = 0.35
    /// 收起动画走完后再缩窗口。
    public static let shrinkDelay: TimeInterval = 0.45
}

/// 弹簧参数（SwiftUI `.spring(response:dampingFraction:)`）。减弱动态效果时不用弹簧，
/// 只做很短的淡入淡出，见 `animated(reduceMotion:)`。
public enum NotchIslandMotion {
    public static let expandResponse: Double = 0.35
    public static let expandDamping: Double = 0.8
    public static let morphResponse: Double = 0.4
    public static let morphDamping: Double = 0.78
    /// 减弱动态效果时的淡入淡出时长。
    public static let reducedFade: Double = 0.15

    /// 减弱动态效果时不放弹簧。
    public static func springs(reduceMotion: Bool) -> Bool { !reduceMotion }
}

// MARK: - 下载

/// 下载这一项的状态：进度来自「下载」文件夹里未完成的文件（`DownloadProgress`），
/// 完成来自下载完成监视（`DesktopPetDownloadWatch`，大小 2 秒不变才算下好）。
///
/// 未完成的文件改名成正式文件到确认下好之间有约 2 秒空档：这时继续转圈（最多
/// `downloadSettleGrace` 秒），确认下好后打勾 `downloadDoneLinger` 秒再收起。
public struct NotchIslandDownloadTracker: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case active(fraction: Double?)
        case settling(since: Date, fraction: Double?)
        case done(until: Date)
    }

    private var phase: Phase = .idle

    public init() {}

    /// 合起来的进度：每个都知道进度时取平均，有一个不知道就是 nil（转圈）。
    public static func combined(_ fractions: [Double?]) -> Double? {
        guard !fractions.isEmpty else { return nil }
        var sum = 0.0
        for fraction in fractions {
            guard let fraction, fraction.isFinite else { return nil }
            sum += min(1, max(0, fraction))
        }
        return sum / Double(fractions.count)
    }

    /// 读了一次「下载」文件夹：还没下完的那些文件的进度。
    public mutating func progress(_ fractions: [Double?], now: Date) {
        if !fractions.isEmpty {
            phase = .active(fraction: Self.combined(fractions))
            return
        }
        switch phase {
        case .active(let fraction):
            phase = .settling(since: now, fraction: fraction)
        case .settling(let since, _):
            if now.timeIntervalSince(since) >= NotchIslandTiming.downloadSettleGrace { phase = .idle }
        case .done(let until):
            if now >= until { phase = .idle }
        case .idle:
            break
        }
    }

    /// 下载完成监视确认有文件下好了。
    public mutating func finished(now: Date) {
        phase = .done(until: now.addingTimeInterval(NotchIslandTiming.downloadDoneLinger))
    }

    /// 时间走了一步（勾和空档到点收起）。
    public mutating func tick(now: Date) {
        switch phase {
        case .settling(let since, _) where now.timeIntervalSince(since) >= NotchIslandTiming.downloadSettleGrace:
            phase = .idle
        case .done(let until) where now >= until:
            phase = .idle
        default:
            break
        }
    }

    /// 现在要显示的下载活动，没有时 nil。
    public func activity(now: Date) -> NotchIslandActivity? {
        switch phase {
        case .idle:
            return nil
        case .active(let fraction):
            return .download(fraction: fraction, done: false)
        case .settling(let since, let fraction):
            guard now.timeIntervalSince(since) < NotchIslandTiming.downloadSettleGrace else { return nil }
            return .download(fraction: fraction.map { max($0, 0.99) }, done: false)
        case .done(let until):
            return now < until ? .download(fraction: 1, done: true) : nil
        }
    }

    /// 还有事要等（空档或勾），需要按时再看一次。
    public var pending: Bool {
        switch phase {
        case .settling, .done: true
        default: false
        }
    }
}

// MARK: - 计时器

public enum NotchIslandTimer {
    /// 一张倒计时卡片里在跑或暂停的计时器（没开始的、到点在响的不上小岛，响铃有弹出卡片）。
    public static func countdowns(widget: UUID, config: WidgetConfig, now: Date) -> [NotchIslandActivity] {
        CountdownList.timers(config).compactMap { (timer: CountdownTimer) -> NotchIslandActivity? in
            let total = max(1, timer.duration)
            let source = NotchIslandTimerSource.countdown(widget: widget, timer: timer.id)
            switch CountdownList.phase(timer, now: now) {
            case .running:
                guard let deadline = timer.deadline else { return nil }
                return .timer(deadline: Date(timeIntervalSince1970: deadline), pausedLeft: nil, total: total,
                              focus: true, source: source, name: timer.name)
            case .paused(let left, _):
                return .timer(deadline: nil, pausedLeft: left, total: total, focus: true, source: source,
                              name: timer.name)
            case .idle, .ringing:
                return nil
            }
        }
    }

    /// 两个计时器活动里 `a` 是不是先结束：在跑的比暂停的先（暂停的不会自己结束），
    /// 都在跑看结束时刻，都暂停看剩下的少。一样时不算先（留先来的）。
    public static func endsBefore(_ a: NotchIslandActivity, _ b: NotchIslandActivity) -> Bool {
        guard case .timer(let da, let pa, _, _, _, _) = a, case .timer(let db, let pb, _, _, _, _) = b else {
            return false
        }
        switch (da, db) {
        case (let x?, let y?): return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return (pa ?? .infinity) < (pb ?? .infinity)
        }
    }

    /// 卡片上的「暂停 / 继续」作用到倒计时卡片里的那个计时器：在跑就暂停，暂停就接着数，
    /// 别的不动。
    public static func toggled(_ timer: CountdownTimer, now: Date) -> CountdownTimer {
        switch CountdownList.phase(timer, now: now) {
        case .running: CountdownList.pausing(timer, now: now)
        case .paused: CountdownList.resuming(timer, now: now)
        case .idle, .ringing: timer
        }
    }

    /// 专注计时现在要不要上小岛：在跑或暂停时要，没开始、到点（等下一步）时不要。
    public static func activity(_ state: TimerState, now: Date) -> NotchIslandActivity? {
        let total = max(1, state.duration ?? Double(max(1, state.minutes) * 60))
        let focus = state.phase == .focus
        if let paused = state.paused {
            return .timer(deadline: nil, pausedLeft: max(0, min(paused, total)), total: total, focus: focus)
        }
        guard let deadline = state.deadline, deadline > now else { return nil }
        return .timer(deadline: deadline, pausedLeft: nil, total: total, focus: focus)
    }

    /// 还剩多少秒。
    public static func remaining(deadline: Date?, pausedLeft: TimeInterval?, now: Date) -> TimeInterval {
        if let pausedLeft { return max(0, pausedLeft) }
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// 卡片上的「暂停 / 继续」，和专注计时面板的主按钮一样：在跑就把剩下的存进暂停，
    /// 暂停或到 0 就（重新）开始，开始时把这一段的长度钉住。
    public static func toggled(_ state: TimerState, now: Date) -> TimerState {
        var next = state
        let total = max(1, state.duration ?? Double(max(1, state.minutes) * 60))
        let left: TimeInterval
        if let paused = state.paused {
            left = max(0, min(paused, total))
        } else if let deadline = state.deadline {
            left = max(0, min(deadline.timeIntervalSince(now), total))
        } else {
            left = total
        }
        if state.deadline != nil, left > 0 {
            next.paused = left
            next.deadline = nil
        } else {
            next.duration = total
            next.deadline = now.addingTimeInterval(left > 0 ? left : total)
            next.paused = nil
        }
        return next
    }

    /// 卡片上的「结束」：同面板的「重置」，回到这一段开始前，连钉住的长度一起清掉。
    public static func ended(_ state: TimerState) -> TimerState {
        var next = state
        next.deadline = nil
        next.paused = nil
        next.duration = nil
        return next
    }

    /// 已经走过的比例（小圆岛上的圆环）。
    public static func elapsedFraction(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }
}

// MARK: - 文字

public enum NotchIslandText {
    /// 「24:58」；一小时以上「1:02:03」。秒向上取整，最后一秒还显示 0:01。
    public static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        let hours = whole / 3600
        let minutes = whole % 3600 / 60
        let secs = whole % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 「60%」：向下取整，没到 100 不写 100。
    public static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        let value = Int((min(1, max(0, fraction)) * 100).rounded(.down))
        return "\(value)%"
    }

    /// 会议在小岛上的短写法：「5 分」（向上取整，不到一分钟也是「1 分」），开始了是「现在」。
    public static func meetingShort(secondsUntil seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return tr("现在") }
        return tr("\(Int((seconds / 60).rounded(.up))) 分")
    }

    /// 电量「80%」，夹在 0...100。
    public static func battery(_ percent: Int) -> String { "\(min(100, max(0, percent)))%" }

    /// 读屏念的一句话。
    public static func spoken(_ activity: NotchIslandActivity, now: Date) -> String {
        switch activity {
        case .charging(let percent):
            return tr("已接通电源，电量 \(battery(percent))")
        case .download(let fraction, let done):
            if done { return tr("下载完成") }
            guard let fraction else { return tr("正在下载") }
            return tr("正在下载，\(percent(fraction))")
        case .timer(let deadline, let pausedLeft, _, let focus, let source, let title):
            let left = clock(NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: now))
            let name: String
            switch source {
            case .focus: name = focus ? tr("专注") : tr("休息")
            case .countdown: name = title.isEmpty ? tr("倒计时") : title
            }
            return pausedLeft != nil ? tr("\(name)已暂停，还剩 \(left)") : tr("\(name)还剩 \(left)")
        case .meeting(let title, let start):
            return IslandCountdown.line(title: title, secondsUntil: start.timeIntervalSince(now))
        case .radio(let station, let playing):
            return playing ? tr("收音机正在播放 \(station)") : tr("收音机已暂停 \(station)")
        }
    }
}

// MARK: - 几何
//
// 坐标以刘海顶边中点为原点：x 向右、y 向下（屏幕顶边是 y = 0）。窗口总是以刘海中线
// 左右对称、顶边贴住屏幕顶边，所以窗口大小变了，这套坐标里的东西不会跳。

/// 刘海（或模拟的刘海）有多大。
public struct NotchIslandGeometry: Equatable, Sendable {
    public var notchWidth: CGFloat
    /// 刘海的高度，也是两侧小岛的高度（和菜单栏一样高）。
    public var notchHeight: CGFloat
    /// 真的刘海；false 是没有刘海、在顶部居中模拟的。
    public var hasNotch: Bool

    public init(notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hasNotch = hasNotch
    }
}

public enum NotchIslandLayout {
    /// 没有刘海时模拟的刘海宽度。
    public static let simulatedNotchWidth: CGFloat = 168
    /// 量不到菜单栏高度时的高度。
    public static let fallbackHeight: CGFloat = 32
    /// 刘海下方显示剩余时间那一条多高（计时器是主活动时）。
    public static let chinHeight: CGFloat = 26
    /// 小岛底部两角的圆角上限。
    public static let bottomRadius: CGFloat = 12
    /// 顶边外侧往里弯的那一小段（和屏幕边框接上，不是飘着的胶囊）。
    public static let topFlare: CGFloat = 6
    /// 右边小圆岛离主岛多远。
    public static let bubbleGap: CGFloat = 6
    /// 插电时趴在右边的小熊猫。
    public static let pandaSize = CGSize(width: 66, height: 28)
    /// 展开卡片底下第二个活动那一行（含上边距）。
    public static let secondaryRowHeight: CGFloat = 44
    /// 展开卡片的宽度。
    public static let cardWidth: CGFloat = 372
    /// 窗口四周给阴影留的透明边（顶边不留）。
    public static let shadowMargin: CGFloat = 24

    /// 这块屏幕上的刘海，没有刘海时按菜单栏高度在正中模拟一个。
    public static func geometry(screen: AINotchScreen) -> NotchIslandGeometry {
        let bar = AINotchLayout.menuBar(of: screen)
        if let notch = screen.notch {
            return NotchIslandGeometry(notchWidth: notch.width, notchHeight: max(notch.height, bar.height),
                                       hasNotch: true)
        }
        let height = bar.height > 0 ? bar.height : fallbackHeight
        return NotchIslandGeometry(notchWidth: simulatedNotchWidth, notchHeight: height, hasNotch: false)
    }

    /// 刘海中线在屏幕上的 x。
    public static func centerX(screen: AINotchScreen) -> CGFloat {
        screen.notch?.midX ?? screen.frame.midX
    }

    /// 一个活动在 compact 形态下左右两侧各多宽，以及刘海下面要不要一条显示剩余时间。
    public static func wings(_ activity: NotchIslandActivity) -> (left: CGFloat, right: CGFloat, chin: CGFloat) {
        switch activity {
        case .charging: return (left: 40, right: 62, chin: 0)
        case .download(_, let done): return (left: 40, right: done ? 40 : 76, chin: 0)
        case .timer: return (left: 14, right: 14, chin: chinHeight)
        case .meeting: return (left: 40, right: 56, chin: 0)
        case .radio: return (left: 40, right: 44, chin: 0)
        }
    }

    /// 主岛（含刘海那一段）在原点坐标里的范围。
    public static func body(_ geometry: NotchIslandGeometry, _ activity: NotchIslandActivity) -> CGRect {
        let wings = wings(activity)
        let half = geometry.notchWidth / 2
        return CGRect(x: -half - wings.left, y: 0, width: geometry.notchWidth + wings.left + wings.right,
                      height: geometry.notchHeight + wings.chin)
    }

    /// 刘海那一段（在主岛里，原点坐标）。
    public static func notch(_ geometry: NotchIslandGeometry) -> CGRect {
        CGRect(x: -geometry.notchWidth / 2, y: 0, width: geometry.notchWidth, height: geometry.notchHeight)
    }

    /// 小圆岛的直径：比刘海矮一点。
    public static func bubbleDiameter(_ geometry: NotchIslandGeometry) -> CGFloat {
        max(22, geometry.notchHeight - 4)
    }

    /// split 形态右边的小圆岛：在主岛右边，竖直方向和两侧小岛对齐。
    public static func bubble(_ geometry: NotchIslandGeometry, body: CGRect) -> CGRect {
        let diameter = bubbleDiameter(geometry)
        return CGRect(x: body.maxX + bubbleGap, y: (geometry.notchHeight - diameter) / 2,
                      width: diameter, height: diameter)
    }

    /// 插电时的小熊猫：趴在主岛右边，底边和主岛底边对齐。
    public static func panda(_ geometry: NotchIslandGeometry, body: CGRect) -> CGRect {
        CGRect(x: body.maxX - 4, y: body.maxY - pandaSize.height + 4, width: pandaSize.width, height: pandaSize.height)
    }

    /// 展开卡片的高度（含刘海那一段）。
    public static func cardHeight(_ geometry: NotchIslandGeometry, kind: NotchIslandKind, hasSecondary: Bool) -> CGFloat {
        let content: CGFloat
        switch kind {
        case .radio: content = 132
        case .timer: content = 122
        case .download: content = 100
        case .meeting: content = 100
        case .charging: content = 92
        }
        return geometry.notchHeight + content + (hasSecondary ? secondaryRowHeight : 0)
    }

    /// 展开卡片的范围：顶边贴住屏幕顶边，宽度至少比刘海宽出两边。
    public static func card(_ geometry: NotchIslandGeometry, kind: NotchIslandKind, hasSecondary: Bool) -> CGRect {
        let width = max(cardWidth, geometry.notchWidth + 120)
        return CGRect(x: -width / 2, y: 0, width: width,
                      height: cardHeight(geometry, kind: kind, hasSecondary: hasSecondary))
    }

    /// 这种形态下画出来的东西（主岛、小圆岛、小熊猫、卡片），原点坐标。
    public static func pieces(_ geometry: NotchIslandGeometry, form: NotchIslandForm) -> [CGRect] {
        switch form {
        case .compact(let primary):
            let main = body(geometry, primary)
            if case .charging = primary { return [main, panda(geometry, body: main)] }
            return [main]
        case .split(let primary, _):
            let main = body(geometry, primary)
            var result = [main, bubble(geometry, body: main)]
            if case .charging = primary { result.append(panda(geometry, body: main)) }
            return result
        case .expanded(let primary, let secondary):
            return [card(geometry, kind: primary.kind, hasSecondary: secondary != nil)]
        }
    }

    /// 指针在这些范围里算「停在小岛上」（原点坐标，往外放宽 `slack`）。
    public static func hotZone(_ geometry: NotchIslandGeometry, form: NotchIslandForm, slack: CGFloat = 4) -> CGRect {
        let rects: [CGRect]
        switch form {
        case .compact(let primary): rects = [body(geometry, primary)]
        case .split(let primary, _):
            let main = body(geometry, primary)
            rects = [main, bubble(geometry, body: main)]
        case .expanded: rects = pieces(geometry, form: form)
        }
        let union = rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
        return union.insetBy(dx: -slack, dy: -slack)
    }

    /// 左右对称的半宽和高度，够放下这些东西（含顶边外弯的一小段）。
    public static func extent(_ rects: [CGRect]) -> (halfWidth: CGFloat, height: CGFloat) {
        var half: CGFloat = 0
        var height: CGFloat = 0
        for rect in rects {
            half = max(half, abs(rect.minX), abs(rect.maxX))
            height = max(height, rect.maxY)
        }
        return (half + topFlare, height)
    }

    /// 窗口（AppKit 屏幕坐标，原点左下）：以刘海中线对称、顶边贴住屏幕顶边，四周（顶边除外）
    /// 留阴影边。
    public static func windowFrame(centerX: CGFloat, screenTop: CGFloat,
                                   halfWidth: CGFloat, height: CGFloat) -> CGRect {
        let half = ceil(halfWidth + shadowMargin)
        let fullHeight = ceil(height + shadowMargin)
        return CGRect(x: centerX - half, y: screenTop - fullHeight, width: half * 2, height: fullHeight)
    }

    /// 原点坐标里的一块换成屏幕坐标（原点左下）。
    public static func screenRect(_ local: CGRect, centerX: CGFloat, screenTop: CGFloat) -> CGRect {
        CGRect(x: centerX + local.minX, y: screenTop - local.maxY, width: local.width, height: local.height)
    }
}
