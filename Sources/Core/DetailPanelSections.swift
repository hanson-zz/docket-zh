import Foundation

/// 详情面板里分页（顶部分段）和折叠（默认收起）的状态记在哪、怎么读。
///
/// 面板统一限高后（见 `DetailPanelFit.cap(visible:)`），最高的几个面板把次要
/// 内容挪进分页或折叠里，默认打开的高度落在上限内。用户切到的那一页、展开的
/// 那一段按小组件种类记在 UserDefaults 里，下次打开照旧。
public enum DetailPanelSections {
    /// 某种小组件面板记住的分页。
    public static func pageKey(_ kind: WidgetKind) -> String {
        "detailPanel.page.\(kind.rawValue)"
    }

    /// 某种小组件面板里某一段折叠的展开状态。
    public static func foldKey(_ kind: WidgetKind, _ section: String) -> String {
        "detailPanel.fold.\(kind.rawValue).\(section)"
    }

    /// 记着的分页还在能选的页里就用它，否则（没记过、那一页被关掉了）用第一页。
    /// 一页都没有时是 nil。
    public static func page<Page: RawRepresentable>(stored: String, available: [Page]) -> Page?
    where Page.RawValue == String {
        available.first { $0.rawValue == stored } ?? available.first
    }

    /// 可以全部收起的分段（收音机）：记着的是空字符串或已不在的页时是 nil，
    /// 也就是一页都不打开。
    ///
    /// `stored` 为 nil 是从没记过（新用户），这时打开 `initial`（不在能选的页里
    /// 就都收起）；记过的（包括收起后存的空字符串）照用户的选择。
    public static func openPage<Page: RawRepresentable>(
        stored: String?, available: [Page], initial: Page? = nil
    ) -> Page? where Page.RawValue == String {
        guard let stored else {
            guard let initial else { return nil }
            return available.first { $0.rawValue == initial.rawValue }
        }
        return available.first { $0.rawValue == stored }
    }

    /// 点了可收起分段里的某一页：点的是已经打开的那页就收起（存空字符串），
    /// 否则打开它。
    public static func toggled<Page: RawRepresentable>(_ tapped: Page, open: Page?) -> String
    where Page.RawValue == String {
        open?.rawValue == tapped.rawValue ? "" : tapped.rawValue
    }
}
