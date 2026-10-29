import AppKit
import Observation
import SwiftUI

/// 消息灵动岛（码头 Pro）：信息、WhatsApp、微信的通知到达时，在刘海下方展开一张液态
/// 玻璃消息卡；几秒后收起成刘海两侧的未读数（耳朵），或刘海旁的小胶囊。
///
/// 来源是系统通知横幅（`NotchBannerWatcher`，辅助功能，只读）。判断都在 Core：解析和
/// 去重 `NotchBannerParser` / `NotchMessageDeduper`，堆叠 `NotchMessageInbox`，自动收起
/// `NotchMessageCountdown`，和码头自己刘海内容的优先级 `NotchMessagePriority`，放哪
/// （自动让位拾掇等刘海 App）`NotchMessagePlacement`，全屏 `NotchFullscreen`。
///
/// 和码头自己的刘海内容：AI 刘海对话面板开着时不展开，只显示未读数；提醒弹窗显示时
/// 排队；卡片展开时灵动提示的小胶囊和 AI 刘海入口让位（`NotchMessageOccupancy`）。
/// 耳朵贴着刘海两边，不盖刘海本身（刘海是 AI 入口）。
@MainActor
final class NotchMessageController {
    static let shared = NotchMessageController()

    /// 「第一次回复前说明过自动化权限」记在这里。
    static let explainedKey = "notchMessage.automationExplained"

    private var settings = NotchMessageSettings()
    private(set) var active = false
    let model = NotchMessageModel()
    private let watcher = NotchBannerWatcher()
    private var dedupe = NotchMessageDeduper()
    /// 消息对应的系统横幅元素，点「打开」时替用户点一下它定位到聊天。
    private var banners: [UUID: BannerBox] = [:]

    private var card: KeyablePanel?
    private var leftEar: NotchIndicatorWindow?
    private var rightEar: NotchIndicatorWindow?
    private var capsule: NotchIndicatorWindow?

    private var countdown = NotchMessageCountdown()
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    /// 有新消息等着展开（被提醒弹窗、拾掇面板挡着时从这时开始算等了多久）。
    private var pendingSince: Date?
    private var lastArrival: Date?
    /// 自动让位等太久，这一轮收起态改用胶囊。
    private var forcedCapsule = false
    private var anchor: Anchor = .hang(top: 0, fromNotch: true)
    private var contentHeight: CGFloat = 220
    private var hideGeneration = 0
    private var hovering = false
    private var lastUnlocked = ProAccess.isUnlocked
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private enum Anchor: Equatable {
        case hang(top: CGFloat, fromNotch: Bool)
        case capsule(CGRect)
    }

    private struct BannerBox: @unchecked Sendable { var element: AXUIElement }

    /// 卡片窗口左右给阴影留的透明边，下面给后两张叠层和阴影留的高度。
    static let sideInset: CGFloat = 24
    static let bottomAllowance: CGFloat = 40

    private init() {
        model.act = { [weak self] action in self?.perform(action) }
        model.hover = { [weak self] inside in self?.hover(inside) }
        model.heightChanged = { [weak self] height in self?.heightChanged(height) }
        watcher.onFound = { [weak self] found, priming in self?.received(found, priming: priming) }
        // 授权（试用、激活、到期）变了：重新判断要不要观察。
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let unlocked = ProAccess.isUnlocked
                guard unlocked != self.lastUnlocked else { return }
                self.lastUnlocked = unlocked
                self.apply(self.settings)
            }
        })
    }

    // MARK: 设置

    func apply(_ next: NotchMessageSettings) {
        settings = next
        model.position = next.position
        let shouldRun = ProLicenseGate.notchMessageActive(next, unlocked: ProAccess.isUnlocked)
        if shouldRun {
            start()
            watcher.update(apps: next.apps)
            for app in NotchMessageApp.allCases where !next.isOn(app) { model.inbox.clear(app) }
        } else {
            stop()
        }
        refresh()
    }

    private func start() {
        guard !active else { return }
        active = true
        watcher.start(apps: settings.apps)
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.appActivated(bundleID) }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.collapse(animated: false)
                self.refresh()
            }
        })
    }

    private func stop() {
        guard active else { return }
        active = false
        watcher.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.removeAll()
        model.inbox.clearAll()
        banners.removeAll()
        pendingSince = nil
        forcedCapsule = false
        collapse(animated: false)
        hideIndicators()
        stopTimer()
    }

    // MARK: 收到横幅

    private func received(_ found: [NotchBannerWatcher.Found], priming: Bool) {
        guard active else { return }
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var fresh = false
        var testArrived = false
        for item in found {
            let key = item.incoming.key
            if priming {
                dedupe.remember(key, now: now)
                continue
            }
            // 设置里「发一条测试通知」读回来的：不看 App 开关和前台 App，弹一张不能回复的卡。
            if item.incoming.isTest {
                guard dedupe.isNew(key, now: now) else { continue }
                probeReceived(now: now)
                model.inbox.receive(NotchMessage(item.incoming, date: now), makeCurrent: !model.replying)
                fresh = true
                testArrived = !model.replying
                continue
            }
            guard dedupe.isNew(key, now: now), settings.isOn(item.incoming.app) else { continue }
            NotchMessageStatus.shared.sawMessage(at: now)
            // 正在看这个 App：不另外弹。
            if let front, NotchMessageApp.match(bundleID: front) == item.incoming.app { continue }
            let message = NotchMessage(item.incoming, date: now)
            model.inbox.receive(message, makeCurrent: !model.replying)
            if let element = item.element { banners[message.id] = BannerBox(element: element) }
            fresh = true
        }
        guard fresh else { return }
        let alive = Set(model.inbox.messages.map(\.id))
        banners = banners.filter { alive.contains($0.key) }
        lastArrival = now
        // 测试是用户在设置里点的：不管位置选的是不是小胶囊，直接展开给他看。
        if testArrived, !model.expanded {
            userExpand()
            return
        }
        if model.expanded {
            if !model.replying, !hovering { countdown.start(Double(settings.dismissSeconds), at: now) }
        } else {
            pendingSince = pendingSince ?? now
        }
        refresh()
    }

    // MARK: 测试通知

    /// 设置里「发一条测试通知」：码头自己发一条通知，读到后弹卡；等 `NotchMessageProbe.timeout`
    /// 秒没读到，设置里写「没读到」和原因。
    func sendTestNotification() {
        let status = NotchMessageStatus.shared
        guard active else {
            status.probe.inactive()
            return
        }
        Task { @MainActor [weak self] in
            guard let token = await NotchMessageProbeSender.send() else {
                status.probe.notificationsOff()
                return
            }
            guard let self, self.active else {
                status.probe.inactive()
                return
            }
            self.watcher.probeToken = token
            status.probe.sent(token: token, at: Date())
            try? await Task.sleep(for: .seconds(NotchMessageProbe.timeout + 0.5))
            guard status.probe.token == token else { return }
            status.probe.tick(now: Date())
            if self.watcher.probeToken == token { self.watcher.probeToken = nil }
        }
    }

    private func probeReceived(now: Date) {
        let status = NotchMessageStatus.shared
        if let token = watcher.probeToken { NotchMessageProbeSender.withdraw(token) }
        watcher.probeToken = nil
        status.probe.received(at: now)
    }

    /// 用户自己打开了消息所在的 App：它的未读清掉。
    private func appActivated(_ bundleID: String?) {
        guard active, let app = NotchMessageApp.match(bundleID: bundleID) else { return }
        model.inbox.clear(app)
        if model.inbox.current == nil { collapse(animated: true) }
        refresh()
    }

    // MARK: 判断现在画什么

    private var screen: NSScreen? { NSScreen.screens.first }

    /// 按优先级和位置重新摆一遍：卡片、耳朵或胶囊。定时器和各种事件都走这里。
    private func refresh() {
        guard active, let screen else {
            collapse(animated: false)
            hideIndicators()
            stopTimer()
            return
        }
        let now = Date()
        if model.inbox.isEmpty {
            collapse(animated: true)
            hideIndicators()
            pendingSince = nil
            forcedCapsule = false
            stopTimer()
            return
        }
        let described = AINotchController.describe(screen, isMain: true)
        let windows = NotchWindowScanner.windows()
        let context = NotchMessagePriority.Context(
            fullscreen: NotchFullscreen.isFullscreen(windows, screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                                     frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                                     ownPID: ProcessInfo.processInfo.processIdentifier),
            aiPanelOpen: AINotchController.shared.isOpen,
            reminderShowing: ReminderPopupCenter.shared.isShowing)
        let waited = pendingSince.map { now.timeIntervalSince($0) } ?? 0

        switch NotchMessagePriority.stage(context, waited: waited) {
        case .suppressed:
            collapse(animated: false)
            hideIndicators()
            pendingSince = nil
        case .indicatorOnly:
            collapse(animated: true)
            // AI 对话面板关上后，最近到的还展开；提醒弹窗等太久就不再展开。
            if !context.aiPanelOpen { pendingSince = nil }
            showIndicator(described, windows: windows)
        case .hold:
            // 提醒弹窗也在刘海下面：卡片先收起让它，收起后最近到的再展开。
            if model.expanded {
                collapse(animated: true)
                pendingSince = pendingSince ?? now
                lastArrival = lastArrival.map { max($0, now) } ?? now
            }
            showIndicator(described, windows: windows)
        case .show:
            if model.expanded {
                if countdown.expired(at: now) {
                    collapse(animated: true)
                    showIndicator(described, windows: windows)
                }
            } else if pendingSince != nil {
                guard NotchMessagePriority.expandsAfterWait(arrival: lastArrival, now: now) else {
                    pendingSince = nil
                    showIndicator(described, windows: windows)
                    break
                }
                switch NotchMessagePlacement.card(settings.position, screen: described, windows: windows, waited: waited) {
                case .hang(let top, let fromNotch):
                    pendingSince = nil
                    forcedCapsule = false
                    // 新到的那条在最上面（之前点过稍后的不抢先）。
                    model.inbox.focus(nil)
                    expand(.hang(top: top, fromNotch: fromNotch), screen: described)
                case .wait:
                    showIndicator(described, windows: windows)
                case .capsule:
                    pendingSince = nil
                    if settings.position == .auto { forcedCapsule = true }
                    showIndicator(described, windows: windows)
                }
            } else {
                showIndicator(described, windows: windows)
            }
        }
        scheduleTimer()
    }

    // MARK: 卡片

    private func expand(_ anchor: Anchor, screen described: AINotchScreen) {
        self.anchor = anchor
        let panel = card ?? makeCard()
        let frame = cardFrame(anchor, screen: described)
        panel.setFrame(frame, display: false)
        if case .hang(_, true) = anchor, let notch = described.notch {
            let bar = AINotchLayout.menuBar(of: described)
            let entry = CGRect(x: notch.minX, y: bar.minY, width: notch.width, height: max(bar.height, 22))
            let cardRect = frame.insetBy(dx: Self.sideInset, dy: 0)
            model.fromNotch = true
            model.notchBlend = AINotchLayout.notchBlend(entry: entry, panel: cardRect)
        } else {
            model.fromNotch = false
            model.notchBlend = nil
        }
        model.replying = false
        model.draft = ""
        model.notice = nil
        model.sending = false
        model.expanded = true
        model.session = UUID()
        hideGeneration += 1
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hovering = false
        countdown.start(Double(settings.dismissSeconds), at: Date())
        hideIndicators()
        NotchMessageOccupancy.shared.update(frame)
    }

    private func cardFrame(_ anchor: Anchor, screen described: AINotchScreen) -> CGRect {
        let size = CGSize(width: NotchMessagePlacement.cardWidth + Self.sideInset * 2,
                          height: contentHeight + Self.bottomAllowance)
        switch anchor {
        case .hang(let top, _):
            return NotchMessagePlacement.cardFrame(top: top, screen: described, size: size)
        case .capsule(let pill):
            let frame = NotchMessagePlacement.cardFrame(belowCapsule: pill, screen: described,
                                                        size: CGSize(width: NotchMessagePlacement.cardWidth,
                                                                     height: size.height))
            return frame.insetBy(dx: -Self.sideInset, dy: 0)
        }
    }

    /// 内容高度变了（回复框、提示、换了一条）：顶边不动，窗口跟着长短。
    private func heightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard model.expanded, let card, let screen else { return }
        let frame = cardFrame(anchor, screen: AINotchController.describe(screen, isMain: true))
        card.setFrame(frame, display: true)
        NotchMessageOccupancy.shared.update(frame)
    }

    private func collapse(animated: Bool) {
        guard model.expanded else { return }
        model.expanded = false
        model.replying = false
        // 测试那条看过就走，不在刘海旁边留未读数。
        model.inbox.clearTests()
        countdown.stop()
        hovering = false
        NotchMessageOccupancy.shared.update(nil)
        guard let card else { return }
        hideGeneration += 1
        let generation = hideGeneration
        if !animated {
            card.orderOut(nil)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self, self.hideGeneration == generation, !self.model.expanded else { return }
            card.orderOut(nil)
        }
    }

    private func makeCard() -> KeyablePanel {
        let size = CGSize(width: NotchMessagePlacement.cardWidth + Self.sideInset * 2, height: 300)
        let panel = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = FirstMouseHostingView(rootView: NotchMessageCardView(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.perform(.dismiss) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar
        card = panel
        return panel
    }

    // MARK: 收起态

    private func showIndicator(_ described: AINotchScreen, windows: [NotchForeignWindow]) {
        guard !model.expanded else { return hideIndicators() }
        let apps = model.inbox.unreadCounts.count
        guard apps > 0 else { return hideIndicators() }
        let position: NotchMessagePosition = forcedCapsule ? .capsule : settings.position
        switch NotchMessagePlacement.indicator(position, screen: described, windows: windows, apps: apps) {
        case .ears(let left, let right):
            capsule?.orderOut(nil)
            leftEar = place(leftEar, .leftEar, frame: left)
            if let right {
                rightEar = place(rightEar, .rightEar, frame: right)
            } else {
                rightEar?.orderOut(nil)
            }
        case .capsule(let frame):
            leftEar?.orderOut(nil)
            rightEar?.orderOut(nil)
            capsule = place(capsule, .capsule, frame: frame)
        }
    }

    private func place(_ existing: NotchIndicatorWindow?, _ kind: NotchIndicatorKind, frame: CGRect) -> NotchIndicatorWindow {
        let window = existing ?? NotchIndicatorWindow.make(kind: kind, model: model)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
        return window
    }

    private func hideIndicators() {
        leftEar?.orderOut(nil)
        rightEar?.orderOut(nil)
        capsule?.orderOut(nil)
    }

    // MARK: 定时

    /// 卡片开着或有消息等着展开时每 0.25 秒看一次（倒计时、AI 面板、拾掇收没收起）；
    /// 只有收起态时每 2 秒看一次（进出全屏）；什么都没有时不跑。
    private func scheduleTimer() {
        let interval: TimeInterval
        if model.expanded || pendingSince != nil {
            interval = 0.25
        } else if !model.inbox.isEmpty {
            interval = 2
        } else {
            return stopTimer()
        }
        guard timer == nil || timerInterval != interval else { return }
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        next.tolerance = interval * 0.2
        RunLoop.main.add(next, forMode: .common)
        timer = next
        timerInterval = interval
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerInterval = 0
    }

    // MARK: 按钮

    private func hover(_ inside: Bool) {
        hovering = inside
        guard model.expanded, !model.replying else { return }
        let now = Date()
        if inside { countdown.pause(at: now) } else { countdown.resume(at: now) }
    }

    private func perform(_ action: NotchMessageAction) {
        switch action {
        case .reply:
            guard let current = model.inbox.current else { return }
            guard current.canReplyInline else { return perform(.open) }
            model.replying = true
            model.notice = nil
            model.showPermissionHint = !UserDefaults.standard.bool(forKey: Self.explainedKey)
            countdown.stop()
            card?.makeKey()
        case .send:
            send()
        case .later:
            model.replying = false
            model.notice = nil
            if model.inbox.later() {
                model.session = UUID()
                countdown.start(Double(settings.dismissSeconds), at: Date())
            } else {
                collapse(animated: true)
            }
            refresh()
        case .open:
            guard let current = model.inbox.current else { return }
            if current.isTest {
                collapse(animated: true)
                refresh()
                return
            }
            NotchMessageOpener.open(current.app, banner: banners[current.id]?.element)
            model.inbox.handle(current.id)
            collapse(animated: true)
            refresh()
        case .dismiss:
            collapse(animated: true)
            refresh()
        case .expand(let app):
            model.inbox.focus(app)
            userExpand()
        }
    }

    /// 点耳朵或胶囊展开：不再排队（用户自己点的），放不下就挂在胶囊下面。
    private func userExpand() {
        guard active, let screen, model.inbox.current != nil else { return }
        let described = AINotchController.describe(screen, isMain: true)
        let windows = NotchWindowScanner.windows()
        let position: NotchMessagePosition = forcedCapsule ? .capsule : settings.position
        pendingSince = nil
        if case .hang(let top, let fromNotch) = NotchMessagePlacement.card(position, screen: described, windows: windows,
                                                                           waited: .infinity) {
            expand(.hang(top: top, fromNotch: fromNotch), screen: described)
        } else {
            let pill = capsule?.isVisible == true ? capsule!.frame
                : NotchMessagePlacement.capsuleFrame(screen: described, windows: windows,
                                                     apps: model.inbox.unreadCounts.count)
            expand(.capsule(pill), screen: described)
        }
        scheduleTimer()
    }

    private func send() {
        guard let current = model.inbox.current, let recipient = current.sender, !model.sending,
              let text = NotchMessageReply.normalized(model.draft) else { return }
        model.sending = true
        model.notice = nil
        let id = current.id
        Task { @MainActor [weak self] in
            let outcome = await MessagesReplier.send(text, to: recipient)
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: Self.explainedKey)
            self.model.showPermissionHint = false
            self.model.sending = false
            if outcome == .sent {
                self.model.draft = ""
                self.model.replying = false
                if self.model.inbox.handle(id), self.model.expanded {
                    self.model.session = UUID()
                    self.countdown.start(Double(self.settings.dismissSeconds), at: Date())
                } else {
                    self.collapse(animated: true)
                }
                self.refresh()
                return
            }
            self.model.notice = NotchMessageReply.message(outcome)
            if outcome != .denied { NotchMessageOpener.activate(.messages) }
        }
    }
}

/// 卡片上的按钮。
enum NotchMessageAction: Equatable {
    case reply, send, later, open, dismiss
    /// 从收起态点开（点的是哪个 App 的未读，nil 是最新一条）。
    case expand(NotchMessageApp?)
}

/// 卡片展开时占的地方，给灵动提示和 AI 刘海入口让位用。变了发 `didChange`。
@MainActor
final class NotchMessageOccupancy {
    static let shared = NotchMessageOccupancy()
    nonisolated static let didChange = Notification.Name("DocklingNotchMessageOccupancyDidChange")

    private(set) var frame: CGRect?
    var cardExpanded: Bool { frame != nil }

    private init() {}

    func update(_ next: CGRect?) {
        guard next != frame else { return }
        let wasExpanded = cardExpanded
        frame = next
        if wasExpanded != cardExpanded || next != nil {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}

/// SwiftUI 那边读的状态。
@MainActor @Observable
final class NotchMessageModel {
    var inbox = NotchMessageInbox()
    var expanded = false
    /// 正接在刘海下面（顶上画黑色过渡）。
    var fromNotch = true
    /// 黑色过渡在卡片里的位置（卡片坐标，原点左上），不接刘海时为 nil。
    var notchBlend: CGRect?
    var replying = false
    var draft = ""
    var sending = false
    /// 卡片底下的一句话（回复没发出去的原因）。
    var notice: String?
    var showPermissionHint = false
    /// 每次展开、换一条时换一个，重放出场动画。
    var session = UUID()
    var position: NotchMessagePosition = .auto

    @ObservationIgnored var act: ((NotchMessageAction) -> Void)?
    @ObservationIgnored var hover: ((Bool) -> Void)?
    @ObservationIgnored var heightChanged: ((CGFloat) -> Void)?
}

// MARK: - 收起态的窗口

enum NotchIndicatorKind {
    /// 刘海左边的耳朵：第一个有未读的 App。
    case leftEar
    /// 刘海右边的耳朵：其余的 App。
    case rightEar
    /// 刘海旁小胶囊：全部。
    case capsule
}

/// 耳朵和胶囊：无边框、不抢焦点、在菜单栏之上，点一个 App 的未读展开它的消息。
@MainActor
final class NotchIndicatorWindow: NSPanel {
    static func make(kind: NotchIndicatorKind, model: NotchMessageModel) -> NotchIndicatorWindow {
        let window = NotchIndicatorWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = FirstMouseHostingView(rootView: NotchIndicatorView(kind: kind, model: model))
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        return window
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
