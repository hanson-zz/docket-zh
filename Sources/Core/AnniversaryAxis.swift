import Foundation

/// 多个纪念日卡片的“接下来一年”时间轴，和单个卡片撕页旁边那行小字要用的数。
///
/// 都是纯函数：日期换成轴上 0...1 的位置，月份刻度，标签放不放得下，指针或点击
/// 落在哪个点上。卡片只管按这些数画。

/// 轴上的一个纪念日。
public struct AnniversaryAxisPoint: Equatable, Sendable, Identifiable {
    public var reading: AnniversaryReading
    /// 定位用的那一天：倒数日是下一次到来，正数日是下一个周年（还没开始的正数日是那天本身）。
    public var date: Date
    /// 从今天起还有几天，今天是 0。
    public var daysLeft: Int
    /// 0 是今天，1 是一年后的今天。
    public var fraction: Double

    public var id: String { reading.event.id }
}

/// 轴上的一个月份刻度：那个月的 1 号。
public struct AnniversaryAxisTick: Equatable, Sendable {
    public var month: Int
    public var fraction: Double
}

extension Anniversary {
    /// 轴的长度：今天到一年后的今天有几天（跨过 2 月 29 日是 366）。
    public static func axisSpan(today: Date, calendar: Calendar = Anniversary.calendar) -> Int {
        let start = calendar.startOfDay(for: today)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 365 }
        return max(1, days(from: start, to: end, calendar: calendar))
    }

    /// 某一天在轴上的位置，今天之前算 0，一年以后算 1。
    public static func axisFraction(_ date: Date, today: Date, calendar: Calendar = Anniversary.calendar) -> Double {
        let left = days(from: today, to: date, calendar: calendar)
        return min(1, max(0, Double(left) / Double(axisSpan(today: today, calendar: calendar))))
    }

    /// 时间轴上给这个纪念日定位的那一天，没有就是 nil（一次性的倒数日已经过去）。
    ///
    /// 倒数日用下一次到来；正数日用下一个周年，今天正好是周年就是今天；正数日的那天
    /// 还没到（比如定好的入职日），就用那天本身。
    public static func axisDate(_ reading: AnniversaryReading, today: Date,
                                calendar: Calendar = Anniversary.calendar) -> Date? {
        let start = calendar.startOfDay(for: today)
        switch reading.event.kind {
        case .countdown:
            return reading.next
        case .countup:
            if reading.original >= start { return reading.original }
            return upcomingAnniversaries(reading.event, today: start, count: 1, calendar: calendar).first?.date
        }
    }

    /// 一年之内要到的纪念日，按日子从近到远（同一天按名字）。一年以外的、已经过去
    /// 不会再来的都不上轴。
    public static func axisPoints(_ events: [AnniversaryEvent], today: Date,
                                  calendar: Calendar = Anniversary.calendar) -> [AnniversaryAxisPoint] {
        let start = calendar.startOfDay(for: today)
        let span = axisSpan(today: start, calendar: calendar)
        let points: [AnniversaryAxisPoint] = events.compactMap { event in
            guard let reading = reading(event, today: start, calendar: calendar),
                  let date = axisDate(reading, today: start, calendar: calendar) else { return nil }
            let left = days(from: start, to: date, calendar: calendar)
            guard left >= 0, left <= span else { return nil }
            return AnniversaryAxisPoint(reading: reading, date: date, daysLeft: left,
                                        fraction: Double(left) / Double(span))
        }
        return points.sorted {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.reading.event.title < $1.reading.event.title
        }
    }

    /// 今天之后、一年之内每个月 1 号的位置。今天正好是 1 号时也算一个刻度。
    public static func axisTicks(today: Date, calendar: Calendar = Anniversary.calendar) -> [AnniversaryAxisTick] {
        let start = calendar.startOfDay(for: today)
        let span = axisSpan(today: start, calendar: calendar)
        var parts = calendar.dateComponents([.year, .month], from: start)
        parts.day = 1
        guard var first = calendar.date(from: parts) else { return [] }
        if first < start, let after = calendar.date(byAdding: .month, value: 1, to: first) { first = after }
        var ticks: [AnniversaryAxisTick] = []
        var day = first
        while true {
            let left = days(from: start, to: day, calendar: calendar)
            guard left <= span else { break }
            ticks.append(AnniversaryAxisTick(month: calendar.component(.month, from: day),
                                             fraction: Double(left) / Double(span)))
            guard let next = calendar.date(byAdding: .month, value: 1, to: day) else { break }
            day = next
        }
        return ticks
    }

    /// 哪些点的标签放得下，放得下的标签中心落在哪里。
    ///
    /// `centers` 是每个点在轴上的横坐标（点），`widths` 是各自标签的宽度，`total` 是
    /// 整条轴的宽度。按 `order`（先排的先放，通常最近的那个排第一）一个个放：标签以点为
    /// 中心，超出两头就往里挪；和已经放下的标签挨得比 `gap` 还近就不放，只画点。
    /// 返回和 `centers` 一样长，放不下的是 nil。
    public static func placeLabels(centers: [Double], widths: [Double], total: Double,
                                   gap: Double = 4, order: [Int]? = nil) -> [Double?] {
        guard centers.count == widths.count, total > 0 else { return centers.map { _ in nil } }
        var placed: [(lo: Double, hi: Double)] = []
        var result = [Double?](repeating: nil, count: centers.count)
        for index in order ?? Array(centers.indices) where centers.indices.contains(index) {
            let width = min(widths[index], total)
            let center = min(max(centers[index], width / 2), total - width / 2)
            let lo = center - width / 2, hi = center + width / 2
            let clashes = placed.contains { lo < $0.hi + gap && hi > $0.lo - gap }
            guard !clashes else { continue }
            placed.append((lo, hi))
            result[index] = center
        }
        return result
    }

    /// 指针或点击落在横坐标 `x` 时指着哪个点：离得最近的那个，而且不超过 `radius`。
    /// 两个点一样近时取前面那个。
    public static func nearestPoint(to x: Double, centers: [Double], radius: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, center) in centers.enumerated() {
            let distance = abs(center - x)
            guard distance <= radius else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// 每个点能点到的那一段横坐标：离它比离旁边的点都近，而且不超过 `radius`。
    /// `centers` 要从左到右排好；和 `nearestPoint` 说的是同一件事，卡片按这些段摆按钮，
    /// 段外面是空白，点了打开时间线。
    public static func hitZones(centers: [Double], radius: Double) -> [ClosedRange<Double>] {
        centers.indices.map { index in
            let center = centers[index]
            var lo = center - radius, hi = center + radius
            if index > 0 { lo = max(lo, (centers[index - 1] + center) / 2) }
            if index < centers.count - 1 { hi = min(hi, (center + centers[index + 1]) / 2) }
            return lo...max(lo, hi)
        }
    }

    // MARK: Single card

    /// 撕页旁边大数字下面那行小字。
    ///
    /// 正数日：第 8 年 · 下个周年 214 天（周年就是今天时写“第 8 个周年”）。倒数日：
    /// 那天是星期几，每年重复的再写“每年”，一次性的写年份。已经过去的一次性倒数日写
    /// 原来的日子。
    public static func tileLine(_ reading: AnniversaryReading, today: Date,
                                calendar: Calendar = Anniversary.calendar) -> String {
        let start = calendar.startOfDay(for: today)
        let event = reading.event
        switch (event.kind, reading.phase) {
        case (.countup, .past):
            if let note = reading.anniversaryNote { return note }
            let year = tr("第 \(reading.years + 1) 年")
            guard let next = upcomingAnniversaries(event, today: start, count: 1, calendar: calendar).first else {
                return year
            }
            // 没勾“每年”的正数日，周年那天卡片不算“就是今天”，这行字照样说是几周年。
            if next.daysLeft == 0 { return tr("\(reading.years) 周年") }
            return tr("\(year) · 下个周年 \(next.daysLeft) 天")
        case (_, .today):
            return event.lunar ? lunarShort(start, calendar: calendar) : weekdayShort(start, calendar: calendar)
        case (.countdown, .past):
            return tr("\(solarText(reading.original, calendar: calendar)) · 已过")
        default:
            let date = reading.kindDate
            let weekday = weekdayShort(date, calendar: calendar)
            if event.yearly { return tr("\(weekday) · 每年") }
            return tr("\(weekday) · \(String(calendar.component(.year, from: date)))年")
        }
    }

    /// 撕页上那一页：中间的大字、下面的小字，农历事件写农历。
    public static func leaf(_ reading: AnniversaryReading,
                            calendar: Calendar = Anniversary.calendar) -> (day: String, month: String) {
        let date = reading.kindDate
        if reading.event.lunar {
            let parts = lunarParts(date, calendar: calendar)
            return (lunarDayName(parts.day), lunarMonthName(parts.month, leap: parts.isLeap))
        }
        let c = calendar.dateComponents([.month, .day], from: date)
        return ("\(c.day ?? 1)", monthShort(c.month ?? 1))
    }

    static let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// 5月；英文界面是 May，撕页和时间轴的月份字都这么短。
    public static func monthShort(_ month: Int) -> String {
        L10n.isEnglish ? englishMonths[max(0, min(month - 1, 11))] : tr("\(month)月")
    }
}

extension AnniversaryReading {
    /// 卡片上写的那一天：正在正数的是开始那天，其余是下一次到来（或那天本身）。
    public var kindDate: Date {
        event.kind == .countup && phase == .past ? original : timelineDate
    }
}
