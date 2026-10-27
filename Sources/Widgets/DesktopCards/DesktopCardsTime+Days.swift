import AppKit
import EventKit
import SwiftUI

// MARK: - 桌面卡片 · 时间组：时间进度、一周日程、农历、纪念日、日历
//
// 入口和共用零件见 DesktopCardsTime.swift。

// MARK: - 时间进度

/// 时间进度：环心大百分比，点周期名换日 / 周 / 月 / 年（存进同一个 period，扩展栏跟着换）。
/// 中号右边说明和四个周期一排可点；大号四个周期一起看，选中的那条高亮。颜色跟主题色。
struct TimeDeskProgressCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private var period: TimeProgress.Period { TimeProgress.period(widget.config) }

    private var accent: Color {
        WidgetTintStyle(kind: .progress, config: widget.config).main(dark: scheme == .dark)
    }

    var body: some View {
        let fraction = TimeProgress.fraction(period, now: now)
        let percent = TimeProgress.percent(fraction)
        switch size {
        case .small:
            VStack(spacing: 8) {
                ZStack {
                    TimeDeskRing(fraction: fraction, tint: accent, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text("\(percent)%")
                            .font(timeDeskNumber(30))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(TimeProgress.remaining(period, now: now))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: 78)
                }
                .frame(width: 102, height: 102)
                periodButton(TimeProgress.label(period, now: now))
            }
            .padding(DesktopCardsTime.inset(size))
        case .medium:
            HStack(spacing: 18) {
                ZStack {
                    TimeDeskRing(fraction: fraction, tint: accent, lineWidth: 11)
                    Text("\(percent)%")
                        .font(timeDeskNumber(28))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 80)
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(TimeProgress.label(period, now: now))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(TimeProgress.remaining(period, now: now))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    periodPicker(height: 30)
                }
                .padding(.vertical, 4)
            }
            .padding(DesktopCardsTime.inset(size))
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                TimeDeskHeader(symbol: "chart.bar.fill", title: WidgetCatalog.entry(.progress)?.name ?? tr("时间进度"),
                               tint: accent)
                ForEach(TimeProgress.quadRows(now: now), id: \.period) { row in
                    quadRow(row)
                }
                Spacer(minLength: 0)
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    /// 一个周期一行：名字、剩余、大百分比、进度条。点它把扩展栏卡片换成这个周期。
    private func quadRow(_ row: TimeProgress.QuadRow) -> some View {
        let selected = row.period == period
        return Button { choose(row.period) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TimeProgress.label(row.period, now: now))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(TimeProgress.remaining(row.period, now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                    Spacer(minLength: 4)
                    Text("\(row.percent)%")
                        .font(timeDeskNumber(20))
                        .monospacedDigit()
                        .foregroundStyle(selected ? accent.panelReadable : Color.panelPrimary)
                }
                .lineLimit(1)
                TimeDeskBar(fraction: row.fraction, tint: selected ? accent : Color.panelSecondary, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.panelSelected : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(TimeProgress.label(row.period, now: now)) \(row.percent)%")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func periodButton(_ title: String) -> some View {
        Button { choose(DesktopTimeCards.nextPeriod(period)) } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.panelFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("换一个周期"))
    }

    private func periodPicker(height: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(TimeProgress.Period.allCases, id: \.self) { item in
                let selected = item == period
                Button { choose(item) } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .background {
                            if selected { Capsule().fill(Color.panelRaised).panelLift() }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.spoken)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.panelFill))
    }

    private func choose(_ next: TimeProgress.Period) {
        guard next != period else { return }
        DesktopCardsTime.write(widget) { $0.set(TimeProgress.periodKey, .string(next.rawValue)) }
    }
}

// MARK: - 日历读取

/// 桌面卡片读日历：和日历卡片同一个 store，从不弹授权（授权在面板里要）。没权限时 nil。
@MainActor
private enum DeskCalendarRead {
    static func entries(_ span: DateInterval, chosen: Set<String>) -> [WeekEntry]? {
        guard CalendarEventStore.hasAccess else { return nil }
        let store = CalendarEventStore.shared
        let all = store.calendars(for: .event)
        let wanted = all.filter { chosen.contains($0.calendarIdentifier) }
        // 筛选里的日历都没了时按全部，不显示成空的一天（同日历卡片）。
        let scope = wanted.isEmpty ? all : wanted
        guard !scope.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: span.start, end: span.end, calendars: scope)
        return store.events(matching: predicate).compactMap { WeekEvents.entry($0) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}

/// 读一段时间的日程：出现时读一次，之后每 5 分钟、日历有改动、卡片改了日历筛选时再读。
private struct DeskEventsReader<Content: View>: View {
    var widget: WidgetInstance
    var now: Date
    var span: DateInterval
    @ViewBuilder var content: ([WeekEntry]?) -> Content

    @State private var entries: [WeekEntry]? = nil
    @State private var loaded = false

    var body: some View {
        content(loaded ? entries : (CalendarEventStore.hasAccess ? [] : nil))
            .onAppear { load() }
            .onChange(of: widget.config.strings("calendars")) { _, _ in load() }
            .onChange(of: Int(now.timeIntervalSince1970) / 300) { _, _ in load() }
            .onChange(of: span) { _, _ in load() }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    private func load() {
        entries = DeskCalendarRead.entries(span, chosen: Set(widget.config.strings("calendars")))
        loaded = true
    }
}

/// 缺日历权限：小锁和「需要日历权限 · 去开启」，点了去开启。
private struct DeskCalendarLock: View {
    var kind: WidgetKind
    var compact: Bool

    var body: some View {
        PermissionLockNote(permission: TilePermission.name(for: kind.rawValue) ?? "日历",
                           compact: compact, stacked: true)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一条日程：日历色条、标题、时间（和地点），进行中的标出来，快开始的会给「加入」。
private struct DeskEventRow: View {
    var entry: WeekEntry
    var now: Date
    var accent: Color
    var showsDay = false

    private var color: Color {
        entry.colorHex.isEmpty ? accent : Color(hex: entry.colorHex)
    }

    var body: some View {
        let ongoing = DesktopTimeCards.isOngoing(entry, now: now)
        HStack(spacing: 10) {
            Capsule().fill(color).frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(detail(ongoing: ongoing))
                    .font(.system(size: 13, weight: ongoing ? .semibold : .regular))
                    .foregroundStyle(ongoing ? color.panelReadable : Color.panelSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = entry.link, entry.end > now, entry.start.timeIntervalSince(now) < 15 * 60 {
                Button { NSWorkspace.shared.open(link.url) } label: {
                    Text(tr("加入"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelOnPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.panelPrimary))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(link.provider.joinTitle)
            }
        }
    }

    private func detail(ongoing: Bool) -> String {
        if entry.isAllDay { return tr("全天") }
        var text = CalendarDay.range(entry.start, entry.end)
        if showsDay, !Calendar.current.isDate(entry.start, inSameDayAs: now) {
            text = tr("周\(WeekAgenda.weekdayNames[MonthGrid.weekdayIndex(entry.start)])") + " " + text
        }
        if ongoing { text = tr("进行中") + " · " + text }
        if !entry.location.isEmpty { text += " · \(entry.location)" }
        return text
    }
}

// MARK: - 一周日程

/// 一周日程：本周已排几小时、哪天下午最空，七列上下午忙闲格（填多少是被占几小时）。
/// 点某一列在日历里打开那天。大号下面再列接下来三个日程。
struct TimeDeskWeekCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var accent: Color { WeekEvents.accent }
    private var freeGreen: Color { Color(hex: "#34B36A") }
    private var showsAllDay: Bool { widget.config.bool("allDay", default: true) }

    var body: some View {
        DeskEventsReader(widget: widget, now: now, span: WeekAgenda.interval(now)) { entries in
            if let entries {
                content(WeekAgenda.days(entries, now: now, includeAllDay: showsAllDay), entries: entries)
            } else {
                DeskCalendarLock(kind: .week, compact: size == .small)
            }
        }
    }

    @ViewBuilder
    private func content(_ days: [WeekDay], entries: [WeekEntry]) -> some View {
        let free = WeekBusy.freestAfternoon(days, now: now, workdays: workdays(days))
        let todayIndex = days.first(where: \.isToday)?.index
        let hours = WeekBusy.hoursText(WeekBusy.totalHours(days))
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("本周已排"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(hours)
                            .font(timeDeskNumber(32))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelPrimary)
                        Text(tr("小时"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                grid(days, free: free, dates: false)
                if let free {
                    freeLine(free, todayIndex: todayIndex)
                }
            }
            .padding(DesktopCardsTime.inset(size))
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                header(hours: hours, free: free, todayIndex: todayIndex)
                grid(days, free: free, dates: true)
            }
            .padding(DesktopCardsTime.inset(size))
        case .large:
            let next = DesktopTimeCards.upcoming(entries, now: now, limit: DesktopTimeCards.rows(.week, .large),
                                                 includeAllDay: false)
            VStack(alignment: .leading, spacing: 10) {
                header(hours: hours, free: free, todayIndex: todayIndex)
                grid(days, free: free, dates: true)
                    .frame(height: 150)
                TimeDeskRule()
                if next.isEmpty {
                    Text(tr("本周接下来没有日程"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(next) { entry in DeskEventRow(entry: entry, now: now, accent: accent, showsDay: true) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    private func header(hours: String, free: FreeAfternoon?, todayIndex: Int?) -> some View {
        HStack(spacing: 6) {
            Text(tr("本周已排 \(hours) 小时"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
            Spacer(minLength: 4)
            if let free { freeLine(free, todayIndex: todayIndex) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func freeLine(_ free: FreeAfternoon, todayIndex: Int?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(freeGreen).frame(width: 7, height: 7)
            Text(WeekBusy.freeTitle(free, todayIndex: todayIndex))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(freeGreen.panelReadable)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// 七列：上半格下午、下半格上午（同扩展栏卡片），底下星期（和日期）。今天整列淡底，
    /// 过去的日子变淡，最空的下午绿色虚线框。点一列在日历里打开那天。
    private func grid(_ days: [WeekDay], free: FreeAfternoon?, dates: Bool) -> some View {
        HStack(spacing: size == .small ? 2 : 6) {
            ForEach(days) { day in
                let load = WeekBusy.load(day)
                let past = !day.isToday && day.date < WeekAgenda.calendar.startOfDay(for: now)
                Button { CalendarOpener.show(day.date) } label: {
                    VStack(spacing: 3) {
                        cell(WeekBusy.fill(hours: load.afternoon), free: free?.dayIndex == day.index)
                        cell(WeekBusy.fill(hours: load.morning), free: false)
                        Text(WeekAgenda.weekdayNames[day.index])
                            .font(.system(size: 13, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? accent.panelReadable : Color.panelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if dates {
                            Text("\(WeekAgenda.calendar.component(.day, from: day.date))")
                                .font(.system(size: 13, weight: day.isToday ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(day.isToday ? Color.panelPrimary : Color.panelTertiary)
                        }
                    }
                    .padding(.horizontal, size == .small ? 1 : 3)
                    .padding(.vertical, 3)
                    .opacity(past ? 0.45 : 1)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(day.isToday ? accent.opacity(0.16) : Color.clear)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("在日历里打开\(WeekAgenda.dayTitle(day))"))
                .accessibilityLabel(tr("在日历里打开\(WeekAgenda.dayTitle(day))"))
            }
        }
    }

    private func cell(_ fill: Double, free: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.panelTrack)
                if fill > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accent.panelGraphic)
                        .frame(height: max(3, proxy.size.height * CGFloat(fill)))
                }
                if free {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(freeGreen, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(freeGreen.opacity(0.15)))
                }
            }
        }
    }

    /// 本周哪几天算工作日：按法定假日和调休（同扩展栏卡片）。
    private func workdays(_ days: [WeekDay]) -> Set<Int> {
        let known = HolidayService.shared.known
        return Set(days.compactMap { day -> Int? in
            switch HolidaySchedule.kind(of: day.date, known: known) {
            case .workday, .makeupWorkday: day.index
            case .holiday, .weekend: nil
            }
        })
    }
}

// MARK: - 农历

/// 农历与假期：大字公历日和星期、农历日期，按优先级只说一件事（调休要上班整行变红、
/// 节气节日、离下个假期几天）。中号加宜忌，大号是带农历、节气和休 / 班的本月月历。
struct TimeDeskLunarCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var holidays: HolidayService { HolidayService.shared }
    private var red: Color { LunarReading.red }
    private var green: Color { Color(hex: "#2E9E5B") }

    var body: some View {
        let reading = LunarReading(now: now, config: widget.config, known: holidays.known,
                                   breaks: holidays.breaks(now: now))
        Group {
            switch size {
            case .small: small(reading)
            case .medium: medium(reading)
            case .large: large(reading)
            }
        }
        .onAppear { holidays.refresh() }
    }

    private var day: Int { ChineseCalendar.gregorian.component(.day, from: now) }

    private func small(_ reading: LunarReading) -> some View {
        VStack(spacing: 3) {
            Text(LunarReading.weekday(now))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(red.panelReadable)
            Text("\(day)")
                .font(timeDeskNumber(50))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(reading.lunar.short)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
            Text(reading.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(reading.isAlert || reading.isCountdown ? red.panelReadable : Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(DesktopCardsTime.inset(.small))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ reading: LunarReading) -> some View {
        HStack(spacing: 16) {
            dateBlock(figure: 44)
                .frame(width: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.lunar.full)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(reading.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(reading.isAlert ? red.panelReadable : Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(reading.caption)
                    .font(.system(size: 13, weight: reading.isCountdown ? .semibold : .regular))
                    .foregroundStyle(reading.isCountdown ? red.panelReadable : Color.panelSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                almanacLine(tr("宜"), LunarAlmanac.good(now), color: green)
                almanacLine(tr("忌"), LunarAlmanac.bad(now), color: red)
            }
            Spacer(minLength: 0)
        }
        .padding(DesktopCardsTime.inset(.medium))
    }

    private func almanacLine(_ mark: String, _ items: [String], color: Color) -> some View {
        HStack(spacing: 6) {
            Text(mark)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color.panelReadable)
                .frame(width: 20, height: 20)
                .background(Circle().fill(color.opacity(0.16)))
            Text(items.prefix(4).map { trKey($0) }.joined(separator: " "))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 日期块：星期红字、大号日、月份。
    private func dateBlock(figure: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(LunarReading.weekday(now))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(red.panelReadable)
            Text("\(day)")
                .font(timeDeskNumber(figure))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
            Text(tr("\(ChineseCalendar.gregorian.component(.month, from: now))月"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.panelFill))
    }

    private func large(_ reading: LunarReading) -> some View {
        let calendar = ChineseCalendar.gregorian
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let cells = LunarCard.month(year: year, month: month, now: now, known: holidays.known,
                                    showTerm: widget.config.bool("showTerm", default: true))
        let blanks = LunarCard.leadingBlanks(year: year, month: month)
        let rows = DesktopTimeCards.monthRows(year: year, month: month)
        let rowHeight: CGFloat = rows > 5 ? 36 : 42
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tr("\(month)月"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(reading.lunar.full)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Text("\(reading.title) · \(reading.caption)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(reading.isAlert || reading.isCountdown ? red.panelReadable : Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(WeekAgenda.weekdayNames[index])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(index >= 5 ? red.panelReadable : Color.panelTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column - blanks
                            if index >= 0, index < cells.count {
                                monthCell(cells[index])
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DesktopCardsTime.inset(.large))
    }

    /// 月历一格：公历日、下面一行农历 / 节气 / 节日；休、班角标；今天实心底。
    private func monthCell(_ cell: LunarCard.MonthCell) -> some View {
        let marked = cell.mark != LunarCard.CellMark.none
        let off = cell.mark == LunarCard.CellMark.off
        return VStack(spacing: 0) {
            Text("\(cell.day)")
                .font(.system(size: 15, weight: cell.isToday ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(cell.isToday ? Color.panelOnPrimary
                                 : (cell.isWeekend || off ? red.panelReadable : Color.panelPrimary))
            Text(LunarCard.cellName(cell.sub))
                .font(.system(size: 13, weight: cell.subIsSpecial ? .semibold : .regular))
                .foregroundStyle(cell.isToday ? Color.panelOnPrimary.opacity(0.85)
                                 : (cell.subIsSpecial ? red.panelReadable : Color.panelTertiary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if cell.isToday {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelPrimary).padding(1)
            } else if marked {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((off ? green : red).opacity(0.1)).padding(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(marked ? "\(cell.day) \(cell.sub) \(off ? tr("休") : tr("班"))" : "\(cell.day) \(cell.sub)")
    }
}

// MARK: - 纪念日

/// 纪念日：核心是置顶的（没置顶时最近的）那个，大号数字「还有 / 已经 N 天」和日期。
/// 中号右边列接下来三个，大号列四个、每个带这一轮的进度，点一行把它置顶到核心
/// （和面板里「置顶」同一个设置）。日子到了那天换成小熊猫和「就是今天」。
struct TimeDeskAnniversaryCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    var body: some View {
        let events = Anniversary.events(widget.config)
        let pinned = Anniversary.pinnedID(widget.config)
        if let featured = Anniversary.featured(events, pinned: pinned, today: now) {
            let readings = Anniversary.readings(events, today: now)
            switch size {
            case .small:
                hero(featured, figure: 46, compact: true)
                    .padding(DesktopCardsTime.inset(size))
            case .medium:
                let others = DesktopTimeCards.otherReadings(readings, featured: featured.event.id,
                                                            limit: DesktopTimeCards.rows(.anniversary, .medium))
                HStack(spacing: 14) {
                    hero(featured, figure: 50, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !others.isEmpty {
                        TimeDeskRule(vertical: true).padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(others, id: \.event.id) { reading in smallRow(reading) }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 128)
                    }
                }
                .padding(DesktopCardsTime.inset(size))
            case .large:
                let others = DesktopTimeCards.otherReadings(readings, featured: featured.event.id,
                                                            limit: DesktopTimeCards.rows(.anniversary, .large))
                VStack(alignment: .leading, spacing: 10) {
                    hero(featured, figure: 58, compact: false)
                        .frame(height: 140)
                    TimeDeskRule()
                    if others.isEmpty {
                        Text(tr("在面板里可以再加纪念日"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(others, id: \.event.id) { reading in bigRow(reading) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(DesktopCardsTime.inset(size))
            }
        } else {
            TimeDeskEmpty(symbol: "gift", title: tr("还没有纪念日"), hint: tr("在扩展栏的纪念日面板里添加"))
        }
    }

    private func color(_ event: AnniversaryEvent) -> Color { AnniversaryTile.base(event) }

    /// 核心：名字、「还有 / 已经」、大数字 + 天、日期。当天是小熊猫和「就是今天」。
    private func hero(_ reading: AnniversaryReading, figure: CGFloat, compact: Bool) -> some View {
        let tint = color(reading.event)
        return VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(reading.event.title)
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if Anniversary.isCelebrating(reading) {
                HStack(alignment: .bottom, spacing: 6) {
                    if let panda = PandaArt.image(LunarReading.pandaPose) {
                        Image(nsImage: panda)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: figure)
                            .accessibilityHidden(true)
                    }
                    Text(reading.anniversaryNote ?? tr("就是今天"))
                        .font(.system(size: compact ? 20 : 26, weight: .heavy))
                        .foregroundStyle(tint.panelReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text(reading.word)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(reading.days)")
                        .font(timeDeskNumber(figure, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(tr("天"))
                        .font(.system(size: compact ? 14 : 17, weight: .bold))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            Text(Anniversary.subtitle(reading))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func smallRow(_ reading: AnniversaryReading) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color(reading.event)).frame(width: 7, height: 7)
            Text(reading.event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(reading.phase == .today ? tr("今天") : "\(reading.days)")
                .font(timeDeskNumber(15))
                .monospacedDigit()
                .foregroundStyle(reading.phase == .past ? Color.panelSecondary : Color.panelPrimary)
        }
    }

    /// 大号一行：名字、日期、这一轮的进度条，右边天数。点一下置顶到核心。
    private func bigRow(_ reading: AnniversaryReading) -> some View {
        let tint = color(reading.event)
        return Button {
            DesktopCardsTime.write(widget) { Anniversary.pin(reading.event.id, in: &$0) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(tint).frame(width: 8, height: 8)
                        Text(reading.event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                        Text(Anniversary.subtitle(reading))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    TimeDeskBar(fraction: reading.progress, tint: tint, height: 4)
                }
                Text(reading.phase == .today ? tr("今天") : reading.sentence)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("放到上面"))
        .accessibilityLabel(tr("\(reading.event.title)\(reading.sentence)，放到上面"))
    }
}

// MARK: - 日历

/// 日历：日期块（星期、大号日、月份和农历）加今天接下来的日程，快开始的会给「加入」。
/// 大号上半是本月月历（有日程的日子下面一个点，点某天在日历里打开），下半是今天的日程。
struct TimeDeskCalendarCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        DesktopCardsTime.accent(widget, own: Color(hex: WidgetCatalog.accentHex(.calendar) ?? PaletteColor.orange.hex),
                                dark: scheme == .dark)
    }

    private var showsAllDay: Bool { widget.config.bool("allDay", default: true) }

    /// 大号读整个月（月历上的点），小号中号只读今天。
    private var span: DateInterval {
        let calendar = WeekAgenda.calendar
        if size == .large,
           let month = MonthGrid.interval(MonthGrid.monthStart(now, calendar: calendar), calendar: calendar) {
            return month
        }
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    var body: some View {
        DeskEventsReader(widget: widget, now: now, span: span) { entries in
            if let entries {
                content(today(entries), all: entries)
            } else if size == .small {
                dateBlock(figure: 52)
            } else {
                DeskCalendarLock(kind: .calendar, compact: false)
            }
        }
    }

    /// 今天的（今天开始的，或者跨着现在的）。
    private func today(_ entries: [WeekEntry]) -> [WeekEntry] {
        entries.filter { Calendar.current.isDate($0.start, inSameDayAs: now) || ($0.start < now && $0.end > now) }
    }

    @ViewBuilder
    private func content(_ today: [WeekEntry], all: [WeekEntry]) -> some View {
        let next = DesktopTimeCards.upcoming(today, now: now, limit: DesktopTimeCards.rows(.calendar, size),
                                             includeAllDay: showsAllDay)
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent.panelReadable)
                Text("\(WeekAgenda.calendar.component(.day, from: now))")
                    .font(timeDeskNumber(48))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let first = next.first {
                    HStack(spacing: 7) {
                        Capsule().fill(eventColor(first)).frame(width: 3, height: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(first.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelPrimary)
                            Text(first.isAllDay ? tr("全天") : CalendarDay.clock(first.start))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Color.panelSecondary)
                        }
                        .lineLimit(1)
                    }
                } else {
                    Text(tr("今天没有别的日程"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(2)
                }
            }
            .padding(DesktopCardsTime.inset(size))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .medium:
            HStack(spacing: 14) {
                dateBlock(figure: 44)
                    .frame(width: 96)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.panelFill))
                VStack(alignment: .leading, spacing: 8) {
                    if next.isEmpty {
                        Spacer(minLength: 0)
                        Text(tr("今天没有别的日程"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary)
                        Text(tr("好好安排自己的时间"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(next) { entry in DeskEventRow(entry: entry, now: now, accent: accent) }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesktopCardsTime.inset(size))
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                monthGrid(busy: DesktopTimeCards.busyDays(all))
                TimeDeskRule()
                if next.isEmpty {
                    Text(tr("今天没有别的日程"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(next) { entry in DeskEventRow(entry: entry, now: now, accent: accent) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    private var weekdayText: String {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.locale = L10n.interfaceLocale
        return now.formatted(style)
    }

    private func eventColor(_ entry: WeekEntry) -> Color {
        entry.colorHex.isEmpty ? accent : Color(hex: entry.colorHex)
    }

    /// 日期块：星期（主题色）、大号日、月份（中文界面再加农历）。
    private func dateBlock(figure: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(weekdayText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent.panelReadable)
                .lineLimit(1)
            Text("\(WeekAgenda.calendar.component(.day, from: now))")
                .font(timeDeskNumber(figure))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(monthLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var monthLine: String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.locale = L10n.interfaceLocale
        let month = now.formatted(style)
        guard !L10n.isEnglish else { return month }
        return "\(month) · \(ChineseCalendar.lunar(now).dayName)"
    }

    /// 本月月历：周一开头，今天实心，有日程的日子下面一个主题色点，点某天在日历里打开。
    private func monthGrid(busy: Set<Date>) -> some View {
        let calendar = WeekAgenda.calendar
        let month = MonthGrid.monthStart(now, calendar: calendar)
        let weeks = MonthGrid.weeks(month, now: now, calendar: calendar)
        let rowHeight: CGFloat = weeks.count > 5 ? 25 : 29
        return VStack(spacing: 2) {
            HStack {
                Text(MonthGrid.title(month, english: L10n.isEnglish, calendar: calendar))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Spacer(minLength: 0)
                Text(weekdayText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
            }
            .padding(.bottom, 2)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(WeekAgenda.weekdayNames[index])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        Button { CalendarOpener.show(day.date) } label: {
                            VStack(spacing: 1) {
                                Text("\(calendar.component(.day, from: day.date))")
                                    .font(.system(size: 13, weight: day.isToday ? .bold : .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(day.isToday ? Color.panelOnPrimary
                                                     : (day.inMonth ? Color.panelPrimary : Color.panelQuaternary))
                                    .frame(width: 24, height: 20)
                                    .background {
                                        if day.isToday { Circle().fill(Color.panelPrimary) }
                                    }
                                Circle()
                                    .fill(busy.contains(calendar.startOfDay(for: day.date)) && day.inMonth
                                          ? accent.panelGraphic : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MonthGrid.dayTitle(day.date, english: L10n.isEnglish, calendar: calendar))
                    }
                }
            }
        }
    }
}
