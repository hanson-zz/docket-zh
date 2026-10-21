import AppKit
import SwiftUI
import Observation

/// Carries scroll-wheel deltas from the shelf's panel into its SwiftUI view.
///
/// The panel is the right place to catch them: a view overlaid to receive
/// scrolls must also accept hits, and one that did swallowed every click on
/// the shelf. Unhandled scroll events bubble up the responder chain to the
/// window, so the panel sees them without taking anything away from the tiles.
@MainActor
@Observable
final class ScrollRelay {
    static let shared = ScrollRelay()

    /// Most recent delta along the shelf's long axis.
    private(set) var delta: CGFloat = 0
    /// Bumped per event, so identical deltas still register as a change.
    private(set) var tick: Int = 0

    /// Mirrors the "switch layouts with gestures" setting, written by the
    /// panel's owner whenever the shelf's settings change.
    @ObservationIgnored var switchesLayouts = true
    /// Whether the shelf has anything to scroll. Written by the shelf view,
    /// which is the only thing that knows; a sideways swipe stays a scroll
    /// while there is something to scroll to.
    @ObservationIgnored var isOverflowing = false
    /// Asked to move one layout forward (+1) or back (-1).
    @ObservationIgnored var onLayoutStep: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var layoutGesture = LayoutGesture()

    /// 设置里的「两指滑动打开面板」，和 `switchesLayouts` 一样由面板的主人写。
    @ObservationIgnored var swipeOpensPanels = true
    /// 指针下那一格能用滑动打开面板时是它的 id，否则 nil。扩展栏视图在悬停
    /// 变化时写：只有它知道指针下是什么、那一格有没有面板。
    @ObservationIgnored var swipeTargetID: UUID?
    /// 扩展栏贴的边（浮动时是当作的顶部或底部），决定面板往哪边弹。
    @ObservationIgnored var swipeEdge: DockPosition = .bottom
    @ObservationIgnored private var panelSwipe = PanelSwipeGesture()

    /// 两指滑动要打开或收起面板时发出，userInfo 里 `id` 是指针下那一格的 id，
    /// `open` 是 true 打开、false 收起。扩展栏视图接，那里才有锚点和面板。
    nonisolated static let panelSwipeRequest = Notification.Name("DocketPanelSwipeRequest")

    private init() {}

    /// 喂一次滚动事件给开面板的手势。返回这次事件是否归它（归它就吞掉）。
    func feedPanelSwipe(_ event: PanelSwipe.Event) -> Bool {
        let target = swipeTargetID
        let outcome = panelSwipe.feed(event, edge: swipeEdge, target: target != nil,
                                      enabled: swipeOpensPanels)
        switch outcome {
        case .pass:
            return false
        case .consume:
            return true
        case .fire(let action):
            if let target {
                NotificationCenter.default.post(name: Self.panelSwipeRequest, object: nil,
                                                userInfo: ["id": target, "open": action == .open])
            }
            return true
        }
    }

    func push(_ value: CGFloat) {
        delta = value
        tick &+= 1
    }

    func beginLayoutGesture() {
        layoutGesture.begin()
    }

    func feedLayoutGesture(_ delta: CGFloat, precise: Bool, at time: TimeInterval) {
        guard let step = layoutGesture.feed(Double(delta), precise: precise, at: time) else { return }
        onLayoutStep?(step)
    }

    /// Points to move the shelf for one scroll event.
    ///
    /// Whichever axis the gesture favours drives the shelf, on either
    /// orientation: a mouse wheel only ever reports Y, and a two-finger swipe
    /// across a side shelf is as natural as one along it.
    ///
    /// A trackpad reports precise deltas already in points, so those map
    /// straight through. A mouse wheel reports *notches* - passing a delta of
    /// 1 through unscaled would creep the shelf one point per click.
    nonisolated static func step(dx: CGFloat, dy: CGFloat, precise: Bool) -> CGFloat {
        let delta = abs(dx) > abs(dy) ? dx : dy
        return precise ? delta : delta * 16
    }
}

/// Hosting view that handles the scroll wheel itself.
///
/// Event monitors are the wrong tool here, and the panel is too far up. A
/// *local* monitor only sees events routed to this app, and a non-activating
/// panel belonging to an accessory agent is often not the event target - macOS
/// hands the scroll to whatever is underneath, so it never fires. A *global*
/// monitor always sees it but needs Accessibility permission and cannot
/// consume, so the window behind scrolls too. Overriding the panel does
/// nothing either, because `NSHostingView` swallows the event before it can
/// walk up the responder chain.
///
/// Handling it on the hosting view itself is the one place it reliably
/// arrives, and not calling `super` consumes it so nothing behind moves.
final class ScrollingHostingView<Content: View>: NSHostingView<Content> {

    override func scrollWheel(with event: NSEvent) {
        if swipedPanel(event) { return }
        if switchedLayout(event) { return }
        let step = ScrollRelay.step(dx: event.scrollingDeltaX,
                                    dy: event.scrollingDeltaY,
                                    precise: event.hasPreciseScrollingDeltas)
        guard step != 0 else {
            super.scrollWheel(with: event)
            return
        }
        ScrollRelay.shared.push(step)
    }

    /// 指针在小组件（或分组、文件夹）上，两指沿面板弹出方向滑：打开它的面板，
    /// 反方向收起。只看扩展栏的短轴，判断和门槛在 Core（`PanelSwipeGesture`）。
    /// 返回事件是否被它拿走；不归它的手势原样往下走，切换布局和滚动照旧。
    private func swipedPanel(_ event: NSEvent) -> Bool {
        let swipe = PanelSwipe.Event(
            dx: Double(event.scrollingDeltaX),
            dy: Double(event.scrollingDeltaY),
            precise: event.hasPreciseScrollingDeltas,
            inverted: event.isDirectionInvertedFromDevice,
            began: event.phase.contains(.began) || event.phase.contains(.mayBegin),
            momentum: !event.momentumPhase.isEmpty,
            phased: !event.phase.isEmpty,
            command: event.modifierFlags.contains(.command),
            time: event.timestamp)
        return ScrollRelay.shared.feedPanelSwipe(swipe)
    }

    /// Command-scroll, or a sideways swipe over a shelf with nothing to
    /// scroll, changes layout instead of scrolling. Returns whether the event
    /// was taken for that.
    ///
    /// Plain scrolling is untouched: without Command a vertical scroll, and
    /// any scroll over an overflowing shelf, falls through to the code above.
    private func switchedLayout(_ event: NSEvent) -> Bool {
        let relay = ScrollRelay.shared
        guard relay.switchesLayouts else { return false }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        let command = event.modifierFlags.contains(.command)
        let sideways = precise && !relay.isOverflowing
            && LayoutGesture.isSideways(dx: Double(dx), dy: Double(dy))
        guard command || sideways else { return false }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            relay.beginLayoutGesture()
        }
        // The momentum tail is still swallowed, or the shelf behind would
        // scroll on after the switch, but it never counts towards a step: the
        // fingers have already decided.
        if event.momentumPhase.isEmpty {
            let delta = command ? (abs(dx) > abs(dy) ? dx : dy) : dx
            relay.feedLayoutGesture(delta, precise: precise, at: event.timestamp)
        }
        return true
    }

    /// Keeps the panel the size SwiftUI wants.
    ///
    /// `NSHostingController` does this for you; using the view directly does
    /// not, and skipping it collapsed the shelf window to zero.
    /// Reports the size SwiftUI wants; the panel's owner decides where that
    /// size sits. Setting it here kept the old origin, so the shelf grew out
    /// of a corner and was re-centred a step later.
    var onWantedSize: ((CGSize) -> Void)?

    override func layout() {
        super.layout()
        let wanted = fittingSize
        guard let window, wanted.width > 1, wanted.height > 1 else { return }
        let current = window.frame.size
        guard abs(current.width - wanted.width) > 0.5
                || abs(current.height - wanted.height) > 0.5 else { return }
        onWantedSize?(wanted)
    }
}
