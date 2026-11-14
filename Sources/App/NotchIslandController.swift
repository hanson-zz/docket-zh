import AppKit
import Observation
import SwiftUI

/// 刘海小岛（码头 Pro，默认关）：从刘海两侧长出的黑色小岛，和刘海连成一体，显示码头
/// 自己正在进行的事。没有刘海的屏幕在顶部居中画一个同样形状的假刘海。
///
/// 活动来源都是现成的：
/// - 下载：下载完成监视 `DesktopPetDownloadsWatcher`（和小熊猫共用，各有各的回调），
///   顺带读「下载」里未完成文件的进度（`DownloadProgress`），拿不到进度只转圈；
/// - 计时器：专注计时 `TimerStateProvider`，以及每个布局里每张倒计时卡片在跑或暂停的
///   计时器（`TimedAlertDriver.widgets`，`NotchIslandTimer.countdowns`）；同时几个时留
///   最先结束的那个（`NotchIslandStack.ordered`）；
/// - 会议：「灵动提示」的会议倒计时找到的那一个（`IslandController.meeting`）；
/// - 收音机：`RadioPlayer`；
/// - 插电：插电霓虹动画 `BatteryNeonPlugController` 看到插上电源时叫 `pluggedIn`。
///
/// 判断都在 Core：活动栈和优先级 `NotchIslandStack`，什么时候不显示 `NotchIslandGate`，
/// 几何 `NotchIslandLayout`，下载的空档和打勾 `NotchIslandDownloadTracker`。
///
/// 和码头自己的刘海内容：消息灵动岛的卡片展开时小岛让位；小岛显示时消息的耳朵和
/// AI 刘海入口让给小岛（`NotchIslandOccupancy`）；插电霓虹动画播放时小岛先让开；
/// 「灵动提示」的音量、亮度胶囊闪着时小岛先收起，会议倒计时胶囊在小岛显示时交给
/// 小岛（`NotchIslandCapsule`）；演示模式和全屏 App 时不显示。
@MainActor
final class NotchIslandController {
    static let shared = NotchIslandController()

    private static let downloadClient = "notchIsland"

    private var settings = NotchIslandSettings()
    private(set) var active = false
    let model = NotchIslandModel()
    private var window: NotchIslandWindow?

    private var downloads = NotchIslandDownloadTracker()
    private var charging: (percent: Int, until: Date)?
    /// 在小岛上按了暂停的收音机，留一会儿方便继续。
    private var radioHold: (station: String, until: Date)?
    private var plugAnimationUntil: Date?
    /// 「灵动提示」的音量、亮度胶囊正闪着。
    private var levelFlash = false

    /// 指针在小岛（或展开的卡片）上，以及停够了要展开。
    private var pointerInside = false
    private var wantsExpanded = false
    private var hoverTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    private var hideGeneration = 0
    private var mouseMonitors: [Any] = []

    /// 窗口现在的半宽和高度（原点坐标）：长大马上长，缩小等动画走完。
    private var windowExtent: (halfWidth: CGFloat, height: CGFloat) = (0, 0)
    private var placement: (centerX: CGFloat, top: CGFloat) = (0, 0)
    private var hotZone: CGRect = .null

    private var fullscreen = false
    private var lastFullscreenCheck = Date.distantPast
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastUnlocked = ProAccess.isUnlocked
    private var observing = false

    private init() {
        model.act = { [weak self] action in self?.perform(action) }
        // 授权（试用、激活、到期）变了：重新判断要不要显示。
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
        // 消息灵动岛的卡片展开、收起：小岛让位、回来。
        observers.append(NotificationCenter.default.addObserver(
            forName: NotchMessageOccupancy.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windowExtent = (0, 0)
                self.refresh()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastFullscreenCheck = .distantPast
                self?.refresh()
            }
        })
    }

    // MARK: 设置

    func apply(_ next: NotchIslandSettings) {
        settings = next
        if ProLicenseGate.notchIslandActive(next, unlocked: ProAccess.isUnlocked) {
            start()
        } else {
            stop()
        }
        refresh()
    }

    private func start() {
        active = true
        if settings.isOn(.download) {
            DesktopPetDownloadsWatcher.shared.start(
                client: Self.downloadClient,
                onFinished: { _ in NotchIslandController.shared.downloadFinished() },
                onProgress: { fractions in NotchIslandController.shared.downloadProgress(fractions) })
        } else {
            DesktopPetDownloadsWatcher.shared.stop(client: Self.downloadClient)
            downloads = NotchIslandDownloadTracker()
        }
        if !settings.isOn(.charging) { charging = nil }
        if !settings.isOn(.radio) { radioHold = nil }
        startTicker()
        if !observing {
            observing = true
            observeSources()
        }
    }

    private func stop() {
        guard active else { return }
        active = false
        DesktopPetDownloadsWatcher.shared.stop(client: Self.downloadClient)
        downloads = NotchIslandDownloadTracker()
        charging = nil
        radioHold = nil
        ticker?.invalidate()
        ticker = nil
        hide(animated: false)
    }

    /// 专注计时、收音机一变就重排（不靠每秒的定时器，按下暂停马上跟上）。
    private func observeSources() {
        guard active else {
            observing = false
            return
        }
        withObservationTracking {
            _ = TimerStateProvider.shared.state
            _ = RadioPlayer.shared.isPlaying
            _ = RadioPlayer.shared.station
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeSources()
            }
        }
    }

    /// 每秒看一次：插电提示、下载的勾到点收起，演示模式、全屏变了。
    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { NotchIslandController.shared.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: 来源

    private func downloadProgress(_ fractions: [Double?]) {
        guard active, settings.isOn(.download) else { return }
        downloads.progress(fractions, now: Date())
        refresh()
    }

    private func downloadFinished() {
        guard active, settings.isOn(.download) else { return }
        downloads.finished(now: Date())
        refresh()
    }

    /// 插电霓虹动画看到插上电源时叫这里。动画播了就让它的电量胶囊来，小岛先让开。
    func pluggedIn(percent: Int, plugAnimation: Bool) {
        guard active, settings.isOn(.charging) else { return }
        let now = Date()
        if plugAnimation {
            plugAnimationUntil = now.addingTimeInterval(BatteryNeon.Plug.total)
            charging = nil
        } else {
            charging = (percent, now.addingTimeInterval(NotchIslandTiming.chargeLinger))
        }
        refresh()
    }

    /// 「灵动提示」的音量、亮度胶囊出现、消失时叫这里：闪着时小岛先收起。
    func levelFlashChanged(_ on: Bool) {
        guard on != levelFlash else { return }
        levelFlash = on
        guard active else { return }
        refresh()
    }

    /// 「灵动提示」的会议倒计时换了一个（或没了）时叫这里，不用等下一秒。
    func meetingChanged() {
        guard active, settings.isOn(.meeting) else { return }
        refresh()
    }

    // MARK: 判断现在画什么

    /// 带刘海的那块屏幕；没有就是带菜单栏的主屏（模拟刘海）。
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func activities(now: Date) -> [NotchIslandActivity] {
        var list: [NotchIslandActivity] = []
        if let charging {
            if now < charging.until {
                list.append(.charging(percent: charging.percent))
            } else {
                self.charging = nil
            }
        }
        downloads.tick(now: now)
        if let download = downloads.activity(now: now) { list.append(download) }
        if settings.isOn(.timer) {
            if let timer = NotchIslandTimer.activity(TimerStateProvider.shared.state, now: now) { list.append(timer) }
            for widget in TimedAlertDriver.shared.widgets() where widget.kind == .countdown {
                list += NotchIslandTimer.countdowns(widget: widget.id, config: widget.config, now: now)
            }
        }
        if settings.isOn(.meeting), let meeting = NotchIslandCapsule.meetingActivity(IslandController.shared.meeting) {
            list.append(meeting)
        }
        let radio = RadioPlayer.shared
        if radio.isPlaying, let station = radio.station {
            radioHold = nil
            list.append(.radio(station: station.name, playing: true))
        } else if let hold = radioHold {
            if now < hold.until {
                list.append(.radio(station: hold.station, playing: false))
            } else {
                radioHold = nil
            }
        }
        return list
    }

    private func refresh() {
        guard active, let screen else { return hide(animated: false) }
        let now = Date()
        let ordered = NotchIslandStack.ordered(activities(now: now), settings: settings)
        guard !ordered.isEmpty else { return hide(animated: true) }

        if now.timeIntervalSince(lastFullscreenCheck) >= 2 {
            lastFullscreenCheck = now
            fullscreen = NotchFullscreen.isFullscreen(
                NotchWindowScanner.windows(), screen: screen.frame, topInset: screen.safeAreaInsets.top,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                ownPID: ProcessInfo.processInfo.processIdentifier)
        }
        if let until = plugAnimationUntil, now >= until { plugAnimationUntil = nil }
        let context = NotchIslandGate.Context(
            active: active,
            presenting: QuickActions.shared.presentation != nil,
            fullscreen: fullscreen,
            messageCard: NotchMessageOccupancy.shared.cardExpanded,
            plugAnimation: plugAnimationUntil != nil,
            levelFlash: levelFlash)
        guard NotchIslandGate.visible(context) else { return hide(animated: true) }
        guard let form = NotchIslandStack.form(ordered, hovering: wantsExpanded) else { return hide(animated: true) }
        show(form, on: screen)
    }

    // MARK: 窗口

    private func show(_ form: NotchIslandForm, on screen: NSScreen) {
        let described = AINotchController.describe(screen, isMain: true)
        let geometry = NotchIslandLayout.geometry(screen: described)
        let centerX = NotchIslandLayout.centerX(screen: described)
        let top = described.frame.maxY
        let needed = NotchIslandLayout.extent(NotchIslandLayout.pieces(geometry, form: form))

        hideGeneration += 1
        let moved = placement.centerX != centerX || placement.top != top
        placement = (centerX, top)
        if moved || model.form == nil {
            windowExtent = needed
        } else if needed.halfWidth > windowExtent.halfWidth || needed.height > windowExtent.height {
            // 长大：马上把窗口放大（以刘海中线对称，里面的东西不会跳），再让内容弹出去。
            windowExtent = (max(windowExtent.halfWidth, needed.halfWidth), max(windowExtent.height, needed.height))
        }
        if needed.halfWidth < windowExtent.halfWidth || needed.height < windowExtent.height {
            scheduleShrink(to: needed)
        } else {
            shrinkTask?.cancel()
            shrinkTask = nil
        }

        let window = window ?? makeWindow()
        let frame = NotchIslandLayout.windowFrame(centerX: centerX, screenTop: top,
                                                  halfWidth: windowExtent.halfWidth, height: windowExtent.height)
        if window.frame != frame { window.setFrame(frame, display: true) }

        model.geometry = geometry
        if case .expanded(.radio(_, _), _) = form {
            model.radioVolume = RadioPlayer.shared.currentVolume
            model.canSwitchStation = RadioPlayer.shared.canSwitchStation
        }
        if model.form != form { model.form = form }
        if !window.isVisible { window.orderFrontRegardless() }

        hotZone = NotchIslandLayout.screenRect(NotchIslandLayout.hotZone(geometry, form: form),
                                               centerX: centerX, screenTop: top)
        installMouseMonitors()
        NotchIslandOccupancy.shared.update(frame, expanded: form.isExpanded)
    }

    /// 内容缩回去以后再把窗口缩小，免得收起动画被窗口边裁掉。
    private func scheduleShrink(to needed: (halfWidth: CGFloat, height: CGFloat)) {
        shrinkTask?.cancel()
        shrinkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchIslandTiming.shrinkDelay))
            guard let self, !Task.isCancelled, let window = self.window, window.isVisible,
                  let form = self.model.form else { return }
            let current = NotchIslandLayout.extent(NotchIslandLayout.pieces(self.model.geometry, form: form))
            self.windowExtent = current
            let frame = NotchIslandLayout.windowFrame(centerX: self.placement.centerX, screenTop: self.placement.top,
                                                      halfWidth: current.halfWidth, height: current.height)
            if window.frame != frame { window.setFrame(frame, display: true) }
            NotchIslandOccupancy.shared.update(frame, expanded: form.isExpanded)
        }
    }

    private func hide(animated: Bool) {
        hoverTask?.cancel()
        hoverTask = nil
        shrinkTask?.cancel()
        shrinkTask = nil
        pointerInside = false
        wantsExpanded = false
        removeMouseMonitors()
        hotZone = .null
        NotchIslandOccupancy.shared.update(nil, expanded: false)
        guard model.form != nil || window?.isVisible == true else { return }
        model.form = nil
        guard let window else { return }
        hideGeneration += 1
        let generation = hideGeneration
        if !animated {
            window.orderOut(nil)
            windowExtent = (0, 0)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchIslandTiming.shrinkDelay))
            guard let self, self.hideGeneration == generation, self.model.form == nil else { return }
            window.orderOut(nil)
            self.windowExtent = (0, 0)
        }
    }

    private func makeWindow() -> NotchIslandWindow {
        let window = NotchIslandWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
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
        let host = FirstMouseHostingView(rootView: NotchIslandRootView(model: model))
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        self.window = window
        return window
    }

    // MARK: 悬停

    /// 看指针在不在小岛上：全局和本进程的鼠标移动都听（只在小岛显示时），不用辅助功能权限。
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            MainActor.assumeIsolated { NotchIslandController.shared.pointerMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { NotchIslandController.shared.pointerMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }

    private func pointerMoved() {
        guard active, model.form != nil else { return }
        let inside = hotZone.contains(NSEvent.mouseLocation)
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverTask?.cancel()
        let delay = inside ? NotchIslandTiming.hoverDelay : NotchIslandTiming.leaveDelay
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.pointerInside == inside, self.wantsExpanded != inside else { return }
            self.wantsExpanded = inside
            self.refresh()
        }
    }

    // MARK: 卡片上的按钮

    private func perform(_ action: NotchIslandAction) {
        let radio = RadioPlayer.shared
        switch action {
        case .radioToggle:
            if radio.isPlaying {
                if let station = radio.station {
                    radioHold = (station.name, Date().addingTimeInterval(NotchIslandTiming.radioPauseLinger))
                }
                radio.pause()
            } else {
                radioHold = nil
                radio.resume()
            }
        case .radioNext:
            radio.switchStation(by: 1)
        case .radioVolume(let level):
            radio.setVolume(level)
        case .timerToggle(.focus):
            commitTimer(NotchIslandTimer.toggled(TimerStateProvider.shared.state, now: Date()))
        case .timerEnd(.focus):
            commitTimer(NotchIslandTimer.ended(TimerStateProvider.shared.state))
        case .timerToggle(.countdown(let widget, let timer)):
            let now = Date()
            writeCountdown(widget, timer: timer) { NotchIslandTimer.toggled($0, now: now) }
        case .timerEnd(.countdown(let widget, let timer)):
            writeCountdown(widget, timer: timer) { CountdownList.stopping($0) }
        case .openDownloads:
            DesktopPetDownloadsWatcher.reveal([])
        case .openCalendar:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.open(url)
            }
        }
        refresh()
    }

    /// 改倒计时卡片里的那一个计时器（卡片可能在文件夹或别的布局里，从 `WidgetWriter` 走）。
    private func writeCountdown(_ widget: UUID, timer: String,
                                _ change: (CountdownTimer) -> CountdownTimer) {
        guard let instance = WidgetWriter.current(widget) else { return }
        WidgetWriter.write(instance) { config in
            CountdownList.update(timer, in: &config) { $0 = change($0) }
        }
    }

    private func commitTimer(_ state: TimerState) {
        TimerStateProvider.shared.state = state
        FocusAmbientDriver.shared.sync(state)
    }
}

/// 卡片上的按钮。
enum NotchIslandAction: Equatable {
    case radioToggle, radioNext
    case radioVolume(Double)
    /// 作用到卡片上显示的那一个计时器。
    case timerToggle(NotchIslandTimerSource)
    case timerEnd(NotchIslandTimerSource)
    case openDownloads
    case openCalendar
}

/// 小岛占的地方，给 AI 刘海入口、消息灵动岛的耳朵和插电动画让位用。变了发 `didChange`。
@MainActor
final class NotchIslandOccupancy {
    static let shared = NotchIslandOccupancy()
    nonisolated static let didChange = Notification.Name("DocklingNotchIslandOccupancyDidChange")

    /// 窗口在屏幕上的范围，不显示时 nil。
    private(set) var frame: CGRect?
    /// 正展开成卡片。
    private(set) var expanded = false

    private init() {}

    func update(_ next: CGRect?, expanded nextExpanded: Bool) {
        guard next != frame || nextExpanded != expanded else { return }
        frame = next
        expanded = nextExpanded
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// SwiftUI 那边读的状态。
@MainActor @Observable
final class NotchIslandModel {
    var form: NotchIslandForm?
    var geometry = NotchIslandGeometry(notchWidth: 180, notchHeight: 32, hasNotch: true)
    /// 展开收音机卡片时读一次，拖音量条时本地改。
    var radioVolume: Double = 60
    var canSwitchStation = true

    @ObservationIgnored var act: ((NotchIslandAction) -> Void)?
}

/// 无边框、不抢焦点、在菜单栏之上；卡片上的按钮第一下就能点。
@MainActor
final class NotchIslandWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
