import AppKit
import Observation
import SwiftUI

/// 悬停扩展栏上正在运行的 App 格子约 0.5 秒，在格子外侧（按扩展栏所在的边）
/// 弹出的窗口预览小窗（码头 Pro，设置 ▸ 扩展栏 ▸ 悬停显示窗口预览，默认关）。
///
/// - 横排列出这个 App 的窗口：有屏幕录制权限时是缩略图（后台截图，几秒内复用），
///   没有时是窗口标题的文字卡，底下一行说明和打开权限的按钮。最小化的窗口也列出，
///   标「已最小化」。最多 8 个，横向滚动。
/// - 点卡片把那个窗口提到最前；卡片右上角悬停出现 ×，关掉那个窗口。
/// - 指针离开格子和小窗后收起。和分组窗口、文件夹小窗、小组件面板互斥：
///   它们开着时不弹，点格子打开它们时先收起这里。按住鼠标（拖动图标、拖动浮动
///   扩展栏、拖手柄改大小）时不弹。
///
/// 悬停的时间规则在 Core 的 `WindowPreviewHover`，尺寸和方向在 `WindowPreview`。
@MainActor
final class WindowPreviewWindow {
    static let shared = WindowPreviewWindow()

    private var panel: WindowPreviewPanel?
    private var hosting: FirstMouseHostingView<WindowPreviewView>?
    private let model = WindowPreviewModel()
    private var hover = WindowPreviewHover()
    private var timer: Timer?

    /// 扩展栏报来的：指针下面那个可以预览的 App，和弹出要用的位置。
    private var tile: String?
    private var settings = CustomDockSettings()
    private var anchor: CGPoint = .zero
    private var edge: DockPosition = .bottom
    /// 扩展栏窗口的范围（屏幕坐标），指针不在里面就当没停在格子上。
    private var host: CGRect = .zero

    /// 截好的缩略图，键见 `WindowPreviewSource.Window.cacheKey`。
    private var cache: [String: (shot: WindowShot, at: Date)] = [:]
    private var captureTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    private init() {}

    var isOpen: Bool { model.bundleID != nil && panel?.isVisible == true }

    /// 扩展栏的悬停目标变了。`bundleID` 是正在运行的 App 才有，其余（小组件、
    /// 文件夹、没运行的 App、离开扩展栏）都是 nil。
    func hoverTile(bundleID: String?, anchor: CGPoint, edge: DockPosition, host: CGRect,
                   settings: CustomDockSettings) {
        tile = bundleID
        self.settings = settings
        if bundleID != nil {
            self.anchor = anchor
            self.edge = edge
        }
        self.host = host
        step()
        // 小窗顶上已经写了 App 名字，格子的名字标签不再叠在小窗上。
        if isOpen, bundleID != nil { TooltipWindow.shared.hide() }
    }

    /// 收起。`suppress` 为真时（点了格子或缩略图）指针离开那个格子之前不再弹。
    func close(suppress: Bool = false) {
        let current = model.bundleID ?? tile
        hover.reset(suppress: suppress ? current : nil)
        dismiss()
        stopTimer()
    }

    // MARK: 状态

    private var blocked: Bool {
        !ProLicenseGate.windowPreviewActive(settings, unlocked: ProAccess.isUnlocked)
            || GroupWindow.shared.isOpen
            || FolderBrowserWindow.shared.isOpen
            || WidgetDetailWindow.shared.isAnchoredOpen
            || ShelfResize.isDragging
    }

    private func step() {
        let mouse = NSEvent.mouseLocation
        let overPopup = isOpen && (panel?.frame.insetBy(dx: -4, dy: -4).contains(mouse) ?? false)
        // 按着鼠标时不弹：拖图标、拖浮动扩展栏、拖手柄改大小都算。在小窗里按下
        // （点缩略图、点 ×）不算。
        let pressing = NSEvent.pressedMouseButtons != 0 && !overPopup
        let onShelf = host == .zero || host.insetBy(dx: -2, dy: -2).contains(mouse)
        let current = onShelf ? tile : nil
        let action = hover.update(tile: current, overPopup: overPopup,
                                  blocked: blocked || pressing, now: .now)
        switch action {
        case .show(let id): present(bundleID: id)
        case .hide: dismiss()
        case nil: break
        }
        if hover.phase == .idle { stopTimer() } else { startTimer() }
    }

    /// 等弹出和开着时每 0.1 秒看一眼指针：指针在小窗上时扩展栏不会报悬停。
    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { WindowPreviewWindow.shared.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 打开、收起

    private func present(bundleID: String) {
        TooltipWindow.shared.hide()
        let app = AppWindows.process(bundleID: bundleID)
        model.bundleID = bundleID
        model.appName = app?.localizedName ?? bundleID
        model.pid = app?.processIdentifier ?? 0
        model.session = UUID()
        // 换了 App：缩略图按窗口序号存，上一个 App 的不能留。
        model.shots = [:]
        model.failed = []
        captureTask?.cancel()
        reload(animated: false)
        let panel = existingOrNew()
        // 正在淡出时又停回来：不重新排到最前，直接淡回来。
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func dismiss() {
        captureTask?.cancel()
        captureTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        guard model.bundleID != nil else { return }
        model.bundleID = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                let me = WindowPreviewWindow.shared
                guard me.model.bundleID == nil else { return }
                me.panel?.orderOut(nil)
                me.panel?.alphaValue = 1
            }
        }
    }

    /// 读一遍窗口、排好、按数量摆好小窗，再在后台补缩略图。
    private func reload(animated: Bool) {
        guard let bundleID = model.bundleID else { return }
        model.trusted = AppWindows.isTrusted
        model.canCapture = WindowPreviewSource.canCapture
        let all = WindowPreviewSource.windows(bundleID: bundleID)
        let arranged = WindowPreview.arrange(all.map {
            WindowPreview.Entry(index: $0.id, title: $0.title, minimized: $0.minimized)
        })
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        model.windows = arranged.shown.compactMap { byID[$0.index] }
        model.total = all.count
        model.more = arranged.more
        let fresh = Date.now
        cache = cache.filter { fresh.timeIntervalSince($0.value.at) < WindowPreview.cacheLifetime }
        model.shots = model.shots.filter { key, _ in model.windows.contains { $0.id == key } }
        for window in model.windows {
            if let hit = cache[window.cacheKey(pid: model.pid)] { model.shots[window.id] = hit.shot.image }
        }
        place(animated: animated)
        captureMissing()
    }

    private func place(animated: Bool) {
        let panel = existingOrNew()
        hosting?.rootView = view()
        let screens = NSScreen.screens
        let index = DetailPanelFit.screenIndex(for: anchor, screens: screens.map(\.frame))
        let screen = index.map { screens[$0] } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        model.scale = screen?.backingScaleFactor ?? 2
        let size = WindowPreview.panelSize(count: model.windows.count,
                                           thumbnails: model.showsThumbnails,
                                           notice: model.notice != nil,
                                           visibleWidth: visible.width)
        let origin = WindowPreview.origin(edge: edge, anchor: anchor, size: size, visible: visible)
        let frame = CGRect(origin: origin, size: size)
        if animated, panel.isVisible {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// 没缓存的、没最小化的窗口在后台截图，截好一批换上一批。
    private func captureMissing() {
        captureTask?.cancel()
        guard model.showsThumbnails, model.pid != 0 else { return }
        let pid = model.pid
        let scale = model.scale
        let requests = model.windows.filter { !$0.minimized && model.shots[$0.id] == nil }.map {
            WindowShotRequest(key: $0.id, pid: pid, title: $0.title, frame: $0.frame,
                              pixelSize: WindowPreview.captureSize(window: $0.frame.size, scale: scale))
        }
        guard !requests.isEmpty else { return }
        let keys = Dictionary(model.windows.map { ($0.id, $0.cacheKey(pid: pid)) },
                              uniquingKeysWith: { a, _ in a })
        let session = model.session
        captureTask = Task { [weak self] in
            let shots = await WindowShots.capture(requests)
            guard !Task.isCancelled, let self, self.model.session == session else { return }
            let now = Date.now
            for (key, shot) in shots {
                self.model.shots[key] = shot.image
                if let cacheKey = keys[key] { self.cache[cacheKey] = (shot, now) }
            }
            self.model.failed = Set(requests.map(\.key)).subtracting(shots.keys)
        }
    }

    // MARK: 动作

    private func view() -> WindowPreviewView {
        WindowPreviewView(model: model, actions: WindowPreviewActions(
            focus: { window in
                let me = WindowPreviewWindow.shared
                guard let bundleID = me.model.bundleID else { return }
                AppWindows.focus(window.appWindow, bundleID: bundleID)
                me.close(suppress: true)
            },
            closeWindow: { window in
                let me = WindowPreviewWindow.shared
                WindowPreviewSource.close(window)
                // 给 App 一点时间关掉（有未存改动时它会弹出询问），再重读一遍。
                me.reloadTask?.cancel()
                let session = me.model.session
                me.reloadTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, me.model.session == session, me.isOpen else { return }
                    me.reload(animated: true)
                }
            },
            allowCapture: {
                WindowPreviewSource.requestCapture()
                WindowPreviewWindow.shared.close()
            },
            allowAccessibility: {
                AppWindows.requestAccess()
                WindowPreviewWindow.shared.close()
            }))
    }

    private func existingOrNew() -> WindowPreviewPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(rootView: view())
        hosting.sizingOptions = []
        let panel = WindowPreviewPanel(contentRect: .zero,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // 比扩展栏高一层，和文件夹小窗一样。
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

/// 小窗的窗口：不抢焦点、不成为 key，只接点击。
final class WindowPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 数据

@MainActor @Observable
final class WindowPreviewModel {
    var bundleID: String?
    var appName = ""
    var pid: pid_t = 0
    var windows: [WindowPreviewSource.Window] = []
    /// 这个 App 一共几个窗口（截断前）。
    var total = 0
    /// 没列出来的个数。
    var more = 0
    var shots: [Int: CGImage] = [:]
    /// 截过但没截到的（窗口在别的桌面、刚关掉），画占位不再转圈。
    var failed: Set<Int> = []
    var trusted = true
    var canCapture = true
    var scale: CGFloat = 2
    /// 每次打开换一个，后台截图据此丢掉过时的结果，滚动位置回到开头。
    var session = UUID()

    var showsThumbnails: Bool { trusted && canCapture }

    enum Notice { case accessibility, capture }

    /// 底部那行权限说明：没辅助功能时连窗口都列不出，先说这个。
    var notice: Notice? {
        if !trusted { return .accessibility }
        if !canCapture { return .capture }
        return nil
    }
}

struct WindowPreviewActions {
    var focus: (WindowPreviewSource.Window) -> Void
    var closeWindow: (WindowPreviewSource.Window) -> Void
    var allowCapture: () -> Void
    var allowAccessibility: () -> Void
}

// MARK: - 界面

struct WindowPreviewView: View {
    var model: WindowPreviewModel
    var actions: WindowPreviewActions

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowPreview.spacing) {
            header
            cards
            if let notice = model.notice { noticeRow(notice) }
        }
        .padding(WindowPreview.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { PanelGlassSurface(cornerRadius: 18, dark: false) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.panelStroke, lineWidth: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(WindowPreview.header(appName: model.appName, count: model.total))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if model.more > 0 {
                Text(tr("还有 \(model.more) 个窗口"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: WindowPreview.headerHeight)
    }

    @ViewBuilder private var cards: some View {
        if model.windows.isEmpty {
            Text(model.trusted ? tr("没有打开的窗口") : tr("看不到窗口列表"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .frame(maxWidth: .infinity, minHeight: WindowPreview.textCardHeight)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill))
        } else {
            ScrollView(.horizontal, showsIndicators: model.windows.count > WindowPreview.maxVisibleColumns) {
                HStack(alignment: .top, spacing: WindowPreview.spacing) {
                    ForEach(model.windows) { window in
                        WindowPreviewCard(window: window,
                                          image: model.shots[window.id],
                                          thumbnails: model.showsThumbnails,
                                          waiting: !model.failed.contains(window.id),
                                          focus: { actions.focus(window) },
                                          close: { actions.closeWindow(window) })
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(model.session)
            .frame(height: WindowPreview.cardHeight(thumbnails: model.showsThumbnails))
        }
    }

    private func noticeRow(_ notice: WindowPreviewModel.Notice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            Text(notice == .capture ? tr("打开屏幕录制权限后可看缩略图")
                                    : tr("打开辅助功能权限后可列出窗口"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            Button {
                notice == .capture ? actions.allowCapture() : actions.allowAccessibility()
            } label: {
                Text(tr("去授权"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.panelRaised))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(height: WindowPreview.noticeHeight)
    }
}

/// 一张窗口卡片：缩略图加名字，或没权限时的文字卡。悬停时右上角出现 ×。
private struct WindowPreviewCard: View {
    var window: WindowPreviewSource.Window
    var image: CGImage?
    var thumbnails: Bool
    /// 还在等截图（截不到时画图标占位）。
    var waiting: Bool
    var focus: () -> Void
    var close: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false

    private var box: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Button(action: focus) {
            Group {
                if thumbnails { thumbnailCard } else { textCard }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(closeHovering ? Color.white : Color.panelPrimary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(closeHovering ? Color.red.opacity(0.9) : Color.panelRaised))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovering = $0 }
                .padding(5)
                .help(tr("关闭窗口"))
                .accessibilityLabel(tr("关闭窗口"))
                .transition(.opacity)
            }
        }
        .onHover { over in
            withAnimation(.easeOut(duration: 0.12)) { hovering = over }
        }
        .help(window.title)
        .accessibilityLabel(window.minimized ? tr("\(window.title)，已最小化") : window.title)
    }

    private var thumbnailCard: some View {
        VStack(spacing: 6) {
            ZStack {
                box.fill(.panelFill)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                } else if window.minimized {
                    VStack(spacing: 6) {
                        Image(systemName: "dock.arrow.down.rectangle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.panelTertiary)
                        minimizedTag
                    }
                } else if waiting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.panelTertiary)
                }
            }
            .frame(width: WindowPreview.thumbnailSize.width, height: WindowPreview.thumbnailSize.height)
            .overlay { box.strokeBorder(hovering ? Color.panelSelected : Color.clear, lineWidth: 2) }
            Text(window.title)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WindowPreview.thumbnailSize.width, height: WindowPreview.captionHeight)
        }
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(window.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(window.minimized ? 1 : 2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            if window.minimized { minimizedTag }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: WindowPreview.thumbnailSize.width, height: WindowPreview.textCardHeight,
               alignment: .topLeading)
        .background(box.fill(hovering ? Color.panelSelected : Color.panelFill))
    }

    private var minimizedTag: some View {
        Text(tr("已最小化"))
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .lineLimit(1)
    }
}
