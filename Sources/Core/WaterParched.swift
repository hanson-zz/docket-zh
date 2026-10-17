import Foundation

/// 喝水卡片的“渴成骷髅”：提醒时段里很久没喝水，或者一天过去大半进度还很低，
/// 角色换成骷髅（小熊猫是趴姿的 WaterPanda-skeleton，其他角色用宠物的骷髅图），
/// 喝一杯或达标就复活。设置里的 `dryUp` 可以关掉，默认开。
///
/// 和电子宠物的“渴成骷髅”（连续几天没达标，见 `VirtualPet.isDried`）是两回事：
/// 这里只看今天。
public enum WaterParched {
    /// 喝水卡片自己的开关，和宠物面板里的同名开关存在各自的配置里。
    public static let key = "dryUp"
    /// 提醒时段里这么久没喝（时段开始前喝的不算）就渴成骷髅。比打瞌睡的 3 小时更久。
    public static let afterHours: Double = 5
    /// 提醒时段过去这么多以后，进度还低于 `lowProgress` 也算。
    public static let lateShare = 0.6
    public static let lowProgress = 0.25

    /// 只在提醒时段里、今天还没达标时才可能是骷髅：时段外它在睡觉。
    public static func isParched(now: Date, lastDrink: Date?, total: Int, goal: Int,
                                 window: WaterReminder, calendar: Calendar = WaterIntake.calendar) -> Bool {
        guard goal > 0, total < goal, window.isActive(now, calendar: calendar) else { return false }
        let hours = window.window(calendar.startOfDay(for: now))
        let since = max(lastDrink ?? hours.start, hours.start)
        if now.timeIntervalSince(since) >= afterHours * 3600 { return true }
        let span = hours.end.timeIntervalSince(hours.start)
        guard span > 0 else { return false }
        let gone = now.timeIntervalSince(hours.start) / span
        return gone >= lateShare && WaterIntake.progress(total: total, goal: goal) < lowProgress
    }

    /// 从喝水卡片的配置读：开关、今天的记录、目标和提醒时段。
    public static func isParched(_ config: WidgetConfig, now: Date,
                                 calendar: Calendar = WaterIntake.calendar) -> Bool {
        guard config.bool(key, default: true) else { return false }
        let days = WaterIntake.days(config)
        let today = WaterIntake.today(days, goal: WaterIntake.goal(config, now: now, calendar: calendar),
                                      now: now, calendar: calendar)
        return isParched(now: now, lastDrink: WaterIntake.lastDrink(days, calendar: calendar),
                         total: today.total, goal: today.goal, window: WaterReminder(config: config),
                         calendar: calendar)
    }

    /// 骷髅图的名字（不带扩展名）。
    public static func imageName(_ character: WaterCharacter) -> String {
        character == .redPanda ? "WaterPanda-skeleton" : "pet-\(character.rawValue)-skeleton"
    }
}
