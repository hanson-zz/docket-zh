import AppKit
import SwiftUI

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
    /// 开着的面板：小组件、它的尾巴指向的点、内容的自然高度（含尾巴）、
    /// 当前给滚动区域的高度。内容变高变矮时按这些重新摆窗口。
    private var fit: (instance: WidgetInstance, anchor: CGPoint, natural: CGSize,
                      viewport: CGFloat, overflows: Bool)?
    private var screenObserver: NSObjectProtocol?

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
        let visible = screen.visibleFrame
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
    /// `contentHeightChanged` 再重新摆窗口，不用关了重开。
    func refresh(_ instance: WidgetInstance) {
        guard openWidgetID == instance.id, let shown, var current = fit else { return }
        current.instance = instance
        fit = current
        hosting?.rootView = chrome(instance, context: shown.context, edge: shown.edge,
                                   arrowOffset: shown.arrowOffset, viewport: current.viewport,
                                   overflows: current.overflows)
    }

    /// 面板的根视图，每次都从这里造，免得哪一处漏了滚动区域的高度或回调。
    private func chrome(_ instance: WidgetInstance, context: WidgetContext, edge: DockPosition,
                        arrowOffset: CGFloat, viewport: CGFloat?,
                        overflows: Bool) -> WidgetDetailChrome {
        let opened = session
        return WidgetDetailChrome(
            instance: instance, context: context, edge: edge, session: opened,
            arrowOffset: arrowOffset, viewport: viewport, overflows: overflows,
            // 放到下一轮再摆窗口：回调来自 SwiftUI 的布局，在布局中途换根视图
            // 和改窗口大小会让 AppKit 重入布局。
            onContentHeight: { [weak self] height in
                Task { @MainActor in self?.contentHeightChanged(height, session: opened) }
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

    /// 面板所在屏幕的可用区域：按小组件那个点找屏幕，不按面板原点找。
    private func visibleFrame(for anchor: CGPoint) -> CGRect? {
        let screens = NSScreen.screens
        if let index = DetailPanelFit.screenIndex(for: anchor, screens: screens.map(\.frame)) {
            return screens[index].visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    /// 滚动区域里的内容报告了新高度：日程、提醒、行情这类打开后才读到的
    /// 数据，或者面板里展开了一段。重新算尺寸和位置，窗口跟着变。
    private func contentHeightChanged(_ inner: CGFloat, session opened: UUID) {
        guard opened == session, isOpen, let shown, let current = fit else { return }
        let natural = CGSize(width: current.natural.width,
                             height: inner + (shown.edge.isHorizontal ? PanelShape.arrowDepth : 0))
        guard DetailPanelFit.needsRefit(old: current.natural.height, new: natural.height) else { return }
        place(current.instance, context: shown.context, edge: shown.edge,
              anchor: current.anchor, natural: natural)
    }

    /// 显示器插拔、分辨率或系统程序坞变了：按新的可用区域重摆。
    private func screensChanged() {
        guard isOpen, let shown, let current = fit else { return }
        place(current.instance, context: shown.context, edge: shown.edge,
              anchor: current.anchor, natural: current.natural)
    }

    /// 按自然尺寸算出 frame，换上对应滚动高度的根视图，摆好窗口。
    private func place(_ instance: WidgetInstance, context: WidgetContext, edge: DockPosition,
                       anchor: CGPoint, natural: CGSize) {
        guard let panel, let visible = visibleFrame(for: anchor) else { return }
        let placement = DetailPanelFit.place(edge: edge, anchor: anchor, natural: natural,
                                             visible: visible)
        let frame = placement.frame
        let viewport = DetailPanelFit.viewportHeight(panelHeight: frame.height, edge: edge,
                                                     tailDepth: PanelShape.arrowDepth)
        // Only now is the tail's offset knowable: clamping against the end of
        // the screen moves the panel but not the tile, and a tail still
        // pointing at the panel's own middle would point at nothing.
        // Screen y counts up and the panel's own coordinates count down, so
        // the sign flips on a side shelf; see Geometry.popupTailOffset.
        let offset = Geometry.popupTailOffset(edge: edge, anchor: anchor,
                                              placed: frame.origin, size: frame.size)
        shown = (context, edge, offset)
        fit = (instance, anchor, natural, viewport, placement.overflows)
        hosting?.rootView = chrome(instance, context: context, edge: edge,
                                   arrowOffset: offset, viewport: viewport,
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
        shown = nil
        fit = nil
        stopWatching()
        guard panel?.isVisible == true else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.openWidgetID == nil else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    private func show(_ instance: WidgetInstance, context: WidgetContext,
                      anchor: CGPoint, edge: DockPosition, host: CGRect, floating: Bool) {
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
        if let previous = openWidgetID, previous != instance.id { announceClosed(previous) }
        openWidgetID = instance.id
        isFloating = floating
        lastShownAnchor = (instance.id, anchor)

        // Almost touching the tile: the panel's own padding already includes
        // the tail's depth, so this is the gap between the tail's tip and the
        // tile, not between the tile and the body. Below the tile on a top
        // shelf, above it on a bottom one. 高度不超过所在屏幕的可用区域，
        // 超出的部分在面板里滚动；见 DetailPanelFit。
        place(instance, context: context, edge: edge, anchor: anchor, natural: size)

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // A panel carrying a text field or a slider needs the keyboard, and a
        // borderless window is refused key status without the override.
        panel.makeKey()
        watchForDismissal()
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(
            rootView: WidgetDetailChrome(instance: WidgetInstance(kind: .clock,
                                                                  config: WidgetConfig()),
                                         context: WidgetContext(),
                                         edge: .bottom, session: session))
        hosting.sizingOptions = [.intrinsicContentSize]

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
    /// 滚动区域的高度，由窗口按所在屏幕算好给进来；内容比它高就能滚。
    /// nil 时还没算过，先按内容的自然高度画。
    var viewport: CGFloat? = nil
    /// 内容比滚动区域高：底边淡出，提示下面还有。
    var overflows = false
    /// 只用来量自然尺寸：不套滚动区域，也不报告高度。
    var measuring = false
    /// 滚动区域里内容的自然高度变了（不含尾巴）。
    var onContentHeight: @MainActor (CGFloat) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    /// 这张卡片在颜色面板里选的强调色，没选过是 nil（各面板照旧）。
    private var panelTint: PanelTint? {
        PanelTint(kind: instance.kind, config: instance.config)
    }

    var body: some View {
        scrolling
            // 各面板里表示本小组件主题色的地方从这里取，见 `PanelTint`。
            .environment(\.panelTint, panelTint)
            // Room for the tail on whichever side the shelf is.
            .padding(tailSide, PanelShape.arrowDepth)
            .frame(width: WidgetDetail.width(instance.kind), alignment: .leading)
            .background(surface(WidgetDetailBody.ground(instance, context)))
            .fixedSize()
            // Rises a little and fades in. It used to scale up out of the
            // tile, which is an iOS sheet's entrance; a panel on this
            // platform arrives more or less where it means to stay.
            .offset(x: rise.width, y: rise.height)
            .opacity(appeared ? 1 : 0)
            .onAppear { enter() }
            .onChange(of: session) { _, _ in
                appeared = false
                Task { @MainActor in enter() }
            }
    }

    /// 小组件的内容，外面总是同一个竖向滚动区域，高度由窗口给。
    ///
    /// 始终套着而不是放不下才套：换结构会让 SwiftUI 把里面的小组件当成新的
    /// 视图，正在输入的文字、展开的编辑行都会丢。滚动区域给内容的竖向尺寸
    /// 提议是 nil，和原来外层 fixedSize 给的一样，所以各小组件排版不变。
    /// 内容不超出时 basedOnSize 让它不弹不滚，看起来和原来一样。
    @ViewBuilder private var scrolling: some View {
        // 间距 20：多数面板的深色卡片（DetailCard）往外多画 10pt，留够了
        // 才和下面的“外观”分得开。
        let content = VStack(spacing: 20) {
            WidgetDetailBody(instance: instance, context: context)
            if showsAppearance {
                WidgetAppearanceSection(instance: instance, context: context,
                                        width: WidgetDetail.width(instance.kind) - 32 - PanelShape.arrowDepth)
                    // 每次打开都从收起开始。
                    .id(session)
                    // 封面这类自己有深色底的面板，入口的字跟着用浅色。
                    .environment(\.colorScheme,
                                 WidgetDetailBody.ground(instance, context) != nil ? .dark : scheme)
            }
        }
        .padding(16)
        if measuring {
            content
        } else {
            ScrollView(.vertical) {
                content
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
            .scrollBounceBehavior(.basedOnSize)
            // 和各深色面板一样不画滚动条：系统设成“始终显示滚动条”时，
            // 右边会压一根浅色竖条，还会把内容挤窄、换行、变高。
            .scrollIndicators(.never)
            .frame(height: viewport)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    if overflows {
                        LinearGradient(colors: [.black, .black.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                    }
                }
            }
        }
    }

    /// 有颜色或背景可选的卡片，面板底部带“外观”入口（见 `WidgetAppearance`）。
    private var showsAppearance: Bool {
        !context.isPreview && WidgetAppearance.offered(instance.kind)
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
        // Every control these have is already on the card; a panel would
        // only repeat the buttons.
        case .capture, .emoji, .volume, .toggles, .mail, .microphone, .gauges:
            false
        default:
            true
        }
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
        // 系统活动按效果图改成 320；网络活动照旧 340。
        case .system: 320
        case .network: 340
        // 天气面板改版：降水条、生活指数三格、6 小时折线和城市管理，320 和第一批面板一致。
        case .weather: 320
        // 正在播放改版：和第一批面板一样 320。
        case .music: 320
        case .photos, .screenshots: 340
        case .downloads, .fileShelf, .clipboard, .search: 320
        case .wallpaper: 340
        case .appSwitcher: 320
        case .bookmarks: 320
        case .recorder: 320
        // 「算」：输入框、结果、最近记录，和原来汇率换算的面板一样宽。
        case .calculator: 320
        // 快捷指令：卡片预览一排 4 个大图标，每行图标、名字、上次结果和运行键。
        case .shortcut: 320
        case .github: 320
        case .posture: 320
        case .aiUsage: 340
        case .todo: 320
        case .ambient: 320
        case .lunar: 320
        case .trash: 320
        case .habit: 340
        case .week: 320
        case .crypto: 340
        // 分时图、提醒列表；自选股每行有代码、迷你走势、现价和色块。
        case .stock, .watchlist: 360
        case .appVolume: 320
        case .radio: 340
        case .anniversary: 360
        case .water: 360
        case .pet: 340
        case .podcast: 340
        // The basket, a seven-column calendar and four badge tags a row.
        case .perfectDay: 380
        // A large copy of the card and the settings rows under it.
        case .slacker: 400
        // The question box, the target picker and a row of buttons.
        case .aiAssistant: 380
        // Two text panes and a row of history, each wide enough for a sentence.
        case .translate: 340
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
