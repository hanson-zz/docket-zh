import CoreGraphics
import Foundation

// 截图工具的设置和面板（第三批 H2）：截完后怎么处理、格式、延时、卡片上放哪几个
// 按钮，以及区域录屏和延时截窗口用到的坐标换算。都是纯逻辑，有测试
// （CaptureSettingsTests）。真正跑 screencapture 的在 Services/ScreenCapture.swift。

// MARK: - 截完后

/// 截完一张图之后做什么。默认「两者」：存进截图文件夹，同时拷贝到剪贴板
/// （用户 10-20 定的）。
public enum CaptureAfter: String, CaseIterable, Sendable, Identifiable {
    case save, copy, both, markup

    public static let key = "after"
    public static let fallback: CaptureAfter = .both

    public var id: String { rawValue }

    /// 面板分段和设置页菜单上的字。
    public var title: String {
        switch self {
        case .save: tr("存文件")
        case .copy: tr("拷贝")
        case .both: tr("两者")
        case .markup: tr("标注")
        }
    }

    /// 面板标题下面那句「截完：存文件 + 拷贝」里的说法。
    public var summary: String {
        switch self {
        case .save: tr("存文件")
        case .copy: tr("只拷贝")
        case .both: tr("存文件 + 拷贝")
        case .markup: tr("打开标注")
        }
    }

    /// 要不要落一个文件。只拷贝时不存，图只在剪贴板里。
    public var savesFile: Bool { self != .copy }
    /// 存好之后要不要把图也拷贝一份（只拷贝时由 screencapture -c 直接放进剪贴板）。
    public var copiesAfterSaving: Bool { self == .both }
    public var opensMarkup: Bool { self == .markup }

    public static func from(_ config: WidgetConfig) -> CaptureAfter {
        CaptureAfter(rawValue: config.string(key, default: fallback.rawValue)) ?? fallback
    }
}

// MARK: - 格式

public enum CaptureFormat: String, CaseIterable, Sendable, Identifiable {
    case png, jpg

    public static let key = "format"
    public static let fallback: CaptureFormat = .png

    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    /// 文件扩展名，也是 screencapture -t 的参数。
    public var fileExtension: String { rawValue }

    public static func from(_ config: WidgetConfig) -> CaptureFormat {
        CaptureFormat(rawValue: config.string(key, default: fallback.rawValue)) ?? fallback
    }
}

// MARK: - 延时

public enum CaptureDelay {
    public static let key = "delay"
    /// 秒。0 是不延时。
    public static let choices = [0, 3, 5, 10]
    public static let fallback = 0

    public static func title(_ seconds: Int) -> String {
        seconds == 0 ? tr("不延时") : tr("\(seconds) 秒")
    }

    /// 存的是字符串（设置页按菜单显示）；认不出的按不延时。
    public static func from(_ config: WidgetConfig) -> Int {
        let value = Int(config.string(key, default: "\(fallback)")) ?? fallback
        return choices.contains(value) ? value : fallback
    }
}

// MARK: - 一次截图的全部选项

public struct CaptureOptions: Equatable, Sendable {
    public var after: CaptureAfter
    public var format: CaptureFormat
    public var delay: Int

    public init(after: CaptureAfter = CaptureAfter.fallback, format: CaptureFormat = CaptureFormat.fallback,
                delay: Int = CaptureDelay.fallback) {
        self.after = after
        self.format = format
        self.delay = CaptureDelay.choices.contains(delay) ? delay : CaptureDelay.fallback
    }

    public init(config: WidgetConfig) {
        self.init(after: .from(config), format: .from(config), delay: CaptureDelay.from(config))
    }

    /// 面板标题下面的一行：「截完：存文件 + 拷贝 · PNG」，有延时再接「· 3 秒」。
    public var summary: String {
        var text = tr("截完：\(after.summary) · \(format.title)")
        if delay > 0 { text += " · " + CaptureDelay.title(delay) }
        return text
    }

    /// 截到哪里：交互框选、交互点选窗口、一块固定的矩形、某个窗口、整个屏幕。
    public enum Target: Equatable, Sendable {
        case interactiveRegion
        case interactiveWindow
        /// screencapture -R 的坐标：原点在主显示器左上角，单位是点。
        case rect(CaptureRect)
        case window(Int)
        case fullScreen
    }

    /// `/usr/sbin/screencapture` 的参数。`path` 为 nil 时是只拷贝（-c），不落文件。
    public func arguments(_ target: Target, path: String?) -> [String] {
        var args: [String]
        switch target {
        case .interactiveRegion: args = ["-i", "-s"]
        case .interactiveWindow: args = ["-i", "-W"]
        case .rect(let rect): args = ["-R", rect.argument]
        case .window(let id): args = ["-l\(id)"]
        case .fullScreen: args = []
        }
        if format != .png { args += ["-t", format.fileExtension] }
        if let path {
            args.append(path)
        } else {
            args.append("-c")
        }
        return args
    }
}

// MARK: - 卡片上的按钮

/// 卡片（和面板顶上）放哪几个动作、什么顺序，存在配置 `buttons` 里。
/// 最多 4 个（卡片 184pt 宽、竖排 2×2），至少 1 个。
public enum CaptureButtons {
    public static let key = "buttons"
    public static let limit = 4
    /// 照效果图：截区域、截窗口、识字、录区域。整屏录屏可以在设置或面板里换上来，
    /// 录区域的选框里单击也是录整个屏幕。
    public static let defaults: [CaptureAction] = [.region, .window, .text, .recordRegion]

    /// 认不出的丢掉、去重、最多 4 个；一个都不剩时用默认。
    public static func resolve(_ raw: [String]) -> [CaptureAction] {
        var seen = Set<CaptureAction>()
        let list = raw.compactMap(CaptureAction.init(rawValue:)).filter { seen.insert($0).inserted }
        let capped = Array(list.prefix(limit))
        return capped.isEmpty ? defaults : capped
    }

    public static func from(_ config: WidgetConfig) -> [CaptureAction] {
        resolve(config.strings(key, default: defaults.map(\.rawValue)))
    }

    /// 面板里勾选或取消一个动作，返回新的列表；不能改（已满 4 个还要加、
    /// 只剩一个还要去掉）时是 nil，界面据此说明原因。
    public static func toggling(_ action: CaptureAction, in current: [CaptureAction]) -> [CaptureAction]? {
        if let index = current.firstIndex(of: action) {
            guard current.count > 1 else { return nil }
            var next = current
            next.remove(at: index)
            return next
        }
        guard current.count < limit else { return nil }
        return current + [action]
    }

    /// 往左（-1）或往右（+1）挪一格，到头了原样返回。
    public static func moving(_ action: CaptureAction, by offset: Int, in current: [CaptureAction]) -> [CaptureAction] {
        guard let index = current.firstIndex(of: action) else { return current }
        let target = index + offset
        guard current.indices.contains(target) else { return current }
        var next = current
        next.swapAt(index, target)
        return next
    }
}

// MARK: - 坐标

/// screencapture -R 要的矩形：原点在主显示器左上角，y 向下，单位是点，取整。
public struct CaptureRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var argument: String { "\(x),\(y),\(width),\(height)" }

    /// 框得太小（误点一下）不算一个区域。
    public static let minimumSide: CGFloat = 8

    /// 从 AppKit 的屏幕坐标（原点在主显示器左下角，y 向上）换过来。
    /// `primaryHeight` 是主显示器（`NSScreen.screens.first`）的高度。
    /// 太小时是 nil。
    public static func from(cocoa rect: CGRect, primaryHeight: CGFloat) -> CaptureRect? {
        let r = rect.standardized
        guard r.width >= minimumSide, r.height >= minimumSide else { return nil }
        let top = primaryHeight - r.maxY
        return CaptureRect(x: Int(r.minX.rounded()), y: Int(top.rounded()),
                           width: Int(r.width.rounded()), height: Int(r.height.rounded()))
    }
}

// MARK: - 延时截窗口：到点截鼠标下面那个窗口

public enum CaptureWindowPick {
    /// `CGWindowListCopyWindowInfo` 里用得到的几项。`bounds` 是 Quartz 坐标
    /// （原点在主显示器左上角，y 向下），和鼠标位置 `CGEvent.location` 一样。
    public struct Window: Equatable, Sendable {
        public var id: Int
        public var layer: Int
        public var bounds: CGRect
        public var ownerPID: Int32
        public var alpha: Double

        public init(id: Int, layer: Int, bounds: CGRect, ownerPID: Int32, alpha: Double = 1) {
            self.id = id
            self.layer = layer
            self.bounds = bounds
            self.ownerPID = ownerPID
            self.alpha = alpha
        }
    }

    /// 列表按前后顺序排（最前的在前）。取第一个普通层级（layer 0）、看得见、
    /// 不是码头自己、盖住鼠标位置的窗口。没有时是 nil（截整个屏幕）。
    public static func topmost(at point: CGPoint, in windows: [Window], excluding pid: Int32) -> Int? {
        windows.first { window in
            window.layer == 0 && window.alpha > 0.01 && window.ownerPID != pid
                && window.bounds.width > 1 && window.bounds.height > 1
                && window.bounds.contains(point)
        }?.id
    }
}
