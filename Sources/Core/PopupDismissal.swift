import CoreGraphics
import Foundation

// 扩展栏弹出小窗（分组窗口、文件夹小窗，以及复用文件夹小窗的其他弹窗）
// 什么时候收起、什么时候不收：点窗口外面、按 Esc、再点一次格子。
// 这里只做判断，不碰界面；监听鼠标和键盘的部分在 DockPanel/PopupDismisser.swift。

public enum PopupDismissal {

    // MARK: 点外面

    /// 按下的是哪个键。
    public enum Button: Sendable, Equatable {
        case primary
        case secondary
        case other
    }

    /// 按下鼠标那一刻的情况。
    public struct Press: Sendable, Equatable {
        public var button: Button
        /// 点在小窗自己（看得见的那块）或它的子窗口里。
        public var inPopup: Bool
        /// 点在快速查看面板上（包括它的关闭按钮）。
        public var inQuickLook: Bool
        /// 快速查看面板开着。
        public var quickLookOpen: Bool
        /// 本 App 的菜单（小窗的右键菜单、排序菜单）正开着。
        public var menuOpen: Bool
        /// 提示框（比如确认移到废纸篓）或别的子弹窗开着。
        public var modalOpen: Bool
        /// 正在把东西拖进、拖出小窗。
        public var dragging: Bool

        public init(button: Button = .primary, inPopup: Bool = false, inQuickLook: Bool = false,
                    quickLookOpen: Bool = false, menuOpen: Bool = false, modalOpen: Bool = false,
                    dragging: Bool = false) {
            self.button = button
            self.inPopup = inPopup
            self.inQuickLook = inQuickLook
            self.quickLookOpen = quickLookOpen
            self.menuOpen = menuOpen
            self.modalOpen = modalOpen
            self.dragging = dragging
        }
    }

    public enum PressDecision: Sendable, Equatable {
        /// 不管这次点击。
        case ignore
        /// 马上收起（右键、中键：右键菜单会吃掉松开那一下，等不到）。
        case dismissNow
        /// 等松开再看：按住拖走了就是拖拽（比如从访达往小窗里拖文件），不收；
        /// 原地松开才算点了一下。
        case dismissOnRelease
    }

    /// 按下鼠标时怎么办。点击本身照常交给被点的东西，这里只决定小窗收不收。
    public static func press(_ press: Press) -> PressDecision {
        if press.inPopup || press.inQuickLook { return .ignore }
        // 快速查看开着时整个不收：点空白处是在和快速查看打交道，关它也不连带收小窗。
        if press.quickLookOpen || press.menuOpen || press.modalOpen || press.dragging { return .ignore }
        return press.button == .primary ? .dismissOnRelease : .dismissNow
    }

    /// 按住移动超过这么多（点）就算拖拽，不算点击。
    public static let dragThreshold: CGFloat = 4

    public enum ReleaseDecision: Sendable, Equatable {
        /// 还按着，没移动多少，接着等。
        case wait
        /// 拖走了，这次不收。
        case cancel
        /// 原地松开了，收起。
        case dismiss
    }

    /// 等松开的这段时间里每次看一眼：从 `start` 按下，现在指针在 `current`。
    /// `buttonDown` 是左键是否还按着，`blocked` 是期间是否出现了不该收的情况
    /// （拖拽开始、快速查看打开、菜单或提示框弹出）。
    public static func release(start: CGPoint, current: CGPoint, buttonDown: Bool,
                               blocked: Bool = false) -> ReleaseDecision {
        if blocked { return .cancel }
        if hypot(current.x - start.x, current.y - start.y) > dragThreshold { return .cancel }
        return buttonDown ? .wait : .dismiss
    }

    // MARK: Esc

    /// 按 Esc 时的情况。
    public struct Escape: Sendable, Equatable {
        /// 输入法正在组字：Esc 是取消组字，交给输入法。
        public var composing: Bool
        /// 本 App 的菜单正开着：Esc 关菜单。
        public var menuOpen: Bool
        /// 正在拖拽：Esc 取消拖拽。
        public var dragging: Bool
        /// 快速查看面板开着：先关它。
        public var quickLookOpen: Bool
        /// 小窗里有能先退一步的东西：搜索框里有字或正在输入、改名框正在编辑、
        /// 展开着的选择列表。
        public var inner: Bool

        public init(composing: Bool = false, menuOpen: Bool = false, dragging: Bool = false,
                    quickLookOpen: Bool = false, inner: Bool = false) {
            self.composing = composing
            self.menuOpen = menuOpen
            self.dragging = dragging
            self.quickLookOpen = quickLookOpen
            self.inner = inner
        }
    }

    public enum EscapeDecision: Sendable, Equatable {
        /// 不处理，交给系统（输入法、菜单、拖拽）。
        case pass
        /// 关掉快速查看，小窗留着。
        case closeQuickLook
        /// 先退一步：清空并退出搜索、撤销改名、收起选择列表。小窗留着。
        case backOut
        /// 收起小窗。
        case dismiss
    }

    public static func escape(_ escape: Escape) -> EscapeDecision {
        if escape.composing || escape.menuOpen || escape.dragging { return .pass }
        if escape.quickLookOpen { return .closeQuickLook }
        if escape.inner { return .backOut }
        return .dismiss
    }

    // MARK: 再点一次格子

    /// 点外面收起和格子自己的「再点一次就关」撞在一起时的保护。
    ///
    /// 点开着的那个格子：按下时它算「外面」，松开时收起；格子的点按也在松开时
    /// 触发，看到小窗已经关了就会再打开它。所以记下刚因为点外面收起的是谁、
    /// 在哪儿点的，同一个格子紧接着的打开请求就吞掉，结果是收起而不是闪一下又开。
    public struct ReopenGuard: Sendable, Equatable {
        /// 这么久以内的打开请求才可能是同一次点击。
        public static let window: TimeInterval = 0.8
        /// 指针离收起时那一下不超过这么远。
        public static let radius: CGFloat = 8

        private var last: Entry?

        private struct Entry: Sendable, Equatable {
            var id: UUID
            var at: Date
            var point: CGPoint
        }

        public init() {}

        /// 因为点外面收起了 `id`。
        public mutating func noteDismissed(id: UUID?, at: Date, point: CGPoint) {
            last = id.map { Entry(id: $0, at: at, point: point) }
        }

        /// 要打开 `id`：是不是刚才那次点击带出来的，是就吞掉（只吞一次）。
        public mutating func swallowsOpen(id: UUID, at: Date, point: CGPoint) -> Bool {
            guard let entry = last else { return false }
            last = nil
            guard entry.id == id else { return false }
            let elapsed = at.timeIntervalSince(entry.at)
            guard elapsed >= 0, elapsed <= Self.window else { return false }
            return hypot(point.x - entry.point.x, point.y - entry.point.y) <= Self.radius
        }
    }
}
