import SwiftUI

/// 一周日程小组件的面板：卡片不变，面板和日历小组件同一套（`CalendarPlannerPanel`）：
/// 一周条点哪天看哪天、时间轴、接下来、快速新建和改日程。日历筛选仍存在这张卡片的
/// `calendars` 选项里，全天日程照 `allDay` 选项显示或不显示。
struct WeekDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        CalendarPlannerPanel(instance: instance, context: context, backdrop: WeekEvents.accent)
    }
}
