import AppKit
import EventKit
import SwiftUI

/// This week at a glance: seven day columns, Monday first, each with a bar
/// per event in its calendar's colour and today picked out.
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
        .accessibilityLabel(tr("一周日程，本周 \(WeekAgenda.total(week)) 个日程"))
    }

    // MARK: Wide

    private func wide(_ days: [WeekDay]) -> some View {
        HStack(spacing: 2) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    Text(WeekAgenda.weekdayNames[day.index])
                        .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? accent : WidgetStyle.secondary)
                    Text("\(WeekAgenda.calendar.component(.day, from: day.date))")
                        .font(WidgetStyle.title)
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    bars(day)
                        .frame(height: 15, alignment: .top)
                }
                .lineLimit(1)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.18))
                    }
                }
            }
        }
    }

    /// One bar per event, up to three, the third turning into "+n".
    private func bars(_ day: WeekDay) -> some View {
        let marks = WeekAgenda.bars(day)
        return VStack(spacing: 2) {
            ForEach(Array(marks.colors.enumerated()), id: \.offset) { _, hex in
                Capsule()
                    .fill(color(hex))
                    .frame(width: 14, height: 3)
            }
            if marks.more > 0 {
                Text("+\(marks.more)")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .frame(height: 5)
            }
        }
    }

    // MARK: Column

    /// 56pt across: a row per day, the weekday, a bar as long as the day is
    /// busy against the busiest day, and the count.
    private func column(_ days: [WeekDay]) -> some View {
        let busiest = days.map(\.count).max() ?? 0
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
                                .frame(width: proxy.size.width * WeekAgenda.fill(count: day.count, busiest: busiest))
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
        return WeekEntry(
            // Recurring instances share an identifier; the start tells them apart.
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(start.timeIntervalSinceReferenceDate)",
            title: title.isEmpty ? tr("新日程") : title,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendar: event.calendar?.title ?? "",
            colorHex: hex(event.calendar?.color))
    }

    static func hex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return "" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent),
                      byte(rgb.blueComponent))
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
