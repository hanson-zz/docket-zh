import SwiftUI

/// 点开农历与假期，两个状态：
///
/// - 浏览：今天的公历和农历，下面分页（顶部分段，记住切到的那页）：近期节日节气
///   （节气、传统节日、法定假日、调休上班），带日期和倒数；生日与纪念日，按农历
///   每年换算成公历，近的在前，写还有几天；宜忌（建除十二值日，可关，关掉就没有
///   这一页）；本月月历，看休、班和节气。
/// - 添加 / 编辑：名字、种类、闰月、农历月日两个滚轮，下面马上算出今年和明年落在
///   哪天（小月没有三十按廿九、没有那个闰月按普通月，都写出来）；提前几天、几点提醒；
///   卡片上显示宜忌、节气、调休补班三个开关。
///
/// 放假和调休只来自 `HolidaySchedule`；生日换算和提醒见 `LunarEvents`，宜忌见
/// `LunarAlmanac`，近期列表见 `LunarCard.agenda`。全部免费。
struct LunarDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    struct Draft: Equatable {
        var id: String
        var name: String
        var kind: LunarEvent.Kind
        var month: Int
        var day: Int
        var leap: Bool
        var lead: Int
        var minute: Int
        var isNew: Bool
    }

    @State private var draft: Draft?
    @State private var confirmDelete = false
    @State private var showAllEvents = false
    /// 浏览态记住的分页，见 `BrowsePage`。
    @AppStorage(DetailPanelSections.pageKey(.lunar)) private var storedPage = ""
    @FocusState private var nameFocused: Bool

    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Self.coral) }
    private var accentInk: Color { panelTint.ink(or: Self.coralInk) }

    static let coral = Color(hex: "#FF8A6B")
    static let coralInk = Color(hex: "#330D04")
    private static let green = Color(hex: "#5BD98A")
    private static let warn = Color(hex: "#FFB86B")
    /// 浏览时生日列表先露这么多条，多的点「展开」。面板统一限高后从 5 条改成
    /// 3 条，让“纪念日”这一页默认不用滚动。
    private static let visibleEvents = 3

    private var holidays: HolidayService { HolidayService.shared }
    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { current.config }
    private var showTerm: Bool { config.bool("showTerm", default: true) }
    private var showAlmanac: Bool { config.bool(LunarPanel.almanacKey, default: true) }
    private var workAlert: Bool { config.bool("workAlert", default: true) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let draft {
                    editor(draft)
                } else {
                    browse(context.now)
                }
            }
        }
        .onAppear { if !context.isPreview { holidays.refresh() } }
    }

    // MARK: - 浏览

    @ViewBuilder
    private func browse(_ now: Date) -> some View {
        let events = shownEvents
        let data = LunarPanelCache.read(now: now, config: config, events: events, known: holidays.known,
                                        breaks: { holidays.breaks(now: now) })
        browseHeader(now, events: events)
        // 面板统一限高后，日期下面分页：近期节日节气、生日与纪念日、宜忌（可关）、
        // 本月月历。切到的那页记住。
        let pages = browsePages
        if let page = DetailPanelSections.page(stored: storedPage, available: pages) {
            DetailSegmented(pages: pages, title: { $0.title }, selected: page) { picked in
                storedPage = picked.rawValue
            }
            switch page {
            case .agenda:
                agenda(data.agenda)
                if workAlert { workAlertNote }
            case .events: birthdays(data.rows)
            case .almanac: almanac(now)
            case .month: monthGrid(now)
            }
        }
        Text(HolidayService.attribution)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 浏览态日期下面的分页。
    private enum BrowsePage: String, CaseIterable {
        case agenda, events, almanac, month

        var title: String {
            switch self {
            case .agenda: tr("近期")
            case .events: tr("纪念日")
            case .almanac: tr("宜忌")
            case .month: tr("月历")
            }
        }
    }

    /// 关掉宜忌时没有那一页。
    private var browsePages: [BrowsePage] {
        BrowsePage.allCases.filter { $0 != .almanac || showAlmanac }
    }

    /// 小组件库里没记生日时放效果图上那三条做样子。
    private var shownEvents: [LunarEvent] {
        let stored = LunarEvents.events(config)
        guard context.isPreview, stored.isEmpty else { return stored }
        return [LunarEvent(id: "p1", name: tr("妈妈生日"), month: 10, day: 8),
                LunarEvent(id: "p2", name: tr("外婆生日"), month: 11, day: 23),
                LunarEvent(id: "p3", name: tr("结婚纪念日"), kind: .anniversary, month: 12, day: 18)]
    }

    private func browseHeader(_ now: Date, events: [LunarEvent]) -> some View {
        let lunar = ChineseCalendar.lunar(now)
        let full = events.count >= LunarEvents.limit
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLine(now))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(tr("农历\(lunar.short) · \(lunar.ganzhiYear)\(lunar.zodiac)年"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !context.isPreview {
                Button { beginNew(now) } label: {
                    Text(tr("添加"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(full)
                .opacity(full ? 0.45 : 1)
                .help(full ? tr("最多记 \(LunarEvents.limit) 条，删掉一条再加") : tr("按农历记一个生日或纪念日"))
            }
        }
    }

    // MARK: 宜忌

    private func almanac(_ now: Date) -> some View {
        let good = LunarAlmanac.good(now).map(trKey)
        let bad = LunarAlmanac.bad(now).map(trKey)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                almanacMark(tr("宜"), filled: true)
                Text(good.joined(separator: "  "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 4)
                Text(tr("\(LunarAlmanac.dayGanzhi(now))日 · \(trKey(LunarAlmanac.officerName(now)))"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
            HStack(spacing: 10) {
                almanacMark(tr("忌"), filled: false)
                Text(bad.joined(separator: "  "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.6)
                }
        }
        .help(tr("按建除十二值日简化排出的宜忌，仅供参考"))
        .accessibilityElement(children: .combine)
    }

    private func almanacMark(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? accentInk : .white)
            .frame(width: 26, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? accent : Color.white.opacity(0.16))
            }
    }

    // MARK: 生日与纪念日

    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func birthdays(_ rows: [LunarEvents.Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("生日与纪念日"), trailing: tr("按农历每年换算"))
            if rows.isEmpty {
                emptyBirthdays
            } else {
                let shown = showAllEvents ? rows : Array(rows.prefix(Self.visibleEvents))
                ForEach(Array(shown.enumerated()), id: \.element.event.id) { index, row in
                    eventRow(row, highlighted: index == 0)
                }
                if rows.count > Self.visibleEvents {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showAllEvents.toggle() }
                    } label: {
                        Text(showAllEvents ? tr("收起") : tr("展开全部 \(rows.count) 条"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if let first = rows.first {
                    Text(LunarEvents.reminderText(first.event))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                NotificationsOffNote(active: rows.contains { $0.event.lead >= 0 }, preview: context.isPreview)
            }
        }
    }

    private var emptyBirthdays: some View {
        Button { beginNew(context.now) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("记一个农历生日"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(tr("每年自动换成公历，提前提醒"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    private func eventRow(_ row: LunarEvents.Row, highlighted: Bool) -> some View {
        let note = LunarEvents.note(row.event, row.next)
        return Button { begin(row.event) } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.event.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(LunarEvents.subtitle(row))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    if let note {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Self.warn.opacity(0.9))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 4)
                if row.days == 0 {
                    HStack(spacing: 4) {
                        if let panda = PandaArt.image(LunarReading.pandaPose) {
                            Image(nsImage: panda)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .accessibilityHidden(true)
                        }
                        Text(tr("今天"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .fixedSize()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: "\(row.days)")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(highlighted ? accent : .white)
                        Text(tr("天"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(highlighted ? 0.10 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(highlighted ? 0.2 : 0.1), lineWidth: 0.6)
                    }
            }
            .overlay(alignment: .leading) {
                if highlighted {
                    Capsule().fill(accent).frame(width: 3.5).padding(.vertical, 12)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(tr("点按修改或删除"))
        .accessibilityLabel(tr("\(row.event.name)，\(LunarEvents.subtitle(row))，还有 \(row.days) 天"))
    }

    // MARK: 近期节日节气

    private func agenda(_ items: [LunarCard.AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("近期节日节气"))
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(tr("近期没有节日节气"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    agendaRow(item)
                    if index < items.count - 1 {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.horizontal, 14)
                    }
                }
            }
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.6)
                    }
            }
        }
    }

    private func agendaRow(_ item: LunarCard.AgendaItem) -> some View {
        let tint: Color = item.isAlert ? LunarReading.red : .white
        return HStack(spacing: 8) {
            Text(trKey(item.name))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .layoutPriority(1)
            Text(item.kindText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.isAlert ? LunarReading.red.opacity(0.85) : .white.opacity(0.62))
            Spacer(minLength: 4)
            Text(LunarEvents.dateText(item.date))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize()
            Text(item.countdownText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(item.isAlert ? LunarReading.red : .white.opacity(0.9))
                .frame(minWidth: 48, alignment: .trailing)
                .fixedSize()
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    // MARK: 本月月历

    /// 调休补班怎么提醒，写在“近期”那一页下面。
    private var workAlertNote: some View {
        Text(tr("调休补班会提前 \(LunarCard.leadDays(config)) 天出现在卡片上，前一天晚上再提醒一次。"))
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func monthGrid(_ now: Date) -> some View {
        let calendar = ChineseCalendar.gregorian
        let year = calendar.component(.year, from: now)
        let monthNumber = calendar.component(.month, from: now)
        let cells = LunarCard.month(year: year, month: monthNumber, now: now, known: holidays.known,
                                    showTerm: showTerm)
        let blanks = LunarCard.leadingBlanks(year: year, month: monthNumber)
        let slots: [LunarCard.MonthCell?] = Array(repeating: nil, count: blanks) + cells.map { Optional($0) }
        let rows = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        let lunarMonths = Array(NSOrderedSet(array: cells.map { ChineseCalendar.lunar($0.date).monthName }))
            .compactMap { $0 as? String }
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("\(String(year)) 年 \(monthNumber) 月"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(tr("农历\(lunarMonths.joined(separator: " · "))"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            HStack(spacing: 1) {
                ForEach(0..<7, id: \.self) { index in
                    Text(WeekAgenda.weekdayNames[index])
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { index in
                        if index < row.count, let cell = row[index] {
                            dayCell(cell)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 40)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .glassPane(cornerRadius: 12)
    }

    private func dayCell(_ cell: LunarCard.MonthCell) -> some View {
        let tint: Color? = switch cell.mark {
        case .off: LunarReading.red
        case .work: Color(hex: "#FF9F45")
        case .none: nil
        }
        let sub: String = switch cell.mark {
        // 假期第一天写假期名（国庆），其余写「休」；节日、节气照写。
        case .off: cell.subIsSpecial ? LunarPanel.cellName(trKey(cell.sub)) : tr("休")
        case .work: tr("班")
        case .none: cell.subIsSpecial ? LunarPanel.cellName(trKey(cell.sub)) : LunarPanel.cellName(cell.sub)
        }
        let subColor: Color = tint ?? (cell.subIsSpecial ? Color(hex: "#FFD36B") : Color.white.opacity(0.5))
        return VStack(spacing: 0) {
            Text(verbatim: "\(cell.day)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(tint == nil && cell.isWeekend ? 0.7 : 1))
            Text(sub)
                .font(.system(size: 13, weight: cell.subIsSpecial || tint != nil ? .semibold : .regular))
                .foregroundStyle(subColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background {
            if let tint {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.22))
            }
        }
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
        }
        .help(helpText(cell))
        .accessibilityElement(children: .combine)
    }

    /// 悬停：节日、节气名，或假期名和休、班。
    private func helpText(_ cell: LunarCard.MonthCell) -> String {
        let lunar = ChineseCalendar.lunar(cell.date).short
        switch HolidaySchedule.kind(of: cell.date, known: holidays.known) {
        case .holiday(let name): return tr("\(trKey(name)) · 放假 · 农历\(lunar)")
        case .makeupWorkday(let name): return tr("\(trKey(name))调休 · 上班 · 农历\(lunar)")
        default: return cell.subIsSpecial ? tr("\(trKey(cell.sub)) · 农历\(lunar)") : tr("农历\(lunar)")
        }
    }

    // MARK: - 添加 / 编辑

    private func beginNew(_ now: Date) {
        guard !context.isPreview, LunarEvents.events(config).count < LunarEvents.limit else { return }
        let lunar = ChineseCalendar.lunar(now)
        present(Draft(id: UUID().uuidString, name: "", kind: .birthday, month: lunar.month, day: lunar.day,
                   leap: lunar.isLeapMonth, lead: LunarEvents.defaultLead, minute: LunarEvents.defaultMinute, isNew: true))
    }

    private func begin(_ event: LunarEvent) {
        guard !context.isPreview else { return }
        present(Draft(id: event.id, name: event.name, kind: event.kind, month: event.month, day: event.day,
                   leap: event.isLeap, lead: event.lead, minute: event.minute, isNew: false))
    }

    private func present(_ value: Draft) {
        withAnimation(.snappy(duration: 0.25)) {
            confirmDelete = false
            draft = value
        }
        if value.isNew {
            WidgetDetailWindow.shared.focusField { nameFocused = true }
        }
    }

    private func close() {
        nameFocused = false
        withAnimation(.snappy(duration: 0.25)) {
            draft = nil
            confirmDelete = false
        }
    }

    /// 改草稿里的一项。
    private func edit(_ change: (inout Draft) -> Void) {
        guard var value = draft else { return }
        change(&value)
        draft = value
        confirmDelete = false
    }

    private func save() {
        guard let value = draft, !context.isPreview, let name = LunarEvents.clean(value.name) else { return }
        let event = LunarEvent(id: value.id, name: name, kind: value.kind, month: value.month, day: value.day,
                               isLeap: value.leap, lead: value.lead, minute: value.minute)
        commit { LunarEvents.saving(event, in: $0) }
        close()
    }

    private func remove(_ id: String) {
        guard !context.isPreview else { return }
        commit { LunarEvents.removing(id, from: $0) }
        close()
    }

    /// 一次写进配置，再按新的那份排提醒。
    private func commit(_ change: ([LunarEvent]) -> [LunarEvent]) {
        var updated = current
        LunarEvents.store(change(LunarEvents.events(updated.config)), in: &updated.config)
        WidgetWriter.update(updated)
        LunarNotifier.shared.updateEvents(updated)
    }

    @ViewBuilder
    private func editor(_ value: Draft) -> some View {
        let canSave = LunarEvents.clean(value.name) != nil
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value.isNew ? tr("添加生日 / 纪念日") : tr("编辑生日 / 纪念日"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(tr("按农历记，每年自动换成公历"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button { close() } label: {
                Text(tr("取消"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            Button { save() } label: {
                Text(tr("保存"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 15)
                    .frame(height: 28)
                    .background(Capsule().fill(accent))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .help(canSave ? tr("保存") : tr("先写个名字"))
        }

        nameField(value)

        HStack(spacing: 6) {
            ForEach(LunarEvent.Kind.allCases, id: \.self) { kind in
                chip(kind.title, selected: value.kind == kind) { edit { $0.kind = kind } }
            }
            Spacer(minLength: 4)
            Text(tr("闰月"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Toggle(isOn: Binding(get: { value.leap }, set: { on in edit { $0.leap = on } })) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(accent)
                .help(tr("记的是闰月：有这个闰月的年份按闰月过，没有就按同名的月过"))
        }

        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("农历日期"))
            HStack(spacing: 8) {
                LunarWheel(items: (1...12).map { ChineseCalendar.LunarDate.monthTitle($0, leap: value.leap) },
                           selection: Binding(get: { value.month - 1 }, set: { index in edit { $0.month = index + 1 } }),
                           accent: accent)
                LunarWheel(items: (1...30).map { ChineseCalendar.LunarDate.dayTitle($0) },
                           selection: Binding(get: { value.day - 1 }, set: { index in edit { $0.day = index + 1 } }),
                           accent: accent)
            }
        }

        preview(value)

        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("提前提醒"))
            HStack(spacing: 6) {
                ForEach(LunarEvents.leadChoices, id: \.self) { lead in
                    chip(leadTitle(lead), selected: value.lead == lead) { edit { $0.lead = lead } }
                }
            }
            HStack(spacing: 10) {
                Text(tr("提醒时间"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Menu {
                    ForEach(LunarEvents.minuteChoices, id: \.self) { minute in
                        Button(LunarEvents.timeText(minute)) { edit { $0.minute = minute } }
                    }
                } label: {
                    Text(LunarEvents.timeText(value.minute))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.6)
                                }
                        }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(value.lead < 0)
                .opacity(value.lead < 0 ? 0.45 : 1)
                Spacer(minLength: 0)
            }
            NotificationsOffNote(active: value.lead >= 0, preview: context.isPreview)
        }

        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("卡片上显示"))
            displayToggles
        }

        pandaNote

        if !value.isNew {
            Button {
                if confirmDelete { remove(value.id) } else {
                    withAnimation(.snappy(duration: 0.2)) { confirmDelete = true }
                }
            } label: {
                Text(confirmDelete ? tr("再点一次删除") : tr("删除这一条"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LunarReading.red)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LunarReading.red.opacity(confirmDelete ? 0.18 : 0.08))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func nameField(_ value: Draft) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextField(tr("名字，比如妈妈生日"),
                      text: Binding(get: { value.name },
                                    set: { text in edit { $0.name = String(text.prefix(LunarEvents.nameLimit)) } }))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .focused($nameFocused)
                .onSubmit { save() }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(nameFocused ? accent : .white.opacity(0.18), lineWidth: nameFocused ? 1.2 : 0.6)
                }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? accentInk : .white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(selected ? accent : Color.white.opacity(0.10)))
                .overlay {
                    if !selected { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func leadTitle(_ lead: Int) -> String {
        switch lead {
        case -1: tr("不提醒")
        case 0: tr("当天")
        default: tr("\(lead) 天")
        }
    }

    /// 绿点那块：今年（或下一次）落在哪天、还有几天、明年是哪天，做了变通的写一句。
    private func preview(_ value: Draft) -> some View {
        let now = context.now
        let found = LunarEvents.occurrences(month: value.month, day: value.day, leap: value.leap, from: now)
        let event = LunarEvent(id: value.id, name: value.name, kind: value.kind, month: value.month,
                               day: value.day, isLeap: value.leap)
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(Self.green).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                if let first = found.first {
                    let days = ChineseCalendar.days(from: now, to: first.date)
                    Text(days == 0 ? tr("就是今天，\(LunarEvents.dateText(first.date))")
                                   : tr("\(yearWord(first.date, now: now))是 \(LunarEvents.dateText(first.date))"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if found.count > 1 {
                        let second = found[1]
                        Text(days == 0
                             ? tr("\(yearWord(second.date, now: now))是 \(shortDate(second.date))")
                             : tr("还有 \(days) 天 · \(yearWord(second.date, now: now))是 \(shortDate(second.date))"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    if let note = LunarEvents.note(event, first) {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Self.warn.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(tr("这个日子算不出来"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                }
        }
    }

    /// 今年、明年、2028年
    private func yearWord(_ date: Date, now: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        let year = calendar.component(.year, from: date)
        let thisYear = calendar.component(.year, from: now)
        if year == thisYear { return tr("今年") }
        if year == thisYear + 1 { return tr("明年") }
        return tr("\(String(year))年")
    }

    /// 11月5日
    private func shortDate(_ date: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        return tr("\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
    }

    private var displayToggles: some View {
        let rows: [(String, String)] = [
            (tr("宜忌"), LunarPanel.almanacKey),
            (tr("节气"), "showTerm"),
            (tr("调休补班"), "workAlert"),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Toggle(isOn: Binding(
                    get: { config.bool(row.1, default: true) },
                    set: { on in
                        guard !context.isPreview else { return }
                        WidgetWriter.write(current) { $0.set(row.1, .bool(on)) }
                        if row.1 == "workAlert", let saved = WidgetWriter.current(instance.id) {
                            LunarNotifier.shared.update(saved, known: holidays.known)
                        }
                    }
                )) {
                    Text(row.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .tint(accent)
                .padding(.horizontal, 14)
                .frame(height: 44)
                if index < rows.count - 1 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.horizontal, 14)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.6)
                }
        }
    }

    private var pandaNote: some View {
        HStack(spacing: 10) {
            if let panda = PandaArt.image("pet-panda-eat") {
                Image(nsImage: panda)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("生日那天卡片上"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text(tr("小熊猫会来送祝福"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05))
        }
    }

    private func dateLine(_ date: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return tr("\(month)月\(day)日 \(LunarReading.weekday(date))")
    }
}

// MARK: - 农历月日滚轮

/// 两个并排的滚轮之一：滚动或点一行选中，选中的那行在中间的高亮框里。
private struct LunarWheel: View {
    var items: [String]
    @Binding var selection: Int
    var accent: Color

    @State private var scrolled: Int?
    private static let row: CGFloat = 30
    private static let height: CGFloat = 150

    init(items: [String], selection: Binding<Int>, accent: Color) {
        self.items = items
        _selection = selection
        self.accent = accent
        // 一打开就停在选中的那行，不从第一行滚过来。
        _scrolled = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        let centre = scrolled ?? selection
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let distance = abs(index - centre)
                    Text(items[index])
                        .font(.system(size: distance == 0 ? 15 : 14, weight: distance == 0 ? .bold : .medium))
                        .foregroundStyle(.white.opacity(distance == 0 ? 1 : (distance == 1 ? 0.55 : 0.3)))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.row)
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { scrolled = index }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled, anchor: .center)
        .contentMargins(.vertical, (Self.height - Self.row) / 2, for: .scrollContent)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(accent.opacity(0.8), lineWidth: 1)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 4)
            }
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .onAppear { scrolled = selection }
        .onChange(of: scrolled) { _, new in
            if let new, new != selection, items.indices.contains(new) { selection = new }
        }
        .onChange(of: selection) { _, new in
            if scrolled != new { scrolled = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(items.indices.contains(selection) ? items[selection] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = min(selection + 1, items.count - 1)
            case .decrement: selection = max(selection - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - 一天只算一次

/// 面板每秒重画，生日列表和近期节日节气只在换天、改了配置或放假数据更新时重算。
@MainActor
enum LunarPanelCache {
    struct Snapshot {
        var rows: [LunarEvents.Row]
        var agenda: [LunarCard.AgendaItem]
    }

    private static var key = ""
    private static var value = Snapshot(rows: [], agenda: [])

    static func read(now: Date, config: WidgetConfig, events: [LunarEvent], known: [Int: [HolidayDay]],
                     breaks: () -> [HolidayBreak]) -> Snapshot {
        let showTerm = config.bool("showTerm", default: true)
        let workAlert = config.bool("workAlert", default: true)
        let wanted = [ChineseCalendar.key(now), showTerm ? "t" : "-", workAlert ? "w" : "-",
                      known.keys.sorted().map { String($0) }.joined(separator: ","),
                      "\(known.values.reduce(0) { $0 + $1.count })"]
            .joined(separator: "|") + "|" + events.map(\.id).joined(separator: ",")
            + "|" + events.map { "\($0.name)\($0.month)/\($0.day)\($0.isLeap)\($0.lead)\($0.minute)" }.joined()
        if wanted != key {
            key = wanted
            value = Snapshot(rows: LunarEvents.rows(events, now: now),
                         agenda: LunarCard.agenda(now: now, known: known, breaks: breaks(),
                                                  showTerm: showTerm, workAlert: workAlert))
        }
        return value
    }
}
