import AppKit
import EventKit
import SwiftUI

/// 这周哪天忙、哪天空：七列，周一开头，每天两格（上半格下午、下半格上午），
/// 填多少是那半天被占了几小时（满格 4 小时），不是日程个数。标题写本周一共排了
/// 几小时，右边绿色标出本周剩下工作日里最空的下午。指着某天，旁边浮出那天的详情：
/// 排了多久、几点以后全空，和每个日程的标题、时间、地点、日历颜色，有会议链接的带
/// 「加入会议」（见 `EventPeekWindow`）；点一下在日历里打开那天，可以直接新建。
/// 会议名不写在卡片上，那是日历小组件的事。忙闲的算法在 `WeekBusy`。
///
/// Reads EventKit the way the Calendar tile does: on the main actor, every
/// `EKEvent` flattened into a value the moment the fetch returns, and never
/// asking for access, since the shelf draws every tile the instant it appears
/// and a prompt nobody clicked for is worse than a line saying what is
/// missing. The panel owns the request. The week itself (which day an event
/// lands on, how full a day is) is `WeekAgenda`.
struct WeekTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var access = EKEventStore.authorizationStatus(for: .event)
    @State private var entries: [WeekEntry] = []
    /// 指针下面是哪一天（0 是周一），没有指着时是 nil。
    @State private var pointed: Int?
    @Environment(\.widgetHovered) private var tileHovered

    private var showsAllDay: Bool { instance.config.bool("allDay", default: true) }
    private var chosen: Set<String> { Set(instance.config.strings("calendars")) }
    private var hasAccess: Bool { context.isPreview || access == .fullAccess }

    private var week: [WeekDay] {
        let all = context.isPreview ? WeekEvents.samples(now: context.now) : entries
        return WeekAgenda.days(all, now: context.now, includeAllDay: showsAllDay)
    }

    var body: some View {
        WidgetSurface {
            Group {
                if !hasAccess {
                    note
                } else if context.position.isVertical {
                    column(week)
                } else {
                    wide(week)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { load() }
        .onChange(of: instance.config.strings("calendars")) { _, _ in load() }
        // Coarse on purpose, as the Calendar tile: five minutes is invisible
        // and still turns the week over at Monday midnight, and it picks up
        // access granted from the panel.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 300) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("一周日程，本周 \(WeekAgenda.total(week)) 个日程，已排 \(WeekBusy.hoursText(WeekBusy.totalHours(week))) 小时"))
    }

    // MARK: Wide

    private func wide(_ days: [WeekDay]) -> some View {
        let now = context.now
        let free = WeekBusy.freestAfternoon(days, now: now, workdays: workdays(days))
        let todayIndex = days.first(where: \.isToday)?.index
        let lit = tileHovered && !context.isPreview ? pointed.flatMap { days.indices.contains($0) ? days[$0] : nil } : nil
        return VStack(spacing: 3) {
            header(days, free: free, todayIndex: todayIndex)
            GeometryReader { proxy in
                grid(days, free: free, size: proxy.size, lit: lit?.index)
            }
        }
        // 整张（标题和七列）跟着指针：横向对上哪天就浮出哪天。不拦点击。
        .overlay {
            if !context.isPreview {
                PointerPeekTracker { fraction, rect in
                    let index = fraction.map { min(6, max(0, Int(Double($0.x) * 7))) }
                    if index != pointed { pointed = index }
                    peek(index.flatMap { days.indices.contains($0) ? days[$0] : nil }, rect: rect)
                }
            }
        }
        .onChange(of: tileHovered) { _, hovered in
            if !hovered { EventPeekWindow.shared.leave(owner: instance.id) }
        }
        .onDisappear { EventPeekWindow.shared.dismiss(owner: instance.id) }
    }

    /// 指着的那天浮出详情；没指着时等一会儿收起。
    private func peek(_ day: WeekDay?, rect: CGRect) {
        guard let day, rect.width > 0 else {
            EventPeekWindow.shared.leave(owner: instance.id)
            return
        }
        let heading = "\(WeekAgenda.dayTitle(day)) \(tr("\(WeekAgenda.calendar.component(.day, from: day.date))日"))"
        let content = EventPeek.day(heading: heading, subheading: dayLine(day), entries: day.entries.map(\.peekItem))
        let focus = rect.minX + (CGFloat(day.index) + 0.5) / 7 * rect.width
        EventPeekWindow.shared.show(content, key: "\(instance.id)#\(day.index)", owner: instance.id,
                                    accent: accent, tile: rect, focusX: focus, edge: context.position)
    }

    private func header(_ days: [WeekDay], free: FreeAfternoon?, todayIndex: Int?) -> some View {
        HStack(spacing: 4) {
            Text(tr("本周已排 \(WeekBusy.hoursText(WeekBusy.totalHours(days))) 小时"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
            Spacer(minLength: 2)
            if let free {
                Circle().fill(freeGreen).frame(width: 5, height: 5)
                Text(WeekBusy.freeTitle(free, todayIndex: todayIndex))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(freeGreen)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// 「已排 2 小时 · 13:00 以后全空」
    private func dayLine(_ day: WeekDay) -> String {
        let hours = WeekBusy.busyHours(day)
        let busy = hours > 0 ? tr("已排 \(WeekBusy.hoursText(hours)) 小时") : ""
        let note = WeekBusy.freeNote(day, now: context.now)
        return busy.isEmpty ? note : "\(busy) · \(note)"
    }

    private func grid(_ days: [WeekDay], free: FreeAfternoon?, size: CGSize, lit: Int?) -> some View {
        let gap: CGFloat = 2
        let columnWidth = max(1, (size.width - gap * 6) / 7)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: gap) {
                ForEach(days) { day in
                    dayColumn(day, freeAfternoon: free?.dayIndex == day.index, lit: lit == day.index)
                        .frame(width: columnWidth, height: size.height)
                }
            }
            if !context.isPreview {
                // 每一列点一下在日历里打开那天。标题那行不盖，留给卡片自己的点击开面板。
                HStack(spacing: gap) {
                    ForEach(days) { day in
                        Button {
                            CalendarOpener.show(day.date)
                        } label: {
                            Color.clear
                                .frame(width: columnWidth, height: size.height)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("在日历里打开\(WeekAgenda.dayTitle(day))，\(dayLine(day))"))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 上半格下午，下半格上午，底下是星期。今天整列浅底、标签橙色；过去的日子变暗。
    private func dayColumn(_ day: WeekDay, freeAfternoon: Bool, lit: Bool) -> some View {
        let load = WeekBusy.load(day)
        let past = !day.isToday && day.date < WeekAgenda.calendar.startOfDay(for: context.now)
        return VStack(spacing: 2) {
            cell(WeekBusy.fill(hours: load.afternoon), free: freeAfternoon)
            cell(WeekBusy.fill(hours: load.morning), free: false)
            Text(WeekAgenda.weekdayNames[day.index])
                .font(.system(size: 9.5, weight: day.isToday || freeAfternoon ? .bold : .medium))
                .foregroundStyle(day.isToday ? accent : (freeAfternoon ? freeGreen : WidgetStyle.secondary))
                .lineLimit(1)
                .frame(height: 11)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .opacity(past ? 0.45 : 1)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(day.isToday ? accent.opacity(0.18) : (lit ? WidgetStyle.primary.opacity(0.08) : .clear))
        }
    }

    /// 一格：底色是空，从下往上填被占的部分。最空的下午画绿色虚线框。
    private func cell(_ fill: Double, free: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(WidgetStyle.primary.opacity(0.08))
                if fill > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent)
                        .frame(height: max(2, proxy.size.height * CGFloat(fill)))
                }
                if free {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(freeGreen, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(freeGreen.opacity(0.15)))
                }
            }
        }
    }

    /// 本周哪几天算工作日：按法定假日和调休，平常是周一到周五。
    private func workdays(_ days: [WeekDay]) -> Set<Int> {
        let known = HolidayService.shared.known
        return Set(days.compactMap { day -> Int? in
            switch HolidaySchedule.kind(of: day.date, known: known) {
            case .workday, .makeupWorkday: day.index
            case .holiday, .weekend: nil
            }
        })
    }

    private var freeGreen: Color { Color(hex: "#6FDC9A") }

    // MARK: Column

    /// 56pt across: a row per day, the weekday, a bar as long as the day is
    /// busy (按占用时长) against the busiest day, and the count.
    private func column(_ days: [WeekDay]) -> some View {
        let hours = days.map { WeekBusy.busyHours($0) }
        let busiest = hours.max() ?? 0
        return VStack(spacing: 2) {
            ForEach(days) { day in
                HStack(spacing: 3) {
                    Text(WeekAgenda.weekdayNames[day.index])
                        .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? accent : WidgetStyle.secondary)
                        .frame(width: 10)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WidgetStyle.primary.opacity(0.08))
                            Capsule()
                                .fill(color(day.entries.first?.colorHex ?? ""))
                                .frame(width: proxy.size.width * fill(hours[day.index], busiest: busiest))
                        }
                    }
                    .frame(height: 5)
                    Text(day.count > 0 ? "\(day.count)" : "")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .frame(width: 11, alignment: .trailing)
                }
                .frame(height: 12)
                .padding(.horizontal, 2)
                .background {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accent.opacity(0.18))
                    }
                }
            }
        }
        .lineLimit(1)
    }

    // MARK: Pieces

    /// 竖排的条：和最忙那天比，有日程就至少露一截。
    private func fill(_ hours: Double, busiest: Double) -> CGFloat {
        guard hours > 0, busiest > 0 else { return 0 }
        return CGFloat(max(0.2, min(1, hours / busiest)))
    }

    private var note: some View {
        // 缺权限：小锁和「需要日历权限 · 去开启」，点按去开启。
        PermissionLockNote(permission: TilePermission.name(for: WidgetKind.week.rawValue) ?? "日历",
                           compact: context.position.isVertical, stacked: true,
                           preview: context.isPreview)
    }

    private var accent: Color { WeekEvents.accent }

    private func color(_ hex: String) -> Color {
        hex.isEmpty ? WeekEvents.accent : Color(hex: hex)
    }

    private func load() {
        guard !context.isPreview else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != access { WeekEvents.store.reset() }
        access = status
        guard status == .fullAccess else {
            entries = []
            return
        }
        entries = WeekEvents.read(WeekAgenda.interval(context.now), chosen: chosen)
    }
}

/// The store, the read and the samples both the tile and the panel use.
///
/// One store for the process, made the first time either draws, for the same
/// reason the Calendar widget keeps one: the views are rebuilt every tick, and
/// a store in `@State` would be a fresh connection to the calendar daemon each
/// second.
@MainActor
enum WeekEvents {
    static let store = EKEventStore()

    static var accent: Color {
        Color(hex: WidgetCatalog.accentHex(.week) ?? PaletteColor.orange.hex)
    }

    /// The calendars the account offers, for the panel's filter.
    static func calendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The week's events from the chosen calendars. An empty filter means all
    /// of them, and so does a filter whose calendars have all since gone: a
    /// predicate over no calendars matches nothing, which would read as an
    /// empty week.
    static func read(_ span: DateInterval, chosen: Set<String>) -> [WeekEntry] {
        let all = store.calendars(for: .event)
        let wanted = all.filter { chosen.contains($0.calendarIdentifier) }
        let scope = wanted.isEmpty ? all : wanted
        guard !scope.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: span.start, end: span.end, calendars: scope)
        return store.events(matching: predicate).compactMap(entry)
    }

    static func entry(_ event: EKEvent) -> WeekEntry? {
        guard let start = event.startDate else { return nil }
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let place = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return WeekEntry(
            // Recurring instances share an identifier; the start tells them apart.
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(start.timeIntervalSinceReferenceDate)",
            title: title.isEmpty ? tr("新日程") : title,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendar: event.calendar?.title ?? "",
            colorHex: hex(event.calendar?.color),
            location: MeetingLink.isOnlyLink(place) ? "" : place,
            link: MeetingLink.find(url: event.url, location: place, notes: event.notes))
    }

    static func hex(_ color: NSColor?) -> String {
        CalendarColorHex.hex(color)
    }

    /// A representative week for the library, which has no store behind it,
    /// anchored to the week being drawn so the ids hold still between ticks.
    static func samples(now: Date) -> [WeekEntry] {
        let calendar = WeekAgenda.calendar
        let monday = WeekAgenda.weekStart(now, calendar: calendar)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: monday) ?? monday
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        let work = PaletteColor.orange.hex
        let team = PaletteColor.blue.hex
        let home = PaletteColor.green.hex
        return [
            WeekEntry(id: "s1", title: tr("周会"), start: at(0, 10), end: at(0, 11), calendar: tr("工作"), colorHex: work),
            WeekEntry(id: "s2", title: tr("设计评审"), start: at(0, 14), end: at(0, 15), calendar: tr("工作"), colorHex: team),
            WeekEntry(id: "s3", title: tr("与小李一对一沟通"), start: at(1, 11), end: at(1, 11, 30),
                      calendar: tr("工作"), colorHex: work),
            WeekEntry(id: "s4", title: tr("产品发布会"), start: at(2, 9, 30), end: at(2, 11), calendar: tr("工作"), colorHex: team),
            WeekEntry(id: "s5", title: tr("客户电话"), start: at(2, 15), end: at(2, 15, 30), calendar: tr("工作"), colorHex: work),
            WeekEntry(id: "s6", title: tr("健身"), start: at(2, 19), end: at(2, 20), calendar: tr("个人"), colorHex: home),
            WeekEntry(id: "s7", title: tr("团队午餐"), start: at(2, 12), end: at(2, 13), calendar: tr("工作"), colorHex: team),
            WeekEntry(id: "s8", title: tr("季度复盘"), start: at(3, 14), end: at(3, 16), calendar: tr("工作"), colorHex: work),
            WeekEntry(id: "s9", title: tr("看牙医"), start: at(4, 16), end: at(4, 17), calendar: tr("个人"), colorHex: home),
            WeekEntry(id: "s10", title: tr("家庭聚餐"), start: at(5, 18), end: at(5, 20), calendar: tr("个人"), colorHex: home),
        ]
    }
}

/// 在日历里打开某一天（日视图），用户在那里直接新建。
///
/// 日历没有公开的“跳到某天”链接，只能问它本人：AppleScript 的 `view calendar at`。
/// 第一次会弹出自动化授权；被拒绝或出错时退回只打开日历。
@MainActor
enum CalendarOpener {
    static func show(_ day: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let date = parts.day else { return open() }
        let source = """
        set d to current date
        set day of d to 1
        set year of d to \(year)
        set month of d to \(month)
        set day of d to \(date)
        set time of d to 13 * hours
        tell application id "com.apple.iCal"
            activate
            switch view to day view
            view calendar at d
        end tell
        """
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { open() }
    }

    private static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
