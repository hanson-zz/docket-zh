import Foundation

/// 收音机面板“我的收藏”列表有多高。
///
/// 原来固定最多 150pt，收藏行字号提到 13pt 后只露三行左右。现在按行数
/// 自适应：最多露 `maxVisibleRows` 行，超过才在列表里滚动；行数少时
/// 列表就是那几行的高度，不在下面留空白。行高由面板量出来传进来
/// （经典和复古皮肤行高不同），还没量到时用 `fallbackRowHeight`。
public enum RadioFavouriteList {
    /// 最多同时露几行，再多就滚动。
    public static let maxVisibleRows = 5
    /// 行与行之间的间距，和面板里的 VStack 一致。
    public static let rowSpacing: CGFloat = 2

    /// 还没量到行高时的估计值：经典皮肤两行 13pt 字加上下内边距，
    /// 复古皮肤固定 34pt。
    public static func fallbackRowHeight(retro: Bool) -> CGFloat { retro ? 34 : 43 }

    /// 列表视口高度。`rowCount` 为 0 时是 0。
    public static func height(rowCount: Int, rowHeight: CGFloat,
                              spacing: CGFloat = rowSpacing,
                              maxRows: Int = maxVisibleRows) -> CGFloat {
        let shown = min(max(rowCount, 0), max(maxRows, 1))
        guard shown > 0, rowHeight > 0 else { return 0 }
        return CGFloat(shown) * rowHeight + CGFloat(shown - 1) * max(spacing, 0)
    }

    /// 行数超过能露的行数，列表要滚动。
    public static func scrolls(rowCount: Int, maxRows: Int = maxVisibleRows) -> Bool {
        rowCount > max(maxRows, 1)
    }
}
