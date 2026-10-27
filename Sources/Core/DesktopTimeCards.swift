import Foundation

// MARK: - 桌面卡片 · 时间组
//
// 时钟、世界时钟、秒表、专注计时、倒计时、闹钟、时间进度、一周日程、农历、纪念日、日历
// 钉在桌面时的专属布局（视图在 Sources/Widgets/DesktopCards/DesktopCardsTime.swift）。
// 这里放纯判断：哪些种类有专属布局、每档显示几条、挑哪几条。

public enum DesktopTimeCards {
    /// 有专属布局的种类（小 / 中 / 大三档都有，小号总能放下）。
    public static let kinds: Set<WidgetKind> = []
}
