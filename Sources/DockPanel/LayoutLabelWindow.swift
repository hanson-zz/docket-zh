import AppKit
import SwiftUI

/// 悬停扩展栏时，在扩展栏外侧（开口那一边）居中浮出的布局名小胶囊：
/// 「工作 ● ○ ○」，点点或两边的小箭头直接切换布局；切换布局时也闪现一下。
///
/// 放在自己的窗口里，不画进扩展栏：画进去就得给扩展栏窗口预留一圈空白，
/// 窗口会因此变大、在出现和消失时跳动，预留区还会挡住后面的点击。独立窗口
/// 只在看得见时占它自己那一小块，扩展栏的格子一个也不挡。
///
/// 什么时候看得见、页码点怎么画在 Core 的 `LayoutLabel` /
/// `LayoutLabelVisibility`，有测试。`DockPanelController` 接上扩展栏的位置和
/// 所在边，`DockShelfView` 报指针进出扩展栏。
@MainActor
final class LayoutLabelWindow {
    static let shared = LayoutLabelWindow()

    /// `DockPanelController` 接上。
    weak var app: AppState?
    /// 扩展栏滑出来时窗口的位置（自动隐藏滑出途中也是终点位置）。
    var shelfFrame: @MainActor () -> CGRect? = { nil }
    /// 扩展栏在哪条边，标签放在它的开口一侧。
    var edge: @MainActor () -> DockPosition = { .bottom }

    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<LayoutLabelCapsule>?
    private var visibility = LayoutLabelVisibility()
    private var hideTask: Task<Void, Never>?
    private var fadingOut = false
    /// 上次画的内容和位置，没变就不重新量、不重新摆。
    private var drawn: LayoutLabelCapsule.Snapshot?
    private var drawnFrame: CGRect = .zero
    /// 上次看到的当前布局，用来分辨“切换了布局”和别的设置变化。
    private var lastProfileID: UUID??

    private init() {}

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: 输入

    /// 指针进出扩展栏。每次移动都会调，没变化时什么也不做。
    func pointerOnShelf(_ inside: Bool) {
        if inside == visibility.onShelf {
            // 指针还在扩展栏上，但刚点开了分组、文件夹小窗或小组件面板：
            // 这些窗口也在扩展栏外侧，标签让开。
            if inside, isShown, blockedByPopup { update() }
            return
        }
        visibility.pointer(onShelf: inside, at: now)
        update()
    }

    fileprivate func pointerOnLabel(_ inside: Bool) {
        guard inside != visibility.onLabel else { return }
        visibility.pointer(onLabel: inside, at: now)
        update()
    }

    /// 扩展栏设置变了（`DockPanelController.refresh` 调）。当前布局换了就闪现
    /// 新名字；开关关了就收起。
    func settingsChanged() {
        guard let app else { return }
        let id = app.state.customDock.profileID
        defer { lastProfileID = .some(id) }
        if let last = lastProfileID, last != id {
            visibility.flash(at: now)
        }
        update()
    }

    /// 扩展栏收起、关闭或开始拖动：立刻收起，不等淡出。
    func dismiss() {
        visibility.reset()
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        drawn = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// 指针在标签上（留一点余量），自动隐藏时当作还在扩展栏上，不收起。
    func contains(_ point: CGPoint) -> Bool {
        guard let panel, panel.isVisible, !fadingOut else { return false }
        return panel.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// 跟着顶部扩展栏给灵动提示让位，见 DockPanelController.islandMoved。
    func shift(by dy: CGFloat) {
        guard let panel, panel.isVisible, dy != 0 else { return }
        drawnFrame = drawnFrame.offsetBy(dx: 0, dy: dy)
        panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: dy), display: false)
    }

    /// 布局数和开关是否允许出现。
    var isAvailable: Bool {
        guard let app else { return false }
        return LayoutLabel.isAvailable(enabled: app.state.customDock.showLayoutLabelOnHover,
                                       layoutCount: app.state.profiles(of: .customDock).count)
    }

    // MARK: 显示

    private var isShown: Bool { panel?.isVisible == true && !fadingOut }

    /// 分组、文件夹小窗、挂在扩展栏上的小组件面板开着时不出标签：它们也弹在
    /// 扩展栏外侧，会叠在一起。
    private var blockedByPopup: Bool {
        GroupWindow.shared.isOpen || FolderBrowserWindow.shared.isOpen
            || WidgetDetailWindow.shared.isAnchoredOpen
            // 悬停窗口预览也在扩展栏外侧，开着时标签让开。
            || WindowPreviewWindow.shared.isOpen
    }

    private func update() {
        guard isAvailable, ShelfPresence.shared.isShown(), !ShelfPresence.shared.isTuckedAway(),
              !blockedByPopup, let shelf = shelfFrame(), let app else {
            if !isAvailable { visibility.reset() }
            hideTask?.cancel()
            hideTask = nil
            return fadeOut()
        }
        let time = now
        guard visibility.isVisible(at: time) else { return fadeOut() }
        show(app: app, shelf: shelf)
        schedule(after: time)
    }

    /// 到点再判断一次：余留或闪现结束时淡出。
    private func schedule(after time: TimeInterval) {
        hideTask?.cancel()
        hideTask = nil
        guard let deadline = visibility.hideDeadline(at: time) else { return }
        let wait = max(0.01, deadline - time + 0.02)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }

    private func snapshot(_ app: AppState) -> LayoutLabelCapsule.Snapshot {
        let profiles = app.state.profiles(of: .customDock)
        let current = app.state.customDock.profileID
        let name = profiles.first { $0.id == current }?.name ?? tr("扩展栏")
        return .init(name: name,
                     pages: LayoutLabel.pages(ids: profiles.map(\.id), current: current),
                     opaque: app.state.customDock.reduceTransparency)
    }

    private func show(app: AppState, shelf: CGRect) {
        let panel = existingOrNew()
        let snap = snapshot(app)
        var size = drawnFrame.size
        if drawn != snap || size.width < 1 {
            hosting?.rootView = capsule(snap)
            drawn = snap
            size = hosting?.fittingSize ?? .zero
        }
        guard size.width > 1 else { return }

        let origin = clamped(Geometry.besideShelfOrigin(edge: edge(), shelf: shelf, size: size, gap: 2),
                             size: size, near: shelf)
        let frame = CGRect(origin: origin, size: size)
        if frame != drawnFrame || !panel.isVisible {
            drawnFrame = frame
            panel.setFrame(frame, display: false)
        }
        if !panel.isVisible || fadingOut {
            fadingOut = false
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible, !fadingOut else { return }
        fadingOut = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // 淡出途中又被叫出来了就不收。
                guard let self, self.fadingOut, let panel = self.panel else { return }
                self.fadingOut = false
                self.drawn = nil
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func capsule(_ snap: LayoutLabelCapsule.Snapshot) -> LayoutLabelCapsule {
        LayoutLabelCapsule(snapshot: snap,
                           onSelect: { [weak self] index in self?.select(index) },
                           onStep: { [weak self] step in self?.step(step) },
                           onHover: { [weak self] inside in self?.pointerOnLabel(inside) })
    }

    /// 点了第几个点。
    private func select(_ index: Int) {
        guard let app else { return }
        let profiles = app.state.profiles(of: .customDock)
        guard profiles.indices.contains(index),
              profiles[index].id != app.state.customDock.profileID else { return }
        app.activate(profiles[index])
    }

    /// 点了左右小箭头。
    private func step(_ step: Int) {
        app?.stepCustomLayout(by: step)
    }

    /// 浮动扩展栏贴近屏幕边时，别让标签挂出屏幕。
    private func clamped(_ origin: CGPoint, size: CGSize, near shelf: CGRect) -> CGPoint {
        let center = CGPoint(x: shelf.midX, y: shelf.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main else { return origin }
        let frame = screen.frame
        return CGPoint(x: min(max(origin.x, frame.minX + 4), frame.maxX - size.width - 4),
                       y: min(max(origin.y, frame.minY + 4), frame.maxY - size.height - 4))
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let view = FirstMouseHostingView(rootView: capsule(.init(name: "", pages: .dots([]), opaque: false)))
        view.sizingOptions = []
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // 胶囊自己画影子
        panel.level = .statusBar                 // 在扩展栏之上
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        self.hosting = view
        return panel
    }
}

/// 胶囊本身：左箭头、布局名、页码点（或「3 / 12」）、右箭头。液态玻璃，
/// 跟着外观走，文字 13pt。
struct LayoutLabelCapsule: View {
    struct Snapshot: Equatable {
        var name: String
        var pages: LayoutLabel.Pages
        var opaque: Bool
    }

    var snapshot: Snapshot
    var onSelect: @MainActor (Int) -> Void
    var onStep: @MainActor (Int) -> Void
    var onHover: @MainActor (Bool) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", step: -1, help: tr("上一个布局"))
            Text(verbatim: snapshot.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)
                .fixedSize()
            pages
            arrow("chevron.right", step: 1, help: tr("下一个布局"))
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background { background }
        .overlay {
            // 只报指针进出，不接点击（见 HoverCatcher）。
            HoverCatcher { point in onHover(point != nil) }
                .allowsHitTesting(false)
        }
        .padding(6)   // 给影子留地方
        .fixedSize()
    }

    @ViewBuilder private var pages: some View {
        switch snapshot.pages {
        case .dots(let dots):
            HStack(spacing: 0) {
                ForEach(dots.indices, id: \.self) { index in
                    Button { onSelect(index) } label: {
                        Circle()
                            .fill(dots[index] ? Color.primary : Color.primary.opacity(0.28))
                            .frame(width: 7, height: 7)
                            .frame(width: 15, height: 24)   // 好点中
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tr("切换到第 \(index + 1) 个布局"))
                }
            }
        case .counter(let index, let total):
            Text(verbatim: index > 0 ? "\(index) / \(total)" : "- / \(total)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func arrow(_ symbol: String, step: Int, help: String) -> some View {
        Button { onStep(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var background: some View {
        let shape = Capsule(style: .continuous)
        if snapshot.opaque {
            shape.fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                .overlay { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.22), radius: 5, y: 1)
        } else {
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
        }
    }
}
