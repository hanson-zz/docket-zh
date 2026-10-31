import Foundation

/// 把东西拖到程序坞（扩展栏、分组窗口）里某个 App 图标上时做什么（码头 Pro 的换图标部分）。
///
/// 默认和系统程序坞一样：拖文件上去就用这个 App 打开。按住 Option 松手才是换图标：
/// 用拖来的图片（PNG、JPG、HEIC、ICNS、TIFF 等文件，或浏览器、预览里拖出来的图片数据）
/// 或另一个 App 的图标当这个 App 在码头里的显示图标。
///
/// 为什么用 Option 而不是松手后弹一个二选一的小浮层：拖文件到 App 上打开是天天在用的
/// 动作，每次都多一步选择会拖慢它；Option 在访达里本来就表示“换一种放法”（拷贝），
/// 不按就和以前完全一样，零误触。拖来的是 .app 也要按 Option，免得把 App 拖过另一个
/// App 时手一松就换掉了它的图标。
///
/// 只放判定，界面（悬停提示、光标角标、确认动效）在 DockPanel 的 `DockIconDropTarget`。
public enum DockIconDrop {

    /// 拖来的一样东西是什么。
    public enum Source: Equatable, Sendable {
        /// 图片文件（`DockAppIcons.imageExtensions` 里的扩展名）。
        case imageFile
        /// 一个 App（.app 包），换图标时取它在访达里的图标。
        case app
        /// 没有文件的图片数据（浏览器、预览里拖出来的图）。
        case imageData
        /// 别的文件（文稿、文件夹、压缩包），只能拿去打开。
        case otherFile

        /// 能不能拿来当图标。
        public var canBeIcon: Bool { self != .otherFile }
        /// 是不是磁盘上的文件（能交给 App 打开的那种）。
        public var isFile: Bool { self != .imageData }
    }

    /// 文件按扩展名分类。`isAppBundle` 由调用方用 UTType 判断（扩展名不是 .app 的
    /// 包也可能是 App）。
    public static func source(pathExtension: String, isAppBundle: Bool) -> Source {
        if isAppBundle || pathExtension.lowercased() == "app" { return .app }
        return DockAppIcons.imageExtensions.contains(pathExtension.lowercased()) ? .imageFile : .otherFile
    }

    /// 哪些格子收：只有 App（扩展栏和分组窗口里的都算），返回它的 bundle id。
    /// 文件夹、文件、分组、小组件、间隔不收；没有 bundle id 的 App 也不收（存不了图标，
    /// 打开也找不到它）。
    public static func appBundleID(of item: DockItem) -> String? {
        guard case .app(_, let bundleID, _) = item else { return nil }
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : bundleID
    }

    // MARK: Option 判定

    /// `NSEvent.ModifierFlags` 的几个位（Core 不导入 AppKit，数值和系统的一致）。
    public enum Modifier {
        public static let shift: UInt = 1 << 17
        public static let control: UInt = 1 << 18
        public static let option: UInt = 1 << 19
        public static let command: UInt = 1 << 20
    }

    /// 按着的修饰键算不算“换图标”：要按着 Option，且没按 Command、Control
    /// （访达里 Command+Option 拖是做替身，Control 拖是别的意思，都不算）。
    /// Shift、大写锁定、Fn 不影响。
    public static func wantsIconChange(modifierFlags: UInt) -> Bool {
        modifierFlags & Modifier.option != 0
            && modifierFlags & (Modifier.command | Modifier.control) == 0
    }

    // MARK: 松手后做什么

    /// 拖到哪种格子上。
    public enum Place: Equatable, Sendable {
        /// 扩展栏上的 App 格子。
        case shelf
        /// 分组窗口里的 App 图标。分组窗口本来就收拖进来的 App（加进组），不按 Option
        /// 拖 App 照旧加进组。
        case groupWindow
    }

    public enum Action: Equatable, Sendable {
        /// 用这个 App 打开拖来的这些文件（下标对应传进来的 `sources`）。
        case open([Int])
        /// 用第几样东西换图标。
        case changeIcon(Int)
        /// 没解锁 Pro：不换，弹升级提示。
        case upgrade
        /// 分组窗口里：把拖来的 App 加进组（下标）。
        case addToGroup([Int])
        /// 不接（光标显示禁止）。
        case refuse
    }

    /// 松手时做什么。`sources` 是拖来的东西，按拖放里的先后。
    public static func action(sources: [Source], option: Bool, unlocked: Bool, place: Place) -> Action {
        guard !sources.isEmpty else { return .refuse }
        if option {
            guard let first = sources.firstIndex(where: \.canBeIcon) else { return .refuse }
            return unlocked ? .changeIcon(first) : .upgrade
        }
        if place == .groupWindow {
            let apps = sources.indices.filter { sources[$0] == .app }
            if !apps.isEmpty { return .addToGroup(apps) }
        }
        // App 拖到 App 上不当文稿打开：多半是手滑，要换图标得按 Option。
        let files = sources.indices.filter { sources[$0].isFile && sources[$0] != .app }
        return files.isEmpty ? .refuse : .open(files)
    }

    // MARK: 悬停提示

    /// 悬停时图标旁的提示。
    public enum Hint: Equatable, Sendable {
        /// 不提示（拖来的东西当不了图标，又按着 Option 以外的方式在打开）。
        case none
        /// 松手用这个 App 打开；`optionTip` 时补一句「按住 Option 换图标」（拖来的里有图片或 App）。
        case open(optionTip: Bool)
        /// 不按 Option 松手什么也不做（拖来的只有 App 或图片数据），提示按 Option。
        case holdOption
        /// 按着 Option：松手换图标。`pro` 时是免费用户，文字带「Pro 专属」。
        case changeIcon(pro: Bool)
        /// 按着 Option 但拖来的东西当不了图标。
        case notAnImage
        /// 分组窗口里不按 Option 拖 App：松手加进组。
        case addToGroup
    }

    public static func hint(sources: [Source], option: Bool, unlocked: Bool, place: Place) -> Hint {
        let iconable = sources.contains(where: \.canBeIcon)
        switch action(sources: sources, option: option, unlocked: unlocked, place: place) {
        case .changeIcon: return .changeIcon(pro: false)
        case .upgrade: return .changeIcon(pro: true)
        case .addToGroup: return .addToGroup
        case .open: return .open(optionTip: iconable)
        case .refuse:
            if option { return sources.isEmpty ? .none : .notAnImage }
            return iconable ? .holdOption : .none
        }
    }

    /// 光标上的角标：换图标是拷贝的加号，打开和系统程序坞一样不带角标（`plain`），
    /// 不接是禁止。
    public enum Cursor: Equatable, Sendable {
        case copy, plain, forbidden
    }

    public static func cursor(for action: Action) -> Cursor {
        switch action {
        case .changeIcon, .upgrade, .addToGroup: .copy
        case .open: .plain
        case .refuse: .forbidden
        }
    }

    // MARK: 确认动效

    /// 换好后图标轻轻弹一下：先放大到这么多，再落回 1。
    public static let confirmPeakScale: Double = 1.12
    /// 整段时长（秒）。
    public static let confirmDuration: Double = 0.42
}
