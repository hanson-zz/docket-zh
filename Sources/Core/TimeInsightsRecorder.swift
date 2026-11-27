import Foundation

/// 时间洞察的采集状态机：吃系统事件（前台切换、空闲秒数、锁屏休眠、暂停），吐出
/// 已经结束的 `ActivitySession`。不碰 AppKit，测试直接喂事件。
///
/// 规则：
/// - 同一时刻最多一段开着（`segment`），所以不会双计。
/// - 前台切换：旧的一段在这一刻结束，新的一段从这一刻开始。
/// - 空闲：距上次输入满门槛时，活跃段在「上次输入那一刻」结束（门槛那几分钟不算活跃），
///   接着开一段「前台停留」（`ActivitySource.idleForeground`）；有输入回来时，
///   停留段在回来那一刻结束，再开新的活跃段。
/// - 锁屏、休眠、屏保、显示器睡眠、切换用户、暂停、排除的 App、卡片没放：开着的段
///   立刻结束，期间什么都不开。
/// - 心跳：每次事件都把开着那段的 `lastSeen` 推到现在。两次事件隔得比 `heartbeatGap`
///   久（休眠了却没收到通知、进程被挂起），开着的段按上一次心跳结束，空档不算。
/// - 崩溃恢复：开着的段（带 `lastSeen`）由采集器定期存下来，下次启动用
///   `recover(_:now:)` 按 `lastSeen` 收尾，进程没在跑的那段时间不算。
public struct TimeInsightsRecorder: Sendable {

    public struct App: Equatable, Codable, Sendable {
        public var bundleID: String
        public var name: String
        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// 不计时的原因。可以同时有好几个，全部解除才恢复。
    public enum Block: String, CaseIterable, Codable, Sendable {
        case asleep, displayOff, locked, screensaver, userSwitched, paused, notPlaced, storage
    }

    public enum Event: Equatable, Sendable {
        /// 前台换成了这个 App；nil 是没有前台 App（极少见）。
        case foreground(App?)
        /// 距上次键盘、鼠标、触控板输入的秒数。
        case idle(TimeInterval)
        case blocked(Block)
        case unblocked(Block)
        /// 定时心跳，什么都没变。
        case tick
    }

    /// 开着的一段，存盘用来崩溃恢复。
    public struct Open: Equatable, Codable, Sendable {
        public var id: String
        public var bundleID: String
        public var appName: String
        public var start: Date
        public var lastSeen: Date
        public var idle: Bool
        public var classification: TimeInsightsCategory

        public init(id: String = UUID().uuidString, bundleID: String, appName: String, start: Date,
                    lastSeen: Date, idle: Bool, classification: TimeInsightsCategory) {
            self.id = id
            self.bundleID = bundleID
            self.appName = appName
            self.start = start
            self.lastSeen = lastSeen
            self.idle = idle
            self.classification = classification
        }

        func closed(at end: Date) -> ActivitySession? {
            let finish = max(start, end)
            guard finish.timeIntervalSince(start) >= TimeInsightsRecorder.minimumLength else { return nil }
            return ActivitySession(id: id, start: start, end: finish, bundleID: bundleID, appName: appName,
                                   classification: classification,
                                   source: idle ? .idleForeground : .foreground)
        }
    }

    /// 比这短的一段不记（切 App 时一闪而过的）。
    public static let minimumLength: TimeInterval = 1

    public var idleAfter: TimeInterval
    public var excluded: Set<String>
    public var rules: [TimeInsightsRule]
    /// 两次事件之间最多隔多久还算连着；采集器每 10 秒一次心跳，默认 90 秒。
    public var heartbeatGap: TimeInterval

    public private(set) var app: App?
    public private(set) var blocks: Set<Block>
    public private(set) var isIdle: Bool
    public private(set) var segment: Open?
    public private(set) var lastEvent: Date?

    public init(idleAfter: TimeInterval = TimeInterval(TimeInsightsSettings.defaultIdleMinutes * 60),
                excluded: Set<String> = [], rules: [TimeInsightsRule] = [], heartbeatGap: TimeInterval = 90,
                blocks: Set<Block> = []) {
        self.idleAfter = idleAfter
        self.excluded = excluded
        self.rules = rules
        self.heartbeatGap = heartbeatGap
        self.blocks = blocks
        self.isIdle = false
    }

    /// 现在该不该有一段开着，开的是哪个 App。
    public var eligibleApp: App? {
        guard blocks.isEmpty, let app, !excluded.contains(app.bundleID),
              !TimeInsightsDefaults.alwaysSkipped.contains(app.bundleID) else { return nil }
        return app
    }

    /// 现在的状态，给卡片和面板看。
    public var status: TimeInsightsStatus {
        if blocks.contains(.storage) { return .storageError }
        if blocks.contains(.paused) { return .paused }
        if !blocks.subtracting([.notPlaced]).isEmpty { return .away }
        guard let app else { return .starting }
        if app.bundleID == TimeInsightsDefaults.ownBundleID { return .ownApp }
        if excluded.contains(app.bundleID) || TimeInsightsDefaults.alwaysSkipped.contains(app.bundleID) {
            return .excluded
        }
        return isIdle ? .idle : .recording
    }

    /// 喂一个事件，返回这一下结束了的段（0 到 2 段）。
    public mutating func handle(_ event: Event, at now: Date) -> [ActivitySession] {
        var finished: [ActivitySession] = []

        // 心跳断了：按上一次心跳收尾，空档不算。之后按现在的状态重新开。
        if let last = lastEvent, now.timeIntervalSince(last) > heartbeatGap, let current = segment {
            if let session = current.closed(at: current.lastSeen) { finished.append(session) }
            segment = nil
        }
        lastEvent = max(lastEvent ?? now, now)

        var reopenAt = now
        switch event {
        case .foreground(let next):
            if next != app {
                finished += close(at: now)
                app = next
            }
        case .idle(let seconds):
            let quiet = max(0, seconds)
            let lastInput = now.addingTimeInterval(-quiet)
            // 新的一段不能早于正在结束的这一段的开始（上次输入可能早于唤醒、解锁），
            // 没有开着的段时从现在开始，免得把锁屏、排除的时间算进来。
            let floor = segment?.start ?? now
            if quiet >= idleAfter, !isIdle {
                // 门槛那几分钟本来就没有输入，活跃段在上次输入那一刻结束。
                finished += close(at: lastInput)
                isIdle = true
                reopenAt = max(lastInput, floor)
            } else if quiet < idleAfter, isIdle {
                finished += close(at: lastInput)
                isIdle = false
                reopenAt = max(lastInput, floor)
            }
        case .blocked(let reason):
            if !blocks.contains(reason) {
                finished += close(at: now)
                blocks.insert(reason)
            }
        case .unblocked(let reason):
            blocks.remove(reason)
        case .tick:
            break
        }

        finished += reconcile(now: now, startAt: min(reopenAt, now))
        return finished
    }

    /// 按现在的状态开、关或续上开着的那段。
    private mutating func reconcile(now: Date, startAt: Date) -> [ActivitySession] {
        guard let target = eligibleApp else {
            return close(at: now)
        }
        if var current = segment {
            if current.bundleID == target.bundleID, current.idle == isIdle {
                current.lastSeen = max(current.lastSeen, now)
                segment = current
                return []
            }
            let ended = close(at: now)
            openSegment(target, at: now)
            return ended
        }
        // 段的开始不能早于上一次事件之前的空档（心跳断了的情况已经在上面收尾）。
        openSegment(target, at: startAt)
        if var current = segment { current.lastSeen = now; segment = current }
        return []
    }

    private mutating func openSegment(_ app: App, at start: Date) {
        segment = Open(bundleID: app.bundleID, appName: app.name, start: start, lastSeen: start, idle: isIdle,
                    classification: TimeInsightsClassifier.classify(bundleID: app.bundleID, rules: rules))
    }

    private mutating func close(at end: Date) -> [ActivitySession] {
        guard let current = segment else { return [] }
        segment = nil
        return current.closed(at: end).map { [$0] } ?? []
    }

    /// 退出或停止时：开着的那段在这一刻结束。
    public mutating func flush(at now: Date) -> [ActivitySession] {
        close(at: now)
    }

    /// 现在开着、还没结束的那段，按到现在为止算，给今日汇总加上（不写盘）。
    public func provisional(now: Date) -> ActivitySession? {
        segment?.closed(at: now)
    }

    /// 上次没收尾的那段（退出或崩溃时开着）：按最后一次心跳收尾，进程没在跑的时间不算。
    public static func recover(_ segment: Open, now: Date) -> ActivitySession? {
        segment.closed(at: min(segment.lastSeen, now))
    }
}
