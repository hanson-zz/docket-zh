import Foundation

/// 相册面板分成标准、宽幅两套之后的规则：顶栏标题、显示方式（完整显示 / 铺满裁切）、
/// 序号和倒计时那一行、照片下沿显示哪些字段、预览露几张、缩略图「…」菜单里有什么、
/// 空着时说哪句话，以及读老配置。轮到哪张照旧是 `PhotoRotation` 的事，这里不碰。
///
/// 所有设置都存在各自的 `WidgetInstance.config` 里，两张相册卡片互不影响。
/// 新加的键只有 `fit`；老卡片没有它时按完整显示（保护照片主体），之前存过的
/// “fill”“crop”这类写法也认。
public enum PhotoAlbumPanel {

    // MARK: 样式

    public enum Layout: String, CaseIterable, Sendable {
        case standard, wide
    }

    public static let layoutKey = "layout"

    public static func layout(_ config: WidgetConfig) -> Layout {
        Layout(rawValue: config.string(layoutKey, default: Layout.standard.rawValue)) ?? .standard
    }

    public static func layoutTitle(_ layout: Layout) -> String {
        switch layout {
        case .standard: tr("标准")
        case .wide: tr("宽幅")
        }
    }

    /// 顶栏标题：“相册 · 标准”“相册 · 宽幅”。
    public static func title(_ layout: Layout) -> String {
        tr("相册 · \(layoutTitle(layout))")
    }

    // MARK: 显示方式

    public enum Fit: String, CaseIterable, Sendable {
        /// 整张照片都在，空出来的地方垫同一张的模糊放大图。
        case fit
        /// 铺满，多出来的裁掉。
        case fill
    }

    public static let fitKey = "fit"
    /// 默认完整显示，竖图不裁掉人物。
    public static let defaultFit: Fit = .fit

    public static func fit(_ config: WidgetConfig) -> Fit {
        switch config.values[fitKey] {
        case .string(let raw):
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "fill", "crop", "cover", "aspectfill": return .fill
            case "fit", "contain", "whole", "aspectfit": return .fit
            default: return defaultFit
            }
        // 早先试过用开关存“铺满”：true 是铺满。
        case .bool(let on): return on ? .fill : .fit
        default: return defaultFit
        }
    }

    public static func fitTitle(_ fit: Fit) -> String {
        switch fit {
        case .fit: tr("完整显示")
        case .fill: tr("铺满裁切")
        }
    }

    // MARK: 设置

    /// 设置页一次读齐的几项，老配置缺哪项就用默认值。
    public struct Settings: Equatable, Sendable {
        public var layout: Layout
        public var fit: Fit
        public var interval: Double
        public var shuffle: Bool
        public var memoriesFirst: Bool
    }

    public static func settings(_ config: WidgetConfig) -> Settings {
        Settings(layout: layout(config), fit: fit(config), interval: interval(config),
                 shuffle: config.bool(PhotoRotation.shuffleKey),
                 memoriesFirst: config.bool(PhotoRotation.memoriesFirstKey, default: true))
    }

    /// 换图间隔。数字照 `PhotoRotation.interval` 读；早先导入的配置里偶尔是
    /// “600”这样的文字，也认，同样夹在 5 秒到每天之间。
    public static func interval(_ config: WidgetConfig) -> Double {
        if case .string(let raw) = config.values[PhotoRotation.intervalKey],
           let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds.isFinite {
            return min(max(seconds, PhotoRotation.minimumInterval), PhotoRotation.maximumInterval)
        }
        return PhotoRotation.interval(config)
    }

    /// 把老配置里的写法改成现在的：`fit` 统一成“fit”/“fill”，文字间隔改成数字。
    /// 其余键不动。改了返回 true。
    @discardableResult
    public static func migrate(_ config: inout WidgetConfig) -> Bool {
        var changed = false
        if config.values[fitKey] != nil, config.values[fitKey] != .string(fit(config).rawValue) {
            config.set(fitKey, .string(fit(config).rawValue))
            changed = true
        }
        if case .string = config.values[PhotoRotation.intervalKey] {
            config.set(PhotoRotation.intervalKey, .number(interval(config)))
            changed = true
        }
        return changed
    }

    // MARK: 序号和倒计时

    /// “第 12 / 300 张”；没有照片时是 nil。
    public static func positionText(index: Int?, count: Int) -> String? {
        guard let index, count > 0 else { return nil }
        let shown = min(max(index, 0), count - 1) + 1
        return tr("第 \(shown) / \(count) 张")
    }

    /// 序号右边那句：暂停时“已暂停”，只有一张时不写，其余是真实剩余时间。
    public static func statusText(paused: Bool, secondsToNext: Double?) -> String? {
        if paused { return tr("已暂停") }
        guard let secondsToNext else { return nil }
        return PhotoRotation.countdownText(secondsToNext)
    }

    // MARK: 照片下沿

    /// 宽幅面板照片下面那一行：那年今天、拍摄日期、地点，没有的就不写。
    public struct Caption: Equatable, Sendable {
        public var onThisDay: Bool
        public var date: String?
        public var place: String?

        public init(onThisDay: Bool = false, date: String? = nil, place: String? = nil) {
            self.onThisDay = onThisDay
            self.date = date
            self.place = place
        }

        public var isEmpty: Bool { !onThisDay && date == nil && place == nil }
    }

    public static func caption(date: Date?, place: String?, today: Date,
                               calendar: Calendar = .current) -> Caption {
        let trimmed = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeText = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard let date else { return Caption(place: placeText) }
        let day = PhotoMemory.dateText(date, calendar: calendar)
        return Caption(onThisDay: PhotoMemory.isOnThisDay(date, today: today, calendar: calendar),
                       date: day.isEmpty ? nil : day, place: placeText)
    }

    // MARK: 预览

    /// 标准面板“接下来”的网格：4 列 2 行。
    public static let gridColumns = 4
    public static let gridRows = 2
    /// 宽幅面板底部一行露 4 张，横着滑最多看到这么多张。
    public static let wideVisible = 4
    public static let wideMaxPreviews = 24
    /// 宽幅主图旁边的小图张数，和宽幅小组件的胶片条一样。
    public static let stripNext = 2

    /// 预览要几张（不含正在显示的这张）。`others` 是除了这张之外还有几张。
    public static func previewCount(_ layout: Layout, others: Int) -> Int {
        let cap = layout == .standard ? gridColumns * gridRows : wideMaxPreviews
        return min(cap, max(0, others))
    }

    /// 宽幅底部预览从第几张起：主图旁边已经露了两张，底部接着往后排，
    /// 照片不够时从头排（不跳过，免得只有三四张时底部是空的）。
    public static func widePreviewOffset(others: Int) -> Int {
        others > stripNext + wideVisible ? stripNext : 0
    }

    /// `display` 里 `id` 之后的几张（不含它自己，绕回开头，不重复）。
    public static func after(_ id: String?, in display: [String], count: Int) -> [String] {
        guard !display.isEmpty else { return [] }
        let start = id.flatMap { display.firstIndex(of: $0) } ?? -1
        let n = min(count, display.count - (start >= 0 ? 1 : 0))
        guard n > 0 else { return [] }
        return (1...n).map { display[(start + $0 + display.count) % display.count] }
    }

    // MARK: 缩略图菜单

    /// 悬停缩略图时右上角“…”里的几项。
    public enum ThumbAction: String, CaseIterable, Sendable {
        case exclude, undo, open
    }

    public static func thumbActions(excluded: Bool, canOpen: Bool) -> [ThumbAction] {
        var actions: [ThumbAction] = [excluded ? .undo : .exclude]
        if canOpen { actions.append(.open) }
        return actions
    }

    public static func thumbActionTitle(_ action: ThumbAction) -> String {
        switch action {
        case .exclude: tr("排除")
        case .undo: tr("撤销排除")
        case .open: tr("打开原图")
        }
    }

    // MARK: 空着的时候

    public enum Empty: Equatable, Sendable {
        /// 一个文件夹都没勾。
        case noFolder
        /// 没有读文件夹的权限。
        case denied
        /// 读不了（文件夹不在了之类）。
        case failed
        case loading
        /// 有图片，但都排除了。
        case allExcluded
        /// 文件夹里没有图片。
        case emptyFolder
    }

    /// 没有可放的照片时是哪种情况。`total` 是排除之前一共有几张。
    public static func empty(activeFolders: Int, loading: Bool, failed: Bool, denied: Bool,
                             total: Int) -> Empty {
        if activeFolders == 0 && total == 0 { return .noFolder }
        if denied { return .denied }
        if failed { return .failed }
        if loading { return .loading }
        if total > 0 { return .allExcluded }
        return .emptyFolder
    }

    public static func emptyText(_ empty: Empty) -> String {
        switch empty {
        case .noFolder: tr("没有勾选的文件夹。点“设置”勾选一个，或添加文件夹。")
        case .denied: tr("码头没有读取这个文件夹的权限，到隐私设置里允许后就能放。")
        case .failed: tr("读不了这个文件夹，可能已被移动或删除。")
        case .loading: tr("正在读取…")
        case .allExcluded: tr("这里的照片都排除了")
        case .emptyFolder: tr("文件夹里还没有图片，放几张进去或换一个文件夹。")
        }
    }
}
