import AppKit
import Observation
import SwiftUI

/// 输入法自动切换：切到某个 App 时按规则换输入法，换了就从刘海落下一个小胶囊提示。
///
/// 来源是 `NSWorkspace.didActivateApplicationNotification`；读、切输入法用系统的 TIS 接口
/// （`InputSourceService`），不要任何权限。判断都在 Core：切到哪个 `InputSourceResolver`
/// （规则 → 规则的输入法被删就用默认输入法 → 用默认输入法 / 记住上次 → 系统第一个），
/// 要不要提示、放哪 `InputSourceHint`。
///
/// 和码头自己的刘海内容：输入法提示是最低一档的灵动提示类。全屏、AI 刘海对话、提醒弹窗、
/// 消息卡、灵动提示（音量、亮度、会议）任何一个占着时直接不显示，不排队；提示正显示时
/// 它们出现，提示立刻收起。拾掇等刘海 App 的让位复用消息灵动岛的判断。
///
/// 按 App 规则是码头 Pro：没解锁时规则不生效（按没有规则处理），规则不改写。
@MainActor
final class InputSourceController {
    static let shared = InputSourceController()

    /// 「记住上次」记在本机，不进设置文件。
    static let memoryKey = "inputSource.memory"

    private var settings = InputSourceSettings()
    private var memory = InputSourceMemory()
    private var running = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var switchGeneration = 0
    private let hint = InputSourceHintController()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.memoryKey),
           let saved = try? JSONDecoder().decode(InputSourceMemory.self, from: data) {
            memory = saved
        }
        // 更高一档的刘海内容出现：提示马上收起。
        let center = NotificationCenter.default
        for name in [NotchMessageOccupancy.didChange, IslandOccupancy.didChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hint.yieldIfBlocked() }
            })
        }
    }

    private var rulesActive: Bool { ProLicenseGate.inputSourceRulesActive(unlocked: ProAccess.isUnlocked) }

    // MARK: 设置

    func apply(_ next: InputSourceSettings) {
        settings = next
        hint.settings = next
        if next.enabled { start() } else { stop() }
        if next.hint == .off { hint.dismiss(animated: false) }
    }

    private func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { self?.activated(bundleID: bundleID, pid: pid) }
        })
        // 用户在某个 App 里手动换了输入法：记下来，给「记住上次」用。
        let distributed = DistributedNotificationCenter.default()
        for name in InputSourceService.changeNotifications {
            distributedObservers.append(distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberCurrent() }
            })
        }
        rememberCurrent()
    }

    private func stop() {
        guard running else { return }
        running = false
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
        switchGeneration += 1
        hint.dismiss(animated: false)
    }

    // MARK: 记住上次

    /// 把现在的输入法记到前台 App 名下（码头自己不记）。输入法没变也要记一次，把这个 App
    /// 挪到最近用过，满 200 个时才不会先丢常用的；记录真的变了（值或先后）才写盘。
    private func rememberCurrent() {
        guard running, let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              !InputSourceResolver.isOwn(front) else { return }
        let before = memory
        memory.record(InputSourceService.currentID(), for: front)
        guard memory != before else { return }
        if let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.memoryKey)
        }
    }

    // MARK: 切

    private func activated(bundleID: String?, pid: pid_t?) {
        guard running, !InputSourceResolver.isOwn(bundleID) else { return }
        switchGeneration += 1
        let generation = switchGeneration
        let available = InputSourceService.available()
        let current = InputSourceService.currentID()
        let target = InputSourceResolver.target(for: bundleID, settings: settings, rulesActive: rulesActive,
                                                memory: memory, available: available)
        guard InputSourceResolver.shouldSwitch(current: current, target: target), let target else {
            // 不用切：也算用过一次，挪到「记住上次」的最近。
            return rememberCurrent()
        }
        let selected = InputSourceService.select(target.sourceID)
        // 有的输入法（多见于中日韩）在 App 刚激活时切了不立刻生效：稍等再看一眼，没变就再切一次。
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.running, self.switchGeneration == generation,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
            if InputSourceService.currentID() != target.sourceID { InputSourceService.select(target.sourceID) }
            self.rememberCurrent()
        }
        // 系统拒绝了就不提示「已切换」（上面 0.15 秒后还会再试一次）。
        guard selected, let source = InputSourceCatalog.find(target.sourceID, in: available) else { return }
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        hint.show(source: source, appIcon: app?.icon, pid: pid)
    }
}

// MARK: - 提示胶囊

/// 提示胶囊的窗口和时序：落下 0.25 秒、停留（默认 1 秒）、收回 0.2 秒；减少动态效果时淡入淡出。
@MainActor
final class InputSourceHintController {
    var settings = InputSourceSettings()
    let model = InputSourceHintModel()
    private var panel: NSPanel?
    private var generation = 0
    /// 等着读光标位置时先记着这次要显示的 App 图标（不跨任务传 NSImage）。
    private var pendingIcon: NSImage?

    /// 窗口四周给阴影留的透明边。
    static let pad: CGFloat = 18

    /// 刘海区被码头自己更高一档的内容占着吗。
    private func occupancy(windows: [NotchForeignWindow], screen: NSScreen) -> InputSourceHint.Occupancy {
        InputSourceHint.Occupancy(
            fullscreen: NotchFullscreen.isFullscreen(windows, screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                                     frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                                     ownPID: ProcessInfo.processInfo.processIdentifier),
            aiPanelOpen: AINotchController.shared.isOpen,
            reminderShowing: ReminderPopupCenter.shared.isShowing,
            messageCardExpanded: NotchMessageOccupancy.shared.cardExpanded,
            islandShowing: IslandOccupancy.shared.frame != nil)
    }

    func show(source: InputSourceInfo, appIcon: NSImage?, pid: pid_t?) {
        guard settings.hint != .off, let screen = NSScreen.screens.first else { return }
        let windows = NotchWindowScanner.windows()
        guard InputSourceHint.shouldShow(switched: true, position: settings.hint,
                                         occupancy: occupancy(windows: windows, screen: screen)) else {
            return dismiss(animated: false)
        }
        generation += 1
        let generation = generation
        let position = settings.hint
        let primaryHeight = screen.frame.height
        guard position == .cursor, let pid else {
            return present(source: source, appIcon: appIcon, caret: nil, trusted: AppWindows.isTrusted,
                           windows: windows, screen: screen, generation: generation)
        }
        // 焦点元素在 App 刚激活时还没就位，稍等再在后台读插入点。
        pendingIcon = appIcon
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            let caret = await Task.detached { InputSourceCaret.rect(pid: pid, primaryHeight: primaryHeight) }.value
            guard let self, self.generation == generation, let screen = NSScreen.screens.first else { return }
            // 等光标的这一会儿更高一档的刘海内容可能出来了：再看一眼，占着就不显示。
            guard !self.occupancy(windows: windows, screen: screen).blocked else { return }
            self.present(source: source, appIcon: self.pendingIcon, caret: caret, trusted: AppWindows.isTrusted,
                         windows: windows, screen: screen, generation: generation)
        }
    }

    private func present(source: InputSourceInfo, appIcon: NSImage?, caret: CGRect?, trusted: Bool,
                         windows: [NotchForeignWindow], screen: NSScreen, generation: Int) {
        let position = InputSourceHint.effectivePosition(settings.hint, trusted: trusted, caret: caret)
        // 光标旁：光标在哪块屏幕就按哪块收边，不然副屏上的光标会被收到主屏边上。
        var target = screen
        if position == .cursor, let caret,
           let caretScreen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY)) }) {
            target = caretScreen
        }
        let described = AINotchController.describe(target, isMain: target == NSScreen.screens.first)
        let nameWidth = (source.name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold)]).width.rounded(.up)
        let width = InputSourceHint.capsuleWidth(nameWidth: nameWidth)
        guard let placement = InputSourceHint.placement(position, screen: described, windows: windows,
                                                        caret: caret, width: width) else { return }
        let frame: CGRect
        switch placement {
        case .hang(let rect, let fromNotch):
            frame = rect
            model.style = .hang(fromNotch: fromNotch)
            if fromNotch, let notch = described.notch {
                let bar = AINotchLayout.menuBar(of: described)
                let entry = CGRect(x: notch.minX, y: bar.minY, width: notch.width, height: max(bar.height, 22))
                model.notchBlend = AINotchLayout.notchBlend(entry: entry, panel: rect)
            } else {
                model.notchBlend = nil
            }
        case .compact(let rect):
            frame = rect
            model.style = .compact
            model.notchBlend = nil
        case .cursor(let rect):
            frame = rect
            model.style = .cursor
            model.notchBlend = nil
        }
        model.glyph = InputSourceGlyph.of(source)
        model.name = source.name
        model.appIcon = appIcon
        model.size = frame.size
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let panel = panel ?? makePanel()
        let wasVisible = panel.isVisible && model.shown
        panel.setFrame(frame.insetBy(dx: -Self.pad, dy: -Self.pad), display: false)
        panel.orderFrontRegardless()
        if wasVisible {
            model.session = UUID()
        } else {
            model.shown = false
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.model.shown = true
            }
        }
        let stay = InputSourceHint.dropDuration + settings.hintSeconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(stay))
            guard let self, self.generation == generation else { return }
            self.dismiss(animated: true)
        }
    }

    /// 更高一档的刘海内容出现时让位：立刻收起，不排队。
    func yieldIfBlocked() {
        guard panel?.isVisible == true else { return }
        if NotchMessageOccupancy.shared.cardExpanded || IslandOccupancy.shared.frame != nil {
            dismiss(animated: false)
        }
    }

    func dismiss(animated: Bool) {
        generation += 1
        guard let panel, panel.isVisible else { return }
        model.shown = false
        guard animated else { return panel.orderOut(nil) }
        let generation = generation
        let duration = model.reduceMotion ? InputSourceHint.fadeDuration : InputSourceHint.retractDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            guard let self, self.generation == generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 240, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: InputSourceHintView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }
}

/// SwiftUI 那边读的状态。
@MainActor @Observable
final class InputSourceHintModel {
    enum Style: Equatable {
        /// 挂在刘海（或别的刘海 App 的窗口、菜单栏）下面。
        case hang(fromNotch: Bool)
        /// 刘海右侧一截，只有徽章和 App 图标。
        case compact
        /// 光标旁。
        case cursor
    }

    var style: Style = .hang(fromNotch: true)
    var glyph = InputSourceGlyph("A", .latin)
    var name = ""
    var appIcon: NSImage?
    /// 胶囊本身的大小（窗口四周还有 `InputSourceHintController.pad` 的透明边）。
    var size = CGSize(width: 220, height: 44)
    /// 黑色过渡在胶囊里的位置（胶囊坐标，原点左上），不接刘海时为 nil。
    var notchBlend: CGRect?
    var shown = false
    var reduceMotion = false
    /// 已经显示着又切了一次：换内容，不重新落下。
    var session = UUID()
}

// MARK: - 胶囊的样子

struct InputSourceHintView: View {
    var model: InputSourceHintModel

    private var pad: CGFloat { InputSourceHintController.pad }

    var body: some View {
        capsule
            .frame(width: model.size.width, height: model.size.height)
            .offset(y: hiddenOffset)
            .opacity(model.shown ? 1 : 0)
            .scaleEffect(model.style == .cursor && !model.shown && !model.reduceMotion ? 0.85 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(pad)
            // 挂在刘海下时从刘海里落下来：窗口上沿（刘海下沿）以上不画。
            .mask(alignment: .top) {
                Rectangle()
                    .padding(.top, clipsTop ? pad : 0)
            }
            .animation(animation, value: model.shown)
            .animation(.smooth(duration: 0.2), value: model.session)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tr("输入法已切换到 \(model.name)"))
    }

    private var clipsTop: Bool {
        if case .hang(true) = model.style { return true }
        return model.style == .compact
    }

    private var hiddenOffset: CGFloat {
        guard !model.shown, !model.reduceMotion else { return 0 }
        switch model.style {
        case .hang: return -model.size.height
        case .compact: return -model.size.height
        case .cursor: return 0
        }
    }

    private var animation: Animation {
        if model.reduceMotion { return .easeInOut(duration: InputSourceHint.fadeDuration) }
        return model.shown ? .easeOut(duration: InputSourceHint.dropDuration)
            : .easeIn(duration: InputSourceHint.retractDuration)
    }

    @ViewBuilder private var capsule: some View {
        switch model.style {
        case .compact: InputSourceCompactHint(model: model)
        case .hang(let fromNotch): InputSourceCapsule(model: model, fromNotch: fromNotch)
        case .cursor: InputSourceCapsule(model: model, fromNotch: false)
        }
    }
}

/// 字形徽章 + 输入法名 + App 图标，液态玻璃，跟随浅色 / 深色。
private struct InputSourceCapsule: View {
    var model: InputSourceHintModel
    var fromNotch: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: UnevenRoundedRectangle {
        let bottom = InputSourceHint.height / 2
        let top: CGFloat = fromNotch ? 10 : bottom
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            InputSourceGlyphBadge(glyph: model.glyph, size: InputSourceHint.glyphSize)
            Text(model.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: InputSourceHint.iconSize, height: InputSourceHint.iconSize)
                    .padding(.leading, 12)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, fromNotch ? AINotchLayout.notchBlendHeight : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .topLeading) {
                if reduceTransparency {
                    shape.fill(scheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F4F4F6"))
                } else {
                    Color.clear.glassEffect(.regular, in: shape)
                }
                if let blend = model.notchBlend {
                    InputSourceNotchBlend()
                        .frame(width: blend.width, height: blend.height)
                        .offset(x: blend.minX, y: blend.minY)
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.panelStroke, lineWidth: 0.6) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 12, y: 5)
        }
    }
}

/// 收纳架展开时刘海右侧那一截：和刘海一样是黑的（它就是刘海往右长出来的一点），只有
/// 字形徽章和 App 图标。
private struct InputSourceCompactHint: View {
    var model: InputSourceHintModel

    var body: some View {
        let side = max(18, min(24, model.size.height - 8))
        HStack(spacing: 6) {
            InputSourceGlyphBadge(glyph: model.glyph, size: side)
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 10, topTrailingRadius: 0, style: .continuous)
                .fill(.black)
        }
    }
}

/// 刘海下那条黑色过渡：顶边和刘海一样纯黑，往下淡到透明。
private struct InputSourceNotchBlend: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(0.85), location: 0.25),
            .init(color: .black.opacity(0.45), location: 0.55),
            .init(color: .black.opacity(0.12), location: 0.82),
            .init(color: .black.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 输入法的字形徽章：拼、A、あ、한 等，底色按语言。设置页和提示胶囊共用。
struct InputSourceGlyphBadge: View {
    var glyph: InputSourceGlyph
    var size: CGFloat

    static func color(_ tint: InputSourceGlyphTint) -> Color {
        switch tint {
        case .chinese: Color(hex: "#E5433D")
        case .latin: Color(hex: "#45454D")
        case .japanese: Color(hex: "#9A4CC4")
        case .korean: Color(hex: "#138A7E")
        case .other: Color(hex: "#2563EB")
        case .missing: Color(hex: "#76767D")
        }
    }

    var body: some View {
        let base = Self.color(glyph.tint)
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [base.opacity(0.88), base], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            }
            .overlay {
                Text(glyph.text)
                    .font(.system(size: max(13, size * 0.56), weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
