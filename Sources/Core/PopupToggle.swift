import CoreGraphics
import Foundation

// 扩展栏弹出小窗（分组窗口、文件夹小窗）点格子时开还是关，以及收起淡出、
// 摆位置失败这些容易让「点了没反应」的边角。只做判断，不碰界面；
// 用的地方在 DockPanel/GroupWindow.swift、FolderBrowserWindow.swift、PopupDismisser.swift。
//
// beta.32 真机反馈「分组有时候点了不弹」，对应这里的几条：
// - 记着「开着的是这个组」但窗口其实没在显示（摆位置失败、被系统收走），
//   点格子会被当成「再点一次关掉」，关的又是一个本来就没显示的窗口，于是一直点不开；
// - 收起的淡出还没走完就又打开（连点、从一个组直接点另一个组），旧的淡出把
//   窗口透明度落回 0，窗口其实开着但看不见；
// - 双击格子：第一下打开，第二下当成「再点一次」或「点外面」又关上，只闪一下。

public enum PopupToggle {

    public enum Decision: Sendable, Equatable {
        /// 打开（或换成）这个格子的小窗。
        case open
        /// 收起开着的这个。
        case close
        /// 什么都不做（刚打开紧接着的连点，或点外面已经收起它的那一下）。
        case ignore
    }

    /// 点格子 `requested` 时怎么办。
    /// - Parameters:
    ///   - openID: 记着开着的是哪个。
    ///   - visible: 小窗此刻真的在屏幕上（`isVisible`，不在淡出收起中）。
    ///   - repeatOfOpen: 这一下是刚打开它的那次点击紧跟着的连点（双击的第二下）。
    ///   - swallow: 点外面收起它的正是这一下（见 `PopupDismissal.ReopenGuard`），
    ///     只在要打开时才问，问了就用掉。
    public static func decide(requested: UUID, openID: UUID?, visible: Bool,
                              repeatOfOpen: Bool, swallow: () -> Bool) -> Decision {
        if openID == requested, visible {
            return repeatOfOpen ? .ignore : .close
        }
        // 记着开着但其实没显示：当没开，直接打开，不去「关」一个看不见的窗口。
        return swallow() ? .ignore : .open
    }

    /// 刚打开紧跟着的连点（双击的第二下、触控板轻点抖出来的两下）不算「再点一次关掉」，
    /// 也不算「点外面」。只认刚才打开时指针附近、很短时间内的点击。
    public struct OpenGrace: Sendable, Equatable {
        /// 半径：双击两下之间指针只会抖一点点。
        public static let radius: CGFloat = 8
        /// 系统「连按速度」可调，夹在这个范围里，免得设得很慢时一直关不掉。
        public static let shortest: TimeInterval = 0.25
        public static let longest: TimeInterval = 0.5

        /// 按系统的双击间隔算这次的宽限时间。
        public static func window(doubleClickInterval: TimeInterval) -> TimeInterval {
            guard doubleClickInterval.isFinite, doubleClickInterval > 0 else { return shortest }
            return min(max(doubleClickInterval, shortest), longest)
        }

        private var last: Entry?

        private struct Entry: Sendable, Equatable {
            var id: UUID
            var at: Date
            var point: CGPoint
            var window: TimeInterval
        }

        public init() {}

        /// 打开了 `id`，那一下点在 `point`。
        public mutating func noteOpened(id: UUID, at: Date, point: CGPoint,
                                        doubleClickInterval: TimeInterval) {
            last = Entry(id: id, at: at, point: point,
                         window: Self.window(doubleClickInterval: doubleClickInterval))
        }

        /// 收起了，之后的点击都不再是连点。
        public mutating func clear() { last = nil }

        /// `at` 时刻在 `point` 的点击是不是刚打开紧跟着的连点。`id` 给了就还要是同一个格子。
        public func isRepeat(id: UUID? = nil, at: Date, point: CGPoint) -> Bool {
            guard let last else { return false }
            if let id, id != last.id { return false }
            let elapsed = at.timeIntervalSince(last.at)
            guard elapsed >= 0, elapsed <= last.window else { return false }
            return hypot(point.x - last.point.x, point.y - last.point.y) <= Self.radius
        }
    }

    /// 收起时的淡出。每次淡出领一个号，打开时作废手上的号：淡出走完时号不对，
    /// 说明中途又打开了，不能把窗口收走，还要把透明度补回 1（旧的淡出可能
    /// 已经把它落到 0，窗口开着却看不见）。
    public struct Fade: Sendable, Equatable {
        public private(set) var generation = 0

        public init() {}

        /// 开始淡出，返回这次的号。
        public mutating func begin() -> Int {
            generation &+= 1
            return generation
        }

        /// 打开了：之前的淡出都作废。
        public mutating func cancel() {
            generation &+= 1
        }

        public enum Finish: Sendable, Equatable {
            /// 收走窗口，透明度复位为 1 留给下次。
            case orderOut
            /// 中途又打开了：窗口留着，透明度补回 1。
            case restore
            /// 都不用管（又被另一次淡出接手了）。
            case nothing
        }

        /// 号为 `token` 的淡出走完了；`isOpen` 是此刻是否记着有东西开着。
        public func finish(_ token: Int, isOpen: Bool) -> Finish {
            if isOpen { return .restore }
            return token == generation ? .orderOut : .nothing
        }
    }

    /// 打开时内容还量不出大小（SwiftUI 这一轮还没排好），窗口摆不上去：
    /// 下一轮再试一次；还不行就放弃，并把「开着的是谁」清掉，下次点击重新打开，
    /// 而不是记着开着、实际没显示。
    public enum Placement: Sendable, Equatable {
        case retry
        case giveUp

        public static let maxAttempts = 2

        /// 第 `attempt` 次（从 1 起）摆失败了。
        public static func afterFailure(attempt: Int) -> Placement {
            attempt < maxAttempts ? .retry : .giveUp
        }
    }
}
