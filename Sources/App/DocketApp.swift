import AppKit
import SwiftUI
@preconcurrency import UserNotifications

@main
struct DocketMain {
    static func main() {
        // 在任何界面文字查表之前定下本次的界面语言，见 LanguageBootstrap。
        LanguageBootstrap.apply()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Agent app: no Dock tile of our own, no menu bar of our own. Docket's
        // only permanent UI is its status item.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// 跟随系统时的兜底：系统按首选语言挑出的资源和“有中文显示简体、有英文显示英文、
/// 都没有显示英文”的规则不一致时，只给这一次进程临时指定 AppleLanguages。
///
/// 写在参数域（和命令行 `-AppleLanguages (en)` 同一处），不落盘、不碰用户的设置，
/// 下次启动重新判断。通常用不上：Info.plist 的开发区域是英文，系统自己就会把法语、
/// 日语这类退回英文，繁体和香港中文也有一份内容是简体的资源。
enum LanguageBootstrap {
    static func apply() {
        let defaults = UserDefaults.standard
        let preferred = Locale.preferredLanguages
        let pick = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferred).first
        guard let code = AppLanguage.launchOverride(
            stored: AppLanguage.current(defaults), preferredLanguages: preferred, bundlePick: pick
        ) else { return }
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[AppLanguage.defaultsKey] = [code]
        // 同名的易失域已存在时直接设置会抛异常，先移除再放回（原有的启动参数一并保留）。
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var shelf: DockPanelController!
    private var menuBar: MenuBarController!
    /// 菜单栏第二时区（设置里打开，默认关，关着时不占菜单栏）。
    private var worldClockItem: WorldClockStatusItem!
    private var observation: NSObjectProtocol?

    /// 通知代理在启动完成之前就设好：点一条通知把没在运行的码头启动起来时，
    /// 那次点击也交给 `BannerPresenter`。各个通知发送方见代理已有就不再换，
    /// 都是同一个类，喝水、久坐、播客、股票的处理合在一起。
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = BannerPresenter.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state

        // 新手引导只给全新安装：在装默认布局之前看一眼，已经有布局或状态文件的
        // 是升级上来的老用户，不弹。
        let hadSavedSetup = !state.state.profiles.isEmpty
            || FileManager.default.fileExists(atPath: Store().url.path(percentEncoded: false))

        // A first run with nothing saved should still show something, or the
        // app looks broken. An empty shelf with a visible Add Widget affordance
        // is better than no window at all.
        state.installDefaultProfile()

        // Widgets write their own state through here - see WidgetWriter. An
        // open detail panel holds the instance by value, so it is redrawn from
        // the same funnel rather than left showing what the tile used to say.
        //
        // 到点弹出的卡片和后台调度要动的小组件可能在文件夹里或别的布局里，
        // 所以读写都先找当前布局、再找其余的（见 WidgetLookup.swift）。
        WidgetWriter.update = { [state] instance in
            state.writeWidgetAnywhere(instance)
            WidgetDetailWindow.shared.refresh(instance)
        }
        WidgetWriter.current = { [state] id in
            state.widgetAnywhere(id)
        }

        shelf = DockPanelController(app: state)
        menuBar = MenuBarController(app: state)
        menuBar.onShelfSettingsChanged = { [weak self] in self?.shelf.refresh() }
        // The Settings window writes the model directly rather than going
        // through the menu bar, so it needs the same wire.
        state.onShelfSettingsChanged = { [weak self] in self?.shelf.refresh() }
        worldClockItem = WorldClockStatusItem(app: state)
        state.onMenuBarSettingsChanged = { [weak self] in
            self?.menuBar.refreshButton()
            self?.worldClockItem.refresh()
        }
        state.onAppearanceChanged = { [weak self] in self?.applyAppearance() }

        // The Focus Timer runs through a shared provider the widgets read,
        // and Settings edits the persisted copy. Neither knew about the
        // other, so the six controls in Settings changed nothing and a
        // session was forgotten on quit. Both ends are connected here.
        TimerStateProvider.shared.adopt(state.state.timer)
        TimerStateProvider.shared.onChange = { [state] timer in state.state.timer = timer }
        state.onTimerChanged = { timer in TimerStateProvider.shared.adopt(timer) }
        // A focus session that ends is a treat for the pet, noticed from launch
        // rather than by a pet tile, which may be on another layout.
        PetFocusWatcher.shared.start()
        // 专注计时面板的“近七天”：每轮专注结束时记下分钟数，同样从启动起就看着。
        FocusLogStore.shared.start()
        // 专注计时一轮到点后接休息、休息完回到专注，同样从启动起就看着。
        FocusCycleDriver.shared.start()
        // 倒计时、闹钟、快速待办和提醒事项到点：从启动起就看着每个布局里的这几种
        // 小组件，扩展栏隐藏、卡片不在当前布局也照样响、照样弹出卡片。
        TimedAlertDriver.shared.widgets = { [state] in state.allWidgets }
        TimedAlertDriver.shared.start()
        // 快速待办和系统提醒事项的双向同步（Pro），没有打开同步的卡片时什么也不做。
        TodoReminderSyncService.shared.start()
        // 久坐提醒的离开检测：锁屏、休眠或很久没碰键盘鼠标满设定时间，自动算一次
        // 起身休息，离开期间到点不提醒。同样看着每个布局里的久坐卡片。
        PostureAwayMonitor.shared.widgets = { [state] in state.allWidgets }
        PostureAwayMonitor.shared.start()
        // 壁纸按早中晚自动换（Pro）：同样看着每个布局里的壁纸卡片，卡片不在屏幕上也换。
        WallpaperAutoDriver.shared.widgets = { [state] in state.allWidgets }
        WallpaperAutoDriver.shared.start()
        // 文件夹轮询只给还有卡片用到的文件夹：相册移除或取消勾选的文件夹、删掉的
        // 截图和下载卡片，一分钟内停掉。
        FolderFeed.sourcesInUse = { [state] in FolderFeed.sources(for: state.allWidgets) }
        // 加密货币只取还在卡片上的币：面板里删掉的币、删掉的卡片，下一次取价就不带。
        CryptoService.shared.inUse = { [state] in
            CryptoWatch.inUse(state.allWidgets.filter { $0.kind == .crypto }.map(\.config),
                              alertsOn: ProLicenseGate.canUseCryptoAlerts(unlocked: ProAccess.isUnlocked))
        }
        // 删掉的农历卡排下的生日、纪念日提醒，启动时撤掉。
        LunarNotifier.shared.sweepEvents(keeping: Set(state.allWidgets.filter { $0.kind == .lunar }.map(\.id)))
        // 点弹出卡片主体、点股票或久坐通知时打开小组件面板：卡片在文件夹里、别的
        // 布局里或扩展栏没开时也打得开。
        WidgetPanelOpener.shared.currentItems = { [state] in state.effectiveItems }
        WidgetPanelOpener.shared.start()

        // 小熊猫的竹篮 reads 喝水, 习惯打卡 and 专注计时 wherever they sit, so it
        // is handed every widget on every layout. Focus minutes come from
        // FocusLogStore, started above.
        PerfectDayCenter.shared.widgets = { [state] in
            func widgets(in items: [DockItem]) -> [WidgetInstance] {
                items.flatMap { item -> [WidgetInstance] in
                    switch item {
                    case .widget(let widget): [widget]
                    case .group(let group): widgets(in: group.items)
                    default: []
                    }
                }
            }
            return state.state.profiles.flatMap { widgets(in: $0.items) }
        }
        PerfectDayCenter.shared.start()

        // Battery reminders take their settings from the first 电池 widget,
        // on whichever layout it sits.
        BatteryAlerts.shared.settings = { [state] in
            func battery(in items: [DockItem]) -> WidgetInstance? {
                for item in items {
                    switch item {
                    case .widget(let widget) where widget.kind == .battery: return widget
                    case .group(let group): if let found = battery(in: group.items) { return found }
                    default: continue
                    }
                }
                return nil
            }
            for profile in state.state.profiles {
                if let widget = battery(in: profile.items) { return BatteryAlertSettings(config: widget.config) }
            }
            return nil
        }

        // 系统活动的超阈值提醒读第一个系统活动小组件的规则，在哪个布局都算。
        SystemAlerts.shared.rules = { [state] in
            func system(in items: [DockItem]) -> WidgetInstance? {
                for item in items {
                    switch item {
                    case .widget(let widget) where widget.kind == .system: return widget
                    case .group(let group): if let found = system(in: group.items) { return found }
                    default: continue
                    }
                }
                return nil
            }
            for profile in state.state.profiles {
                if let widget = system(in: profile.items) { return SystemAlertRules.rules(widget.config) }
            }
            return nil
        }

        // 麦克风与摄像头：提醒、静音快捷键和「静音时卡片变红」读第一个麦克风小组件，
        // 在哪个布局都算；有麦克风小组件就开始每秒读，使用记录和提醒不靠卡片在屏幕上。
        MicrophoneMonitor.shared.settings = { [state] in
            func microphone(in items: [DockItem]) -> WidgetInstance? {
                for item in items {
                    switch item {
                    case .widget(let widget) where widget.kind == .microphone: return widget
                    case .group(let group): if let found = microphone(in: group.items) { return found }
                    default: continue
                    }
                }
                return nil
            }
            for profile in state.state.profiles {
                if let widget = microphone(in: profile.items) { return MicPrivacySettings(config: widget.config) }
            }
            return nil
        }
        if MicrophoneMonitor.shared.settings() != nil { MicrophoneMonitor.shared.start() }

        // 灵动提示: off unless switched on in Settings ▸ 通用.
        IslandController.shared.apply(state.state.island)
        state.onIslandChanged = { island in IslandController.shared.apply(island) }

        // AI 助手的刘海对话：入口、展开面板和快捷键。会话状态和货架上的
        // AI 卡片共用一份。
        AIChatCenter.shared.app = state
        AINotchController.shared.apply(state.state.aiNotch)
        state.onAINotchChanged = { settings in AINotchController.shared.apply(settings) }

        // 快速待办的小输入框：快捷键默认不设，在设置 ▸ 快捷键里录制。
        QuickTodoCapture.shared.app = state
        QuickTodoCapture.shared.apply(state.state.quickTodoHotKey)
        state.onQuickTodoHotKeyChanged = { combo in QuickTodoCapture.shared.apply(combo) }

        // 截图编辑、截图翻译两个快捷键（默认不设）；编辑工具条的「送翻译」「问 AI」
        // 要找扩展栏上的卡片。
        ShotEditor.shared.app = state
        ShotHotKey.shared.apply(state.state.shotHotKeys)

        // ⌥Tab 按窗口切换：默认 ⌥Tab，要辅助功能权限，没给时不注册。平时只占这一个快捷键。
        WindowSwitcherController.shared.apply(state.state.windowSwitcher)

        // Layout hotkeys. Registered now and again whenever a layout gains,
        // loses or changes its combination; the service ignores a list that
        // has not changed, so the didSet that reports it can be generous.
        HotKeyService.shared.onPress = { [state] id in
            guard let profile = state.state.profile(id) else { return }
            state.activate(profile)
        }
        state.onShortcutsChanged = { bindings in HotKeyService.shared.update(bindings) }
        HotKeyService.shared.update(state.state.shortcutBindings)

        // Before the shelf appears, so a Focus change the system delivered
        // while launching picks the layout the shelf first shows.
        LayoutIntentBridge.attach(state)

        applyAppearance()
        // 设置 ▸ 通用 ▸ 应用图标：只换运行时图标，不改 bundle。
        AppIconSwitcher.start()
        if state.state.setup != .macOSDockOnly {
            shelf.show()
        }

        LibraryWindow.shared.openFromEmptyState = { [state] in LibraryWindow.shared.show(app: state) }

        OnboardingWindow.shared.showIfFirstLaunch(app: state, hadSavedSetup: hadSavedSetup)

        if ProcessInfo.processInfo.environment["PLINTH_OPEN_LIBRARY"] != nil {
            LibraryWindow.shared.show(app: state)
        }
        if let tab = ProcessInfo.processInfo.environment["PLINTH_OPEN_SETTINGS"] {
            SettingsWindow.shared.show(app: state, tab: tab.isEmpty ? "Shelf" : tab)
        }
        if ProcessInfo.processInfo.environment["PLINTH_PROBE_LOCATION"] != nil {
            SettingsWindow.shared.show(app: state)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                LocationService.shared.start()
            }
        }
        // A recorded snapshot means a previous run changed Apple's Dock and
        // did not put it back, which is what a crash or a force quit leaves
        // behind. The debt is paid before anything else touches the Dock.
        // 替换并自动隐藏留下的程序坞自动隐藏也一样：上次没还原又不在这一档了，
        // 现在还原。仍在这一档就留着，程序坞本来就该藏着。
        DockHidingMode.repayIfOwed(state: state.state,
                                   record: { state.state.hiddenDockAutoHide = $0 })
        Task { @MainActor [state] in
            await StrutMode.repayIfOwed(state: state.state,
                                        clear: { state.state.borrowedDockPrefs = nil })
        }

        startUpdateChecks(state)

        // 码头 Pro：从钥匙串算出试用或激活状态，按需联网校验。不会自动开始试用。
        ProLicenseManager.shared.start()

        SystemDockSettings.shared.start()
        // Reads the wallpaper, not the screen, so it needs no permission.
        DesktopLuminance.shared.start()
        SystemMetrics.shared.start()
        NetworkMetrics.shared.start()
        BatteryMetrics.shared.start()

        observation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shelf.refresh() }
        }

        // The Dock's own preferences drive our edge, size and hiding, so
        // follow them. Through SystemDockSettings rather than by observing the
        // notification here: it is a *distributed* notification, posted by
        // another process, and the observer this used to register on
        // NotificationCenter.default could never have fired. Nothing re-placed
        // or re-hid the shelf when the Dock changed, so "Match the macOS Dock"
        // only matched it at launch.
        SystemDockSettings.shared.onChange = { [weak self] in self?.shelf.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchronous on purpose. Restoring the Dock means writing its
        // preferences and restarting it, and a Task would not be given the
        // time: quitting must not be how someone loses their Dock settings.
        if let borrowed = state?.state.borrowedDockPrefs {
            state?.state.borrowedDockPrefs = nil
            DockStrut.releaseNow(borrowed)
        }
        // 替换并自动隐藏改过的程序坞自动隐藏，退出时还原成原值。
        if let state {
            DockHidingMode.restoreOnQuit(state: state.state,
                                         record: { state.state.hiddenDockAutoHide = $0 })
        }
        state?.saveNow()
        // 今天累计的网络流量平时 15 秒一存，退出时补上最后几秒。
        NetworkMetrics.shared.flushToday()
    }

    /// Asks once, then remembers.
    ///
    /// Checking for releases is the only thing Docket does unprompted that
    /// talks to a server, and it necessarily tells GitHub that someone ran it.
    /// Everything else that leaves this machine is there because the user
    /// added a weather or stocks widget. So it is asked rather than assumed,
    /// and asked once: a nil answer means the question has not been put yet.
    ///
    /// Deferred so the question does not land while the shelf is still
    /// appearing, which would make it the first thing a new user ever sees.
    private func startUpdateChecks(_ state: AppState) {
        guard state.state.checkForUpdates != false else { return }
        if state.state.checkForUpdates == true {
            UpdateService.shared.start()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            // 首次启动时新手引导还开着就先不问，等引导关掉（再缓两秒）再弹，
            // 免得模态提示框盖住引导。
            while !OnboardingWindow.shared.allowsUpdatePrompt {
                try? await Task.sleep(for: .seconds(1))
                guard self != nil, !Task.isCancelled else { return }
            }
            guard self != nil else { return }
            // 等的这段时间里也许已经在设置里选过了。
            guard state.state.checkForUpdates == nil else {
                if state.state.checkForUpdates == true { UpdateService.shared.start() }
                return
            }
            let alert = NSAlert()
            alert.messageText = tr("要检查码头的新版本吗？")
            alert.informativeText = tr(
                "Docket 可以每天检查一次新版本，并在发现新版本时通过菜单栏项提示你。更新永远不会自动安装。\n\n检查时只会向 GitHub 查询最新版本号，不会发送其他任何信息。你可以在“设置”中更改此选项。")
            alert.alertStyle = .informational
            alert.addButton(withTitle: tr("检查更新"))
            alert.addButton(withTitle: tr("不检查"))
            NSApp.activate(ignoringOtherApps: true)
            let wanted = alert.runModal() == .alertFirstButtonReturn
            state.state.checkForUpdates = wanted
            if wanted { UpdateService.shared.start() }
        }
    }

    private func applyAppearance() {
        NSApp.appearance = switch state.state.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
