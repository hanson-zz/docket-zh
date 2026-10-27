import Foundation

// MARK: - 桌面卡片专属布局：Tasks 组
//
// 快速待办、提醒事项、便签、习惯打卡、喝水、久坐提醒、小熊猫的竹篮、电子宠物钉在桌面时
// 不再是放大的扩展栏卡片或塞进卡片的面板，而是为小 160×160 / 中 340×160 / 大 340×340
// 专门排的布局（视图在 Sources/Widgets/DesktopCards/DesktopCardsTasks.swift）。
// 这里放纯判断：哪些种类走专属布局、每档列几条、放不下时怎么收、主操作是哪个。

public enum DesktopCardsTasksPlan {
    /// 本组接管的八种小组件。三档都提供（小号是专门排的，总能放下）。
    public static let kinds: Set<WidgetKind> = [
        .todo, .reminders, .notes, .habit, .water, .posture, .perfectDay, .pet,
    ]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    // MARK: 列表

    /// 列表类每档最多占几行（放不下时最后一行写「还有 N 项」）。
    /// 小号只列一条（核心是左上的大数字），中号三条，大号按 340 高里 13pt 以上的行排满。
    public static func listRows(_ kind: WidgetKind, size: DesktopPinSize) -> Int {
        switch (kind, size) {
        case (.todo, .small), (.reminders, .small), (.habit, .small): 1
        case (.todo, .medium), (.reminders, .medium), (.habit, .medium): 3
        case (.todo, .large): 6
        case (.reminders, .large): 5
        case (.habit, .large): 6
        default: 0
        }
    }

    public struct ListCut: Equatable, Sendable {
        /// 画出来的条数。
        public var shown: Int
        /// 没画出来的条数，大于 0 时最后一行写「还有 N 项」。
        public var more: Int

        public init(shown: Int, more: Int) {
            self.shown = shown
            self.more = more
        }
    }

    /// 放得下就全放；放不下就让出一行写「还有 N 项」，卡片不能看起来像是全部。
    /// 只有一行可用时那一行画第一条，剩下的数交给别处（小号的大数字）。
    public static func cut(total: Int, rows: Int) -> ListCut {
        let total = max(0, total)
        guard rows > 0 else { return ListCut(shown: 0, more: total) }
        if total <= rows { return ListCut(shown: total, more: 0) }
        let shown = max(1, rows - 1)
        return ListCut(shown: shown, more: total - shown)
    }

    // MARK: 习惯

    /// 小号上那一个「打卡」按钮给谁：今天还没完成、也没被 Pro 锁住的第一个习惯。
    /// 都完成了（或只剩锁着的）是 nil，卡片写「今天都打完了」。
    public static func nextHabit(_ habits: [Habit], today: Date, unlocked: Bool,
                                 calendar: Calendar = HabitTracker.calendar) -> Habit? {
        habits.first { habit in
            !HabitTracker.isDone(habit, on: today, calendar: calendar)
                && !ProLicenseGate.isHabitLocked(habit.id, in: habits, unlocked: unlocked)
        }
    }

    // MARK: 电子宠物

    /// 小号上唯一的按钮做什么：病了先看病；有一项低于警戒线就照顾最低的那项；
    /// 都还好时照顾数值最低的那项（喂、玩、睡、洗，和卡片上点格子一样）。
    public static func petPrimaryAction(_ state: PetState) -> PetAction {
        if VirtualPet.isSick(state) { return .heal }
        if let need = WaterPetCards.mostNeeded(state) { return WaterPetCards.action(for: need) }
        let lowest = PetNeed.allCases.min { state[$0] < state[$1] } ?? .food
        return WaterPetCards.action(for: lowest)
    }

    // MARK: 便签

    /// 便签纸上的字号：大号按面板里选的字号，中号略小，小号再小一档但不小于 13pt。
    public static func notePointSize(panel: Double, size: DesktopPinSize) -> Double {
        switch size {
        case .large: max(13, panel)
        case .medium: max(13, (panel * 0.86).rounded())
        case .small: max(13, (panel * 0.7).rounded())
        }
    }

    /// 小号纸上不写「便签 · 第 2 张」那行标题，字从顶上开始，叠了几张只在右下角写「2/3」。
    public static func noteShowsTitle(_ size: DesktopPinSize) -> Bool { size != .small }

    // MARK: 喝水

    /// 大号上的快捷量：一杯（卡片设置的杯量）和半杯（取整到 5）。杯量很小时只有一杯。
    public static func waterQuickAmounts(cup: Int) -> [Int] {
        let cup = max(10, cup)
        guard cup >= 20 else { return [cup] }
        let half = Int((Double(cup) / 2 / 5).rounded()) * 5
        return [cup, half]
    }
}
