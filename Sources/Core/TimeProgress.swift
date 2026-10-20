import Foundation

/// 时间进度小组件的规则：周期（日、周、月、年）、过去的比例、卡片上的标签和
/// “剩多少”，以及新卡片用哪种外观、液态要不要动。卡片和面板只负责画。
///
/// 外观（`layout`）有四种：圆环（新卡片的推荐默认）、百分比、液态，以及老的
/// 进度条。老卡片保存的 layout 不动；没存 layout 的旧数据仍按进度条读，
/// 只有新放上去的卡片才是圆环。
public enum TimeProgress {
    public static let periodKey = "period"
    public static let layoutKey = "layout"
    /// 液态外观的水面动效（波纹和气泡）。关掉或系统开了“减少动态效果”时静止。
    public static let motionKey = "liquidMotion"

    /// 没存 layout 的旧卡片按进度条读，保持原样。
    public static let legacyLayout = "bars"
    /// 新放上去的卡片用圆环。
    public static let newWidgetLayout = "ring"

    /// 圆环描边、进度条和水的蓝色渐变，从浅到深。
    public static let gradientHex = ("#6ED3FF", "#2F7BFF")

    /// 时间进度用的日历：系统日历，但一周固定从周一开始，不跟系统设置里的
    /// 每周第一天。卡片和面板都用它，本周进度、第几周、本周七天对得上。
    public static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    public enum Period: String, CaseIterable, Sendable {
        case day, week, month, year

        public var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }

        /// 设置里的名字。
        public var title: String {
            switch self {
            case .day: tr("日", context: "period")
            case .week: tr("周", context: "period")
            case .month: tr("月", context: "period")
            case .year: tr("年", context: "period")
            }
        }

        /// 读屏时说的话。
        public var spoken: String {
            switch self {
            case .day: tr("今天")
            case .week: tr("本周")
            case .month: tr("本月")
            case .year: tr("今年")
            }
        }

        /// 点卡片上的标签换到下一个：日、周、月、年，再回到日。
        public var next: Period {
            let all = Period.allCases
            let index = all.firstIndex(of: self) ?? 0
            return all[(index + 1) % all.count]
        }
    }

    public static func period(_ config: WidgetConfig) -> Period {
        Period(rawValue: config.string(periodKey, default: Period.year.rawValue)) ?? .year
    }

    public static func layout(_ config: WidgetConfig) -> String {
        config.string(layoutKey, default: legacyLayout)
    }

    /// 液态外观的水面动不动：设置关掉或系统要求减少动态效果时静止。
    public static func liquidAnimates(_ config: WidgetConfig, reduceMotion: Bool) -> Bool {
        config.bool(motionKey, default: true) && !reduceMotion
    }

    /// 当前周期的日历区间。按真实日历算，夏令时那天和闰年都不会错。
    public static func interval(_ period: Period, now: Date,
                                calendar: Calendar = TimeProgress.calendar) -> DateInterval? {
        calendar.dateInterval(of: period.component, for: now)
    }

    /// 0...1，这个周期过去了多少。
    public static func fraction(_ period: Period, now: Date,
                                calendar: Calendar = TimeProgress.calendar) -> Double {
        guard let span = interval(period, now: now, calendar: calendar), span.duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(span.start) / span.duration))
    }

    /// 卡片上的整数百分比，向下取整：过了 99.6% 也不提前写 100%。
    public static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int(min(1, max(0, fraction)) * 100)
    }

    /// 周期的名字：2026年、10月、第42周、周六。
    public static func label(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        switch period {
        case .year: return tr("\(calendar.component(.year, from: now))年")
        case .month: return tr("\(calendar.component(.month, from: now))月")
        case .week: return tr("第\(calendar.component(.weekOfYear, from: now))周")
        case .day:
            let names = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
            let weekday = calendar.component(.weekday, from: now)
            return names[max(0, min(names.count - 1, weekday - 1))]
        }
    }

    /// 还剩多少：一天按小时（不到一小时按分钟），更长的周期按天。
    ///
    /// 天数从今天零点数到周期结束，今天也算一天，夏令时不会少算一天。
    public static func remaining(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        guard let end = interval(period, now: now, calendar: calendar)?.end else { return "" }
        switch period {
        case .day:
            let minutes = Int((max(0, end.timeIntervalSince(now)) / 60).rounded(.up))
            return minutes >= 60 ? tr("剩 \(minutes / 60) 小时") : tr("剩 \(minutes) 分钟")
        case .week, .month, .year:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
            return tr("剩 \(max(0, days)) 天")
        }
    }

    /// 四格外观：年、月、周、今天四个周期一起看，只给百分比。
    public static let quadLayout = "quad"

    /// 四格里的一行。
    public struct QuadRow: Equatable, Sendable {
        public var period: Period
        public var title: String
        public var fraction: Double
        public var percent: Int
    }

    /// 四格的四行，从长到短：年、月、周、今天。
    public static func quadRows(now: Date, calendar: Calendar = TimeProgress.calendar) -> [QuadRow] {
        [Period.year, .month, .week, .day].map { period in
            let value = TimeProgress.fraction(period, now: now, calendar: calendar)
            return QuadRow(period: period, title: quadTitle(period), fraction: value,
                           percent: TimeProgress.percent(value))
        }
    }

    /// 四格行首的字：年、月、周、今天。
    public static func quadTitle(_ period: Period) -> String {
        switch period {
        case .year: tr("年", context: "period")
        case .month: tr("月", context: "period")
        case .week: tr("周", context: "period")
        case .day: tr("今天")
        }
    }

    /// 圆环版的说明：「2026年 · 剩 80 天」。
    public static func caption(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        let rest = remaining(period, now: now, calendar: calendar)
        let name = label(period, now: now, calendar: calendar)
        return rest.isEmpty ? name : "\(name) · \(rest)"
    }
}
