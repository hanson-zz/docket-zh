import SwiftUI

/// Every date on a timeline, latest at the top, with a red line at today
/// between what is still to come and what has passed. Click a date to edit
/// it; the button at the bottom adds one. A date can be pinned to the single
/// card from its editor or its context menu.
///
/// 单个卡片和多个卡片点开不一样：单个卡片开它显示的那一个的专属页
/// （`AnniversaryEventPage`），多个卡片开时间线，顶部有“这个月”的小概览；在多个
/// 卡片里点某一列，直接开那一列的专属页。开哪一页记在 `AnniversaryRoute`。
struct AnniversaryDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Tab: Hashable { case all, countdown, countup }

    /// The editor's working copy, written back only on 保存.
    private struct Draft: Equatable {
        var id: String
        var title: String
        var date: Date
        var kind: AnniversaryEvent.Kind
        var yearly: Bool
        var lunar: Bool
        var color: PaletteColor?
        var pinned: Bool
        var isNew: Bool
    }

    @State private var tab: Tab = .all
    @State private var draft: Draft?
    @FocusState private var titleFocused: Bool

    private var events: [AnniversaryEvent] {
        context.isPreview ? AnniversarySamples.events : Anniversary.events(instance.config)
    }

    private var pinned: String? {
        context.isPreview ? nil : Anniversary.pinnedID(instance.config)
    }

    private var accent: Color {
        panelTint.accent(or: Color(hex: WidgetCatalog.accentHex(.anniversary) ?? PaletteColor.pink.hex))
    }

    private static let todayRed = Color(hex: PaletteColor.red.hex)

    private var route: AnniversaryRoute { .shared }

    private var isMulti: Bool { instance.config.string("layout", default: "single") == "multi" }

    /// 现在这一页要讲的那个纪念日；在时间线上时是 nil。
    ///
    /// 记过页就按记的来（那个纪念日删掉了就回时间线）；没记过，单个卡片开它显示的
    /// 那一个，多个卡片开时间线。
    private func shownReading(_ all: [AnniversaryEvent]) -> AnniversaryReading? {
        let page = context.isPreview ? nil : route.page(instance.id)
        switch page {
        case .timeline?:
            return nil
        case .event(let id)?:
            guard let event = all.first(where: { $0.id == id }) else { return nil }
            return Anniversary.reading(event, today: context.now)
        case nil:
            guard !isMulti else { return nil }
            return Anniversary.featured(all, pinned: pinned, today: context.now)
        }
    }

    var body: some View {
        let all = events
        if let reading = shownReading(all) {
            eventScreen(reading, all: all)
        } else {
            timelineScreen(all)
        }
    }

    // MARK: Event page

    private func eventScreen(_ reading: AnniversaryReading, all: [AnniversaryEvent]) -> some View {
        DetailCard {
            MeshBackdrop(color: AnniversaryTile.base(reading.event), fixed: true)
        } content: {
            Group {
                if let draft {
                    VStack(alignment: .leading, spacing: 12) {
                        AnniversaryBackButton { showTimeline() }
                        editor(draft)
                    }
                } else {
                    AnniversaryEventPage(
                        reading: reading, events: all, pinned: pinned,
                        showsSwitcher: !isMulti, now: context.now, isPreview: context.isPreview,
                        onBack: { showTimeline() },
                        onEdit: { begin(reading.event) },
                        onPick: { id in
                            AnniversaryLog.pin(id, in: instance)
                            route.show(.event(id), in: instance.id)
                        })
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: draft)
    }

    private func showTimeline() {
        draft = nil
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.25)) { route.show(.timeline, in: instance.id) }
    }

    private func showEvent(_ id: String) {
        guard !context.isPreview else { return }
        draft = nil
        withAnimation(.snappy(duration: 0.25)) { route.show(.event(id), in: instance.id) }
    }

    // MARK: Timeline page

    private func timelineScreen(_ all: [AnniversaryEvent]) -> some View {
        let shown = all.filter { event in
            switch tab {
            case .all: true
            case .countdown: event.kind == .countdown
            case .countup: event.kind == .countup
            }
        }
        let line = Anniversary.timeline(shown, today: context.now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(all)
                if !all.isEmpty, draft == nil { monthOverview(all) }
                Picker("", selection: $tab) {
                    Text("时间线").tag(Tab.all)
                    Text("倒数").tag(Tab.countdown)
                    Text("正数").tag(Tab.countup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                if let draft {
                    editor(draft)
                } else if all.isEmpty {
                    PandaEmptyState(empty: .anniversary, title: tr("添加纪念日"), panel: true) { beginNew() }
                } else {
                    timeline(line)
                }

                if draft == nil, !all.isEmpty { addButton(count: all.count) }
            }
        }
        .animation(.snappy(duration: 0.25), value: draft)
    }

    // MARK: This month

    /// 这个月：10 月有 2 个纪念日，最近的「生日」还有 12 天。
    private func monthOverview(_ all: [AnniversaryEvent]) -> some View {
        let summary = Anniversary.monthSummary(all, today: context.now)
        let text: String
        if summary.count == 0 {
            text = tr("\(summary.month) 月没有纪念日")
        } else if let nearest = summary.nearest, let days = summary.nearestDays {
            text = days == 0
                ? tr("\(summary.month) 月有 \(summary.count) 个纪念日，「\(nearest.title)」就是今天")
                : tr("\(summary.month) 月有 \(summary.count) 个纪念日，最近的「\(nearest.title)」还有 \(days) 天")
        } else {
            text = tr("\(summary.month) 月有 \(summary.count) 个纪念日，都已经过去了")
        }
        return Button {
            if let nearest = summary.nearest { showEvent(nearest.id) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("这个月")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPane(cornerRadius: 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview || summary.nearest == nil)
        .help(summary.nearest == nil ? "" : tr("点按打开最近的这个纪念日"))
    }

    // MARK: Header

    private func header(_ all: [AnniversaryEvent]) -> some View {
        let next = Anniversary.featured(all, pinned: nil, today: context.now)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("纪念日")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.panelSecondary)
                Text(next.map { "\($0.event.title) \($0.sentence)" } ?? tr("添加第一个纪念日"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Text("\(all.count)/\(Anniversary.maxEvents)")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelTertiary)
                .monospacedDigit()
        }
    }

    // MARK: Timeline

    private func timeline(_ line: (future: [AnniversaryReading], past: [AnniversaryReading])) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    section(line.future)
                    todayLine.id("today")
                    section(line.past)
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 420)
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo("today", anchor: .center) }
        }
    }

    /// Rows with a year heading wherever the year changes.
    private func section(_ readings: [AnniversaryReading]) -> some View {
        let calendar = Anniversary.calendar
        return ForEach(Array(readings.enumerated()), id: \.element.event.id) { index, reading in
            let year = calendar.component(.year, from: reading.timelineDate)
            let previous = index > 0 ? calendar.component(.year, from: readings[index - 1].timelineDate) : nil
            VStack(alignment: .leading, spacing: 6) {
                if year != previous {
                    Text(tr("\(String(year)) 年"))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelSecondary)
                        .padding(.top, index > 0 ? 4 : 0)
                }
                row(reading)
            }
        }
    }

    private var todayLine: some View {
        HStack(spacing: 6) {
            Text("今天")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.todayRed.panelReadable)
                .frame(width: 34, alignment: .trailing)
            Circle()
                .fill(Self.todayRed)
                .frame(width: 7, height: 7)
                .frame(width: 12)
            Rectangle()
                .fill(Self.todayRed.opacity(0.8))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("今天")
    }

    private func row(_ reading: AnniversaryReading) -> some View {
        let calendar = Anniversary.calendar
        let event = reading.event
        let tint = AnniversaryTile.tint(event)
        return HStack(spacing: 6) {
            VStack(spacing: -1) {
                Text("\(calendar.component(.day, from: reading.timelineDate))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                Text(tr("\(calendar.component(.month, from: reading.timelineDate))月"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelTertiary)
            }
            .frame(width: 34)

            ZStack {
                Rectangle()
                    .fill(.panelSeparator)
                    .frame(width: 1)
                Circle()
                    .fill(reading.isToday ? Self.todayRed : Color.panelTertiary)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 12)

            Button {
                begin(event)
            } label: {
                card(reading, tint: tint)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help("点按编辑")
            .contextMenu { menu(event) }
        }
    }

    private func card(_ reading: AnniversaryReading, tint: Color) -> some View {
        let event = reading.event
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint.panelReadable)
                        .lineLimit(1)
                    Image(systemName: event.kind == .countdown ? "arrow.down" : "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle((event.kind == .countdown ? Self.todayRed : Color(hex: PaletteColor.green.hex)).panelReadable)
                        .help(event.kind.title)
                    if pinned == event.id {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.panelTertiary)
                            .help("显示在单个卡片上")
                    }
                }
                Text(Anniversary.subtitle(reading))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text(reading.anniversaryNote.map { tr("\($0) · 今天") } ?? reading.sentence)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.panelReadable)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 10)
        .overlay {
            if reading.isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.8), lineWidth: 1)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func menu(_ event: AnniversaryEvent) -> some View {
        Button("打开专属页") { showEvent(event.id) }
        Button("编辑") { begin(event) }
        if pinned == event.id {
            Button("不再固定在卡片上") { AnniversaryLog.pin(nil, in: instance) }
        } else {
            Button("显示在单个卡片上") { AnniversaryLog.pin(event.id, in: instance) }
        }
        Divider()
        Button("删除", role: .destructive) {
            AnniversaryLog.change(instance) { Anniversary.removing(event.id, from: $0) }
        }
    }

    private func addButton(count: Int) -> some View {
        Button {
            beginNew()
        } label: {
            Label(count >= Anniversary.maxEvents ? tr("最多 \(Anniversary.maxEvents) 个纪念日") : tr("添加纪念日"),
                  systemImage: "plus")
                .font(WidgetStyle.label(13))
                .foregroundStyle(count >= Anniversary.maxEvents ? Color.panelTertiary : Color.panelPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .glassPane(cornerRadius: 10)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview || count >= Anniversary.maxEvents)
    }

    // MARK: Editor

    private func editor(_ current: Draft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(current.isNew ? tr("添加纪念日") : tr("编辑纪念日"))
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.panelSecondary)

            TextField("", text: binding(\.title), prompt: Text("名称，比如“生日”或“在一起”"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassPane(cornerRadius: 8)
                .onSubmit(save)

            // 带说明的两格放不下（英文 "Countdown (days to go)" 两格约 290pt，
            // 编辑框里只有 280 上下）就换成短名，不撑宽也不截断。
            ViewThatFits(in: .horizontal) {
                Picker("", selection: binding(\.kind)) {
                    Text("倒数日（还有几天）").tag(AnniversaryEvent.Kind.countdown)
                    Text("正数日（已经几天）").tag(AnniversaryEvent.Kind.countup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Picker("", selection: binding(\.kind)) {
                    Text("倒数日").tag(AnniversaryEvent.Kind.countdown)
                    Text("正数日").tag(AnniversaryEvent.Kind.countup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            HStack {
                Text("日期")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Spacer()
                DatePicker("", selection: binding(\.date), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.calendar, Anniversary.calendar)
            }

            Toggle("每年重复", isOn: binding(\.yearly))
                .toggleStyle(.switch)
                .tint(panelTint.control)
                .controlSize(.small)
                .font(WidgetStyle.label(13))
            Toggle("按农历", isOn: binding(\.lunar))
                .toggleStyle(.switch)
                .tint(panelTint.control)
                .controlSize(.small)
                .font(WidgetStyle.label(13))
            if current.lunar { lunarPickers(current) }

            swatches(current)

            Toggle("显示在单个卡片上", isOn: binding(\.pinned))
                .toggleStyle(.switch)
                .tint(panelTint.control)
                .controlSize(.small)
                .font(WidgetStyle.label(13))

            HStack(spacing: 8) {
                if !current.isNew {
                    Button("删除", role: .destructive) { remove(current.id) }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(Self.todayRed.panelReadable)
                }
                Spacer()
                Button("取消") { draft = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                    .disabled(Anniversary.clean(current.title) == nil)
            }
        }
        .padding(12)
        .glassPane(cornerRadius: 12)
        .onAppear { titleFocused = current.isNew }
    }

    /// The lunar month and day of the date picked, as menus: choosing one
    /// moves the date to that lunar day in the same lunar year.
    private func lunarPickers(_ current: Draft) -> some View {
        let parts = Anniversary.lunarParts(current.date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("农历")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { parts.month },
                    set: { moveLunar(month: $0, day: parts.day) })) {
                    ForEach(1...12, id: \.self) { Text(Anniversary.lunarMonthName($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("", selection: Binding(
                    get: { parts.day },
                    set: { moveLunar(month: parts.month, day: $0) })) {
                    ForEach(1...30, id: \.self) { Text(Anniversary.lunarDayName($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .controlSize(.small)
            Text(tr("\(Anniversary.lunarText(current.date))，每年按这个农历日子计算，闰月按平月，没有三十的月份算廿九。"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatches(_ current: Draft) -> some View {
        HStack(spacing: 7) {
            Text("颜色")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            Spacer(minLength: 4)
            swatch(nil, selected: current.color == nil)
            ForEach(PaletteColor.picker, id: \.self) { color in
                swatch(color, selected: current.color == color)
            }
        }
    }

    private func swatch(_ color: PaletteColor?, selected: Bool) -> some View {
        Button {
            draft?.color = color
        } label: {
            Circle()
                .fill(Color(hex: color?.hex ?? WidgetCatalog.accentHex(.anniversary) ?? PaletteColor.pink.hex))
                .frame(width: 14, height: 14)
                .overlay {
                    if color == nil {
                        Text("A")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(2)
                .overlay { Circle().strokeBorder(selected ? Color.panelPrimary : Color.clear, lineWidth: 1.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color == nil ? tr("默认颜色") : "")
    }

    // MARK: Editing

    private func binding<Value>(_ path: WritableKeyPath<Draft, Value>) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: path] ?? Self.blank[keyPath: path] },
            set: { value in draft?[keyPath: path] = value })
    }

    private static let blank = Draft(id: "", title: "", date: .now, kind: .countdown, yearly: false,
                                     lunar: false, color: nil, pinned: false, isNew: true)

    private func beginNew() {
        guard !context.isPreview, events.count < Anniversary.maxEvents else { return }
        draft = Draft(id: AnniversaryEvent.newID(), title: "", date: Anniversary.calendar.startOfDay(for: context.now),
                      kind: .countdown, yearly: true, lunar: false, color: nil, pinned: false, isNew: true)
    }

    private func begin(_ event: AnniversaryEvent) {
        guard !context.isPreview else { return }
        draft = Draft(id: event.id, title: event.title,
                      date: Anniversary.date(fromKey: event.day) ?? context.now,
                      kind: event.kind, yearly: event.yearly, lunar: event.lunar, color: event.color,
                      pinned: pinned == event.id, isNew: false)
    }

    private func moveLunar(month: Int, day: Int) {
        guard let current = draft,
              let moved = Anniversary.solarDate(lunarMonth: month, day: day, inLunarYearOf: current.date) else { return }
        draft?.date = moved
    }

    private func save() {
        guard let current = draft, !context.isPreview, Anniversary.clean(current.title) != nil else { return }
        let event = AnniversaryEvent(id: current.id, title: current.title,
                                     day: Anniversary.dayKey(current.date), kind: current.kind,
                                     yearly: current.yearly, lunar: current.lunar, color: current.color)
        let wasPinned = pinned == current.id
        // One write: the writer starts from the instance it is handed, so a
        // second write here would put back the list the first one replaced.
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(instance) { config in
                Anniversary.store(Anniversary.saving(event, in: Anniversary.events(config)), in: &config)
                if current.pinned != wasPinned {
                    Anniversary.pin(current.pinned ? current.id : nil, in: &config)
                }
            }
        }
        draft = nil
    }

    private func remove(_ id: String) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.3)) {
            AnniversaryLog.change(instance) { Anniversary.removing(id, from: $0) }
        }
        draft = nil
    }
}
