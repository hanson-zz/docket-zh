import AppKit
import SwiftUI

/// 新手引导的独立窗口。
///
/// 首次启动时由 `AppDelegate` 弹出一次，之后只能从“设置 ▸ 通用 ▸ 重新显示新手引导”
/// 打开。每次打开都从第一步开始，所以先关掉旧窗口再新建。
@MainActor
final class OnboardingWindow: HostedWindow {
    static let shared = OnboardingWindow()

    /// 首次启动时已经排好、还没弹出来的引导。
    private var pending = false
    /// 引导最近一次关掉的时刻，给“检查更新”提示框排队用。
    private(set) var closedAt: Date?
    private var closeObserver: NSObjectProtocol?

    /// 引导是否还在（或马上要弹）。关掉窗口（点“开始使用”“跳过”或红色关闭按钮）后为 false。
    var isActive: Bool { pending || window?.isVisible == true }

    /// 首次启动时“检查更新”的提示框现在能不能弹，见 `Onboarding.mayPromptForUpdates`。
    var allowsUpdatePrompt: Bool {
        Onboarding.mayPromptForUpdates(onboardingActive: isActive, closedAt: closedAt, now: .now)
    }

    /// - Parameter firstRun: 首次启动时默认选底部；从设置里打开时默认选扩展栏现在的位置。
    func show(app: AppState, firstRun: Bool = false) {
        // 一出现就记为看过：中途退出也不会下次启动再弹，想再看可以去设置里打开。
        UserDefaults.standard.set(true, forKey: Onboarding.seenKey)
        close()
        pending = false
        closedAt = nil
        present(
            OnboardingView(app: app,
                           startPosition: firstRun ? .bottom : app.effectivePosition,
                           onFinish: { [weak self] in self?.close() }),
            title: tr("欢迎使用码头"),
            size: NSSize(width: 560, height: 640)
        )
        watchClose()
    }

    /// 记下引导窗口关掉的时刻，不管是走完、跳过还是点了红色关闭按钮。
    private func watchClose() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        guard let window else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closedAt = .now }
        }
    }

    /// 启动时调用：只有全新安装才弹出。
    ///
    /// - Parameter hadSavedSetup: 启动时（安装默认布局之前）是否已经有保存的布局或配置。
    func showIfFirstLaunch(app: AppState, hadSavedSetup: Bool) {
        let seen = UserDefaults.standard.bool(forKey: Onboarding.seenKey)
        guard Onboarding.shouldShow(seen: seen, hasSavedSetup: hadSavedSetup) else {
            // 老用户升级上来：记为看过，以后也不再弹。
            if hadSavedSetup { UserDefaults.standard.set(true, forKey: Onboarding.seenKey) }
            return
        }
        // 稍等扩展栏先出现，引导里选位置时能直接看到它移动。排好的这段时间也算
        // 引导开着，“检查更新”的提示框不会抢在它前面弹出来。
        pending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.show(app: app, firstRun: true)
        }
    }
}

// MARK: - 应用到 AppState

extension AppState {
    /// 新手引导第二步：把扩展栏放到选中的边缘，立即生效。
    ///
    /// 位置只有在不跟随系统程序坞时才由自己决定（跟随时扩展栏会自动选一条
    /// 系统程序坞不在的边），所以这里先关掉跟随，并把当前大小记下来，
    /// 免得关掉跟随的一瞬间扩展栏变大或变小。
    func applyOnboardingPosition(_ edge: DockPosition) {
        var dock = state.customDock
        if dock.followSystemDock {
            dock.scale = effectiveScale
            dock.followSystemDock = false
        }
        dock.position = edge
        state.customDock = dock
        // “替换系统程序坞”模式不支持顶部，和设置里一样退回普通模式。
        if edge == .top, state.setup == .customReplacement {
            state.setup = .both
        }
    }

    /// 当前扩展栏布局里已有的小组件种类（含分组里的）。
    var onboardingExistingKinds: Set<String> {
        func collect(_ items: [DockItem]) -> [String] {
            items.flatMap { item -> [String] in
                switch item {
                case .widget(let widget): [widget.kind.rawValue]
                case .group(let group): collect(group.items)
                default: []
                }
            }
        }
        return Set(collect(customProfile?.items ?? []))
    }

    /// 新手引导第五步：按选择生成小组件，追加到当前布局末尾，不删除已有的任何东西。
    ///
    /// - Returns: 实际添加的小组件种类。
    @discardableResult
    func addOnboardingWidgets(for uses: Set<OnboardingUse>) -> [String] {
        let available = Set(WidgetCatalog.shippable.map(\.kind.rawValue))
        let kinds = Onboarding.kinds(for: uses, available: available, existing: onboardingExistingKinds)
        let widgets = kinds.compactMap { raw -> WidgetInstance? in
            guard var widget = WidgetKind(rawValue: raw).flatMap({ WidgetCatalog.make($0) }) else { return nil }
            // 引导不用 Pro 外观做默认（电池新建默认液态，这里改回经典）。
            for (key, value) in Onboarding.freeLookOverrides(widget.config.values) { widget.config.set(key, value) }
            return widget
        }
        guard !widgets.isEmpty else { return [] }

        if customProfile == nil {
            createProfile(kind: .customDock, named: tr("日常"))
        }
        guard let id = state.customDock.profileID,
              let index = state.profiles.firstIndex(where: { $0.id == id }) else { return [] }
        // 一次写入，扩展栏只重排一次，也不会连响十几声添加音效。
        state.profiles[index].items.append(contentsOf: widgets.map { DockItem.widget($0) })
        return widgets.map(\.kind.rawValue)
    }
}
