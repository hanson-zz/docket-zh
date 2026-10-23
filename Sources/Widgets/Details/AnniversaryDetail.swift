import SwiftUI

/// 纪念日面板。时间线一页从今天往后排，最近的在最上面，过去不会再来的收在“已经过去”；
/// 点一行进它的专属页，右键编辑、固定到单个卡片或删除，底部添加。
///
/// 单个卡片和多个卡片点开不一样：单个卡片开它显示的那一个的专属页
/// （`AnniversaryEventPage`），多个卡片开时间线；在多个卡片里点某个图标或胶囊，
/// 直接开那一个的专属页。开哪一页记在 `AnniversaryRoute`。
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            // 角上一抹沙色，不用事件色：深色下不要大面积的蓝。
            MeshBackdrop(color: AnniversarySandColor.sand, fixed: true)
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
                        look: hourglassLook,
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

    /// 多个卡片点开的样子（单个卡片点“时间线”回到这里也是）：顶上“纪念日”和全部 /
    /// 倒数 / 正数分段，今天一枚红胶囊，下面一根竖向时间轴，还会来的从近到远，最近一个
    /// 是玻璃高亮行，带一只小沙漏；过去不会再来的放进“已经过去”。点一行进它的专属页。
    private func timelineScreen(_ all: [AnniversaryEvent]) -> some View {
        let shown = all.filter { event in
            switch tab {
            case .all: true
            case .countdown: event.kind == .countdown
            case .countup: event.kind == .countup
            }
        }
        let line = Anniversary.agenda(shown, today: context.now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let draft {
                    editor(draft)
                } else if all.isEmpty {
                    PandaEmptyState(empty: .anniversary, title: tr("添加纪念日"), panel: true) { beginNew() }
                } else {
                    todayChip
                    timeline(line)
                    footer(count: all.count)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: draft)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("纪念日")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Picker("", selection: $tab) {
                Text("全部").tag(Tab.all)
                Text("倒数").tag(Tab.countdown)
                Text("正数").tag(Tab.countup)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    /// 今天 10月22日 周四：红点加红字的淡红胶囊，压在时间轴的顶头。
    private var todayChip: some View {
        let today = Anniversary.calendar.startOfDay(for: context.now)
        return HStack(spacing: 6) {
            Circle()
                .fill(Self.todayRed)
                .frame(width: 7, height: 7)
            Text(tr("今天 \(Anniversary.monthDayText(today)) \(Anniversary.weekdayShort(today))"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.todayRed.panelReadable)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Self.todayRed.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Timeline

    /// 时间轴竖线的横坐标（图标的中心）。
    private static let railX: CGFloat = 12

    private func timeline(_ line: (upcoming: [AnniversaryAgendaItem], past: [AnniversaryReading])) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if line.upcoming.isEmpty, line.past.isEmpty {
                    Text(tab == .countup ? tr("还没有正数日") : tr("还没有倒数日"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .padding(.leading, Self.railX * 2 + 6)
                        .padding(.vertical, 8)
                }
                ForEach(Array(line.upcoming.enumerated()), id: \.element.id) { index, item in
                    agendaRow(item, lead: index == 0)
                }
                if !line.past.isEmpty {
                    Rectangle()
                        .fill(.panelSeparator)
                        .frame(height: 1)
                        .padding(.leading, Self.railX * 2 + 6)
                        .padding(.vertical, 4)
                    Text("已经过去")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .padding(.leading, Self.railX * 2 + 6)
                    ForEach(line.past, id: \.event.id) { reading in pastRow(reading) }
                }
            }
            .background(alignment: .topLeading) {
                Rectangle()
                    .fill(.panelSeparator)
                    .frame(width: 1.5)
                    .padding(.vertical, 6)
                    .offset(x: Self.railX - 0.75)
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 400)
        .scrollIndicators(.never)
    }

    /// 还会来的一行：线上事件图标，名字（事件色）和一行日期，右边天数。最近一个是玻璃
    /// 高亮行，左边一道事件色竖条，右边一只小沙漏。
    private func agendaRow(_ item: AnniversaryAgendaItem, lead: Bool) -> some View {
        let event = item.reading.event
        let tint = AnniversaryTile.tint(event)
        return HStack(spacing: 10) {
            AnniversaryIconChip(event: event, diameter: lead ? 20 : 16, ring: true)
                .frame(width: Self.railX * 2)
            Button {
                showEvent(event.id)
            } label: {
                HStack(spacing: 8) {
                    if lead {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(AnniversaryTile.base(event))
                            .frame(width: 3, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(tint.panelReadable)
                                .lineLimit(1)
                            if pinned == event.id {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.panelSecondary)
                                    .help("显示在单个卡片上")
                            }
                        }
                        Text(Anniversary.agendaLine(item))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    daysLabel(item.daysLeft, tint: tint, size: lead ? 22 : 17)
                    if lead {
                        AnniversaryHourglass(look: hourglassLook,
                                             sand: Anniversary.sand(item.reading, today: context.now),
                                             cap: AnniversaryTile.base(event), animate: !reduceMotion)
                            .frame(width: 18, height: 32)
                    }
                }
                .padding(.horizontal, lead ? 8 : 4)
                .padding(.vertical, lead ? 8 : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if lead {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AnniversaryTile.base(event).opacity(0.08))
                    }
                }
                .modifier(LeadGlass(active: lead))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help("点按打开专属页")
            .contextMenu { menu(event) }
            .accessibilityLabel(tr("\(event.title)，\(Anniversary.agendaLine(item))，\(Self.daysPhrase(item.daysLeft))"))
        }
    }

    /// 71 天；今天的写“就是今天”。
    @ViewBuilder
    private func daysLabel(_ days: Int, tint: Color, size: CGFloat) -> some View {
        if days == 0 {
            Text("就是今天")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint.panelReadable)
                .fixedSize()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(days.formatted())
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                Text("天")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
            }
            .fixedSize()
        }
    }

    private static func daysPhrase(_ days: Int) -> String {
        days == 0 ? tr("就是今天") : tr("还有 \(days) 天")
    }

    /// 已经过去的一行：小图标、名字、几天前。
    private func pastRow(_ reading: AnniversaryReading) -> some View {
        let event = reading.event
        return HStack(spacing: 10) {
            AnniversaryIconChip(event: event, diameter: 14, ring: true)
                .opacity(0.8)
                .frame(width: Self.railX * 2)
            Button {
                showEvent(event.id)
            } label: {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(tr("\(reading.days) 天前"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .fixedSize()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help("点按打开专属页")
            .contextMenu { menu(event) }
        }
    }

    /// 最近一个的沙漏：跟卡片选的样式，撕页卡片画线条沙漏，玻璃没解锁时也是线条。
    private var hourglassLook: AnniversaryLook {
        AnniversaryLook.hourglass(config: instance.config, unlocked: context.isPreview || ProAccess.isUnlocked)
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

    /// 底部：红色加号“添加纪念日”，右边一句“点一行进它的专属页”。
    private func footer(count: Int) -> some View {
        let full = count >= Anniversary.maxEvents
        return HStack(spacing: 8) {
            Button {
                beginNew()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(full ? Color.panelTertiary : Self.todayRed)
                    Text(full ? tr("最多 \(Anniversary.maxEvents) 个纪念日") : tr("添加纪念日"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(full ? Color.panelSecondary : Color.panelPrimary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview || full)
            Spacer(minLength: 4)
            Text("点一行进它的专属页")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
        }
        .padding(.top, 2)
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

/// 最近一个的那一行：一块液态玻璃小块（和面板里其他玻璃小块同一套）。
private struct LeadGlass: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content.glassPane(cornerRadius: 12)
        } else {
            content
        }
    }
}
