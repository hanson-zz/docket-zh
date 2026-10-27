import SwiftUI

// MARK: - 桌面卡片 · 时间组

@MainActor
enum DesktopCardsTime {
    /// 时间组的专属布局；不是本组的种类返回 nil，走通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopTimeCards.kinds.contains(widget.kind) else { return nil }
        return nil
    }
}
