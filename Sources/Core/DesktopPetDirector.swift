import Foundation

// 小熊猫做码头的「状态助手」：码头里发生了一件事（第一版只有文件暂存成功），
// 决定小熊猫怎么回应。都是纯逻辑，窗口、气泡、打开面板在 `DesktopPetController`。
//
// 一件事的来回：
// 1. 码头发一个 `DesktopPetEvent`。
// 2. 小熊猫被拖着、正在落地这类没站稳的时候先排队（`DesktopPetDirector.enqueue`），
//    站稳了再一件件交给 `decide`。
// 3. `decide` 给出 `DesktopPetReaction`：叼着纸团跑到卡片旁，或者就地抬头加一句气泡。
// 4. 到了以后进入「有待查看」（`DesktopPetReview`）：坐在卡片旁约 60 秒，单击打开那张卡片。
//
// 加事件：在 `DesktopPetEvent` 加一种，`decide` 里给它一条规则。
//
// 专注结束（`.focusFinished`）：朝计时器卡片那边看一眼、举爪欢呼一次、坐回去，有待查看时单击打开计时器。
// 离开回来（`.welcomeBack`）：离开（锁屏、显示器睡了、或系统空闲满 5 分钟）期间发生的事先不演，
// 记在 `DesktopPetAwayLog` 里；回来时小熊猫从睡着抬头探看，把记下的事合并成一条气泡（取最重要的）。
// 活动提醒（`.stretchReminder`）：连续打字满 50 分钟伸个懒腰说一句，计时在 `DesktopPetStretchClock`。
// 下载完成（`.downloadFinished`）：叼纸团跑一小段放下说一句，单击在访达中显示；
// 看下载文件夹的规则在 `DesktopPetDownloadWatch`。见 DesktopPetUseful.swift。

// MARK: - 事件

/// 码头里发生的、小熊猫要回应的事。
public enum DesktopPetEvent: Equatable, Sendable {
    /// 文件暂存成功：`count` 个文件放进了 `widgetID` 那张文件暂存卡片，`newItemIDs` 是新条目
    /// 的标识（暂存清单里的路径），`at` 是松手的位置（屏幕坐标，左下原点）。
    case fileStored(count: Int, widgetID: UUID, newItemIDs: [String], at: CGPoint)
    /// 专注计时完成一轮。`widgetID` 是码头上的计时器卡片（没有就是 nil），`at` 是那张卡片在屏幕上的
    /// 中心（屏幕坐标，左下原点；卡片看不见时是 nil）。
    case focusFinished(widgetID: UUID?, at: CGPoint?)
    /// 离开一阵又回来了；`summary` 是离开期间发生的事合并成的那一条（什么都没发生是 nil）。
    case welcomeBack(DesktopPetWelcome?)
    /// 文件暂存里有 `count` 个条目到期被自动移出。平时不演，只在离开期间记下，回来时说一句。
    case shelfExpired(count: Int, widgetID: UUID)
    /// 连续打字太久：伸个懒腰，提醒起来活动一下。
    case stretchReminder
    /// 下载文件夹里有文件下好了（完整路径，按下好的先后）。
    case downloadFinished(paths: [String])

    /// 排队时同一类只留一件。
    public var kind: String {
        switch self {
        case .fileStored: "fileStored"
        case .focusFinished: "focusFinished"
        case .welcomeBack: "welcomeBack"
        case .shelfExpired: "shelfExpired"
        case .stretchReminder: "stretchReminder"
        case .downloadFinished: "downloadFinished"
        }
    }
}

// MARK: - 常量

public enum DesktopPetAssist {
    /// 这么多秒内接连暂存，合并成一趟，计数相加。
    public static let mergeWindow: TimeInterval = 3
    /// 到了卡片旁以后「有待查看」多久。
    public static let reviewDuration: TimeInterval = 60
    /// 就地提示的气泡停几秒。
    public static let noticeBubble: TimeInterval = 3.5
    /// 叼到卡片旁时离卡片中线多远（点，按大小设置缩放）：坐在旁边，不挡卡片。
    public static let besideGap: Double = 34
    /// 打开面板后新条目高亮多久。
    public static let highlightDuration: TimeInterval = 2.4

    /// 专注完成：先朝计时器那边抬头看多久，再欢呼。
    public static let focusLook: TimeInterval = 0.9
    /// 欢呼帧每秒几帧；播一遍（cheer 6 帧）要多久。
    public static let cheerFPS: Double = 8
    public static var cheerOnce: TimeInterval { Double(DesktopPetStrip.cheer.frameCount) / cheerFPS }
    /// 看一眼加欢呼一遍，之后坐回去。
    public static var celebrateDuration: TimeInterval { focusLook + cheerOnce }
    /// 专注完成的气泡停几秒。
    public static let focusBubble: TimeInterval = 5
    /// 离开电脑满这么多秒（系统空闲，或锁屏、显示器睡了这么久）算「离开一阵」，回来时探头打招呼。
    public static let awayAfter: TimeInterval = 300
    /// 回来时那条气泡停几秒。
    public static let welcomeBubble: TimeInterval = 5

    /// 专注完成的气泡：「专注完成」/ "Focus done"。
    public static var focusDoneText: String { tr("专注完成") }

    /// 气泡上的话：「已暂存 N 个文件」/ "Stored N files"（一个时用单数）。
    public static func storedText(_ count: Int) -> String {
        count == 1 ? tr("已暂存 1 个文件") : tr("已暂存 \(max(0, count)) 个文件")
    }
}

// MARK: - 一趟

/// 正在办的一趟：合并后的计数、新条目、最新的松手位置。
public struct DesktopPetErrand: Equatable, Sendable {
    public var widgetID: UUID
    public var count: Int
    /// 新条目，最新放进来的在前，不重复。
    public var itemIDs: [String]
    public var at: CGPoint
    /// 最近一次合并进来的时刻，算 3 秒窗口用。
    public var lastAt: Date

    public init(widgetID: UUID, count: Int, itemIDs: [String], at: CGPoint, lastAt: Date) {
        self.widgetID = widgetID
        self.count = count
        self.itemIDs = itemIDs
        self.at = at
        self.lastAt = lastAt
    }

    public var text: String { DesktopPetAssist.storedText(count) }

    /// 把新的一批并进来：计数相加、新条目排前面去重、位置换成最新的。
    public func merging(count more: Int, itemIDs fresh: [String], at point: CGPoint, now: Date) -> DesktopPetErrand {
        var next = self
        next.count += max(0, more)
        var seen = Set<String>()
        next.itemIDs = (fresh + itemIDs).filter { seen.insert($0).inserted }
        next.at = point
        next.lastAt = now
        return next
    }
}

// MARK: - 回应

public enum DesktopPetReaction: Equatable, Sendable {
    /// 不管（预留的事件、小熊猫不在屏幕上）。
    case ignore
    /// 还没站稳：先排队，站稳了再交给 `decide`。
    case queue
    /// 叼着纸团跑到 `to`（沿边坐标，卡片旁），放下坐好，进入「有待查看」。
    case deliver(DesktopPetErrand, to: Double)
    /// 就地抬头或探头（吊着的晃大一下，`swing`），头顶气泡说一句。
    case notice(DesktopPetErrand, swing: Bool)
    /// 活动提醒：伸个懒腰（吊着的晃一下），头顶说「起来活动一下吧」。
    case stretch(swing: Bool)
    /// 下载好了：叼着纸团跑到 `to`（沿边坐标，身边一小段）放下，说一句，单击在访达中显示。
    /// `to` 是 nil 时就地抬头或探头（吊着的晃一下）。
    case fetch(DesktopPetDownloads, to: Double?, swing: Bool)
    /// 专注完成：朝 `toward`（计时器卡片在沿边坐标上的位置；异屏、看不见时是 nil，就地）看一眼，
    /// 欢呼一次再坐回去；有计时器卡片（`widgetID`）时进入「有待查看」，单击打开它。
    case celebrate(widgetID: UUID?, toward: Double?, swing: Bool)
    /// 离开回来：从睡着抬头探看（吊着的晃一下）；`summary` 不是 nil 时说那一句，单击打开对应卡片。
    case welcome(DesktopPetWelcome?, swing: Bool)
}

/// 做决定时要知道的小熊猫现状。
public struct DesktopPetDirectorContext: Equatable, Sendable {
    public var now: Date
    /// 被拖着、正在落地、跳着、救回途中：还没站稳。
    public var settling: Bool
    /// 小熊猫待的那条边；没显示时是 nil。
    public var track: DesktopPetTrack?
    /// 小熊猫现在的沿边坐标。
    public var petX: Double
    /// 松手的位置和小熊猫在同一块屏幕上。
    public var sameScreen: Bool
    /// 设置里的大小。
    public var scale: Double
    /// 正在办（或刚办完）的那一趟，3 秒内的新事件并进去。
    public var recent: DesktopPetErrand?
    /// 刚报过的那一批下载，3 秒内新下好的并进去。
    public var recentDownloads: DesktopPetDownloads?

    public init(now: Date, settling: Bool, track: DesktopPetTrack?, petX: Double, sameScreen: Bool,
                scale: Double = 1, recent: DesktopPetErrand? = nil, recentDownloads: DesktopPetDownloads? = nil) {
        self.now = now
        self.settling = settling
        self.track = track
        self.petX = petX
        self.sameScreen = sameScreen
        self.scale = scale
        self.recent = recent
        self.recentDownloads = recentDownloads
    }
}

public enum DesktopPetDirector {
    /// 一件事怎么回应。
    public static func decide(_ event: DesktopPetEvent, context: DesktopPetDirectorContext) -> DesktopPetReaction {
        guard let track = context.track else { return .ignore }
        switch event {
        case .fileStored(let count, let widgetID, let ids, let point):
            if context.settling { return .queue }
            return stored(count: count, widgetID: widgetID, itemIDs: ids, at: point, track: track, context: context)
        case .focusFinished(let widgetID, let point):
            if context.settling { return .queue }
            // 朝计时器卡片那一侧看：同一块屏幕、卡片看得见才转头；左右边按纵坐标。
            let toward: Double? = if let point, context.sameScreen {
                Double(track.edge.vertical ? point.y : point.x)
            } else { nil }
            return .celebrate(widgetID: widgetID, toward: toward, swing: track.style == .hang)
        case .welcomeBack(let summary):
            if context.settling { return .queue }
            return .welcome(summary, swing: track.style == .hang)
        case .shelfExpired:
            // 平时不演，离开期间由 `DesktopPetAwayLog` 记下。
            return .ignore
        case .stretchReminder:
            if context.settling { return .queue }
            return .stretch(swing: track.style == .hang)
        case .downloadFinished(let paths):
            if context.settling { return .queue }
            let batch = DesktopPetDownloads.merged(paths, into: context.recentDownloads, now: context.now)
            guard !batch.paths.isEmpty else { return .ignore }
            if track.style == .stroll, track.lane.upperBound - track.lane.lowerBound > 1 {
                return .fetch(batch, to: fetchSpot(from: context.petX, lane: track.lane, scale: context.scale),
                              swing: false)
            }
            return .fetch(batch, to: nil, swing: track.style == .hang)
        }
    }

    /// 下载好了叼过来：朝可走范围中间那边跑一小段（`DesktopPetAssist.fetchRun`），夹在范围里。
    public static func fetchSpot(from petX: Double, lane: ClosedRange<Double>, scale: Double) -> Double {
        let run = DesktopPetAssist.fetchRun * max(scale, 0.1)
        let mid = (lane.lowerBound + lane.upperBound) / 2
        return DesktopPetBrain.clamp(petX <= mid ? petX + run : petX - run, lane)
    }

    private static func stored(count: Int, widgetID: UUID, itemIDs ids: [String], at point: CGPoint,
                               track: DesktopPetTrack, context: DesktopPetDirectorContext) -> DesktopPetReaction {
        let errand = merged(count: count, widgetID: widgetID, itemIDs: ids, at: point, into: context.recent,
                            now: context.now)
        if canDeliver(track: track, sameScreen: context.sameScreen) {
            let goal = beside(card: Double(point.x), from: context.petX, lane: track.lane, scale: context.scale)
            return .deliver(errand, to: goal)
        }
        return .notice(errand, swing: track.style == .hang)
    }

    /// 程序坞上沿能走、投放点在同一块屏幕：叼过去。侧边程序坞、贴边、吊着、随意放的都不跑。
    public static func canDeliver(track: DesktopPetTrack, sameScreen: Bool) -> Bool {
        sameScreen && track.style == .stroll && track.edge == .bottom
            && track.lane.upperBound - track.lane.lowerBound > 1
    }

    /// 3 秒内、同一张卡片：并进正在办的那一趟；否则另起一趟。
    public static func merged(count: Int, widgetID: UUID, itemIDs: [String], at point: CGPoint,
                              into recent: DesktopPetErrand?, now: Date) -> DesktopPetErrand {
        if let recent, recent.widgetID == widgetID, now >= recent.lastAt,
           now.timeIntervalSince(recent.lastAt) <= DesktopPetAssist.mergeWindow {
            return recent.merging(count: count, itemIDs: itemIDs, at: point, now: now)
        }
        var seen = Set<String>()
        return DesktopPetErrand(widgetID: widgetID, count: max(0, count),
                                itemIDs: itemIDs.filter { seen.insert($0).inserted }, at: point, lastAt: now)
    }

    /// 卡片旁的落脚点：从小熊猫这一侧靠过去，停在离卡片中线 `besideGap` 的地方；
    /// 这一侧超出可走范围就换另一侧，都不行就夹在范围里。
    public static func beside(card: Double, from petX: Double, lane: ClosedRange<Double>, scale: Double) -> Double {
        let gap = DesktopPetAssist.besideGap * max(scale, 0.1)
        let near = petX <= card ? card - gap : card + gap
        let far = petX <= card ? card + gap : card - gap
        if lane.contains(near) { return near }
        if lane.contains(far) { return far }
        return DesktopPetBrain.clamp(card, lane)
    }

    /// 没站稳时排队：同一类只留最新的一件；同一张卡片的文件暂存把计数、新条目并进最新那件。
    public static func enqueue(_ event: DesktopPetEvent, into queue: [DesktopPetEvent]) -> [DesktopPetEvent] {
        var incoming = event
        if case .fileStored(let count, let widgetID, let ids, let point) = event,
           let old = queue.first(where: { $0.kind == event.kind }),
           case .fileStored(let oldCount, let oldWidget, let oldIDs, _) = old, oldWidget == widgetID {
            var seen = Set<String>()
            incoming = .fileStored(count: count + oldCount, widgetID: widgetID,
                                   newItemIDs: (ids + oldIDs).filter { seen.insert($0).inserted }, at: point)
        }
        if case .downloadFinished(let paths) = event,
           case .downloadFinished(let oldPaths)? = queue.first(where: { $0.kind == event.kind }) {
            var seen = Set<String>()
            incoming = .downloadFinished(paths: (oldPaths + paths).filter { seen.insert($0).inserted })
        }
        return queue.filter { $0.kind != event.kind } + [incoming]
    }

    /// 码头上的计时器卡片（文件夹里的也算，按出现的先后取第一张）：专注完成时朝它看、单击打开它。
    public static func timerWidget(in widgets: [WidgetInstance]) -> UUID? {
        widgets.first { $0.kind == .timer }?.id
    }

    /// 拖到小熊猫身上的文件放进哪张文件暂存卡片：码头上（文件夹里的也算）第一张没隐藏的；没有是 nil。
    public static func shelfWidget(in widgets: [WidgetInstance]) -> WidgetInstance? {
        widgets.first { $0.kind == .fileShelf && WidgetManagement.isShown($0) }
    }
}

// MARK: - 有待查看

/// 叼到了（或就地提示过）：坐在那里等你看一眼。被点、拖走、来了新事件、超时都结束。
public struct DesktopPetReview: Equatable, Sendable {
    /// 单击打开的卡片。
    public var widgetID: UUID
    /// 打开文件暂存面板时闪一下的新条目（别的卡片是空的）。
    public var itemIDs: [String]
    public var count: Int
    public var until: Date
    /// 气泡上说的那句。
    public var text: String

    public init(_ errand: DesktopPetErrand, now: Date, duration: TimeInterval = DesktopPetAssist.reviewDuration) {
        widgetID = errand.widgetID
        itemIDs = errand.itemIDs
        count = errand.count
        until = now.addingTimeInterval(duration)
        text = DesktopPetAssist.storedText(errand.count)
    }

    /// 专注完成、离开回来这类：只记打开哪张卡片和说的话。
    public init(widgetID: UUID, text: String, itemIDs: [String] = [], now: Date,
                duration: TimeInterval = DesktopPetAssist.reviewDuration) {
        self.widgetID = widgetID
        self.itemIDs = itemIDs
        count = itemIDs.count
        until = now.addingTimeInterval(duration)
        self.text = text
    }

    public func expired(at now: Date) -> Bool { now >= until }
}

// MARK: - 离开回来

/// 离开期间发生、先不演的事。
public enum DesktopPetMissed: Equatable, Sendable {
    case focusFinished(widgetID: UUID?)
    case filesStored(count: Int, widgetID: UUID, itemIDs: [String])
    case filesExpired(count: Int, widgetID: UUID)
    case downloaded(paths: [String])

    /// 合并成一条时谁优先：专注结束 > 新暂存 > 下载好了 > 到期移出。数大的优先。
    public var priority: Int {
        switch self {
        case .focusFinished: 4
        case .filesStored: 3
        case .downloaded: 2
        case .filesExpired: 1
        }
    }
}

/// 回来时说的那一条：说什么、单击打开哪张卡片、打开文件暂存时闪哪些新条目。
public struct DesktopPetWelcome: Equatable, Sendable {
    public var text: String
    public var widgetID: UUID?
    public var itemIDs: [String]
    /// 单击在访达中显示的文件（离开期间下好的）；不是下载时为空。
    public var revealPaths: [String]

    public init(text: String, widgetID: UUID?, itemIDs: [String] = [], revealPaths: [String] = []) {
        self.text = text
        self.widgetID = widgetID
        self.itemIDs = itemIDs
        self.revealPaths = revealPaths
    }

    /// 离开期间的事合并成一条：只说最重要的那一类；同一类的计数相加，卡片取最近那件的。
    public static func summary(_ missed: [DesktopPetMissed]) -> DesktopPetWelcome? {
        guard let top = missed.map(\.priority).max() else { return nil }
        let same = missed.filter { $0.priority == top }
        switch same.last {
        case .focusFinished?:
            let widget = same.reversed().lazy.compactMap { item -> UUID? in
                if case .focusFinished(let id) = item { return id } else { return nil }
            }.first
            return DesktopPetWelcome(text: focusText, widgetID: widget)
        case .filesStored(_, let widget, _)?:
            var count = 0
            var ids: [String] = []
            for case .filesStored(let n, _, let fresh) in same {
                count += max(0, n)
                ids = fresh + ids
            }
            var seen = Set<String>()
            return DesktopPetWelcome(text: storedText(count), widgetID: widget,
                                     itemIDs: ids.filter { seen.insert($0).inserted })
        case .filesExpired(_, let widget)?:
            var count = 0
            for case .filesExpired(let n, _) in same { count += max(0, n) }
            return DesktopPetWelcome(text: expiredText(count), widgetID: widget)
        case .downloaded?:
            var paths: [String] = []
            for case .downloaded(let fresh) in same { paths += fresh }
            var seen = Set<String>()
            paths = paths.filter { seen.insert($0).inserted }
            return DesktopPetWelcome(text: DesktopPetAssist.downloadedText(paths), widgetID: nil, revealPaths: paths)
        case nil:
            return nil
        }
    }

    /// 「离开时专注结束了」/ "Focus ended while you were away"。
    public static var focusText: String { tr("离开时专注结束了") }

    /// 「暂存里有 N 个新文件」/ "N new files on the shelf"。
    public static func storedText(_ count: Int) -> String {
        count == 1 ? tr("暂存里有 1 个新文件") : tr("暂存里有 \(max(0, count)) 个新文件")
    }

    /// 「暂存里有 N 个文件到期移出了」/ "N shelf files expired"。
    public static func expiredText(_ count: Int) -> String {
        count == 1 ? tr("暂存里有 1 个文件到期移出了") : tr("暂存里有 \(max(0, count)) 个文件到期移出了")
    }
}

/// 离开、回来，和离开期间记下的事。离开的判断沿用久坐提醒的 `PostureAway.Tracker`：
/// 系统空闲满 `DesktopPetAssist.awayAfter`、或者锁屏、显示器睡了、休眠、屏保、切换用户。
public struct DesktopPetAwayLog: Equatable, Sendable {
    public private(set) var tracker = PostureAway.Tracker(idleAfter: DesktopPetAssist.awayAfter)
    public private(set) var missed: [DesktopPetMissed] = []

    public init() {}

    public var isAway: Bool { tracker.isAway }

    /// 喂一次空闲读数或锁屏、睡眠通知。回来时返回要演的那一件 `.welcomeBack`：离开满门槛、或者
    /// 离开期间记下了事（锁屏一小会儿也算）才有；否则 nil。
    /// `focusing`：专注计时正在走。专注时看书、想事情不碰键盘鼠标很正常，空闲读数不算离开
    /// （锁屏、睡眠照样算）。
    public mutating func handle(_ event: PostureAway.Event, at now: Date, focusing: Bool = false) -> DesktopPetEvent? {
        if focusing, !isAway, case .idle = event { return nil }
        guard case .back(let since, let at)? = tracker.handle(event, at: now) else { return nil }
        let held = missed
        missed = []
        guard at.timeIntervalSince(since) >= DesktopPetAssist.awayAfter || !held.isEmpty else { return nil }
        return .welcomeBack(DesktopPetWelcome.summary(held))
    }

    /// 离开着时把这件事记下、先不演（返回 true）；没离开时返回 false，照常交给 `decide`。
    public mutating func hold(_ event: DesktopPetEvent) -> Bool {
        guard isAway else { return false }
        switch event {
        case .fileStored(let count, let widgetID, let ids, _):
            missed.append(.filesStored(count: count, widgetID: widgetID, itemIDs: ids))
        case .focusFinished(let widgetID, _):
            missed.append(.focusFinished(widgetID: widgetID))
        case .shelfExpired(let count, let widgetID):
            missed.append(.filesExpired(count: count, widgetID: widgetID))
        case .downloadFinished(let paths):
            if !paths.isEmpty { missed.append(.downloaded(paths: paths)) }
        case .stretchReminder:
            // 人不在，不提醒，也不记。
            break
        case .welcomeBack:
            return false
        }
        return true
    }
}

// MARK: - 就地提示的动作

extension DesktopPetBrain {
    /// 就地抬头看一眼：吊着的晃大一下（跳的那套晃法），其余的抬头或探头。救回途中、拖着时不理会。
    public static func noticed(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        // 抱树的先爬出来露全身，再说话；没人理约 5 秒缩回去。
        if style == .side { return hugTapped(state, now: now) }
        var next = state
        next.since = now
        next.activity = style == .hang ? .jump(since: now) : .peek(until: now.addingTimeInterval(peekDuration))
        return next
    }

    /// 专注完成：朝 `toward`（计时器那边）转头，看一眼、欢呼一次，再坐着等到 `until`。
    /// 救回途中、拖着时不打断。
    public static func celebrate(_ state: DesktopPetState, toward: Double?, until: Date, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        if let toward { face(&next, toward: toward, now: now) }
        next.activity = .celebrate(since: now, until: max(until, now.addingTimeInterval(DesktopPetAssist.celebrateDuration)))
        next.since = now
        return next
    }

    /// 离开回来：从睡着（或者随便在做什么）抬头探看一眼。吊着的晃一下（抬头那套晃法），
    /// 其余的抬头或探头，同 `noticed`。
    public static func wokeUp(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        if style == .side { return hugTapped(state, now: now) }
        var next = state
        next.since = now
        next.activity = .peek(until: now.addingTimeInterval(peekDuration))
        return next
    }

    /// 活动提醒：伸个懒腰。吊着的不伸懒腰，晃大一下（跳的那套晃法）。救回途中、拖着时不打断。
    public static func stretched(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        next.since = now
        next.activity = style == .hang ? .jump(since: now) : .stretch(since: now)
        return next
    }

    /// 文件拖到身上还没松手：抬头张望等着接（一直探着，直到松手或移开）。救回途中、拖着时不理会。
    public static func expecting(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged, .fileDelivery: return state
        default: break
        }
        var next = state
        if case .peek = state.activity {} else { next.since = now }
        next.activity = .peek(until: now.addingTimeInterval(DesktopPetAssist.expectHold))
        return next
    }

    /// 文件移开了（没松手）：快点趴回去。
    public static func stopExpecting(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        guard case .peek(let until) = state.activity, until > now.addingTimeInterval(0.4) else { return state }
        var next = state
        next.activity = .peek(until: now.addingTimeInterval(0.4))
        return next
    }

    /// 叼到卡片旁：放下纸团（drop 帧播一次）坐好，停在纸团在脚边那一帧，一直坐到「有待查看」结束。
    public static func waitingBeside(_ state: DesktopPetState, until: Date, now: Date) -> DesktopPetState {
        var next = state
        next.activity = .putDown(until: until)
        next.since = now
        return next
    }
}
