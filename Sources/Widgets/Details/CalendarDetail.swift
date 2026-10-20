import SwiftUI

/// 日历小组件的面板：一周条、那天的时间轴、接下来、快速新建和改日程，写回系统日历。
///
/// 和一周日程共用 `CalendarPlannerPanel`；卡片仍各是各的。角上的暖光照旧是台历撕页的红。
struct CalendarDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        CalendarPlannerPanel(instance: instance, context: context,
                             backdrop: Color(red: 0.78, green: 0.2, blue: 0.22))
    }
}
