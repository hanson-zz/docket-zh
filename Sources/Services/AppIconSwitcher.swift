import AppKit

/// 把 设置 ▸ 通用 ▸ 应用图标 的选择交给 `NSApplication.applicationIconImage`。
///
/// 两处一起换：运行时图标（程序坞、应用切换器、“关于”、提示框），以及
/// Finder 里“应用程序”文件夹显示的图标。后者用 NSWorkspace.setIcon 给 .app
/// 贴一个自定义图标（和在“显示简介”里粘贴图标是同一回事），不改应用包里
/// 签过名的文件；选回经典就揭掉。应用所在文件夹不可写时贴不上，设置里会提示。
/// 更新会整包替换、自定义图标随之消失，所以每次启动检查一遍再补贴。
@MainActor
enum AppIconSwitcher {
    private static var observer: NSObjectProtocol?

    /// 现在保存的选择，未解锁的赞助者图标按经典处理。
    static var current: AppIconOption {
        AppIconCatalog.shown(UserDefaults.standard.string(forKey: AppIconCatalog.key),
                             unlocked: Supporter.isUnlocked)
    }

    /// 启动时调用一次：套用保存的选择。码头在需要前台时会临时切成普通应用，
    /// 程序坞图标那时才出现，所以每次被激活再套一遍，免得程序坞先显示经典。
    static func start() {
        apply(current)
        syncFinder(current)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let option = AppIconSwitcher.current
                if !option.isBundleIcon { AppIconSwitcher.apply(option) }
            }
        }
    }

    /// 保存并立即套用。
    static func choose(_ option: AppIconOption) {
        UserDefaults.standard.set(option.id, forKey: AppIconCatalog.key)
        let shown = AppIconCatalog.shown(option.id, unlocked: Supporter.isUnlocked)
        apply(shown)
        syncFinder(shown)
    }

    /// 上次给 Finder 贴图标失败（多半是应用所在文件夹不可写），设置里据此提示。
    static var finderFailed: Bool {
        UserDefaults.standard.bool(forKey: "appIcon.finderFailed")
    }

    /// 应用包上有没有贴自定义图标：Finder 把它存在包根目录的 "Icon\r" 里。
    private static var hasCustomIcon: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Icon\r")
    }

    /// 让 Finder 里“应用程序”文件夹的图标和所选一致。
    static func syncFinder(_ option: AppIconOption) {
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        let action = AppIconCatalog.finderAction(
            for: option, hasCustomIcon: hasCustomIcon,
            lastApplied: defaults.string(forKey: AppIconCatalog.finderAppliedKey))
        let ok: Bool
        switch action {
        case .none:
            return
        case .set:
            guard let image = image(for: option) else { return }
            ok = NSWorkspace.shared.setIcon(image, forFile: path, options: [])
            if ok { defaults.set(option.id, forKey: AppIconCatalog.finderAppliedKey) }
        case .clear:
            ok = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
            if ok { defaults.removeObject(forKey: AppIconCatalog.finderAppliedKey) }
        }
        defaults.set(!ok, forKey: "appIcon.finderFailed")
        guard ok else { return }
        // 碰一下修改时间、通知 Finder，让“应用程序”文件夹和程序坞尽快重画。
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
        NSWorkspace.shared.noteFileSystemChanged(path)
    }

    static func apply(_ option: AppIconOption) {
        // 设为 nil 交还给系统，显示 bundle 自带的图标。读不到图片也回到经典。
        NSApp.applicationIconImage = image(for: option)
    }

    /// 设置卡片上的缩略图。经典取 bundle 自带的图标（Finder 里可能贴着
    /// 自定义图标，所以不能问 NSWorkspace 要）。
    static func thumbnail(for option: AppIconOption) -> NSImage {
        if let image = image(for: option) { return image }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let bundled = NSImage(named: name) {
            return bundled
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private static var cache: [String: NSImage] = [:]

    /// 资源图，把 1024、512、256 三张合成一张多尺寸图，小尺寸也清楚。
    static func image(for option: AppIconOption) -> NSImage? {
        guard let name = option.resourceName else { return nil }
        if let cached = cache[name] { return cached }
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for file in [name, "\(name)-512", "\(name)-256"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "png"),
                  let rep = NSImageRep(contentsOf: url) else { continue }
            // 三张都按同一个点尺寸登记，系统按屏幕倍率挑像素最合适的一张。
            rep.size = image.size
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        cache[name] = image
        return image
    }
}
