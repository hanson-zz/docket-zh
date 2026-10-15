import AppKit

/// 把 设置 ▸ 通用 ▸ 应用图标 的选择交给 `NSApplication.applicationIconImage`。
///
/// 只改运行时图标，不碰 bundle：用 NSWorkspace.setIcon 改 .app 会破坏签名，
/// 所以 Finder 和启动台里始终是经典图标。码头平时是不在程序坞显示的后台应用，
/// 运行时图标只在它短暂成为前台应用时（程序坞、应用切换器），以及设置里的
/// “关于”、新手引导和提示框里看得到。
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
        apply(AppIconCatalog.shown(option.id, unlocked: Supporter.isUnlocked))
    }

    static func apply(_ option: AppIconOption) {
        // 设为 nil 交还给系统，显示 bundle 自带的图标。读不到图片也回到经典。
        NSApp.applicationIconImage = image(for: option)
    }

    /// 设置卡片上的缩略图。经典取 Finder 看到的 bundle 图标。
    static func thumbnail(for option: AppIconOption) -> NSImage {
        image(for: option) ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
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
