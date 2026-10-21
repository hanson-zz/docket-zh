import SwiftUI

/// 农历与假期：只管节气、法定假日和调休上班。
///
/// 同一张卡按优先级只说一件事（见 `LunarCard`）：接下来几天有调休要上班时整行变红，
/// 「下周六要上班 / 10月10日 调休补班」；节气、传统节日当天做大标题，「今日霜降 /
/// 农历九月十四」；平常是离下一个法定假日还有几天，「国庆还有 12 天 / 10月1日起
/// 连放 7 天」。徽章只留星期和日做定位，大号日期请用日历的「日期」样式。
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
                    TileBadge(size: WidgetStyle.badgeCompact) { badge(reading, now: now, size: 15) }
                    Text(reading.shortTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(reading.isAlert ? LunarReading.red : WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(reading.shortCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(reading.isCountdown ? LunarReading.red : WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge { badge(reading, now: now, size: 17) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(reading.isAlert ? LunarReading.red : WidgetStyle.primary)
                        Text(reading.caption)
                            .font(.system(size: 13, weight: reading.isCountdown ? .semibold : .regular))
                            .foregroundStyle(reading.isCountdown ? LunarReading.red : WidgetStyle.secondary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            holidays.refresh()
            LunarNotifier.shared.update(instance, known: holidays.known)
            LunarNotifier.shared.updateEvents(instance)
        }
        // 放假数据联网更新后，或第二天，重新排前一晚的提醒；生日过了一天也要排下一次。
        .onChange(of: ChineseCalendar.key(now)) { _, _ in
            guard !context.isPreview else { return }
            LunarNotifier.shared.update(instance, known: holidays.known)
            LunarNotifier.shared.updateEvents(instance)
        }
        // 面板里加、改、删了生日。
        .onChange(of: instance.config.strings(LunarEvents.key)) { _, _ in
            if !context.isPreview { LunarNotifier.shared.updateEvents(instance) }
        }
        .onChange(of: holidays.known.keys.sorted()) { _, _ in
            if !context.isPreview { LunarNotifier.shared.update(instance, known: holidays.known) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("农历\(reading.lunar.short)，\(reading.title)，\(reading.caption)"))
    }

    /// 生日、纪念日当天换成小熊猫来送祝福，平常是星期和日。
    @ViewBuilder
    private func badge(_ reading: LunarReading, now: Date, size: CGFloat) -> some View {
        if reading.isEvent, let panda = PandaArt.image(LunarReading.pandaPose) {
            Image(nsImage: panda)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(2)
                .accessibilityHidden(true)
        } else {
            dayBadge(now, size: size)
        }
    }

    private func dayBadge(_ now: Date, size: CGFloat) -> some View {
        let calendar = ChineseCalendar.gregorian
        return VStack(spacing: -1) {
            Text(LunarReading.weekday(now))
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(LunarReading.red)
            Text("\(calendar.component(.day, from: now))")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
        }
    }
}

/// What the tile and the panel both say, worked out once.
@MainActor
struct LunarReading {
    var lunar: ChineseCalendar.LunarDate
    var headline: LunarCard.Headline
    var title: String
    var caption: String
    var today: Date

    init(now: Date, config: WidgetConfig, known: [Int: [HolidayDay]], breaks: [HolidayBreak]) {
        today = now
        lunar = ChineseCalendar.lunar(now)
        headline = LunarCard.headline(now: now, known: known, breaks: breaks,
                                      leadDays: LunarCard.leadDays(config),
                                      showTerm: config.bool("showTerm", default: true),
                                      workAlert: config.bool("workAlert", default: true),
                                      events: LunarEventCache.todays(config, now: now))
        title = LunarCard.title(headline, now: now)
        caption = LunarCard.caption(headline, now: now)
    }

    var isAlert: Bool { headline.isAlert }

    var isCountdown: Bool {
        if case .countdown = headline { return true }
        return false
    }

    var isEvent: Bool {
        if case .event = headline { return true }
        return false
    }

    /// 生日那天卡片上的小熊猫。
    static let pandaPose = "pet-panda-cheer"

    /// 竖排 56pt：调休写「周六上班」这类短句，倒计时写名字。
    var shortTitle: String {
        switch headline {
        case .makeupWorkday(_, let days, _):
            return days == 0 ? tr("今天上班") : (days == 1 ? tr("明天上班") : tr("\(days) 天后上班"))
        case .event(let name, _, _): return name
        case .special(let name): return trKey(name)
        case .countdown(let item): return trKey(HolidaySchedule.shortName(item.name))
        case .none: return lunar.dayName
        }
    }

    var shortCaption: String {
        switch headline {
        case .makeupWorkday: return tr("调休")
        case .event(_, let kind, _): return LunarEvents.greeting(kind)
        case .special, .none: return lunar.dayName
        case .countdown(let item):
            let days = ChineseCalendar.days(from: today, to: item.start)
            return days > 0 ? tr("\(days) 天") : tr("放假中")
        }
    }

    static let red = Color(hex: "#FF6B6B")

    static func weekday(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = ChineseCalendar.gregorian.component(.weekday, from: date) - 1
        return tr("周\(trKey(names[max(0, min(index, 6))]))")
    }
}

/// 卡片每秒重画一次，今天有没有人过生日一天只算一次（加、改、删了就重算）。
@MainActor
enum LunarEventCache {
    private static var key = ""
    private static var value: [LunarEvent] = []

    static func todays(_ config: WidgetConfig, now: Date) -> [LunarEvent] {
        let stored = config.strings(LunarEvents.key)
        guard !stored.isEmpty else { return [] }
        let wanted = ChineseCalendar.key(now) + "\n" + stored.joined(separator: "\n")
        if wanted != key {
            key = wanted
            value = LunarEvents.today(LunarEvents.events(config), now: now)
        }
        return value
    }
}
