import AppKit
import EventKit
import SwiftUI

/// 日历面板，日历和一周日程两种小组件共用（卡片各管各的，面板是这一套）。
///
/// 浏览：头上大日期和「10 月 · 今天 4 个日程」，一周条（每天下面圆点是日程数，点哪天看哪天），
/// 那天的时间轴（空档 30 分钟以上写「专注一下」，点了开专注计时），「接下来」，底下「写一句」。
/// 新建：标题、时间预设（30 分钟 / 1 小时 / 2 小时 / 全天）、日历、冲突提示，写回系统日历。
/// 点开日程：拖两端改时间，或删除，都写回系统日历；重复日程只动这一次。
///
/// 要完整的日历读写权限；没有时照旧只给「允许访问」或「打开系统设置」，不画编出来的日程。
/// 逻辑（空档、预设、冲突、拖动吸附、一句话解析）在 Core 的 `CalendarPlanner`、`CalendarSentence`。
struct CalendarPlannerPanel: View {
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext
    /// 卡片角上那一抹暖光，各小组件原来的颜色。
    var backdrop: Color

    /// 效果图的珊瑚红和实心按钮上的深字；颜色面板里选了颜色就用选的。
    static let coral = Color(hex: "#FF7A66")
    static let coralInk = Color(hex: "#330B05")
    private static let okGreen = Color(hex: "#5BD98A")
    private static let warnRed = Color(hex: "#FF6B5A")

    private var accent: Color { panelTint.accent(or: Self.coral) }
    private var ink: Color { panelTint.ink(or: Self.coralInk) }

    @State private var access = EKEventStore.authorizationStatus(for: .event)
    @State private var entries: [WeekEntry] = []
    @State private var sources: [PlannerCalendar] = []
    @State private var writable: [PlannerCalendar] = []
    /// 日历筛选，面板里改了先记在这（打开着的面板收不到配置写回）。nil 是读配置。
    @State private var picked: Set<String>?
    /// 一周条上选中的那天（零点）；nil 是今天。
    @State private var selected: Date?
    @State private var mode: Mode = .browse
    @State private var sentence = ""
    @State private var notice: String?

    // 新建
    @State private var draftTitle = ""
    @State private var draftStart = Date()
    @State private var draftSlot = CalendarPlanner.Slot(start: .now, end: .now)
    @State private var draftCalendar: String?
    @State private var showsTimePicker = false
    @FocusState private var titleFocused: Bool

    // 点开已有日程
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editAxis = 9...12
    @State private var editWritable = true
    @State private var editRecurring = false
    @State private var confirmDelete = false

    enum Mode: Equatable {
        case browse
        case new
        case edit(WeekEntry)
    }

    private var calendar: Calendar { WeekAgenda.calendar }
    private var config: WidgetConfig { instance.config }
    private var chosen: Set<String> { picked ?? Set(config.strings("calendars")) }
    private var showsAllDay: Bool { config.bool("allDay", default: true) }
    private var granted: Bool { context.isPreview || access == .fullAccess }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: backdrop)
        } content: {
            // 面板的 context 只在打开那一刻取一次，现在线和空档靠这个每分钟往前走。
            TimelineView(.everyMinute) { tick in
                let now = context.isPreview ? context.now : tick.date
                VStack(alignment: .leading, spacing: 14) {
                    switch mode {
                    case .browse: browse(now: now)
                    case .new: newForm(now: now)
                    case .edit(let entry): editor(entry, now: now)
                    }
                }
            }
        }
        .onAppear { load() }
        .onChange(of: instance.id) { _, _ in
            picked = nil
            selected = nil
            mode = .browse
            load()
        }
        .onChange(of: calendar.startOfDay(for: context.now)) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    // MARK: - 浏览

    private func shownDay(now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let selected, WeekAgenda.interval(now, calendar: calendar).contains(selected) else { return today }
        return selected
    }

    @ViewBuilder
    private func browse(now: Date) -> some View {
        let day = shownDay(now: now)
        let onDay = CalendarPlanner.entries(on: day, shown(now: now), includeAllDay: showsAllDay, calendar: calendar)
        header(day: day, count: onDay.count, now: now)
        if granted {
            weekStrip(now: now, day: day)
            allDayRow(onDay.filter(\.isAllDay), now: now)
            timeline(onDay.filter { !$0.isAllDay }, day: day, now: now)
            upcoming(now: now)
            sentenceField
            if let notice { noticeLine(notice) }
        } else {
            permission
        }
    }

    private func shown(now: Date) -> [WeekEntry] {
        context.isPreview ? WeekEvents.samples(now: now) : entries
    }

    private func header(day: Date, count: Int, now: Date) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(String(calendar.component(.day, from: day)))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayTitle(day))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(granted ? CalendarPlanner.headline(day: day, now: now, count: count, calendar: calendar)
                             : tr("\(calendar.component(.month, from: day)) 月"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if granted, !context.isPreview {
                if sources.count > 1 { picker }
                Button {
                    startNew(day: day, now: now)
                } label: {
                    Text(tr("＋ 新建"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekdayTitle(_ day: Date) -> String {
        let index = (calendar.component(.weekday, from: day) + 5) % 7
        return tr("周\(WeekAgenda.weekdayNames[index])")
    }

    /// 日历筛选：账户里挂了一堆订阅日历时，面板只看想看的。
    private var picker: some View {
        Menu {
            Button(tr("所有日历")) { apply([]) }
            Divider()
            ForEach(sources) { source in
                Toggle(source.title, isOn: Binding(
                    get: { chosen.isEmpty || chosen.contains(source.id) },
                    set: { _ in toggle(source) }))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("日历…"))
    }

    // MARK: 一周条

    private func weekStrip(now: Date, day: Date) -> some View {
        let days = WeekAgenda.days(shown(now: now), now: now, includeAllDay: showsAllDay, calendar: calendar)
        return HStack(spacing: 0) {
            ForEach(days) { item in
                let isSelected = item.date == day
                Button {
                    selected = item.date
                } label: {
                    VStack(spacing: 3) {
                        Text(WeekAgenda.weekdayNames[item.index])
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.62))
                        Text(String(calendar.component(.day, from: item.date)))
                            .font(.system(size: 15, weight: item.isToday ? .bold : .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(item.isToday ? accent : .white)
                        HStack(spacing: 2.6) {
                            ForEach(0..<CalendarPlanner.dots(item.count), id: \.self) { _ in
                                Circle().fill(.white.opacity(0.7)).frame(width: 4.4, height: 4.4)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(width: 38, height: 58)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.6)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("\(WeekAgenda.dayTitle(item)) \(item.count) 个日程"))
            }
        }
    }

    // MARK: 全天

    @ViewBuilder
    private func allDayRow(_ items: [WeekEntry], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        HStack(spacing: 8) {
                            Capsule().fill(color(item)).frame(width: 4, height: 16)
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 4)
                            Text(tr("全天"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color(item).opacity(0.22)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 时间轴

    private func timeline(_ timed: [WeekEntry], day: Date, now: Date) -> some View {
        let hours = CalendarPlanner.hourRange(timed, day: day, now: now, calendar: calendar)
        let span = hours.upperBound - hours.lowerBound
        // 9 到 18 点每小时 30pt；范围更大时压一点，最少 20pt，面板不至于太长。
        let hourHeight: CGFloat = span <= 10 ? 30 : max(20, 300 / CGFloat(span))
        let height = CGFloat(span) * hourHeight
        let spans = timed.map { CalendarSpan(id: $0.id, start: $0.start, end: $0.end) }
        let blocks = DayTimeline.blocks(spans, hours: hours, day: day, now: now, maxLanes: 2, calendar: calendar)
        let gaps = context.isPreview ? [] : CalendarPlanner.gaps(timed, day: day, hours: hours, now: now, calendar: calendar)
        let byID = Dictionary(timed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let axisX: CGFloat = 40

        return GeometryReader { geo in
            let width = geo.size.width - axisX
            ZStack(alignment: .topLeading) {
                ForEach(Array(hours), id: \.self) { hour in
                    let y = CGFloat(hour - hours.lowerBound) * hourHeight
                    Text(String(hour))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 30, alignment: .trailing)
                        .offset(y: y - 8)
                    Rectangle()
                        .fill(.white.opacity(0.10))
                        .frame(width: width, height: 0.5)
                        .offset(x: axisX, y: y)
                }

                ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                    let y0 = CGFloat(CalendarPlanner.offset(gap.start, hours: hours, day: day, calendar: calendar)) * hourHeight
                    let y1 = CGFloat(CalendarPlanner.offset(gap.end, hours: hours, day: day, calendar: calendar)) * hourHeight
                    gapBlock(gap, now: now, height: max(0, y1 - y0 - 6))
                        .frame(width: width - 2)
                        .offset(x: axisX + 2, y: y0 + 3)
                }

                ForEach(blocks, id: \.id) { block in
                    if let entry = byID[block.id] {
                        let laneWidth = (width - 2) / CGFloat(max(1, block.lanes))
                        let y0 = CGFloat(block.from) * height
                        let h = max(16, CGFloat(block.to - block.from) * height - 3)
                        eventBlock(entry, height: h, narrow: block.lanes > 1, past: block.isPast)
                            .frame(width: laneWidth - (block.lanes > 1 ? 2 : 0), height: h)
                            .offset(x: axisX + 2 + CGFloat(block.lane) * laneWidth, y: y0 + 1.5)
                    }
                }

                if let fraction = DayTimeline.nowFraction(now, hours: hours, day: day, calendar: calendar) {
                    let y = CGFloat(fraction) * height
                    Rectangle()
                        .fill(.white.opacity(0.95))
                        .frame(width: width + 2, height: 1.6)
                        .offset(x: axisX - 2, y: y - 0.8)
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .offset(x: axisX - 6, y: y - 4)
                }
            }
        }
        .frame(height: height + 8)
    }

    private func eventBlock(_ entry: WeekEntry, height: CGFloat, narrow: Bool, past: Bool) -> some View {
        let tint = color(entry)
        let detail = entry.location.isEmpty
            ? CalendarPlanner.rangeText(entry.start, entry.end, calendar: calendar)
            : "\(CalendarPlanner.rangeText(entry.start, entry.end, calendar: calendar)) · \(entry.location)"
        return Button { open(entry) } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.26))
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).frame(width: 4)
                Group {
                    if height >= 40 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Text(detail).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Spacer(minLength: 2)
                            if !narrow {
                                Text(CalendarPlanner.rangeText(entry.start, entry.end, calendar: calendar))
                                    .font(.system(size: 13, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .lineLimit(1)
                .padding(.leading, 12)
                .padding(.trailing, 8)
            }
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(past ? 0.5 : 1)
        .help(entry.title)
    }

    /// 空档：虚线框，够高时两行字加小熊猫和「专注一下」，矮的只留按钮。
    @ViewBuilder
    private func gapBlock(_ gap: DateInterval, now: Date, height: CGFloat) -> some View {
        let frame = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .leading) {
            frame.fill(.white.opacity(0.03))
            frame.strokeBorder(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            HStack(spacing: 6) {
                if height >= 44 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CalendarPlanner.gapTitle(gap))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(CalendarPlanner.rangeText(gap.start, gap.end, calendar: calendar))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if let image = PandaArt.image("pet-panda-rest") {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                    }
                    focusButton(gap, now: now, title: tr("专注一下"), height: 30)
                } else if height >= 22 {
                    Text(CalendarPlanner.gapTitle(gap))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    focusButton(gap, now: now, title: tr("专注一下"), height: max(20, min(26, height - 2)))
                } else {
                    Spacer(minLength: 0)
                    focusButton(gap, now: now, title: tr("专注一下"), height: 22)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
        .frame(height: height)
    }

    private func focusButton(_ gap: DateInterval, now: Date, title: String, height: CGFloat) -> some View {
        Button {
            startFocus(gap, now: now)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(Capsule().fill(accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("开始专注 \(CalendarPlanner.focusMinutes(gap, now: now, preferred: TimerStateProvider.shared.state.work)) 分钟"))
    }

    // MARK: 接下来

    @ViewBuilder
    private func upcoming(now: Date) -> some View {
        let items = CalendarPlanner.upcoming(shown(now: now).filter { showsAllDay || !$0.isAllDay },
                                             now: now, limit: 3, calendar: calendar)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("接下来"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                ForEach(items) { item in
                    Button { open(item.entry) } label: {
                        HStack(spacing: 10) {
                            Capsule().fill(color(item.entry)).frame(width: 4, height: 20)
                            Text(item.day)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.66))
                                .frame(minWidth: 34, alignment: .leading)
                            Text(item.entry.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 6)
                            Text(item.time)
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.86))
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 写一句

    private var sentenceField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: $sentence, prompt: Text(tr("写一句，如「明天下午 3 点开会」")))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .onSubmit { submitSentence() }
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glassPane(cornerRadius: 11)
    }

    private func noticeLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 新建

    @ViewBuilder
    private func newForm(now: Date) -> some View {
        formHeader(title: tr("新日程"))
        TextField("", text: $draftTitle, prompt: Text(tr("日程标题")))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .focused($titleFocused)
            .onSubmit { addDraft() }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.10)))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(accent.opacity(0.9), lineWidth: 1.2)
            }
            .onAppear { titleFocused = true }

        timeBox(now: now)
        calendarChips
        Button { addDraft() } label: {
            Text(tr("加到日历"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(writable.isEmpty)
        .opacity(writable.isEmpty ? 0.5 : 1)
        if writable.isEmpty {
            noticeLine(tr("没有能写的日历，请先在日历 App 里建一个。"))
        } else if let notice {
            noticeLine(notice)
        }
    }

    private func formHeader(title: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Text(tr("写回系统日历"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 8)
            Button {
                mode = .browse
                notice = nil
            } label: {
                Text(tr("取消"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func timeBox(now: Date) -> some View {
        let line = CalendarPlanner.conflictLine(draftSlot, in: entries, calendar: calendar)
        let current = CalendarPlanner.length(of: draftSlot)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                showsTimePicker.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text(tr("时间"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(CalendarPlanner.dayLabel(draftSlot.start, now: now, calendar: calendar))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(draftSlot.isAllDay ? tr("全天")
                                            : CalendarPlanner.rangeText(draftSlot.start, draftSlot.end, calendar: calendar))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Image(systemName: showsTimePicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("改开始时间"))

            if showsTimePicker {
                DatePicker("", selection: Binding(get: { draftStart }, set: { moveDraft(to: $0) }),
                           displayedComponents: pickerParts)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .font(.system(size: 13))
            }

            HStack(spacing: 6) {
                ForEach(CalendarPlanner.Length.allCases, id: \.self) { length in
                    let on = current == length
                    Button {
                        draftSlot = CalendarPlanner.slot(length, start: draftStart, calendar: calendar)
                    } label: {
                        Text(length.title)
                            .font(.system(size: 13, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? ink : .white)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Capsule().fill(on ? accent : .white.opacity(0.10)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Text(line.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(line.clash ? 0.9 : 0.62))
                    .lineLimit(1)
                Circle()
                    .fill(line.clash ? Self.warnRed : Self.okGreen)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(14)
        .glassPane(cornerRadius: 12)
    }

    private var pickerParts: DatePickerComponents {
        draftSlot.isAllDay ? .date : [.date, .hourAndMinute]
    }

    private var calendarChips: some View {
        HStack(spacing: 8) {
            Text(tr("日历"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(writable) { item in
                        let on = item.id == draftCalendar
                        Button {
                            draftCalendar = item.id
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(item.color).frame(width: 10, height: 10)
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(.white.opacity(on ? 0.16 : 0.07)))
                            .overlay { Capsule().strokeBorder(.white.opacity(on ? 0.6 : 0.14), lineWidth: on ? 0.9 : 0.6) }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - 点开已有日程

    @ViewBuilder
    private func editor(_ entry: WeekEntry, now: Date) -> some View {
        formHeader(title: tr("日程"))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(color(entry)).frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(entry.calendar.isEmpty ? CalendarPlanner.dayLabel(entry.start, now: now, calendar: calendar)
                                                : "\(entry.calendar) · \(CalendarPlanner.dayLabel(entry.start, now: now, calendar: calendar))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .lineLimit(1)
            }

            if entry.isAllDay {
                Text(tr("全天"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                if editWritable { dragAxis(entry) }
                HStack {
                    Text(CalendarPlanner.rangeText(editStart, editEnd, calendar: calendar))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Spacer(minLength: 6)
                    if editWritable {
                        Text(tr("拖两端改时间"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                if editWritable {
                    let line = CalendarPlanner.conflictLine(CalendarPlanner.Slot(start: editStart, end: editEnd),
                                                            in: entries, excluding: entry.id, calendar: calendar)
                    if line.clash {
                        HStack(spacing: 6) {
                            Text(line.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Circle().fill(Self.warnRed).frame(width: 7, height: 7)
                        }
                    }
                }
            }

            if editWritable {
                if editRecurring {
                    Text(tr("重复日程：只改这一次"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                HStack(spacing: 8) {
                    Button { deleteEntry(entry) } label: {
                        Text(confirmDelete ? tr("再点一次删除") : tr("删除"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Self.warnRed)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(Capsule().fill(.white.opacity(confirmDelete ? 0.18 : 0.12)))
                            .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if !entry.isAllDay {
                        Button { saveEntry(entry) } label: {
                            Text(tr("保存"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(Capsule().fill(accent))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(editStart == entry.start && editEnd == entry.end)
                        .opacity(editStart == entry.start && editEnd == entry.end ? 0.5 : 1)
                    }
                }
            } else {
                Text(tr("这个日历是只读的，改不了。"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            if let notice { noticeLine(notice) }
        }
        .padding(12)
        .glassPane(cornerRadius: 12)
    }

    /// 拖两端改时间的小时间轴：整点刻度，色条两头各一个白把手，按 15 分钟吸附。
    private func dragAxis(_ entry: WeekEntry) -> some View {
        let hours = editAxis
        let labels = DayTimeline.labelHours(hours, maxLabels: 4)
        return GeometryReader { geo in
            let inset: CGFloat = 12
            let width = geo.size.width - inset * 2
            let span = CGFloat(max(1, hours.upperBound - hours.lowerBound))
            let dayStart = calendar.startOfDay(for: entry.start)
            let x: (Date) -> CGFloat = { date in
                let hour = CGFloat(date.timeIntervalSince(dayStart) / 3_600) - CGFloat(hours.lowerBound)
                return inset + min(max(hour / span, 0), 1) * width
            }
            let date: (CGFloat) -> Date = { position in
                let fraction = min(max((position - inset) / width, 0), 1)
                return dayStart.addingTimeInterval((Double(hours.lowerBound) + Double(fraction * span)) * 3_600)
            }
            let x0 = x(editStart), x1 = x(editEnd)
            ZStack(alignment: .topLeading) {
                ForEach(labels, id: \.self) { hour in
                    let lx = inset + CGFloat(hour - hours.lowerBound) / span * width
                    Rectangle().fill(.white.opacity(0.15)).frame(width: 0.6, height: 22).offset(x: lx, y: 8)
                    Text("\(hour):00")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize()
                        .frame(width: 50)
                        .offset(x: lx - 25, y: 34)
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.85))
                    .frame(width: max(4, x1 - x0), height: 22)
                    .offset(x: x0, y: 8)
                handle
                    .offset(x: x0 - 3, y: 6)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("calendarEditAxis"))
                        .onChanged { value in
                            let moved = CalendarPlanner.drag(start: editStart, end: editEnd, edge: .start,
                                                             to: date(value.location.x), calendar: calendar)
                            editStart = moved.start
                        })
                handle
                    .offset(x: x1 - 3, y: 6)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("calendarEditAxis"))
                        .onChanged { value in
                            let moved = CalendarPlanner.drag(start: editStart, end: editEnd, edge: .end,
                                                             to: date(value.location.x), calendar: calendar)
                            editEnd = moved.end
                        })
            }
            .coordinateSpace(.named("calendarEditAxis"))
        }
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.white)
            .frame(width: 6, height: 26)
            // 把手只有 6pt 宽，点中的范围放大一圈。
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .padding(.horizontal, -6)
    }

    // MARK: - 没有权限

    private var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(permissionText)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            // 拒绝过以后再问也不会弹框，只能去系统设置里改。
            Button {
                guard !context.isPreview else { return }
                if access == .notDetermined { request() } else { openPrivacySettings() }
            } label: {
                Text(access == .notDetermined ? tr("允许访问") : tr("打开系统设置"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionText: String {
        switch access {
        case .notDetermined: tr("码头尚未获得访问你日历的权限。")
        case .writeOnly: tr("码头只能添加日程，读不到日历。请在系统设置里改成完整访问。")
        default: tr("码头的日历访问权限已关闭。")
        }
    }

    // MARK: - 动作

    private func startNew(day: Date, now: Date, title: String = "", slot: CalendarPlanner.Slot? = nil) {
        let start = slot?.start ?? CalendarPlanner.defaultStart(day: day, now: now, calendar: calendar)
        draftTitle = title
        draftSlot = slot ?? CalendarPlanner.slot(.half, start: start, calendar: calendar)
        draftStart = draftSlot.isAllDay ? CalendarPlanner.defaultStart(day: draftSlot.start, now: now, calendar: calendar)
                                        : draftSlot.start
        if draftCalendar == nil || !writable.contains(where: { $0.id == draftCalendar }) {
            let fallback = CalendarEventStore.defaultCalendarID
            draftCalendar = writable.first { $0.id == fallback }?.id ?? writable.first?.id
        }
        showsTimePicker = false
        notice = nil
        mode = .new
    }

    /// 改了开始时间：时长不变，全天的换到那一天。
    private func moveDraft(to start: Date) {
        if draftSlot.isAllDay {
            draftStart = start
            draftSlot = CalendarPlanner.slot(.allDay, start: start, calendar: calendar)
        } else {
            let length = draftSlot.end.timeIntervalSince(draftSlot.start)
            draftStart = start
            draftSlot = CalendarPlanner.Slot(start: start, end: start.addingTimeInterval(length))
        }
    }

    private func submitSentence() {
        guard !context.isPreview,
              let parsed = CalendarSentence.parse(sentence, now: .now, calendar: calendar) else { return }
        sentence = ""
        let now = Date()
        if parsed.understood {
            startNew(day: parsed.slot.start, now: now, title: parsed.title, slot: parsed.slot)
        } else {
            startNew(day: shownDay(now: now), now: now, title: parsed.title)
        }
    }

    private func addDraft() {
        guard !context.isPreview, !writable.isEmpty else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CalendarEventStore.add(title: title.isEmpty ? tr("新日程") : title, slot: draftSlot,
                                       calendarID: draftCalendar)
            let day = calendar.startOfDay(for: draftSlot.start)
            selected = day
            mode = .browse
            notice = tr("已加到日历：\(CalendarPlanner.dayLabel(draftSlot.start, now: .now, calendar: calendar))")
            load()
        } catch {
            notice = tr("没能写进日历，请稍后再试。")
        }
    }

    private func open(_ entry: WeekEntry) {
        guard !context.isPreview else { return }
        editStart = entry.start
        editEnd = entry.end
        editAxis = CalendarPlanner.editHours(start: entry.start, end: entry.end, calendar: calendar)
        editWritable = CalendarEventStore.canEdit(entry)
        editRecurring = CalendarEventStore.isRecurring(entry)
        confirmDelete = false
        notice = nil
        mode = .edit(entry)
    }

    private func saveEntry(_ entry: WeekEntry) {
        do {
            try CalendarEventStore.move(entry, start: editStart, end: editEnd)
            mode = .browse
            notice = nil
            load()
        } catch {
            notice = tr("没能写回日历，请稍后再试。")
        }
    }

    /// 删除要点两次，第一次按钮变成「再点一次删除」。
    private func deleteEntry(_ entry: WeekEntry) {
        guard confirmDelete else {
            confirmDelete = true
            return
        }
        do {
            try CalendarEventStore.delete(entry)
            mode = .browse
            notice = nil
            load()
        } catch {
            notice = tr("没能删除，请稍后再试。")
        }
    }

    /// 空档上「专注一下」：有专注计时卡片就按空档长度开一轮专注并打开它的面板；
    /// 已经在计时就只打开面板；没放卡片就提示并打开小组件库去添加。
    private func startFocus(_ gap: DateInterval, now: Date) {
        guard !context.isPreview else { return }
        guard let timer = TimedAlertDriver.shared.widgets().first(where: { $0.kind == .timer }) else {
            notice = tr("还没放专注计时卡片，先添加一个再来专注。")
            LibraryWindow.shared.openFromEmptyState()
            return
        }
        var state = TimerStateProvider.shared.state
        if state.deadline == nil {
            let minutes = CalendarPlanner.focusMinutes(gap, now: now, preferred: state.work)
            state.phase = .focus
            state.duration = Double(minutes * 60)
            state.deadline = Date().addingTimeInterval(Double(minutes * 60))
            state.paused = nil
            TimerStateProvider.shared.state = state
        }
        WidgetPanelOpener.shared.open(timer.id)
    }

    // MARK: - 读取

    private func load() {
        guard !context.isPreview else { return }
        access = EKEventStore.authorizationStatus(for: .event)
        guard access == .fullAccess, CalendarEventStore.hasAccess else {
            entries = []
            sources = []
            writable = []
            return
        }
        let now = Date()
        let week = WeekAgenda.interval(now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        // 这一周，再加两周给「接下来」。
        let ahead = calendar.date(byAdding: .day, value: 15, to: today) ?? week.end
        let span = DateInterval(start: week.start, end: max(week.end, ahead))
        entries = CalendarEventStore.entries(in: span, chosen: chosen)
        let all = CalendarEventStore.calendars()
        sources = all.map(PlannerCalendar.init)
        writable = all.filter(\.allowsContentModifications).map(PlannerCalendar.init)
    }

    private func request() {
        Task { @MainActor in
            // 请求用新建的 store：共享的那个属于主线程，异步调用不能把它带过去。
            _ = try? await EKEventStore().requestFullAccessToEvents()
            CalendarEventStore.shared.reset()
            load()
        }
    }

    private func openPrivacySettings() {
        guard let url = WidgetTarget.settings("com.apple.preference.security?Privacy_Calendars").settingsURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 筛选

    private func toggle(_ source: PlannerCalendar) {
        var wanted = chosen.isEmpty ? Set(sources.map(\.id)) : chosen
        if wanted.contains(source.id) { wanted.remove(source.id) } else { wanted.insert(source.id) }
        apply(wanted.count == sources.count ? [] : sources.map(\.id).filter(wanted.contains))
    }

    private func apply(_ identifiers: [String]) {
        guard !context.isPreview else { return }
        picked = Set(identifiers)
        WidgetWriter.write(instance) { config in
            config.set("calendars", .list(identifiers.map(WidgetConfig.Value.string)))
        }
        load()
    }

    private func color(_ entry: WeekEntry) -> Color {
        entry.colorHex.isEmpty ? accent : Color(hex: entry.colorHex)
    }
}

/// 账户里的一个日历：筛选菜单和新建时的日历选择用。
private struct PlannerCalendar: Identifiable, Hashable {
    var id: String
    var title: String
    var color: Color

    init(_ calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        let hex = CalendarColorHex.hex(calendar.color)
        color = Color(hex: hex.isEmpty ? "#FF7A66" : hex)
    }
}
