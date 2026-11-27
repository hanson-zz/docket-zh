import AppKit
import SwiftUI
import os

/// 面板内容比面板宽时记一条（见 `DetailPanelWidth`），方便在控制台里抓到撑宽的面板。
private let detailWidthLog = Logger(subsystem: "com.docket-zh.app", category: "detail-width")

/// A widget's detail panel: what opens when its tile is clicked.
///
/// This is the shape the reference shelf takes and the one thing the tiles
/// were missing. A tile is a glance - a temperature, a percentage, a title -
/// and the panel is where the same widget says everything it knows: the whole
/// day's events rather than the next one, every battery rather than the Mac's,
/// a chart behind the number.
///
/// Its own window for the same reason the hover label and an opened group have
/// theirs: drawing it inside the shelf would mean reserving space for the
/// largest panel any widget might want.
@MainActor
final class WidgetDetailWindow {
    static let shared = WidgetDetailWindow()

    /// Which widget is showing, so clicking its tile again closes it.
    private(set) var openWidgetID: UUID?

    private var panel: KeyablePanel?
    private var hosting: FirstMouseHostingView<WidgetDetailChrome>?
    /// Watches for the click that dismisses it - one monitor for clicks
    /// landing in another app, one for clicks landing in this one.
    private var monitors: [Any] = []
    /// The shelf's own frame, which the dismissal watcher ignores.
    ///
    /// The shelf already decides what a click on it means - the same tile
    /// toggles this shut, another widget swaps it, an app tile closes it. A
    /// monitor closing it first would let the tile's own tap reopen it on the
    /// very same press.
    private var host: CGRect = .zero
    /// Changes on every open, to replay the entrance.
    private var session = UUID()
    /// What the open panel was shown with, so a config change underneath it
    /// can be redrawn without reopening it.
    private var shown: (context: WidgetContext, edge: DockPosition,
                        arrowOffset: CGFloat)?
    /// 开着的面板：小组件、它的尾巴指向的点、面板宽、滚动区里内容的自然
    /// 高度、底部“外观”栏的自然高度（都不含尾巴），和当前分给滚动区、外观栏
    /// 的高度。内容或外观栏变高变矮时按这些重新摆窗口。
    private var fit: (instance: WidgetInstance, anchor: CGPoint, width: CGFloat,
                      content: CGFloat, footer: CGFloat,
                      viewports: DetailPanelFit.Viewports, overflows: Bool)?
    private var screenObserver: NSObjectProtocol?
    /// 面板窗口挪动、变大小时检查是否还在屏幕里，见 `keepOnScreen`。
    private var frameObservers: [NSObjectProtocol] = []
    /// 收起时的淡出领号，淡出途中又打开就作废，见 `PopupToggle.Fade`。
    private var fade = PopupToggle.Fade()

    private init() {}

    /// 面板关上，或者换成了另一个小组件的面板。`object` 是原来那个小组件的 id。
    static let didClose = Notification.Name("com.docket-zh.widget-detail.did-close")

    var isOpen: Bool { openWidgetID != nil && panel?.isVisible == true }

    /// 开着的面板不挂在扩展栏的卡片上，而是独立浮在屏幕顶部（点弹出卡片主体时，
    /// 卡片在别的布局里、扩展栏没开或卡片被条件隐藏）。这样的面板不把自动隐藏的
    /// 扩展栏钉住，扩展栏滑走、跟着灵动提示挪动时它也不动。
    private(set) var isFloating = false

    /// 开着、挂在扩展栏上的面板。
    var isAnchoredOpen: Bool { isOpen && !isFloating }

    /// 扩展栏收起或滑走时调用：只收挂在它上面的那种。
    func closeIfAnchored() {
        if !isFloating { close() }
    }

    /// 以独立浮动面板打开：挂在带菜单栏那块屏幕的顶部正中，也就是到点弹出卡片
    /// 刚才的位置，尾巴朝上。已经开着同一个就不动。
    func openFloating(_ instance: WidgetInstance, now: Date) {
        guard openWidgetID != instance.id || !isOpen else { return }
        guard let screen = NSScreen.screens.first else { return }
        // 按让出菜单栏后的区域挂：菜单栏自动隐藏时 visibleFrame 伸到屏幕顶边，
        // 尾巴会指到菜单栏底下。
        let visible = Self.usableFrame(of: screen, isMain: true)
        let anchor = CGPoint(x: visible.midX, y: visible.maxY - 6)
        show(instance, context: WidgetContext(position: .top, now: now), anchor: anchor, edge: .top,
             host: .zero, floating: true)
    }

    /// 开着的面板的中心点（屏幕坐标），关着时为 nil。
    var openCenter: CGPoint? {
        guard isOpen, let frame = panel?.frame else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The tile the last panel grew from, kept so a panel that closed itself
    /// for a moment (AI 助手 hiding while the app chooser is up) can come back
    /// pointing at the same tile, rather than at whichever tile the pointer
    /// last crossed on its way back.
    private var lastShownAnchor: (id: UUID, point: CGPoint)?

    func lastAnchor(for id: UUID) -> CGPoint? {
        lastShownAnchor?.id == id ? lastShownAnchor?.point : nil
    }

    private func announceClosed(_ id: UUID) {
        NotificationCenter.default.post(name: Self.didClose, object: id)
    }

    /// Moves the open panel up or down with a top shelf stepping aside for
    /// 灵动提示, inside the shelf's own animation. See
    /// DockPanelController.islandMoved.
    func shift(by dy: CGFloat) {
        guard isAnchoredOpen, let panel, dy != 0 else { return }
        panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: dy), display: false)
        // The shelf moved with it, and a click on the shelf is still the
        // shelf's to handle.
        host = host.offsetBy(dx: 0, dy: dy)
        // 小组件也跟着挪了，之后内容变高重新摆窗口时要从新位置算。
        if var moved = fit {
            moved.anchor.y += dy
            fit = moved
        }
    }

    func toggle(_ instance: WidgetInstance, context: WidgetContext,
                anchor: CGPoint, edge: DockPosition, host: CGRect) {
        if openWidgetID == instance.id { return close() }
        show(instance, context: context, anchor: anchor, edge: edge, host: host, floating: false)
    }

    /// Redraws the open panel after its widget's config changed.
    ///
    /// The panel is handed a `WidgetInstance` by value, so a tile that edits
    /// its own config - the stocks chevron stepping to the next symbol, a
    /// setting changed while the panel is up - left the two disagreeing until
    /// it was closed and reopened. Every widget write funnels through
    /// `WidgetWriter`, which is where this is called from.
    ///
    /// Deliberately keeps `session`, so the entrance does not replay. 宽度
    /// 每种固定；改设置让内容变高或变矮时，滚动区域里的内容报告新高度，
    /// `partChanged` 再重新摆窗口，不用关了重开。
    func refresh(_ instance: WidgetInstance) {
        guard openWidgetID == instance.id, let shown, var current = fit else { return }
        // 面板宽跟着配置变了（纪念日换卡片样式）：重新量一遍、
        // 按新宽度重摆窗口。原来宽度只在打开时量，换宽后内容被裁或两边空一截。
        if abs(WidgetDetail.width(instance) - WidgetDetail.width(current.instance)) >= 0.5 {
            return rewidth(instance, context: shown.context, edge: shown.edge, anchor: current.anchor)
        }
        current.instance = instance
        fit = current
        hosting?.rootView = chrome(instance, context: shown.context, edge: shown.edge,
                                   arrowOffset: shown.arrowOffset, viewports: current.viewports,
                                   overflows: current.overflows)
    }

    /// 宽度变了：量新内容的自然尺寸，按它重摆（位置仍夹在屏幕里，高度仍受上限）。
    private func rewidth(_ instance: WidgetInstance, context: WidgetContext, edge: DockPosition,
                         anchor: CGPoint) {
        let size = measure(instance, context: context, edge: edge)
        guard size.width > 1, size.height > 1 else { return }
        let footer = min(measureFooter(instance, context: context, edge: edge),
                         max(0, size.height - tailHeight(edge)))
        place(instance, context: context, edge: edge, anchor: anchor, width: size.width,
              content: max(0, size.height - tailHeight(edge) - footer), footer: footer)
    }

    /// 模型里这个小组件变了（`AppState` 每次改动都会调）：配置和面板手里的
    /// 不一样时才重画，一样时不动，免得每次改模型都换一遍根视图。
    func follow(_ instance: WidgetInstance) {
        guard openWidgetID == instance.id, let current = fit, current.instance != instance else { return }
        refresh(instance)
    }

    /// 面板的根视图，每次都从这里造，免得哪一处漏了滚动区域的高度或回调。
    private func chrome(_ instance: WidgetInstance, context: WidgetContext, edge: DockPosition,
                        arrowOffset: CGFloat, viewports: DetailPanelFit.Viewports?,
                        overflows: Bool) -> WidgetDetailChrome {
        let opened = session
        return WidgetDetailChrome(
            instance: instance, context: context, edge: edge, session: opened,
            arrowOffset: arrowOffset, viewports: viewports, overflows: overflows,
            // 放到下一轮再摆窗口：回调来自 SwiftUI 的布局，在布局中途换根视图
            // 和改窗口大小会让 AppKit 重入布局。
            onContentHeight: { [weak self] height in
                Task { @MainActor in self?.partChanged(content: height, session: opened) }
            },
            onFooterHeight: { [weak self] height in
                Task { @MainActor in self?.partChanged(footer: height, session: opened) }
            })
    }

    /// 量内容的自然尺寸：不带滚动区域，在一个不进窗口的临时视图里量，
    /// 不动正在显示的那个，里面小组件的状态不会因此重置。
    private func measure(_ instance: WidgetInstance, context: WidgetContext,
                         edge: DockPosition) -> CGSize {
        let probe = NSHostingView(rootView: WidgetDetailChrome(
            instance: instance, context: context, edge: edge, session: session,
            measuring: true))
        return probe.fittingSize
    }

    /// 单独量底部“外观”栏的自然高度，好把它从整块内容里分出来钉在底部。
    /// 这张卡片没有外观入口时是 0。
    private func measureFooter(_ instance: WidgetInstance, context: WidgetContext,
                               edge: DockPosition) -> CGFloat {
        guard WidgetDetailChrome.offersAppearance(instance, context) else { return 0 }
        let probe = NSHostingView(rootView: WidgetDetailChrome(
            instance: instance, context: context, edge: edge, session: session,
            measuring: true, measuringFooter: true))
        // 量的是整个外框，横排扩展栏时含尾巴，扣掉。
        return max(0, probe.fittingSize.height - tailHeight(edge))
    }

    /// 一块屏幕上面板能用的区域：visibleFrame，顶上再确保让出菜单栏（菜单栏
    /// 自动隐藏时 visibleFrame 不扣它）。“每个显示器有单独的空间”打开时
    /// 每块屏幕都有菜单栏，关掉时只有主屏有。
    static func usableFrame(of screen: NSScreen, isMain: Bool) -> CGRect {
        let hasMenuBar = NSScreen.screensHaveSeparateSpaces || isMain
        let menuBar = hasMenuBar ? max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) : 0
        return DetailPanelFit.usableArea(visible: screen.visibleFrame, screen: screen.frame,
                                         menuBar: menuBar)
    }

    /// 面板所在屏幕的可用区域：按小组件那个点找屏幕，不按面板原点找。
    private func visibleFrame(for anchor: CGPoint) -> CGRect? {
        let screens = NSScreen.screens
        if let index = DetailPanelFit.screenIndex(for: anchor, screens: screens.map(\.frame)) {
            return Self.usableFrame(of: screens[index], isMain: index == 0)
        }
        return NSScreen.main.map { Self.usableFrame(of: $0, isMain: $0 == screens.first) }
    }

    /// 尾巴在上下方向占的高度（只有横排扩展栏的尾巴占）。
    private func tailHeight(_ edge: DockPosition) -> CGFloat {
        edge.isHorizontal ? PanelShape.arrowDepth : 0
    }

    /// 滚动区里的内容或底部外观栏报告了新高度：日程、提醒、行情这类打开后
    /// 才读到的数据，面板里展开了一段，或者外观展开、收起。重新算尺寸和
    /// 位置，窗口跟着变，高度仍不超过上限。
    private func partChanged(content: CGFloat? = nil, footer: CGFloat? = nil, session opened: UUID) {
        guard opened == session, isOpen, let shown, var current = fit else { return }
        let old = current.content + current.footer
        if let content { current.content = content }
        if let footer { current.footer = footer }
        guard DetailPanelFit.needsRefit(old: old, new: current.content + current.footer) else { return }
        fit = current
        place(current.instance, context: shown.context, edge: shown.edge,
              anchor: current.anchor, width: current.width,
              content: current.content, footer: current.footer)
    }

    /// 窗口一旦超出所在屏幕的可用区域（减边距），夹回去：高度不超过可用高度，
    /// 位置整个落在里面。正常情况下 place() 已经算好，这里只是兜底。
    private func keepOnScreen() {
        guard let panel, isOpen, let current = fit,
              let visible = visibleFrame(for: current.anchor) else { return }
        let fixed = DetailPanelFit.contain(panel.frame, in: visible)
        guard fixed != panel.frame else { return }
        if fixed.height < panel.frame.height - 0.5, let shown {
            // 太高：整套重算，滚动区和外观栏的高度跟着变，不是硬切窗口。
            place(current.instance, context: shown.context, edge: shown.edge,
                  anchor: current.anchor, width: current.width,
                  content: current.content, footer: current.footer)
            if let again = self.panel, DetailPanelFit.contain(again.frame, in: visible) == again.frame { return }
        }
        panel.setFrame(fixed, display: panel.isVisible)
    }

    /// 显示器插拔、分辨率、菜单栏或系统程序坞变了：按新的可用区域重摆。
    private func screensChanged() {
        guard isOpen, let shown, let current = fit else { return }
        place(current.instance, context: shown.context, edge: shown.edge,
              anchor: current.anchor, width: current.width,
              content: current.content, footer: current.footer)
    }

    /// 按自然尺寸算出 frame，换上对应滚动高度的根视图，摆好窗口。`content`
    /// 和 `footer` 是滚动区内容和外观栏的自然高度，都不含尾巴。
    private func place(_ instance: WidgetInstance, context: WidgetContext, edge: DockPosition,
                       anchor: CGPoint, width: CGFloat, content: CGFloat, footer: CGFloat) {
        guard let panel, let visible = visibleFrame(for: anchor) else { return }
        let natural = CGSize(width: width, height: content + footer + tailHeight(edge))
        let placement = DetailPanelFit.place(edge: edge, anchor: anchor, natural: natural,
                                             visible: visible,
                                             capped: !DetailPanelFit.isCapExempt(instance.kind))
        let frame = placement.frame
        let viewports = DetailPanelFit.viewports(panelHeight: frame.height, edge: edge,
                                                 tailDepth: PanelShape.arrowDepth, footer: footer)
        // Only now is the tail's offset knowable: clamping against the end of
        // the screen moves the panel but not the tile, and a tail still
        // pointing at the panel's own middle would point at nothing.
        // Screen y counts up and the panel's own coordinates count down, so
        // the sign flips on a side shelf; see Geometry.popupTailOffset.
        let offset = Geometry.popupTailOffset(edge: edge, anchor: anchor,
                                              placed: frame.origin, size: frame.size)
        shown = (context, edge, offset)
        fit = (instance, anchor, width, content, footer, viewports, placement.overflows)
        hosting?.rootView = chrome(instance, context: context, edge: edge,
                                   arrowOffset: offset, viewports: viewports,
                                   overflows: placement.overflows)
        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible)
        }
    }

    /// Closes on the next click outside the panel and its own tile.
    ///
    /// The panel used to close when the *pointer* left it, on a half-second
    /// timer - which is why it needed a close button: a panel that vanishes
    /// because you looked away is one you cannot trust to stay. Nothing on
    /// this platform behaves that way. A popover waits for a click.
    private func watchForDismissal() {
        stopWatching()
        let dismiss: (NSEvent) -> Void = { [weak self] event in
            guard let self, let panel = self.panel else { return }
            // 面板底部“外观”里的自定义取色打开的是系统颜色面板，在那里点
            // 颜色不算点到外面。
            if event.window is NSColorPanel { return }
            // A local event reports a window-relative location; a global one
            // is already on screen.
            let point = event.window?.convertPoint(toScreen: event.locationInWindow)
                ?? NSEvent.mouseLocation
            guard !panel.frame.contains(point),
                  !self.host.contains(point) else { return }
            self.close()
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: dismiss) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            dismiss(event)
            return event
        }) { monitors.append(local) }
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// 先让面板成为 key 再聚焦输入框：非 key 的面板不接受文字输入，
    /// 空状态的“添加”按钮直接设焦点可能点了没反应。
    func focusField(_ focus: @escaping @MainActor () -> Void) {
        panel?.makeKey()
        Task { @MainActor in focus() }
    }

    func close() {
        guard let closing = openWidgetID else { return }
        openWidgetID = nil
        announceClosed(closing)
        SystemColorPanel.shared.closeIfOwned()
        shown = nil
        fit = nil
        stopWatching()
        guard let closing = panel, closing.isVisible else { return }
        let token = fade.begin()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            closing.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let current = self.panel else { return }
                // 淡出途中又点开了（同一个或另一个小组件）：不收，透明度补回 1。
                // 以前这里直接返回，旧淡出已经把窗口落到 0，面板开着却看不见。
                switch self.fade.finish(token, isOpen: self.openWidgetID != nil) {
                case .orderOut:
                    current.orderOut(nil)
                    current.alphaValue = 1
                case .restore:
                    current.alphaValue = 1
                case .nothing:
                    break
                }
            }
        }
    }

    private func show(_ instance: WidgetInstance, context: WidgetContext,
                      anchor: CGPoint, edge: DockPosition, host: CGRect, floating: Bool,
                      rebuilt: Bool = false) {
        let panel = existingOrNew()
        session = UUID()
        self.host = host
        // 没有悬停位置时 anchor 是零点，面板会甩到主屏左下角；改用扩展栏
        // 开口那一侧的中点。
        let anchor = anchor == .zero && host != .zero
            ? DetailPanelFit.fallbackAnchor(edge: edge, shelf: host) : anchor

        let size = measure(instance, context: context, edge: edge)
        // Claimed only once there is something to show. Setting it above the
        // guard meant a bail here left the widget marked open with no window,
        // and `toggle` would then answer every later click by closing a panel
        // that was never up.
        guard size.width > 1, size.height > 1 else { return }
        if let previous = openWidgetID, previous != instance.id {
            announceClosed(previous)
            // 换到别的卡片：上一张卡片打开的颜色面板收起，不再往它身上写。
            SystemColorPanel.shared.closeIfOwned()
        }
        openWidgetID = instance.id
        isFloating = floating
        lastShownAnchor = (instance.id, anchor)

        // Almost touching the tile: the panel's own padding already includes
        // the tail's depth, so this is the gap between the tail's tip and the
        // tile, not between the tile and the body. Below the tile on a top
        // shelf, above it on a bottom one. 高度不超过统一上限（约 560pt、
        // 屏幕的六成）和所在屏幕的可用区域，超出的部分在面板里滚动；见
        // DetailPanelFit。
        let footer = min(measureFooter(instance, context: context, edge: edge),
                         max(0, size.height - tailHeight(edge)))
        place(instance, context: context, edge: edge, anchor: anchor, width: size.width,
              content: max(0, size.height - tailHeight(edge) - footer), footer: footer)

        // 上一次收起的淡出可能还在走：作废它的号，并用一段零时长动画顶掉它，
        // 不然面板摆好、排到最前，最后却停在透明度 0。
        fade.cancel()
        panel.showOpaqueCancellingFade()
        panel.orderFrontRegardless()
        // 系统把窗口钉在了另一个桌面：丢掉它，在新窗口里重摆，新窗口落在当前桌面。
        if PanelSpaceRescue.shouldRebuild(isOnActiveSpace: panel.isOnActiveSpace, alreadyRebuilt: rebuilt) {
            discardPanel()
            return show(instance, context: context, anchor: anchor, edge: edge, host: host,
                        floating: floating, rebuilt: true)
        }
        // A panel carrying a text field or a slider needs the keyboard, and a
        // borderless window is refused key status without the override.
        panel.makeKey()
        watchForDismissal()
    }

    /// 收走并放掉当前窗口，下次 `existingOrNew` 造一个新的。用 orderOut 不用
    /// close：close 掉的面板可能被 AppKit 释放，而这里还拿着它。
    private func discardPanel() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers.removeAll()
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(
            rootView: WidgetDetailChrome(instance: WidgetInstance(kind: .clock,
                                                                  config: WidgetConfig()),
                                         context: WidgetContext(),
                                         edge: .bottom, session: session))
        // 窗口大小只由 place() 按所在屏幕算出来定。原来是 .intrinsicContentSize：
        // 内容的固有高度在自动布局里优先级比窗口“保持原尺寸”高，内容一变高，
        // AppKit 就按原点往上把窗口撑高，顶上一截跑出屏幕，绕过了限高。
        hosting.sizingOptions = []

        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

        self.panel = panel
        self.hosting = hosting
        // 兜底：不管谁改了窗口（系统、自动布局、别的代码），只要超出所在屏幕
        // 的可用区域就立刻拉回来，面板任何时候都不出屏幕。
        frameObservers = [NSWindow.didResizeNotification, NSWindow.didMoveNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepOnScreen() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
        return panel
    }
}

/// What every detail panel is wrapped in: the surface, its outline, and the
/// tail pointing back at the tile.
///
/// There is no header at all. It carried the widget's name, a settings button
/// and a close button, and each has somewhere better to be - the tail says
/// which tile this belongs to, settings are in that tile's context menu, and
/// it closes on a click outside, on Escape or on Command-W. A close button is
/// what you add when you do not trust the dismissal, and it was the first
/// thing that made this read as a web dialog rather than a Mac window.
struct WidgetDetailChrome: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var edge: DockPosition
    /// Identifies one opening, so the entrance replays each time.
    var session: UUID
    /// How far the tile's centre is from the panel's along the shelf. Zero
    /// until the panel is clamped against the end of the screen, after which
    /// the tail has to reach back toward the tile.
    var arrowOffset: CGFloat = 0
    /// 滚动区域和底部钉住的“外观”栏各多高，由窗口按所在屏幕算好给进来；
    /// 内容比滚动区域高就能滚。nil 时还没算过，先按内容的自然高度画。
    var viewports: DetailPanelFit.Viewports? = nil
    /// 内容比面板高：外观栏顶上画一道细线，和滚动的内容分开。
    var overflows = false
    /// 只用来量自然尺寸：不套滚动区域，也不报告高度。
    var measuring = false
    /// 和 `measuring` 一起用：只量底部外观栏。
    var measuringFooter = false
    /// 滚动区域里内容的自然高度变了（不含尾巴）。
    var onContentHeight: @MainActor (CGFloat) -> Void = { _ in }
    /// 底部外观栏的自然高度变了（展开、收起）。
    var onFooterHeight: @MainActor (CGFloat) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false
    /// 外层滚动区的位置。窗口和根视图在两次打开之间是复用的，SwiftUI 会把
    /// 上一次滚到的位置留下来，再打开时顶上一截看着像被截掉；每次打开都
    /// 回到顶上。
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// 滚动区两头的淡出，见 `DetailPanelFit.fades`。
    /// 用户自己用触控板、滚轮或拖动滚过。没滚过时滚动区一直停在顶上：点面板
    /// 里靠下的按钮（拔牙的牙、列表行）时系统会把它滚进视野，内容变高时也会
    /// 跟着跑，顶上一截就像被切掉了。
    @State private var userScrolled = false
    @State private var fadeTop = false
    @State private var fadeBottom = false

    /// 这张卡片在颜色面板里选的强调色，没选过是 nil（各面板照旧）。
    private var panelTint: PanelTint? {
        PanelTint(kind: instance.kind, config: instance.config)
    }

    var body: some View {
        // 订阅通用外观，见 `WidgetLook`。
        let _ = WidgetLook.shared.config
        scrolling
            // 各面板里表示本小组件主题色的地方从这里取，见 `PanelTint`。
            .environment(\.panelTint, panelTint)
            // Room for the tail on whichever side the shelf is.
            .padding(tailSide, PanelShape.arrowDepth)
            .frame(width: WidgetDetail.width(instance), alignment: .leading)
            .background(surface(WidgetDetailBody.ground(instance, context)))
            .fixedSize()
            // 窗口和内容万一差一点，顶边对齐：多出来的只会落在底下，标题一行
            // 永远不被切掉。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Rises a little and fades in. It used to scale up out of the
            // tile, which is an iOS sheet's entrance; a panel on this
            // platform arrives more or less where it means to stay.
            .offset(x: rise.width, y: rise.height)
            .opacity(appeared ? 1 : 0)
            .onAppear { enter() }
            .onChange(of: session) { _, _ in
                appeared = false
                userScrolled = false
                scrollPosition.scrollTo(edge: .top)
                Task { @MainActor in enter() }
            }
    }

    /// 小组件的内容，外面总是同一个竖向滚动区域，高度由窗口给；有“外观”
    /// 入口的卡片，外观栏钉在滚动区下面，不随内容滚走。
    ///
    /// 始终套着而不是放不下才套：换结构会让 SwiftUI 把里面的小组件当成新的
    /// 视图，正在输入的文字、展开的编辑行都会丢。滚动区域给内容的竖向尺寸
    /// 提议是 nil，和原来外层 fixedSize 给的一样，所以各小组件排版不变。
    /// 内容不超出时 basedOnSize 让它不弹不滚，看起来和原来一样。
    ///
    /// 内边距和原来一整块 `VStack(spacing: 20) { 内容; 外观 }.padding(16)`
    /// 一样：内容块上、左右 16，外观栏顶上 20（多数面板的深色卡片往外多画
    /// 10pt，留够了才和外观分得开）、左右和底下 16，不超出时两块拼起来和
    /// 原来一模一样。
    @ViewBuilder private var scrolling: some View {
        let pad = DetailPanelWidth.padding
        let main = WidgetDetailBody(instance: instance, context: context)
            // 内容区左右边距对称的前提是没有哪一块比内容区宽：外框靠左对齐，
            // 撑宽的部分全落到右边被裁掉。量到超出就记一条，不改排版。
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                let extra = DetailPanelWidth.overflow(content: width, available: contentWidth)
                guard extra > 0, !measuring else { return }
                let kind = instance.kind.rawValue
                detailWidthLog.error("detail content wider than panel by \(Double(extra), privacy: .public)pt: \(kind, privacy: .public)")
            }
            .padding([.top, .horizontal], pad)
            .padding(.bottom, showsAppearance ? 0 : pad)
        if measuring {
            if measuringFooter {
                footer
            } else {
                VStack(spacing: 0) {
                    main
                    if showsAppearance { footer }
                }
            }
        } else {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    main
                        // 下面两项只给外层这个滚动区域用；各面板里自己的滚动列表
                        // 照旧按它们自己的设置来。
                        .scrollIndicators(.automatic)
                        .scrollBounceBehavior(.automatic)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            onContentHeight(height)
                        }
                }
                .scrollPosition($scrollPosition)
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .interacting, .tracking, .decelerating: userScrolled = true
                    default: break
                    }
                }
                // 滚动区变矮（屏幕变了、外观栏展开）时保持顶边不动，不往中间跑。
                .defaultScrollAnchor(.top)
                .scrollBounceBehavior(.basedOnSize)
                // 和各深色面板一样不画滚动条：系统设成“始终显示滚动条”时，
                // 右边会压一根浅色竖条，还会把内容挤窄、换行、变高。还能滚
                // 由两头的淡出提示。
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                    [geometry.contentOffset.y + geometry.contentInsets.top,
                     geometry.containerSize.height, geometry.contentSize.height]
                } action: { _, values in
                    if !userScrolled, values[0] > 0.5 {
                        scrollPosition.scrollTo(edge: .top)
                    }
                    let fades = DetailPanelFit.fades(offset: values[0], container: values[1],
                                                     content: values[2])
                    fadeTop = fades.top
                    fadeBottom = fades.bottom
                }
                .frame(height: viewports?.scroll)
                .mask {
                    VStack(spacing: 0) {
                        if fadeTop {
                            LinearGradient(colors: [.black.opacity(0), .black],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 18)
                        }
                        Rectangle()
                        if fadeBottom {
                            LinearGradient(colors: [.black, .black.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 18)
                        }
                    }
                }
                if showsAppearance {
                    ScrollView(.vertical) {
                        footer
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                onFooterHeight(height)
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.never)
                    // 每次打开从头开始，外观本身也是每次收起。
                    .id(session)
                    .frame(height: viewports?.footer)
                    .overlay(alignment: .top) {
                        // 内容在上面滚时，外观栏顶上一道细线，不占高度。
                        if overflows {
                            Rectangle().fill(.panelSeparator).frame(height: 0.6)
                                .padding(.horizontal, pad)
                        }
                    }
                }
            }
        }
    }

    /// 底部“外观”栏，带它自己的内边距。
    private var footer: some View {
        WidgetAppearanceSection(instance: instance, context: context, width: contentWidth)
            // 每次打开都从收起开始。
            .id(session)
            // 封面这类自己有深色底的面板，入口的字跟着用浅色。
            .environment(\.colorScheme,
                         WidgetDetailBody.ground(instance, context) != nil ? .dark : scheme)
            .padding(.top, 20)
            .padding([.horizontal, .bottom], DetailPanelWidth.padding)
    }

    /// 内容区宽度：面板宽减两侧内边距，尾巴在左右两侧时再让出尾巴。
    private var contentWidth: CGFloat {
        DetailPanelWidth.content(panel: WidgetDetail.width(instance),
                                 tailDepth: PanelShape.arrowDepth, tailOnSide: !edge.isHorizontal)
    }

    /// 有颜色或背景可选的卡片，面板底部带“外观”入口（见 `WidgetAppearance`）。
    private var showsAppearance: Bool {
        Self.offersAppearance(instance, context)
    }

    /// 11-24 起面板底部不再挂「外观」栏（用户觉得每个面板都拖着一块太臃肿）：
    /// 颜色和背景在 设置 ▸ 小组件 里改；正在播放从面板右上角 ··· 进它自己的外观页。
    static func offersAppearance(_ instance: WidgetInstance, _ context: WidgetContext) -> Bool {
        false
    }

    /// Which side the tail sits on, which is the side facing the shelf.
    private var tailSide: Edge.Set {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var outline: PanelShape {
        PanelShape(edge: edge, arrowOffset: arrowOffset)
    }

    /// The material AppKit gives a popover, not a guess at one.
    ///
    /// This has been wrong twice. First `.regularMaterial` with the widget's
    /// accent flooded over the whole surface, which reads as a web card and
    /// defeats vibrancy - the thing that makes native text sit *in* a surface
    /// rather than on it. Then an opaque window background, which fixed the
    /// stain and lost the vibrancy with it. `.popover` is documented as
    /// exactly this material, and a real popover's layer tree carries no tint
    /// at all, so neither does this.
    private func surface(_ ground: ArtworkTint?) -> some View {
        VisualEffectPlate(material: .popover, blending: .behindWindow)
            // Inside the clip rather than behind the plate. As a
            // `.background` on the body it would paint the whole window
            // rect, which is wider than the panel by the tail's depth, and
            // leave a square-cornered strip across the shelf-facing edge
            // that the panel's shadow traces.
            .overlay {
                if let ground {
                    // 正在播放：深色玻璃打底，顶上叠封面主色的光晕（不超过 15%，
                    // 往下渐隐），不再整面铺封面色。
                    ZStack {
                        Color(.sRGB, red: 0.11, green: 0.11, blue: 0.125, opacity: 1)
                        LinearGradient(stops: [
                            .init(color: Self.colour(ground.glow).opacity(ArtworkTint.glowOpacity), location: 0),
                            .init(color: Self.colour(ground.glow).opacity(0), location: ArtworkTint.glowReach),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            // Opaque where there is a ground, because a translucent tint over
            // a sampled desktop is how the accent stain happened twice
            // before: the colour underneath is somebody's wallpaper and the
            // result is unpredictable. Where there is no ground this is
            // untouched and vibrancy still does its work.
            //
            // Reduce Transparency and Increase Contrast take the same door,
            // which closes a gap every one of these panels had: the chrome
            // never read either setting.
            // 跟外观走的半透明底色（同 PanelGlassSurface）：系统材质在深色内容上
            // 仍可能变深，垫一层后浅色外观的面板始终是浅底，深色字看得清。
            .overlay {
                if ground == nil {
                    Rectangle().fill(scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.55))
                }
            }
            .overlay {
                if ground == nil, reduceTransparency || contrast == .increased {
                    Rectangle().fill(scheme == .dark ? Color(white: 0.11) : Color(white: 0.95))
                }
            }
            // 选了颜色时顶上一抹淡淡的主题色（不超过 15%），往下渐隐。不是
            // 上面说的整面染色：只在顶边，透明度有上限，默认颜色时不画。
            .overlay {
                if ground == nil, let panelTint {
                    // 浅色外观的面板本身亮，颜色更显，收一点。
                    TintGlow(color: panelTint.color,
                             opacity: scheme == .dark ? panelTint.glow : panelTint.glow * 0.8,
                             reach: panelTint.reach)
                }
            }
            .clipShape(outline)
            .overlay {
                // A hairline at the edge, not a drawn border. White over a
                // ground: a dark hairline on a dark colour disappears.
                outline.stroke(ground == nil
                               ? Color.primary.opacity(scheme == .dark ? 0.16 : 0.10)
                               : Color.white.opacity(0.14),
                               lineWidth: 0.5)
            }
    }

    /// `ArtworkTint` stays free of SwiftUI so the core can hold it, so the
    /// conversion lives at the only place that needs it.
    private static func colour(_ c: (red: Double, green: Double, blue: Double)) -> Color {
        Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// Three points, away from the shelf, so it settles toward the tile.
    private var rise: CGSize {
        guard !appeared else { return .zero }
        return switch edge {
        case .bottom: CGSize(width: 0, height: 3)
        // Starts a little lower and settles up toward a tile above it.
        case .top: CGSize(width: 0, height: -3)
        case .left: CGSize(width: -3, height: 0)
        case .right: CGSize(width: 3, height: 0)
        }
    }

    private func enter() {
        withAnimation(.easeOut(duration: 0.14)) { appeared = true }
    }
}

/// How wide each kind's panel is.
///
/// Per kind rather than one width for all: a battery panel is a list of four
/// rows, a revenue panel carries a chart, and a sticky note is a square of
/// paper. Forcing them to a common width leaves most of them padded out.
enum WidgetDetail {
    /// Whether this kind has more to say than its tile already shows.
    ///
    /// Kinds without a panel keep opening their app instead. A panel that
    /// only restates the tile, or apologises for having nothing, is worse
    /// than the app the widget is about.
    static func exists(for kind: WidgetKind) -> Bool {
        switch kind {
        // Every control it has is already on the card; a panel would only
        // repeat the buttons. 快速开关和圆环仪表从第三批起有自己的面板。
        case .volume:
            false
        default:
            true
        }
    }

    /// 按这张卡片定的面板宽：纪念日单个卡片 340、多个卡片 328
    /// （`Anniversary.panelWidth`），其余按种类。
    static func width(_ instance: WidgetInstance) -> CGFloat {
        if instance.kind == .anniversary {
            return CGFloat(Anniversary.panelWidth(layout: instance.config.string("layout", default: "single")))
        }
        // 正在播放：黑胶面板 360 宽横排（完整卡片默认），精简面板 300 宽。
        if instance.kind == .music {
            let vinyl = ProLicenseGate.musicPanelStyle(config: instance.config,
                                                       unlocked: ProAccess.isUnlocked) == .vinyl
            return CGFloat(vinyl ? MusicVinyl.panelWidth : MusicCard.compactPanelWidth)
        }
        return width(instance.kind)
    }

    static func width(_ kind: WidgetKind) -> CGFloat {
        switch kind {
        case .stripe, .paddle, .shopify: 340
        case .calendar, .reminders: 320
        // Set by the twelve-column strip of the next hours there.
        case .world: 320
        // 时钟面板跟着卡片外观分好几套，带今天进度、三座城市的世界时钟、
        // 农历和本周两张小卡，320 才排得下三列城市。
        case .clock: 320
        // 时间进度面板跟着卡片样式分五套，四个周期、本周七天和 53 列的年度点阵。
        case .progress: 320
        case .battery: 330
        // 倒计时四列快速开始、秒表四列计次表、闹钟的今天时间轴和重复日。
        case .countdown, .stopwatch, .alarm: 320
        case .notes: 300
        // 系统活动按效果图改成 320；网络活动按面板实用性效果图也改成 320。
        case .system: 320
        case .network: 320
        // 天气面板改版：降水条、生活指数三格、6 小时折线和城市管理，320 和第一批面板一致。
        case .weather: 320
        // 正在播放改版：和第一批面板一样 320。
        case .music: 320
        // 复古卡带：机身、玻璃键帽、推子和接下来 3 首，和正在播放一样 320（效果图）。
        case .cassette: 320
        // 扫雷：初级、中级棋盘一样宽，换难度面板不跳。
        case .minesweeper: CGFloat(Minesweeper.panelWidth)
        // 拔牙：380（效果图里小熊猫占满面板宽，每颗牙点击区至少 24pt），按卡片真实内容宽画（PullTooth.panelContentWidth）。
        case .pullTooth: CGFloat(PullTooth.panelWidth)
        // 柴犬翻翻乐：和同组的扫雷一样 340，3 行 4 列按卡片真实内容宽排（ShibaMatch.panelContentWidth）。
        case .shibaMatch: CGFloat(ShibaMatch.panelWidth)
        // 卜卦：和同组的扫雷一样 340，内容按卡片真实内容宽排（Divination.panelContentWidth）。
        case .divination: CGFloat(Divination.panelWidth)
        // 时间洞察：四张指标卡、24 小时分布、Top 5、分类占比和当前记录，按内容加宽到 680；
        // 高度仍交给 DetailPanelFit，内容多时面板内滚动，内容区窄时（钉在桌面）排成单列。
        case .timeInsights: TimeInsightsLayout.wideWidth
        // 相册按第二批效果图改成 320；标准、宽幅两套面板一样宽，换样式面板不跳。
        case .photos: 320
        // 最近截图改版：搜索、筛选、多选和标注，和下载一样 320。
        case .screenshots: 320
        case .downloads, .fileShelf, .clipboard, .search: 320
        // 壁纸按第二批效果图改成 320。
        case .wallpaper: 320
        case .appSwitcher: 320
        case .bookmarks: 320
        case .recorder: 320
        // 邮件：最近几封未读，和第二批面板一样 320。
        case .mail: 320
        // 「算」：汇率页的从 / 到两行要放下大号金额和币种按钮，和 Codex 用量一样 340。
        case .calculator: 340
        // 快捷指令：卡片预览一排 4 个大图标，每行图标、名字、上次结果和运行键。
        case .shortcut: 320
        case .github: 320
        case .posture: 320
        case .aiUsage: 340
        case .todo: 320
        case .ambient: 320
        case .lunar: 320
        case .trash: 320
        // 截图工具：四个大按钮、截完后 / 格式 / 延时和最近 3 张，和其他面板一样 320。
        case .capture: 320
        case .habit: 340
        case .week: 320
        // 加密货币：币种行、到价提醒和编辑币种，和第二批面板一样 320。
        case .crypto: 320
        // 分时图、提醒列表；自选股每行有代码、迷你走势、现价和色块。
        case .stock, .watchlist: 360
        case .appVolume: 320
        // 麦克风与摄像头：谁在用、全局静音、输入设备和音量，和第二批面板一样 320。
        case .microphone: 320
        case .radio: 340
        // 实际按卡片样式分 340 / 328，见 width(_ instance:)。
        case .anniversary: 340
        case .water: 360
        case .pet: 340
        case .podcast: 340
        // The basket, a seven-column calendar and four badge tags a row.
        case .perfectDay: 380
        // A large copy of the card and the settings rows under it.
        case .slacker: 400
        // 竖版：欢迎区、2×2 快捷操作、输入框、整行主按钮和「使用模型」下拉。
        case .aiAssistant: 380
        // Two text panes and a row of history, each wide enough for a sentence.
        case .translate: 340
        // 表情符号：一行 8 个 36 的格子，和第二批面板一样 320。
        case .emoji: 320
        // 快速开关三列大按钮、圆环仪表每个圆环一行详情，和第三批面板一样 320。
        case .toggles, .gauges: 320
        default: 300
        }
    }
}

/// The panel's outline: a rounded rectangle with a tail pointing at the tile
/// that opened it.
///
/// The tail is the thing that was missing. Apple's positioning rules for a
/// popover are written entirely in terms of it, and without one the panel is
/// a rectangle that happens to be near a tile rather than something belonging
/// to it. Measured off a real `NSPopover`: a 20pt continuous corner, and a
/// tail roughly 26pt across and 10pt deep.
struct PanelShape: Shape {
    /// Which edge the shelf is on; the tail goes on the side facing it.
    var edge: DockPosition
    /// Distance along the shelf from the panel's middle to the tile's, which
    /// is zero until the panel is clamped against the end of the screen.
    var arrowOffset: CGFloat

    static let radius: CGFloat = 20
    static let arrowBase: CGFloat = 26
    static let arrowDepth: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let depth = Self.arrowDepth
        var body = rect
        switch edge {
        case .bottom: body.size.height -= depth
        case .top: body.origin.y += depth; body.size.height -= depth
        case .left: body.origin.x += depth; body.size.width -= depth
        case .right: body.size.width -= depth
        }

        let outline = Path(roundedRect: body, cornerRadius: Self.radius, style: .continuous)

        // Kept clear of the corners: a tail growing out of the curve reads as
        // a dent in the outline rather than a point at anything.
        let half = Self.arrowBase / 2
        let limit = Self.radius + half
        // The tail starts a little inside the body so the two overlap, and
        // is then merged into it. It used to be a second shape added beside
        // the rounded rectangle, so the hairline traced both: a line straight
        // across the tail's base, and the tail's sides drawn over the body's
        // edge where they met. One outline has neither.
        let overlap: CGFloat = 2
        var tail = Path()
        switch edge {
        case .bottom:
            let x = min(max(body.minX + limit, body.midX + arrowOffset), body.maxX - limit)
            tail.move(to: CGPoint(x: x - half, y: body.maxY - overlap))
            tail.addLine(to: CGPoint(x: x - 2.5, y: rect.maxY - 1.4))
            // A softened point, the way a popover's tail ends.
            tail.addQuadCurve(to: CGPoint(x: x + 2.5, y: rect.maxY - 1.4),
                              control: CGPoint(x: x, y: rect.maxY + 0.4))
            tail.addLine(to: CGPoint(x: x + half, y: body.maxY - overlap))
        case .top:
            // The bottom tail mirrored: the shape's y runs down, so pointing
            // up at a tile above means toward `rect.minY`.
            let x = min(max(body.minX + limit, body.midX + arrowOffset), body.maxX - limit)
            tail.move(to: CGPoint(x: x - half, y: body.minY + overlap))
            tail.addLine(to: CGPoint(x: x - 2.5, y: rect.minY + 1.4))
            tail.addQuadCurve(to: CGPoint(x: x + 2.5, y: rect.minY + 1.4),
                              control: CGPoint(x: x, y: rect.minY - 0.4))
            tail.addLine(to: CGPoint(x: x + half, y: body.minY + overlap))
        case .left:
            let y = min(max(body.minY + limit, body.midY + arrowOffset), body.maxY - limit)
            tail.move(to: CGPoint(x: body.minX + overlap, y: y - half))
            tail.addLine(to: CGPoint(x: rect.minX + 1.4, y: y - 2.5))
            tail.addQuadCurve(to: CGPoint(x: rect.minX + 1.4, y: y + 2.5),
                              control: CGPoint(x: rect.minX - 0.4, y: y))
            tail.addLine(to: CGPoint(x: body.minX + overlap, y: y + half))
        case .right:
            let y = min(max(body.minY + limit, body.midY + arrowOffset), body.maxY - limit)
            tail.move(to: CGPoint(x: body.maxX - overlap, y: y - half))
            tail.addLine(to: CGPoint(x: rect.maxX - 1.4, y: y - 2.5))
            tail.addQuadCurve(to: CGPoint(x: rect.maxX - 1.4, y: y + 2.5),
                              control: CGPoint(x: rect.maxX + 0.4, y: y))
            tail.addLine(to: CGPoint(x: body.maxX - overlap, y: y + half))
        }
        tail.closeSubpath()
        return outline.union(tail)
    }
}
