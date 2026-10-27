import Foundation

// MARK: - 钉在桌面 · Files 组的专属布局
//
// 下载、文件暂存、剪贴板、书签、截图工具、相册、最近截图、壁纸、摸鱼时钟、音量这十种
// 小组件在桌面卡片小 160×160 / 中 340×160 / 大 340×340 三档各有一套专门排的布局
// （视图在 Sources/Widgets/DesktopCards/DesktopCardsFiles.swift），不再是放大的扩展栏卡片
// 或塞进去滚动的面板。这里只放纯判断：哪些种类走专属布局、每档显示几条、网格几行几列、
// 放不下时最后一格写「+N」。
//
// 相册、壁纸、最近截图以前因为「大图在卡片里看不清」不给钉，摸鱼时钟因为面板 400 宽不给钉，
// 音量因为没有面板不给钉，截图工具因为「截完后要退开」不给钉；有了专属布局后都开放三档。
// AI 助手仍不开放。

public enum DesktopCardsFilesPlan {
    /// 走本组专属布局的种类。
    public static let kinds: Set<WidgetKind> = [
        .downloads, .fileShelf, .clipboard, .bookmarks, .capture,
        .photos, .screenshots, .wallpaper, .slacker, .volume,
    ]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 本组每种都有小 / 中 / 大三档（大号仍按码头 Pro 规则）。
    public static func sizes(_ kind: WidgetKind) -> [DesktopPinSize] {
        handles(kind) ? DesktopPinSize.allCases : []
    }

    // MARK: 列表

    /// 列表类每档除了主角以外再列几条。
    ///
    /// - 下载：小号只有最新一个；中号左边最新一个的大缩略图，右边再列 3 个；大号列 5 行，
    ///   正在下载的卡片（最多 2 张，每张约占一行多）顶掉相应的行，至少留 3 行。
    /// - 剪贴板：小号只有最新一条；中号 3 行；大号 6 行（星标和最近合起来，见 `clipboardSplit`）。
    /// - 音量：小号只有总音量；中号一排 4 个输出设备；大号列 5 个设备。
    public static func rows(_ kind: WidgetKind, size: DesktopPinSize, downloading: Int = 0) -> Int {
        switch (kind, size) {
        case (_, .small): return 0
        case (.downloads, .medium): return 3
        case (.downloads, .large): return max(3, 5 - min(max(downloading, 0), 2))
        case (.clipboard, .medium): return 3
        case (.clipboard, .large): return 6
        case (.volume, .medium): return 4
        case (.volume, .large): return 5
        default: return 0
        }
    }

    /// 下载大号最多摆几张「正在下载」卡片。
    public static let maxDownloadingCards = 2

    /// 剪贴板大号：星标最多 3 条排在上面，剩下的行给最近拷贝。没有星标时全给最近。
    public static func clipboardSplit(pins: Int, recent: Int, size: DesktopPinSize) -> (pins: Int, recent: Int) {
        let total = rows(.clipboard, size: size)
        guard size == .large else { return (0, min(max(recent, 0), total)) }
        let starred = min(max(pins, 0), 3)
        let latest = min(max(recent, 0), total - starred)
        // 最近的不够，星标可以多摆几条把空位补上。
        let refill = min(max(pins, 0), total - latest)
        return (max(starred, refill), latest)
    }

    // MARK: 网格

    public struct Grid: Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        public var capacity: Int { columns * rows }

        public init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }
    }

    /// 书签：小号 2×2 个大圆，中号 4×2，大号一列 6 行（圆、标题和网址）。
    public static func bookmarkGrid(_ size: DesktopPinSize) -> Grid {
        switch size {
        case .small: Grid(columns: 2, rows: 2)
        case .medium: Grid(columns: 4, rows: 2)
        case .large: Grid(columns: 1, rows: 6)
        }
    }

    /// 文件暂存：小号叠在一起的图标加个数，中号一排 4 格，大号 4×3。
    public static func shelfGrid(_ size: DesktopPinSize) -> Grid {
        switch size {
        case .small: Grid(columns: 1, rows: 1)
        case .medium: Grid(columns: 4, rows: 1)
        case .large: Grid(columns: 4, rows: 3)
        }
    }

    /// 最近截图：最新一张画大，其余放网格。小号只有最新一张；中号右边 2×2；大号下面 3×2。
    public static func shotGrid(_ size: DesktopPinSize) -> Grid {
        switch size {
        case .small: Grid(columns: 0, rows: 0)
        case .medium: Grid(columns: 2, rows: 2)
        case .large: Grid(columns: 3, rows: 2)
        }
    }

    /// 壁纸大号：当前壁纸下面一排排文件夹里的图，点一下设为壁纸。
    public static let wallpaperGrid = Grid(columns: 4, rows: 2)

    /// 截图工具的按钮（最多 4 个）怎么排：小号只放排第一的那个（一个大按钮），中号和大号
    /// 一排全放。
    public static func captureGrid(count: Int, size: DesktopPinSize) -> Grid {
        let n = min(max(count, 0), 4)
        guard n > 0 else { return Grid(columns: 0, rows: 0) }
        switch size {
        case .small: return Grid(columns: 1, rows: 1)
        case .medium, .large: return Grid(columns: n, rows: 1)
        }
    }

    /// 截图工具大号下面摆几张最近截图。
    public static let captureRecentShots = 3

    /// 网格放 `total` 个东西、最多 `capacity` 格：放得下全放；放不下时最后一格写「+N」，
    /// 前面放 capacity - 1 个，N 是没放出来的个数。
    public static func slots(total: Int, capacity: Int) -> (shown: Int, more: Int) {
        let total = max(total, 0)
        guard capacity > 0 else { return (0, total) }
        guard total > capacity else { return (total, 0) }
        let shown = capacity - 1
        return (shown, total - shown)
    }

    // MARK: 摸鱼时钟

    /// 摸鱼时钟每档摆几个小格（设置里最多 4 个）：小号不摆；中号右边有小熊猫，一排最多 3 个
    /// （每格约 66 宽，「6420元」这种 13pt 以上放得下，4 个就得缩到 13pt 以下）；大号 2×2。
    public static func slackerCells(_ size: DesktopPinSize, available: Int) -> Int {
        switch size {
        case .small: 0
        case .medium: min(max(available, 0), 3)
        case .large: min(max(available, 0), 4)
        }
    }

    // MARK: 相册

    /// 相册卡片多久重画一次：轮播按设置的间隔换，按秒对齐就不会晚；暂停或只有一张时按分钟。
    public static func photoTick(interval: Double, count: Int, paused: Bool) -> TimeInterval {
        guard !paused, count > 1, interval.isFinite, interval > 0 else { return 60 }
        return 1
    }
}
