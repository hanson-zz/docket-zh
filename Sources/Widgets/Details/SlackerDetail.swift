import AppKit
import SwiftUI

/// 摸鱼时钟的面板：上面是放大的卡片（每秒走），下面是全部设置：工作日、
/// 工作时间、背景（颜色或图片）、字体颜色、字体、显示更多、发薪日、每天的
/// 收入和法定节假日。改动立即写回小组件，卡片跟着变。
struct SlackerDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum BackgroundTab: Hashable { case color, image }

    @State private var backgroundTab: BackgroundTab?
    @State private var timeWarning = false
    @State private var hexDraft = ""
    @State private var textHexDraft = ""

    private var config: WidgetConfig { instance.config }
    private var settings: SlackerClock.Settings { SlackerClock.Settings(config: config) }

    private var accent: Color { Color(hex: SlackerClock.workHex) }

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
                .frame(height: 360)
            }
            .disabled(context.isPreview)
        }
    }

    // MARK: Preview

    private var preview: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let now = context.isPreview ? SlackerSamples.now : tick.date
            let reading = SlackerClock.reading(now: now, settings: settings, known: HolidayService.shared.known)
            let look = SlackerLook(config: config, art: reading.art)
            SlackerFace(reading: reading, look: look, metrics: .panel)
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
                .environment(\.colorScheme, .light)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SlackerLook.spoken(reading))
        }
    }

    // MARK: Rows

    private var workdaysRow: some View {
        let chosen = settings.workdays
        return VStack(alignment: .leading, spacing: 6) {
            Text("工作日")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(SlackerClock.weekdayChoices, id: \.value) { choice in
                    let day = Int(choice.value) ?? 0
                    pill(choice.title, on: chosen.contains(day)) {
                        var next = chosen
                        if next.contains(day) { next.remove(day) } else { next.insert(day) }
                        writeWorkdays(next)
                    }
                }
                Spacer(minLength: 4)
                pill(tr("工作日"), on: chosen == Set(SlackerClock.weekdays)) {
                    writeWorkdays(Set(SlackerClock.weekdays))
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
                    Text("至").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    timePicker(s.end) { setHours(start: s.start, end: $0) }
                }
            }
            if timeWarning {
                Text("下班时间要晚于上班时间，暂不支持跨午夜。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex).mix(with: .white, by: 0.35))
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
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                Picker("", selection: Binding(get: { tab }, set: { backgroundTab = $0 })) {
                    Text("颜色").tag(BackgroundTab.color)
                    Text("图片").tag(BackgroundTab.image)
                }
                .pickerStyle(.segmented)
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
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
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
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
        return row(tr("显示更多")) {
            HStack(spacing: 4) {
                ForEach(SlackerClock.Item.allCases) { item in
                    pill(item.title, on: chosen.contains(item)) {
                        var next = chosen
                        if next.contains(item) { next.remove(item) } else if next.count < SlackerClock.maxItems { next.insert(item) }
                        let ordered = SlackerClock.Item.allCases.filter { next.contains($0) }
                        write { $0.set(SlackerClock.itemsKey, .list(ordered.map { .string($0.rawValue) })) }
                    }
                }
            }
        }
    }

    private var paydayRow: some View {
        row(tr("发薪日")) {
            HStack(spacing: 4) {
                Text("每月").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                Picker("", selection: Binding(
                    get: { settings.payday },
                    set: { day in write { $0.set(SlackerClock.paydayKey, .number(Double(day))) } })) {
                    ForEach(Array(SlackerClock.paydayRange), id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Text("日").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
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
                Text("元").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
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
                .controlSize(.mini)
        }
    }

    // MARK: Pieces

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
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

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.6))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? accent.opacity(0.85) : Color.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(on ? 0.35 : 0.18), lineWidth: 0.5)
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
                            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
                            .padding(2)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1.5).opacity(on ? 1 : 0) }
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
                Text("自定义").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                TextField("#RRGGBB", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
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

    /// 只写合格的时间段；不合格时提示，卡片照旧。
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
