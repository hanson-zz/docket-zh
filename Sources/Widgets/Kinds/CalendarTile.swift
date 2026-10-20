import AppKit
import EventKit
import SwiftUI

/// Today's date and what is next on it. The whole day belongs to the panel.
///
/// Reads EventKit exactly the way `CalendarDetail` does - one single-day fetch
/// on the main actor, every `EKEvent` flattened into a value type the moment
/// the fetch returns - with one difference that matters: it never asks for
/// access. The shelf draws every tile it has the instant it appears, so a tile
/// that requested consent would raise a prompt nobody clicked for, from a
/// process that never becomes frontmost. The panel owns the request; until the
/// answer changes, the tile says which of the two states it is in.
struct CalendarTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var access = EKEventStore.authorizationStatus(for: .event)
    @State private var events: [TileEvent] = []
    /// 时间线上指针下面是第几块，没有指着时是 nil。
    @State private var pointed: Int?
    @Environment(\.widgetHovered) private var tileHovered
    /// 颜色面板里选的主题色（`WidgetTintStyle`），选过颜色时日期块的橙跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 存的旧值 agenda 也当成今日时间线，见 `CalendarDay.layout`。
    private var layout: String { CalendarDay.layout(instance.config) }

    private var showsAllDay: Bool { instance.config.bool("allDay", default: true) }

    /// Identifiers the widget was told to show. Empty means all of them, which
    /// is what the catalog default stores and what the panel's filter writes.
    private var chosen: Set<String> { Set(instance.config.strings("calendars")) }

    /// Only full access can read a day; write-only is no better than none here.
    private var hasAccess: Bool { context.isPreview || access == .fullAccess }

    /// 日期样式也画当天会议的小点，所以每个样式都要读日历。
    private var needsEvents: Bool { true }

    /// 小组件库里固定在早上 10:05，和设计稿一样：倒计时、时间线和变暗的过去都有东西可看。
    private var now: Date {
        guard context.isPreview else { return context.now }
        return Calendar.current.date(bySettingHour: 10, minute: 5, second: 0, of: context.now) ?? context.now
    }

    /// Midnight of the day being drawn. Derived from the tick, so the tile
    /// turns the page rather than holding yesterday open.
    private var day: Date { Calendar.current.startOfDay(for: context.now) }

    var body: some View {
        WidgetSurface {
            Group {
                if context.position.isVertical { column } else { wide }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { load() }
        .onChange(of: instance.config.strings("calendars")) { _, _ in load() }
        // `now` ticks every second; a day out of the local cache is cheap but
        // not free. Five minutes is coarse enough to be invisible and still
        // lands on midnight, which is when the page has to turn - and it is
        // also what picks up access granted from the panel (the store is
        // shared now, see `CalendarEventStore`, but the tile still has to
        // read again to show it).
        .onChange(of: Int(context.now.timeIntervalSince1970) / 300) { _, _ in load() }
        // An event added or moved in Calendar while the shelf is up.
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    // MARK: Wide layouts

    @ViewBuilder
    private var wide: some View {
        switch layout {
        case "date":
            dateBlock(weekday: 12, day: 28, dots: true)
        case "dateAndEvent":
            HStack(spacing: 12) {
                dateBlock(weekday: 10, day: 24, dots: true)
                nextEvent
            }
        case CalendarDay.timelineLayout:
            timeline
        default:
            nextEvent
        }
    }

    // MARK: 下一个日程

    /// 还有多久、会议名、时间和地点，有会议链接就有「加入」，底下一行是之后那个。
    @ViewBuilder
    private var nextEvent: some View {
        let queue = upcomingTimed
        if let event = queue.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    dot(accent, size: 6)
                    Text(CalendarDay.countdown(start: event.start, end: event.end, now: now))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Spacer(minLength: 2)
                    Text(CalendarDay.clock(event.start))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                }
                Text(event.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .padding(.top, 1)
                Text(event.whereLine)
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
                Spacer(minLength: 2)
                if let link = event.link {
                    joinButton(link)
                }
                if let after = queue.dropFirst().first {
                    Rectangle()
                        .fill(WidgetStyle.primary.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.top, 2)
                    Text(tr("之后 \(CalendarDay.clock(after.start)) \(after.title)"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                }
            }
            // Truncated rather than wrapped: a second line would not fit the
            // card, and half a clipped title is worse than an honest ellipsis.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let allDay = upcoming.first {
            // 今天只剩全天日程：和原来一样一行标题一行说明。
            HStack(alignment: .top, spacing: 8) {
                dot(allDay.color, size: 7).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(allDay.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                    Text(allDay.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetStyle.secondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        } else {
            note(stateLine)
        }
    }

    /// 绿色的「加入腾讯会议」。只占按钮自己那块，卡片别处照旧点开面板。
    private func joinButton(_ link: MeetingLink) -> some View {
        Button {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(link.provider.joinTitle)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(Capsule().fill(joinGreen))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(link.provider.joinTitle)
    }

    // MARK: 今日时间线

    /// 今天的定时日程按时长画在一根轴上：9 点到 19 点（日程更早更晚就往外扩），
    /// 过去的变暗，红线是现在。指着一块，那块描白边，旁边浮出它的详情（标题、时间、
    /// 地点、日历颜色和「加入会议」，见 `EventPeekWindow`）；有会议链接的那块点一下就加入。
    @ViewBuilder
    private var timeline: some View {
        let spans = timedEvents.map(\.span)
        if !hasAccess {
            note(stateLine)
        } else {
            let hours = DayTimeline.hourRange(spans, day: day)
            let blocks = DayTimeline.blocks(spans, hours: hours, day: day, now: now)
            let left = CalendarDay.remaining(spans, now: now)
            VStack(alignment: .leading, spacing: 3) {
                timelineHeader(remaining: left)
                GeometryReader { proxy in
                    timelineBand(blocks, hours: hours, size: proxy.size)
                }
                .frame(height: 15)
                GeometryReader { proxy in
                    timelineTicks(hours, width: proxy.size.width)
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 整块（标题、轴、刻度）都跟着指针：横向对上哪一块就浮出哪一块，
            // 不必正好指在 15pt 高的轴上。不拦点击，块上的「加入」和卡片的点击照旧。
            .overlay {
                if !context.isPreview {
                    PointerPeekTracker { fraction, rect in
                        let index = fraction.flatMap { DayTimeline.block(at: Double($0.x), in: blocks) }
                        if index != pointed { pointed = index }
                        peek(index.map { blocks[$0] }, rect: rect)
                    }
                }
            }
            .onChange(of: tileHovered) { _, hovered in
                if !hovered { EventPeekWindow.shared.leave(owner: instance.id) }
            }
            .onDisappear { EventPeekWindow.shared.dismiss(owner: instance.id) }
        }
    }

    /// 指着的那一块浮出详情；没指着时等一会儿收起。
    private func peek(_ block: TimelineBlock?, rect: CGRect) {
        guard let block, let item = event(id: block.id), rect.width > 0 else {
            EventPeekWindow.shared.leave(owner: instance.id)
            return
        }
        let focus = rect.minX + CGFloat((block.from + block.to) / 2) * rect.width
        EventPeekWindow.shared.show(EventPeek(items: [item.peekItem]), key: "\(instance.id)#\(block.id)",
                                    owner: instance.id, accent: accent, tile: rect, focusX: focus,
                                    edge: context.position)
    }

    private func timelineHeader(remaining: [CalendarSpan]) -> some View {
        HStack(spacing: 6) {
            Text(remaining.isEmpty
                 ? (timedEvents.isEmpty ? tr("今天没有日程") : tr("今天的日程都结束了"))
                 : tr("今天还剩 \(remaining.count) 个"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
            Spacer(minLength: 4)
            if let next = remaining.first {
                Text(CalendarDay.nextLine(start: next.start, now: now))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func timelineBand(_ blocks: [TimelineBlock], hours: ClosedRange<Int>, size: CGSize) -> some View {
        let width = size.width, height = size.height
        let nowX = DayTimeline.nowFraction(now, hours: hours, day: day).map { CGFloat($0) * width }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WidgetStyle.primary.opacity(0.07))
                .frame(width: width, height: height)
            // 过去的部分压暗。
            if let nowX, nowX > 0 {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .frame(width: nowX, height: height)
            }
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                let x = CGFloat(block.from) * width
                let w = max(3, CGFloat(block.to - block.from) * width - 1)
                let laneHeight = (height - CGFloat(block.lanes - 1)) / CGFloat(block.lanes)
                let y = CGFloat(block.lane) * (laneHeight + 1)
                let item = event(id: block.id)
                let color = item?.color ?? accent
                let lit = tileHovered && pointed == index && !context.isPreview
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(block.isPast ? 0.35 : (lit ? 1 : 0.88)))
                    if let item, w > 26, block.lanes == 1 {
                        Text(item.title)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.black.opacity(block.isPast ? 0.5 : 0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 3)
                    }
                }
                .frame(width: w, height: laneHeight)
                .overlay {
                    if lit {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                    }
                }
                .offset(x: x, y: y)
            }
            if let nowX {
                Rectangle()
                    .fill(nowRed)
                    .frame(width: 1.5, height: height + 4)
                    .offset(x: nowX - 0.75, y: -2)
                Circle()
                    .fill(nowRed)
                    .frame(width: 5, height: 5)
                    .offset(x: nowX - 2.5, y: -4)
            }
            // 有会议链接、还没开完的那块可以点一下加入；别的地方交给卡片自己的点击开面板。
            if !context.isPreview {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { _, block in
                    if let item = event(id: block.id), let link = item.link, !block.isPast {
                        let x = CGFloat(block.from) * width
                        let w = max(6, CGFloat(block.to - block.from) * width)
                        Button {
                            NSWorkspace.shared.open(link.url)
                        } label: {
                            Color.clear
                                .frame(width: w, height: height)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .offset(x: x)
                        .accessibilityLabel(tr("\(link.provider.joinTitle)：\(item.title)"))
                    }
                }
                }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func timelineTicks(_ hours: ClosedRange<Int>, width: CGFloat) -> some View {
        let span = CGFloat(max(1, hours.upperBound - hours.lowerBound))
        let labels = DayTimeline.labelHours(hours)
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.self) { hour in
                let x = CGFloat(hour - hours.lowerBound) / span * width
                let text = String(format: "%d:00", hour)
                // 两头的字往里收，不出卡片。
                let w: CGFloat = 30
                let left = min(max(0, x - (hour == hours.lowerBound ? 0 : w / 2)), width - w)
                Text(verbatim: text)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
                    .frame(width: w, alignment: hour == hours.lowerBound ? .leading : .center)
                    .offset(x: left)
            }
        }
        .frame(width: width, height: 10, alignment: .topLeading)
    }

    // MARK: Column layouts
    //
    // 56pt of usable width and 76pt of height. 今日时间线在竖排里画不开：一根
    // 56pt 的轴上十个小时，每块只剩一两个点宽，所以它和「日期 + 下一个日程」
    // 一样退成日期加下一个日程。The rest of the day is one click away in the panel.

    @ViewBuilder
    private var column: some View {
        switch layout {
        case "date":
            dateBlock(weekday: 11, day: 27, dots: true)
        case "nextEvent":
            columnEvent
        default:
            VStack(spacing: 4) {
                dateBlock(weekday: 9, day: 20)
                columnEvent
            }
        }
    }

    /// Time first and biggest: with no room for a calendar name, the clock is
    /// the only part of a row that is useful at a glance.
    @ViewBuilder
    private var columnEvent: some View {
        if let event = upcoming.first {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    dot(event.color, size: 5)
                    Text(event.timeText)
                        .font(WidgetStyle.value(14))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                }
                Text(event.title)
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(layout == "nextEvent" ? 2 : 1)
                    .multilineTextAlignment(.center)
            }
            .minimumScaleFactor(0.6)
        } else if !hasAccess {
            PermissionLockNote(permission: Self.permission, compact: true, stacked: true,
                               preview: context.isPreview)
        } else {
            Text(shortStateLine)
                .font(WidgetStyle.caption(9))
                .foregroundStyle(WidgetStyle.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Pieces

    /// Weekday over the day number, the calendar page every Dock has had since
    /// there were Docks. Sized to its content so the agenda beside it keeps
    /// every point it is not using. `dots` 时下面一排小点，一个点一个会，开完的变淡。
    private func dateBlock(weekday: CGFloat, day: CGFloat, dots: Bool = false) -> some View {
        VStack(spacing: 0) {
            // Grey, not the calendar's red: colour on the shelf is kept to
            // small marks, and the dots beside each event already carry it.
            Text(context.now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(WidgetStyle.label(weekday))
                .foregroundStyle(WidgetStyle.secondary)
            Text(context.now.formatted(.dateTime.day()))
                .font(WidgetStyle.value(day))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
            if dots, hasAccess {
                let marks = CalendarDay.dots(timedEvents.map(\.span), now: now)
                if !marks.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(marks, id: \.id) { mark in
                            dot(event(id: mark.id)?.color ?? accent, size: 5)
                                .opacity(mark.past ? 0.35 : 1)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize()
    }

    /// The calendar's own colour, the one thing that says which calendar a row
    /// came from when there is no room to name it.
    private func dot(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

    @ViewBuilder
    private func note(_ text: String) -> some View {
        if !hasAccess {
            // 缺权限：小锁和「需要日历权限 · 去开启」，点按去开启。
            PermissionLockNote(permission: Self.permission, preview: context.isPreview)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            plainNote(text)
        }
    }

    /// 日历权限的名字，和新手引导、小组件库里写的一样。
    static let permission = TilePermission.name(for: WidgetKind.calendar.rawValue) ?? "日历"

    private func plainNote(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: hasAccess ? "calendar" : "calendar.badge.exclamationmark")
                .font(.system(size: 14))
                .foregroundStyle(WidgetStyle.secondary)
            Text(text)
                .font(WidgetStyle.caption(12))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: What the tile has to say

    /// The shortest honest version of what the panel says at length. Never a
    /// truncation of it, and never a plausible empty day standing in for a day
    /// the tile was not allowed to read.
    private var stateLine: String {
        guard hasAccess else {
            return access == .notDetermined ? tr("未获得日历访问权限") : tr("日历访问权限已关闭")
        }
        return dayEvents.isEmpty ? tr("没有日程") : tr("今天没有剩余日程")
    }

    /// The same four states in the width a column has for them.
    private var shortStateLine: String {
        guard hasAccess else {
            return access == .notDetermined ? tr("尚无权限") : tr("权限已关闭")
        }
        return dayEvents.isEmpty ? tr("没有日程") : tr("没有剩余日程")
    }

    // MARK: Data

    /// Everything on today that this widget was configured to count.
    private var dayEvents: [TileEvent] {
        // The library has no store behind it and must not reach for one.
        let all = context.isPreview ? TileEvent.samples(on: day) : events
        return showsAllDay ? all : all.filter { !$0.isAllDay }
    }

    private var upcoming: [TileEvent] {
        let ahead = dayEvents.filter { $0.end > now }
        // Timed first, all-day after, which is the order the panel lists them
        // in: an entry with no time does not belong in a queue sorted by time.
        return ahead.filter { !$0.isAllDay } + ahead.filter(\.isAllDay)
    }

    /// 还没结束的定时日程，下一个日程和「之后」从这里取。
    private var upcomingTimed: [TileEvent] { upcoming.filter { !$0.isAllDay } }

    /// 今天全部定时日程，时间线和日期小点用。
    private var timedEvents: [TileEvent] {
        (context.isPreview ? TileEvent.samples(on: day) : events).filter { !$0.isAllDay }
    }

    private func event(id: String) -> TileEvent? {
        timedEvents.first { $0.id == id }
    }

    /// 日期块的橙：选过颜色就换成选的。
    private var accent: Color { theme.chosen(or: Color(hex: "#FF9F45"), dark: scheme == .dark) }
    private var joinGreen: Color { Color(hex: "#6FDC9A") }
    private var nowRed: Color { Color(hex: "#FF5A5F") }

    /// Reads the day straight through on the main actor, as the panel does:
    /// EventKit answers a single day out of its local cache, and carrying
    /// `EKEvent`s - neither `Sendable` nor safe to hold - across an isolation
    /// boundary would buy nothing.
    private func load() {
        guard !context.isPreview, needsEvents else { return }

        let status = EKEventStore.authorizationStatus(for: .event)
        // A store built before the grant keeps answering as if it had none
        // until it is told to look again.
        if status != access { CalendarEventStore.shared.reset() }
        access = status
        guard status == .fullAccess else {
            events = []
            return
        }

        let store = CalendarEventStore.shared
        let all = store.calendars(for: .event)
        let wanted = all.filter { chosen.contains($0.calendarIdentifier) }
        // A predicate over no calendars matches nothing, so a filter whose
        // identifiers have all since disappeared falls back to the whole
        // account rather than to an empty day.
        let scope = wanted.isEmpty ? all : wanted
        guard !scope.isEmpty,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: day, end: end, calendars: scope)
        events = store.events(matching: predicate)
            .compactMap(TileEvent.init)
            .sorted { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
    }
}

/// The widget's accent, for the date block and for an event whose calendar has
/// no colour of its own.

/// The dot an event gets when its calendar has no colour of its own.
private let calendarAccent = Color(hex: WidgetCatalog.accentHex(.calendar) ?? PaletteColor.orange.hex)

/// One entry, flattened off its `EKEvent` when the day is read.
///
/// The tile keeps these instead of the events themselves: an `EKEvent` is a
/// live object the store may mutate or invalidate underneath the shelf, and
/// Apple's own advice is to re-fetch rather than hold one.
private struct TileEvent: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendar: String
    /// 日历的颜色 `#RRGGBB`，空时用小组件的强调色。
    var colorHex: String
    /// 地点；只是一条会议链接时为空，链接放进 `link`。
    var location: String
    var link: MeetingLink?

    init(id: String, title: String, start: Date, end: Date,
         isAllDay: Bool = false, calendar: String, colorHex: String,
         location: String = "", link: MeetingLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.colorHex = colorHex
        self.location = location
        self.link = link
    }

    /// The calendar's own colour, which is the only thing that makes a dot
    /// mean anything. Falls back to the widget's accent rather than to a
    /// colour no calendar actually uses.
    var color: Color { colorHex.isEmpty ? calendarAccent : Color(hex: colorHex) }

    /// 悬停浮出卡片上的这一条。
    var peekItem: EventPeekItem {
        EventPeekItem(id: id, title: title, start: start, end: end, isAllDay: isAllDay,
                      calendar: calendar, colorHex: colorHex, location: location, link: link)
    }

    init?(_ event: EKEvent) {
        guard let start = event.startDate else { return nil }
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let place = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            // Recurring instances share one identifier, so the start has to be
            // part of it or two occurrences on one day collide in the list.
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(start.timeIntervalSinceReferenceDate)",
            // An untitled event is a real event; the calendar apps call it this.
            title: title.isEmpty ? tr("新日程") : title,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendar: event.calendar?.title ?? "",
            colorHex: CalendarColorHex.hex(event.calendar?.color),
            location: MeetingLink.isOnlyLink(place) ? "" : place,
            link: MeetingLink.find(url: event.url, location: place, notes: event.notes))
    }

    var span: CalendarSpan { CalendarSpan(id: id, start: start, end: end, isAllDay: isAllDay) }

    /// Where the clock goes for something that has no clock.
    var timeText: String {
        isAllDay ? tr("全天") : start.formatted(date: .omitted, time: .shortened)
    }

    /// The panel's second line, and a calendar with no name does not earn a
    /// separator to itself.
    var detail: String {
        calendar.isEmpty ? timeText : "\(timeText) · \(calendar)"
    }

    /// 「10:30-11:15 · 3 号会议室」；没有地点时写会议来源或日历名。
    var whereLine: String {
        let range = CalendarDay.range(start, end)
        let place = location.isEmpty ? (link?.provider.title ?? calendar) : location
        return place.isEmpty ? range : "\(range) · \(place)"
    }

    /// A representative day for the widget library, which has no store behind
    /// it. Anchored to the date being drawn so the ids hold still between
    /// ticks rather than churning the list once a second. 小组件库里的“现在”是 10:05。
    static func samples(on day: Date) -> [TileEvent] {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let tencent = URL(string: "https://meeting.tencent.com/dm/sample").map { MeetingLink(url: $0, provider: .tencent) }
        let feishu = URL(string: "https://vc.feishu.cn/j/sample").map { MeetingLink(url: $0, provider: .feishu) }
        return [
            TileEvent(id: "sample-standup", title: tr("站会"),
                      start: at(9, 0), end: at(9, 30),
                      calendar: tr("工作"), colorHex: "#3E7A5E"),
            TileEvent(id: "sample-weekly", title: tr("产品周会"),
                      start: at(10, 30), end: at(11, 15),
                      calendar: tr("工作"), colorHex: "#FF9F45",
                      location: tr("3 号会议室"), link: tencent),
            TileEvent(id: "sample-review", title: tr("设计评审"),
                      start: at(14, 0), end: at(15, 0),
                      calendar: tr("工作"), colorHex: "#FF7AA8", link: feishu),
            TileEvent(id: "sample-one", title: "1:1",
                      start: at(16, 30), end: at(17, 15),
                      calendar: tr("工作"), colorHex: "#B48CFF"),
        ]
    }
}
