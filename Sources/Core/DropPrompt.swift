import Foundation

/// 拖入类卡片拖着东西停在上面时写什么、用什么颜色。
///
/// 按“放下后东西去哪”区分：文件暂存是先放着（青），隔空投送是发出去（系统蓝），
/// 废纸篓是扔掉（红），快速待办是变成一件要做的事（橙）。共用一套排法：
/// 虚线框和图标同色，第一行写结果（动词开头），第二行写数量或后果；
/// 松手后卡片回到平时的样子。画法在 `DropTargetOutline`。
public enum DropPrompt: Equatable, Sendable {
    /// 文件暂存：只记位置，原文件不动。
    case fileShelf(files: Int)
    /// 隔空投送：松手后在系统面板里选设备。
    case airDrop(files: Int)
    /// 废纸篓：不是真删，所以不写“删除”。
    case trash(items: Int)
    /// 快速待办：文字、链接、文件都能记。
    case todo

    /// 每种结果的颜色。
    public enum Tint: String, Sendable, CaseIterable {
        case teal, blue, red, orange

        /// 深色外观用的那档。
        public var darkHex: String {
            switch self {
            case .teal: "#40C8C0"
            case .blue: DockMetrics.dropBlueDark
            case .red: "#FF453A"
            case .orange: "#FF9F0A"
            }
        }

        /// 浅色外观用深一点的那档，白底上才看得清。
        public var lightHex: String {
            switch self {
            case .teal: "#0F9A92"
            case .blue: DockMetrics.dropBlueLight
            case .red: "#FF3B30"
            case .orange: "#E07800"
            }
        }

        /// 底下垫的淡色。系统蓝本来就亮，垫得更淡一些。
        public func fillOpacity(dark: Bool) -> Double {
            let base = dark ? DockMetrics.dropFillDark : DockMetrics.dropFillLight
            return self == .blue ? base * 0.6 : base
        }
    }

    public var tint: Tint {
        switch self {
        case .fileShelf: .teal
        case .airDrop: .blue
        case .trash: .red
        case .todo: .orange
        }
    }

    /// 第一行：放下去会怎样。
    public var title: String {
        switch self {
        case .fileShelf: tr("暂存在这里")
        case .airDrop: tr("发送给附近设备")
        case .trash: tr("移到废纸篓")
        case .todo: tr("记一条待办")
        }
    }

    /// 竖排或很窄的卡片上只放得下的短说法，两行。
    public var compactTitle: String {
        switch self {
        case .fileShelf: tr("暂存\n在这里")
        case .airDrop: tr("发给\n附近设备")
        case .trash: tr("移到\n废纸篓")
        case .todo: tr("记一条\n待办")
        }
    }

    /// 第二行：数量或后果。数不出个数（0）时只写后果。
    public var caption: String {
        switch self {
        case .fileShelf(let files):
            files > 0 ? tr("\(files) 个文件") : tr("只记位置，原文件不动")
        case .airDrop(let files):
            files > 0 ? tr("\(files) 个文件 · 松手选设备") : tr("松手选设备")
        case .trash(let items):
            items > 0 ? tr("\(items) 个 · 之后还能拿回来") : tr("之后还能拿回来")
        case .todo:
            tr("文字、链接、文件都行")
        }
    }

    /// 图标（SF Symbols）。隔空投送的图形 SF Symbols 里没有，由卡片自己画，这里给个替身。
    public var symbol: String {
        switch self {
        case .fileShelf: "tray.and.arrow.down"
        case .airDrop: "dot.radiowaves.up.forward"
        case .trash: "trash"
        case .todo: "plus.square"
        }
    }
}
