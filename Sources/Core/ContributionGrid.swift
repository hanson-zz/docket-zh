import Foundation

/// 像 GitHub 贡献图那样的周格子：一列是一周（周一在上），最右一列是本周，
/// 每格按当天的数量分成 0 到 4 五档深浅。
///
/// 习惯卡片和 GitHub 面板都用它。纯函数，测试可以拨到任意一天。
public enum ContributionGrid {

    public static let maxLevel = 4

    public struct Cell: Equatable, Hashable, Sendable {
        public var date: Date
        public var count: Int
        /// 0 是空格，`maxLevel` 是最深。
        public var level: Int
        public var isToday: Bool
        public var isFuture: Bool

        public init(date: Date, count: Int, level: Int, isToday: Bool, isFuture: Bool) {
            self.date = date
            self.count = count
            self.level = level
            self.isToday = isToday
            self.isFuture = isFuture
        }
    }

    /// 周一开头的公历，和习惯打卡用的同一种。
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// 最近 `weeks` 周，旧的在左；每列 7 格，周一到周日。本周今天之后的格子标成未来。
    /// `count` 给出某天的数量，`level` 把数量换成深浅档。
    public static func columns(weeks: Int, today: Date, calendar: Calendar = ContributionGrid.calendar,
                               count: (Date) -> Int, level: (Int) -> Int) -> [[Cell]] {
        guard weeks > 0 else { return [] }
        let start = calendar.startOfDay(for: today)
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        guard let thisMonday = calendar.date(byAdding: .day, value: -lead, to: start),
              let firstMonday = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday)
        else { return [] }
        return (0..<weeks).map { week in
            (0..<7).compactMap { row in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + row, to: firstMonday)
                else { return nil }
                let future = date > start
                let value = future ? 0 : max(0, count(date))
                return Cell(date: date, count: value, level: future ? 0 : clamp(level(value)),
                            isToday: date == start, isFuture: future)
            }
        }
    }

    /// 有目标的计数：做满是最深，做了一部分按比例落在 1 到 3 档，没做是 0。
    public static func level(count: Int, goal: Int) -> Int {
        guard count > 0 else { return 0 }
        let goal = max(goal, 1)
        if count >= goal { return maxLevel }
        let ratio = Double(count) / Double(goal)
        return min(maxLevel - 1, max(1, Int((ratio * Double(maxLevel - 1)).rounded(.up))))
    }

    /// 没有目标的计数（比如一天来了几条反馈）：和这段时间里最多的那天比，分四档。
    public static func level(count: Int, busiest: Int) -> Int {
        guard count > 0 else { return 0 }
        let top = max(busiest, 1)
        let ratio = Double(min(count, top)) / Double(top)
        return min(maxLevel, max(1, Int((ratio * Double(maxLevel)).rounded(.up))))
    }

    /// 把一串时间按天数一数，键是当天零点。
    public static func tally(_ dates: [Date], calendar: Calendar = ContributionGrid.calendar) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for date in dates { result[calendar.startOfDay(for: date), default: 0] += 1 }
        return result
    }

    /// 出场动画里这一格晚多久亮：从左往右一列一列推过去，同一列从上往下错开一点，
    /// 整张图不超过 `total` 秒。
    public static func delay(column: Int, row: Int, columns: Int, total: Double = 0.45) -> Double {
        let steps = Double(max(columns - 1, 0) + 6)
        guard steps > 0 else { return 0 }
        let step = Double(max(column, 0) + min(max(row, 0), 6))
        return total * step / steps
    }

    /// 读屏和悬停提示用的一句话。
    public static func describe(_ cell: Cell, unit: String) -> String {
        let c = calendar.dateComponents([.month, .day], from: cell.date)
        let day = tr("\(c.month ?? 0) 月 \(c.day ?? 0) 日")
        if cell.isFuture { return day }
        return cell.count == 0 ? tr("\(day)，没有记录") : "\(day)，\(cell.count) \(unit)"
    }

    static func clamp(_ level: Int) -> Int { min(max(level, 0), maxLevel) }
}
