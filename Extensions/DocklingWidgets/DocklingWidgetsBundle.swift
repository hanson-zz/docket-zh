import SwiftUI
import WidgetKit

/// 码头的系统小组件：桌面右键「编辑小组件」，小组件库里的「码头」。
///
/// 第一版：时钟、天气、纪念日、快速待办（能打勾）、喝水（能加一杯）、电池、小熊猫，
/// 以及只显示的便签和「算」。股票汇率、音乐控制留到下一批。
@main
struct DocklingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClockWidget()
        WeatherWidget()
        AnniversaryWidget()
        TodoWidget()
        WaterWidget()
        BatteryWidget()
        PetWidget()
        NoteWidget()
        CalcWidget()
    }
}
