import AppKit
import SwiftUI

/// 摸鱼时钟的面板：上面是放大的卡片（每秒走），下面是全部设置：工作日、
/// 工作时间、背景（颜色或图片）、字体颜色、字体、显示更多、发薪日、每天的
/// 收入和法定节假日。改动立即写回小组件，卡片跟着变。
struct SlackerDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum BackgroundTab: Hashable { case color, image }

    @State private var backgroundTab: BackgroundTab?
    @State private var timeWarning = false
    @State private var hexDraft = ""
    @State private var textHexDraft = ""

    private var config: WidgetConfig { instance.config }
    private var settings: SlackerClock.Settings { SlackerClock.Settings(config: config) }

    private var accent: Color { panelTint.accent(or: Color(hex: SlackerClock.workHex)) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        workdaysRow
                        hoursRow
                        backgroundSection
                        textColorRow
                        lookRow
                        fontRow
                        itemsRow
                        paydayRow
                        incomeRow
                        holidaysRow
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.never)
                .frame(height: 330)
            }
            .disabled(context.isPreview)
        }
    }

    // MARK: Preview

    private var preview: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let now = context.isPreview ? SlackerSamples.now : tick.date
            let reading = SlackerClock.reading(now: now, settings: settings, known: HolidayService.shared.known)
            VStack(alignment: .leading, spacing: 8) {
                face(reading)
                if let progress = SlackerClock.progress(reading.phase, settings: settings) {
                    progressRow(progress)
                }
            }
        }
    }

    /// 上班中：一条进度和“已上 4 小时 24 分 · 还有 3 小时 36 分”，夜班跨过午夜也对。
    private func progressRow(_ progress: (done: Int, left: Int, fraction: Double)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack)
                    Capsule().fill(accent)
                        .frame(width: max(6, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 8)
            Text(SlackerClock.progressLine(done: progress.done, left: progress.left))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    private func face(_ reading: SlackerClock.Reading) -> some View {
        let look = SlackerLook(config: config, art: reading.art)
        return SlackerFace(reading: reading, look: look, metrics: .panel)
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .background {
                    ZStack {
                        look.background
                        if let image = look.image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .overlay(Color.black.opacity(0.18))
                        }
                        if SlackerClock.look(config) == .liquid {
                            SlackerWater(phase: reading.phase,
                                         level: SlackerClock.waterLevel(reading.phase, settings: settings),
                                         animates: !context.isPreview,
                                         tint: WidgetTintStyle.chosenColor(kind: .slacker, config: config) ?? .white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                // 表盘画在自己的底色或图片上，不跟面板外观：保持浅色环境，字和水波的颜色才和底色对得上。
                .environment(\.colorScheme, .light)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SlackerLook.spoken(reading))
    }

    // MARK: Rows

    /// 一排 7 个星期加「工作日」用 13pt 放不下：星期写单字（一二三四五六日，英文
    /// M T W T F S S）平分一整行，「周一到周五」快捷挪到标题行右边。
    private var workdaysRow: some View {
        let chosen = settings.workdays
        let short = [tr("一"), tr("二"), tr("三"), tr("四"), tr("五"), tr("六"), tr("日")]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("工作日")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 4)
                pill(tr("周一到周五"), on: chosen == Set(SlackerClock.weekdays)) {
                    writeWorkdays(Set(SlackerClock.weekdays))
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(SlackerClock.weekdayChoices.enumerated()), id: \.element.value) { index, choice in
                    let day = Int(choice.value) ?? 0
                    pill(index < short.count ? short[index] : choice.title, on: chosen.contains(day), fill: true) {
                        var next = chosen
                        if next.contains(day) { next.remove(day) } else { next.insert(day) }
                        writeWorkdays(next)
                    }
                    .help(choice.title)
                    .accessibilityLabel(choice.title)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var hoursRow: some View {
        let s = settings
        return VStack(alignment: .leading, spacing: 4) {
            row(tr("工作时间")) {
                HStack(spacing: 6) {
                    timePicker(s.start) { setHours(start: $0, end: s.end) }
                    Text("至").font(.system(size: 13)).foregroundStyle(.panelSecondary)
                    timePicker(s.end) { setHours(start: s.start, end: $0) }
                }
            }
            if timeWarning {
                Text("上班和下班不能是同一时间。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex).mix(with: .white, by: 0.35).panelReadable)
                    .padding(.horizontal, 10)
            } else if s.isOvernight {
                // 下班早于上班按第二天算。
                Text(SlackerClock.hoursLine(s))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var backgroundSection: some View {
        let tab = backgroundTab ?? (SlackerClock.backgroundImagePath(config) == nil ? .color : .image)
        let tinted = config.bool(SlackerClock.tintKey, default: true)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("背景")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Picker("", selection: Binding(get: { tab }, set: { backgroundTab = $0 })) {
                    Text("颜色").tag(BackgroundTab.color)
                    Text("图片").tag(BackgroundTab.image)
                }
                .pickerStyle(.segmented)
                .tint(panelTint.control)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            if tab == .color {
                swatches(SlackerClock.backgroundSwatches,
                         selected: tinted || SlackerClock.backgroundImagePath(config) != nil
                             ? nil : config.string(SlackerClock.backgroundKey, default: SlackerClock.defaultBackgroundHex),
                         custom: Binding(
                            get: { Color(hex: config.string(SlackerClock.backgroundKey,
                                                            default: SlackerClock.defaultBackgroundHex)) },
                            set: { if let hex = Self.hex($0) { pickBackground(hex) } }),
                         draft: $hexDraft) { pickBackground($0) }
            } else {
                imagePicker
            }
            Toggle(isOn: Binding(
                get: { tinted },
                set: { on in write { $0.set(SlackerClock.tintKey, .bool(on)) } })) {
                Text("随状态变色（上班橙、下班绿、周末蓝）")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary)
            }
            .toggleStyle(.switch)
            .tint(panelTint.control)
            .controlSize(.mini)
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var imagePicker: some View {
        let path = config.string(SlackerClock.backgroundImageKey, default: "")
        return HStack(spacing: 8) {
            if let image = path.isEmpty ? nil : SlackerArt.background(path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 30)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
            }
            Button(path.isEmpty ? tr("选择图片…") : tr("换一张…")) { chooseImage() }
                .controlSize(.small)
            if !path.isEmpty {
                Button("移除") {
                    let item = instance
                    WidgetWriter.write(item) { $0.set(SlackerClock.backgroundImageKey, nil) }
                    SlackerArt.discard(path)
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    private var textColorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("字体颜色")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            swatches(SlackerClock.textSwatches,
                     selected: SlackerClock.textHex(config),
                     custom: Binding(
                        get: { Color(hex: SlackerClock.textHex(config)) },
                        set: { if let hex = Self.hex($0) { write { $0.set(SlackerClock.textColorKey, .string(hex)) } } }),
                     draft: $textHexDraft) { hex in
                write { $0.set(SlackerClock.textColorKey, .string(hex)) }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var lookRow: some View {
        row(tr("外观")) {
            Picker("", selection: Binding(
                get: { SlackerClock.look(config) },
                set: { look in write { $0.set(SlackerClock.lookKey, .string(look.rawValue)) } })) {
                ForEach(SlackerClock.Look.allCases, id: \.self) { look in
                    Text(look.title).tag(look)
                }
            }
            .pickerStyle(.segmented)
            .tint(panelTint.control)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var fontRow: some View {
        row(tr("字体")) {
            Picker("", selection: Binding(
                get: { SlackerClock.font(config) },
                set: { choice in write { $0.set(SlackerClock.fontKey, .string(choice.rawValue)) } })) {
                ForEach(SlackerClock.FontChoice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var itemsRow: some View {
        let chosen = Set(settings.items)
        let items = SlackerClock.Item.allCases
        let toggle: (SlackerClock.Item) -> Void = { item in
            var next = chosen
            if next.contains(item) { next.remove(item) } else if next.count < SlackerClock.maxItems { next.insert(item) }
            let ordered = SlackerClock.Item.allCases.filter { next.contains($0) }
            write { $0.set(SlackerClock.itemsKey, .list(ordered.map { .string($0.rawValue) })) }
        }
        // 标题单独一行，4 个标签 13pt：一排放得下就一排，放不下（英文
        // "Today's earnings" 这类）换成两行两列，不再把整行撑出面板。
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("显示更多"))
                .font(WidgetStyle.label(13))
                .foregroundStyle(.white.opacity(0.85))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(items) { item in
                        pill(item.title, on: chosen.contains(item), size: 13) { toggle(item) }
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(items[start..<min(start + 2, items.count)]) { item in
                                pill(item.title, on: chosen.contains(item), size: 13) { toggle(item) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var paydayRow: some View {
        row(tr("发薪日")) {
            HStack(spacing: 4) {
                Text("每月").font(.system(size: 13)).foregroundStyle(.panelSecondary)
                Picker("", selection: Binding(
                    get: { settings.payday },
                    set: { day in write { $0.set(SlackerClock.paydayKey, .number(Double(day))) } })) {
                    ForEach(Array(SlackerClock.paydayRange), id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Text("日").font(.system(size: 13)).foregroundStyle(.panelSecondary)
            }
        }
    }

    private var incomeRow: some View {
        let income = settings.income
        return row(tr("每天的收入")) {
            HStack(spacing: 6) {
                TextField("", value: Binding(
                    get: { income },
                    set: { value in setIncome(value) }), format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Text("元").font(.system(size: 13)).foregroundStyle(.panelSecondary)
                Stepper("", value: Binding(get: { income }, set: { setIncome($0) }),
                        in: SlackerClock.incomeRange, step: SlackerClock.incomeStep)
                    .labelsHidden()
            }
        }
    }

    private var holidaysRow: some View {
        row(tr("按法定节假日和调休")) {
            Toggle("", isOn: Binding(
                get: { settings.followsHolidays },
                set: { on in write { $0.set(SlackerClock.holidaysKey, .bool(on)) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(panelTint.control)
                .controlSize(.mini)
        }
    }

    // MARK: Pieces

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            content()
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 10)
    }

    private func pill(_ title: String, on: Bool, size: CGFloat = 13, fill: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, fill ? 0 : 5)
                .padding(.vertical, 4)
                .frame(maxWidth: fill ? .infinity : nil)
                .foregroundStyle(on ? Color.white : Color.panelSecondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? accent.opacity(0.85) : Color.panelFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(on ? Color.white.opacity(0.35) : .panelStroke, lineWidth: 0.5)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 一排预设色，最后是系统取色器和一个可以直接输入 #RRGGBB 的框。
    private func swatches(_ hexes: [String], selected: String?, custom: Binding<Color>,
                          draft: Binding<String>, pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(hexes, id: \.self) { hex in
                    let on = selected?.uppercased() == hex.uppercased()
                    Button { pick(hex) } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(.panelQuaternary, lineWidth: 0.5) }
                            .padding(2)
                            .overlay { Circle().strokeBorder(.panelPrimary, lineWidth: 1.5).opacity(on ? 1 : 0) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
                ColorPicker("", selection: custom, supportsOpacity: false)
                    .labelsHidden()
                    .help("自定义颜色")
            }
            HStack(spacing: 6) {
                Text("自定义").font(.system(size: 13)).foregroundStyle(.panelSecondary)
                TextField("#RRGGBB", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 90)
                    .onSubmit {
                        if let code = ColorCode(hex: draft.wrappedValue) { pick(code.hex) }
                    }
            }
            .controlSize(.small)
        }
    }

    private func timePicker(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        DatePicker("", selection: Binding(
            get: { Self.date(minutes: minutes) },
            set: { date in
                let calendar = Calendar.current
                set(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    // MARK: Writing

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance, change)
    }

    private func writeWorkdays(_ days: Set<Int>) {
        let list = days.sorted().map { WidgetConfig.Value.string(String($0)) }
        write { $0.set(SlackerClock.workdaysKey, .list(list)) }
    }

    /// 只写合格的时间段（下班早于上班是夜班，也合格）；开始和结束一样时提示，卡片照旧。
    private func setHours(start: Int, end: Int) {
        guard SlackerClock.isValidWindow(start: start, end: end) else {
            timeWarning = true
            return
        }
        timeWarning = false
        write { config in
            config.set(SlackerClock.startKey, .string(PostureSchedule.clock(start)))
            config.set(SlackerClock.endKey, .string(PostureSchedule.clock(end)))
        }
    }

    private func setIncome(_ value: Double) {
        guard value.isFinite else { return }
        let clamped = min(max(value, SlackerClock.incomeRange.lowerBound), SlackerClock.incomeRange.upperBound)
        write { $0.set(SlackerClock.incomeKey, .number(clamped)) }
    }

    /// 选了颜色就用这个颜色：关掉随状态变色，清掉背景图。
    private func pickBackground(_ hex: String) {
        let old = config.string(SlackerClock.backgroundImageKey, default: "")
        write { config in
            config.set(SlackerClock.backgroundKey, .string(hex))
            config.set(SlackerClock.tintKey, .bool(false))
            config.set(SlackerClock.backgroundImageKey, nil)
        }
        if !old.isEmpty { SlackerArt.discard(old) }
    }

    private func chooseImage() {
        guard !context.isPreview else { return }
        let item = instance
        let old = item.config.string(SlackerClock.backgroundImageKey, default: "")
        // 面板会在打开文件面板时收起，选好的图照样写回小组件。
        guard let path = SlackerArt.chooseBackground() else { return }
        WidgetWriter.write(item) { config in
            config.set(SlackerClock.backgroundImageKey, .string(path))
            config.set(SlackerClock.tintKey, .bool(false))
        }
        if !old.isEmpty { SlackerArt.discard(old) }
    }

    private static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                         blue: Double(rgb.blueComponent)).hex
    }
}
