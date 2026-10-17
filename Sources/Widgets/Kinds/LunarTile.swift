import SwiftUI

/// Today's date with its lunar date beside it, and the next public holiday.
///
/// The second line is the one worth reading: a worked weekend coming up
/// ("明天调休，要上班") when there is one, otherwise how long until the
/// next break. See `ChineseCalendar` and `HolidaySchedule`.
struct LunarTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var holidays: HolidayService { HolidayService.shared }

    var body: some View {
        let now = context.now
        let reading = LunarReading(now: now, config: instance.config, known: holidays.known,
                                   breaks: holidays.breaks(now: now))
        return WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: WidgetStyle.badgeCompact) { dayBadge(now, size: 15) }
                    Text(reading.lunar.dayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                    Text(reading.shortCountdown)
                        .font(.system(size: 10))
                        .foregroundStyle(reading.alert == nil ? WidgetStyle.secondary : tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge { dayBadge(now, size: 17) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                        Text(reading.caption)
                            .font(.system(size: 12, weight: reading.alert == nil ? .regular : .semibold))
                            .foregroundStyle(reading.alert == nil ? WidgetStyle.secondary : tint)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { if !context.isPreview { holidays.refresh() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("农历\(reading.lunar.short)，\(reading.caption)")
    }

    private var tint: Color { Color(hex: PaletteColor.red.hex).mix(with: WidgetStyle.primary, by: 0.15) }

    private func dayBadge(_ now: Date, size: CGFloat) -> some View {
        let calendar = ChineseCalendar.gregorian
        return VStack(spacing: -1) {
            Text(LunarReading.weekday(now))
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(calendar.component(.day, from: now))")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
        }
    }
}

/// What the tile and the panel both say, worked out once.
struct LunarReading {
    var lunar: ChineseCalendar.LunarDate
    var special: String?
    var alert: String?
    var next: HolidayBreak?
    var countdown: String
    var today: Date

    init(now: Date, config: WidgetConfig, known: [Int: [HolidayDay]], breaks: [HolidayBreak]) {
        today = now
        lunar = ChineseCalendar.lunar(now)
        let showTerm = config.bool("showTerm", default: true)
        special = ChineseCalendar.festival(on: now) ?? (showTerm ? ChineseCalendar.term(on: now) : nil)
        alert = config.bool("workAlert", default: true) ? HolidaySchedule.alert(now: now, known: known) : nil
        next = HolidaySchedule.next(after: now, in: breaks)
        countdown = next.map { HolidaySchedule.countdown($0, now: now) } ?? ""
    }

    /// 九月初三 · 霜降
    var headline: String { special.map { "\(lunar.short) · \($0)" } ?? lunar.short }
    var caption: String { alert ?? countdown }

    /// For the narrow column: 80 天, or the alert squeezed.
    var shortCountdown: String {
        if alert != nil { return "调休" }
        guard let next else { return "" }
        let days = ChineseCalendar.days(from: today, to: next.start)
        return days > 0 ? "\(days) 天" : HolidaySchedule.shortName(next.name)
    }

    static func weekday(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = ChineseCalendar.gregorian.component(.weekday, from: date) - 1
        return "周" + names[max(0, min(index, 6))]
    }
}
