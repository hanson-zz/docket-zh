import AppKit
import SwiftUI

@main
struct DocketMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Agent app: no Dock tile of our own, no menu bar of our own. Docket's
        // only permanent UI is its status item.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var shelf: DockPanelController!
    private var menuBar: MenuBarController!
    private var observation: NSObjectProtocol?

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
        WidgetWriter.update = { [state] instance in
            state.updateWidget(instance)
            WidgetDetailWindow.shared.refresh(instance)
        }
        WidgetWriter.current = { [state] id in
            func find(_ items: [DockItem]) -> WidgetInstance? {
                for item in items {
                    switch item {
                    case .widget(let widget) where widget.id == id: return widget
                    case .group(let group): if let found = find(group.items) { return found }
                    default: continue
                    }
                }
                return nil
            }
            return find(state.customProfile?.items ?? [])
        }

        shelf = DockPanelController(app: state)
        menuBar = MenuBarController(app: state)
        menuBar.onShelfSettingsChanged = { [weak self] in self?.shelf.refresh() }
        // The Settings window writes the model directly rather than going
        // through the menu bar, so it needs the same wire.
        state.onShelfSettingsChanged = { [weak self] in self?.shelf.refresh() }
        state.onMenuBarSettingsChanged = { [weak self] in self?.menuBar.refreshButton() }
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

        // 灵动提示: off unless switched on in Settings ▸ 通用.
        IslandController.shared.apply(state.state.island)
        state.onIslandChanged = { island in IslandController.shared.apply(island) }

        // AI 助手的刘海对话：入口、展开面板和快捷键。会话状态和货架上的
        // AI 卡片共用一份。
        AIChatCenter.shared.app = state
        AINotchController.shared.apply(state.state.aiNotch)
        state.onAINotchChanged = { settings in AINotchController.shared.apply(settings) }

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
        state?.saveNow()
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
