import AppKit
import UniformTypeIdentifiers

/// 「更换图标…」的选择流程（码头 Pro）：没解锁弹付费墙；解锁后用系统的打开面板选一张
/// 图片（PNG、JPG、HEIC、ICNS 等）或一个 App（取它的图标），交给 `DockAppIconStore`。
///
/// 用系统面板而不是自己画一张表单：它本身就是 macOS 26 的玻璃材质，深浅色、无障碍、
/// 预览（空格快速查看）都是现成的，也和扩展栏上「重命名分组」「设置位置」的做法一致。
@MainActor
enum DockAppIconPicker {

    /// 能不能换：试用中、已激活或老赞助者。
    static var unlocked: Bool {
        ProLicenseGate.canUse(.dockAppIcons, unlocked: ProAccess.isUnlocked)
    }

    /// 菜单里的名字：免费用户带「（Pro 专属）」。和小组件「样式」菜单一样，菜单项里放不了胶囊。
    static func menuTitle(_ title: String) -> String {
        ProFeatures.menuTitle(title, isPro: !unlocked)
    }

    /// App 显示的名字，面板标题里用。
    static func appName(bundleID: String, ref: FileRef?) -> String {
        let url = ref?.resolve() ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url else { return bundleID }
        return WidgetLibraryGroups.appTitle(FileManager.default.displayName(atPath: url.path(percentEncoded: false)))
    }

    /// 右键「更换图标…」。没解锁弹付费墙，不改任何东西。
    static func choose(bundleID: String, ref: FileRef?) {
        guard unlocked else {
            PaywallWindow.shared.show()
            return
        }
        guard DockAppIcons.fileName(for: bundleID) != nil else {
            showError(tr("这个 App 没有可用的标识，不能更换图标。"))
            return
        }
        let name = appName(bundleID: bundleID, ref: ref)
        guard let source = pickSource(appName: name) else { return }
        Task { @MainActor in
            report(await DockAppIconStore.shared.setIcon(from: source, for: bundleID))
        }
    }

    /// 换图标的结果：失败时弹和「更换图标…」同一套的错误提示。成功返回 true。
    /// 拖放换图标（`DockIconDropTarget`）也走这里，文案只有一份。
    @discardableResult
    static func report(_ result: Result<Void, DockAppIconStore.ChangeError>) -> Bool {
        switch result {
        case .success:
            return true
        case .failure(.unreadable):
            showError(tr("读不出这张图片。换一张 PNG、JPG、HEIC 或 ICNS 试试，边长至少 16 像素。"))
        case .failure(.writeFailed):
            showError(tr("图标没能存下来，请检查磁盘空间后再试。"))
        case .failure(.noBundleID):
            showError(tr("这个 App 没有可用的标识，不能更换图标。"))
        }
        return false
    }

    /// 打开面板选图片或 App。取消时是 nil。
    private static func pickSource(appName: String) -> URL? {
        // 码头平时是辅助 App，不在最前；模态面板要先临时变成普通 App 才会到前面来。
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.title = tr("更换“\(appName)”的图标")
        panel.message = tr("选一张图片（PNG、JPG、HEIC、ICNS），会缩放成方形；也可以选一个 App，用它的图标。只改码头里显示的图标，不改 App 本身。")
        panel.prompt = tr("使用")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .applicationBundle]
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func showError(_ message: String) {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let alert = NSAlert()
        alert.messageText = tr("没能更换图标")
        alert.informativeText = message
        alert.addButton(withTitle: tr("好"))
        alert.runModal()
    }
}
