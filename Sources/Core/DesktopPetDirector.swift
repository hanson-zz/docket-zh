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
// 以后加事件（专注结束、离开回来）：在 `DesktopPetEvent` 加一种，`decide` 里给它一条规则。

// MARK: - 事件

/// 码头里发生的、小熊猫要回应的事。
public enum DesktopPetEvent: Equatable, Sendable {
    /// 文件暂存成功：`count` 个文件放进了 `widgetID` 那张文件暂存卡片，`newItemIDs` 是新条目
    /// 的标识（暂存清单里的路径），`at` 是松手的位置（屏幕坐标，左下原点）。
    case fileStored(count: Int, widgetID: UUID, newItemIDs: [String], at: CGPoint)
    /// 预留：专注结束。第一版不处理。
    case focusFinished
    /// 预留：离开一阵又回来了。第一版不处理。
    case welcomeBack

    /// 排队时同一类只留一件。
    public var kind: String {
        switch self {
        case .fileStored: "fileStored"
        case .focusFinished: "focusFinished"
        case .welcomeBack: "welcomeBack"
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

    public init(now: Date, settling: Bool, track: DesktopPetTrack?, petX: Double, sameScreen: Bool,
                scale: Double = 1, recent: DesktopPetErrand? = nil) {
        self.now = now
        self.settling = settling
        self.track = track
        self.petX = petX
        self.sameScreen = sameScreen
        self.scale = scale
        self.recent = recent
    }
}

public enum DesktopPetDirector {
    /// 一件事怎么回应。
    public static func decide(_ event: DesktopPetEvent, context: DesktopPetDirectorContext) -> DesktopPetReaction {
        guard case .fileStored(let count, let widgetID, let ids, let point) = event,
              let track = context.track else { return .ignore }
        if context.settling { return .queue }
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
        return queue.filter { $0.kind != event.kind } + [incoming]
    }
}

// MARK: - 有待查看

/// 叼到了（或就地提示过）：坐在那里等你看一眼。被点、拖走、来了新事件、超时都结束。
public struct DesktopPetReview: Equatable, Sendable {
    public var widgetID: UUID
    public var itemIDs: [String]
    public var count: Int
    public var until: Date

    public init(_ errand: DesktopPetErrand, now: Date, duration: TimeInterval = DesktopPetAssist.reviewDuration) {
        widgetID = errand.widgetID
        itemIDs = errand.itemIDs
        count = errand.count
        until = now.addingTimeInterval(duration)
    }

    public func expired(at now: Date) -> Bool { now >= until }

    public var text: String { DesktopPetAssist.storedText(count) }
}

// MARK: - 就地提示的动作

extension DesktopPetBrain {
    /// 就地抬头看一眼：吊着的晃大一下（跳的那套晃法），其余的抬头或探头。救回途中、拖着时不理会。
    public static func noticed(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        next.since = now
        next.activity = style == .hang ? .jump(since: now) : .peek(until: now.addingTimeInterval(peekDuration))
        return next
    }

    /// 叼到卡片旁：放下坐好，一直坐到「有待查看」结束。
    public static func waitingBeside(_ state: DesktopPetState, until: Date, now: Date) -> DesktopPetState {
        var next = state
        next.activity = .idle(until: until)
        next.since = now
        return next
    }
}
