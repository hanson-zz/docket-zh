import Foundation

// MARK: - 钉在桌面 · 系统组
//
// 电池、系统活动、网络、圆环仪表、快速开关、隔空投送、废纸篓、应用切换器、快捷指令、
// 搜索这 10 种钉在桌面时不再是「放大的扩展栏卡片」或「面板塞进卡片」，而是按小 160×160、
// 中 340×160、大 340×340 专门排的布局（视图在 Sources/Widgets/DesktopCards/DesktopCardsSystem.swift）。
//
// 这里只放纯判断：哪几种走专属布局、每档摆几个、几列几行、写不写状态那行字、列表列几条、
// 电池剩余时间那行字。界面按这里的数排，测试直接编译。

public enum DesktopSystemCards {
    /// 走专属布局的 10 种。它们三档都有：小号是专门排的，总能放下（电池和快速开关原来
    /// 放大的扩展栏卡片在 160×160 里要缩小，所以没有小号，现在有了）。
    public static let kinds: Set<WidgetKind> = [
        .battery, .system, .network, .gauges, .toggles,
        .airdrop, .trash, .appSwitcher, .shortcut, .search,
    ]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 一组按钮 / 圆环 / 图标怎么排。
    public struct Grid: Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        /// 画出来几个（从前往后取）。
        public var shown: Int
        /// 没画出来的几个；大于 0 时最后一格写「+N」（快速开关、应用切换器）。
        public var overflow: Int
        /// 名字下面写不写状态那行（开 / 关、读数说明）。
        public var showsCaption: Bool

        public init(columns: Int, rows: Int, shown: Int, overflow: Int = 0, showsCaption: Bool) {
            self.columns = columns
            self.rows = rows
            self.shown = shown
            self.overflow = overflow
            self.showsCaption = showsCaption
        }

        public static let empty = Grid(columns: 0, rows: 0, shown: 0, showsCaption: false)
    }

    private static func rows(_ count: Int, columns: Int) -> Int {
        columns > 0 ? (count + columns - 1) / columns : 0
    }

    // MARK: 快速开关

    /// 小号：1 个是一整块大按钮，2 个上下两条（图标、名字、开 / 关），3、4 个是 2×2 的
    /// 大图标（160 宽里两列放不下四个字的名字，名字放在悬停提示里，开着的整块亮起）。中号：4 个以内一排大按钮写状态，5 个起两排四列（最多 8 个）。
    /// 大号：9 个以内三列写状态，下面还放得下「保持唤醒多久」；更多时四列四行（最多 16 个）。
    /// 放不下的最后一格写「+N」，点它打开扩展栏上的面板。
    public static func toggleGrid(count: Int, size: DesktopPinSize) -> Grid {
        let total = max(0, count)
        guard total > 0 else { return .empty }
        switch size {
        case .small:
            if total <= 2 { return Grid(columns: 1, rows: total, shown: total, showsCaption: true) }
            return clipped(total, columns: 2, rows: 2, caption: false)
        case .medium:
            if total <= 4 { return Grid(columns: total, rows: 1, shown: total, showsCaption: true) }
            return clipped(total, columns: 4, rows: 2, caption: false)
        case .large:
            if total <= 9 {
                return Grid(columns: 3, rows: rows(total, columns: 3), shown: total, showsCaption: true)
            }
            return clipped(total, columns: 4, rows: 4, caption: false)
        }
    }

    /// 大号快速开关下面「保持唤醒多久」那排：勾了保持唤醒、并且是三列写状态的排法时才放。
    public static func showsAwakeChips(count: Int, hasKeepAwake: Bool, size: DesktopPinSize) -> Bool {
        size == .large && hasKeepAwake && toggleGrid(count: count, size: .large).showsCaption
    }

    /// 放得下就全放；放不下留最后一格写「+N」。
    private static func clipped(_ total: Int, columns: Int, rows: Int, caption: Bool) -> Grid {
        let capacity = columns * rows
        if total <= capacity {
            return Grid(columns: columns, rows: Self.rows(total, columns: columns), shown: total, showsCaption: caption)
        }
        let shown = capacity - 1
        return Grid(columns: columns, rows: rows, shown: shown, overflow: total - shown, showsCaption: caption)
    }

    // MARK: 圆环仪表

    /// 小号：1 个圆环画大圆环、读数写在圆环里；2 个左右并排带说明；3、4 个 2×2 只写读数。
    /// 中号：一排最多 4 个，都带说明。大号：每个圆环一行（`showsCaption` 写完整说明）。
    public static func gaugeGrid(count: Int, size: DesktopPinSize) -> Grid {
        let total = min(max(0, count), 4)
        guard total > 0 else { return .empty }
        switch size {
        case .small:
            if total <= 2 { return Grid(columns: total, rows: 1, shown: total, showsCaption: true) }
            return Grid(columns: 2, rows: 2, shown: total, showsCaption: false)
        case .medium:
            return Grid(columns: total, rows: 1, shown: total, showsCaption: true)
        case .large:
            return Grid(columns: 1, rows: total, shown: total, showsCaption: true)
        }
    }

    // MARK: 应用切换器

    /// 小号 3×3 个 36 的图标，中号两排六列 44 的图标，大号一行一个 App（图标、名字、
    /// 当前 / 没开），最多 7 行。放不下时最后一格（大号是最后一行）写「+N」。
    public static func appGrid(count: Int, size: DesktopPinSize) -> Grid {
        let total = max(0, count)
        guard total > 0 else { return .empty }
        switch size {
        case .small: return clipped(total, columns: 3, rows: 3, caption: false)
        case .medium: return clipped(total, columns: 6, rows: 2, caption: false)
        case .large: return clipped(total, columns: 1, rows: 7, caption: true)
        }
    }

    // MARK: 快捷指令

    /// 小号、中号画卡片上那几个（列表前 4 个）：小号 1 个是一整块大按钮，2 个上下两条，
    /// 3、4 个 2×2 的大图标；中号一排，2 个以内每块写名字和上次结果。大号一行一个，带上次运行的结果和运行键，最多 5 行，
    /// 列表里第 5 个以后的也列（卡片上只放得下前 4 个）。
    public static func shortcutGrid(count: Int, size: DesktopPinSize) -> Grid {
        let total = max(0, count)
        guard total > 0 else { return .empty }
        switch size {
        case .small:
            let shown = min(total, 4)
            if shown <= 2 { return Grid(columns: 1, rows: shown, shown: shown, showsCaption: true) }
            return Grid(columns: 2, rows: 2, shown: shown, showsCaption: false)
        case .medium:
            let shown = min(total, 4)
            return Grid(columns: shown, rows: 1, shown: shown, showsCaption: shown <= 2)
        case .large:
            let shown = min(total, 5)
            return Grid(columns: 1, rows: shown, shown: shown, overflow: total - shown, showsCaption: true)
        }
    }

    // MARK: 列表几行

    /// 列表类的内容每档列几条。
    public enum Rows: Sendable {
        /// 电池：Mac 以外再列几个蓝牙设备。
        case batteryAccessories
        /// 系统活动：最占 CPU 的几个进程（`metrics` 是卡片上选了几个读数）。
        case processes(metrics: Int)
        /// 隔空投送：最近发过的。
        case airDropRecent
        /// 废纸篓：最近扔进去的。
        case trashRecent
        /// 搜索：查找文件的结果。
        case fileResults
        /// 搜索：网页搜索的搜索站图标。
        case searchSites
    }

    public static func rows(_ list: Rows, size: DesktopPinSize) -> Int {
        switch (list, size) {
        case (.batteryAccessories, .small): 0
        case (.batteryAccessories, .medium): 2
        case (.batteryAccessories, .large): 4
        case (.processes, .small), (.processes, .medium): 0
        // 大号先放读数（每个一行带走势），剩下的地方列进程：读数满 4 个时列 2 个，否则 3 个。
        case (.processes(let metrics), .large): metrics >= 4 ? 2 : 3
        case (.airDropRecent, .small), (.airDropRecent, .medium): 0
        case (.airDropRecent, .large): 3
        case (.trashRecent, .small): 0
        case (.trashRecent, .medium): 1
        case (.trashRecent, .large): 4
        case (.fileResults, .small): 1
        case (.fileResults, .medium): 2
        case (.fileResults, .large): 5
        case (.searchSites, .small): 0
        case (.searchSites, .medium): 6
        case (.searchSites, .large): 12
        }
    }

    // MARK: 系统活动

    /// 卡片上画哪几个读数：小号最多 2 个（第一个大字，第二个小字），中号、大号最多 4 个。
    public static func systemMetrics(_ chosen: [String], size: DesktopPinSize) -> [String] {
        let known = ["cpu", "memory", "network", "disk", "battery"]
        var seen = Set<String>()
        let list = chosen.filter { known.contains($0) && seen.insert($0).inserted }
        let usable = list.isEmpty ? ["cpu", "memory"] : list
        return Array(usable.prefix(size == .small ? 2 : 4))
    }

    // MARK: 电池

    /// 电池大字下面那行剩余时间：充电时「约 1 小时 20 分钟充满」，用电池时「还能用约
    /// 3 小时」，macOS 还没估出来或接着电源不充时是 nil。
    public static func batteryRemaining(charging: Bool, onPower: Bool,
                                        minutesToFull: Int?, minutesToEmpty: Int?) -> String? {
        if charging {
            return BatteryStatusText.validMinutes(minutesToFull).map {
                tr("约 \(BatteryStatusText.duration(minutes: $0))充满")
            }
        }
        guard !onPower else { return nil }
        return BatteryStatusText.validMinutes(minutesToEmpty).map {
            tr("还能用约 \(BatteryStatusText.duration(minutes: $0))")
        }
    }

    /// 电池的状态词：没连上、正在充电、已充满、已接电源、使用电池。和扩展栏卡片一样。
    public static func batteryState(present: Bool, charging: Bool, onPower: Bool, level: Double) -> String {
        guard present else { return tr("未连接") }
        if charging { return tr("正在充电") }
        if onPower { return level >= 0.995 ? tr("已充满") : tr("已接电源") }
        return tr("使用电池")
    }

    /// 电量的颜色档：20% 以下橙、10% 以下红（不在充电时），其余正常。
    public enum BatteryTone: Equatable, Sendable { case normal, low, critical, absent }

    public static func batteryTone(level: Double, charging: Bool, onPower: Bool, present: Bool) -> BatteryTone {
        guard present else { return .absent }
        if charging || onPower { return .normal }
        if level <= 0.10 { return .critical }
        if level <= 0.20 { return .low }
        return .normal
    }
}
