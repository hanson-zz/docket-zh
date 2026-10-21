import AppKit
import SwiftUI

/// 倒计时面板：头上名字和状态，中间一个大进度环写剩余和几点结束，
/// 下面主按钮居中，再往下是“快速开始”八个常用时长和自定义时长。
///
/// 状态全部来自 `CountdownRun`，和卡片读同样的键（`deadline`、`paused`、
/// `duration`、`presets`），所以面板和卡片不会说两样。时间到了还没人点停时，
/// 环里换成小熊猫和“时间到”，主按钮是“停”。卡片上的三个预设在“调整卡片预设”里改。
///
/// 再往下两组（`CountdownList`）：“同时计时”是同时在跑的其余计时器，各自有名字和
/// 时长，列表里写剩余，能暂停、继续、删掉，加一个就马上开始；“日期倒计时”写到某一天
/// 还有几天（生日、发布日），可以每年重复。卡片只显示最近的一个。
struct CountdownDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    /// 自定义时长（分钟）；没动过时跟着上次的时长。
    @State private var custom: Int?
    @State private var editingPresets = false

    // 加计时器
    @State private var addingTimer = false
    @State private var timerName = ""
    @State private var timerMinutes = CountdownList.newTimerMinutes

    // 加日期倒计时
    @State private var addingDate = false
    @State private var dateName = ""
    @State private var dateDay = Date()
    @State private var dateYearly = true

    var body: some View {
        // 面板的 context 只在打开那一刻取一次，靠这个每秒刷新。
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private var config: WidgetConfig { (WidgetWriter.current(instance.id) ?? instance).config }

    private func content(now: Date) -> some View {
        let config = config
        let total = CountdownRun.duration(config)
        let phase: CountdownRun.Phase = context.isPreview ? .idle : CountdownRun.phase(config, now: now)

        return DetailCard {
            MeshBackdrop(color: Color.timerOrange)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(phase)
                ring(phase, total: total, now: now)
                    .frame(maxWidth: .infinity)
                controls(phase, total: total)
                if editingPresets {
                    presetEditor(config)
                } else {
                    quickStart(config, total: total)
                    customRow(total: total)
                }
                timersSection(config, now: now)
                datesSection(config, now: now)
            }
        }
    }

    /// 计时类卡片的橙，颜色面板里选了颜色就换成选的。
    private var accent: Color { panelTint.accent(or: Color.timerOrange) }
    /// 橙色实心按钮上的深字；白字在这个橙上不够清楚。
    private var ink: Color { panelTint.ink(or: Self.orangeInk) }
    static let orangeInk = Color(hex: "#2A1500")

    // MARK: Pieces

    private func header(_ phase: CountdownRun.Phase) -> some View {
        let name = config.string("name")
        return HStack(alignment: .center, spacing: 8) {
            Text(name.isEmpty ? tr("倒计时") : name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let state = CountdownRun.stateText(phase) {
                Text(state)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }
        }
    }

    private func ring(_ phase: CountdownRun.Phase, total: TimeInterval, now: Date) -> some View {
        let (left, fraction) = Self.reading(phase, total: total)
        let ringing = isRinging(phase)
        return ZStack {
            Circle()
                .stroke(.panelTrack, lineWidth: 7)
            Circle()
                .trim(from: 0, to: ringing ? 1 : min(1, max(0, 1 - fraction)))
                .stroke(accent.opacity(phase == .idle ? 0.35 : 1),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                if ringing {
                    if let image = PandaArt.image("pet-panda-cheer") {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 64)
                            .accessibilityHidden(true)
                    }
                    Text(tr("时间到"))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                } else {
                    Text(CountdownRun.remainingText(left))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.panelPrimary)
                        .rollingValue(Int(left.rounded(.up)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(caption(phase, left: left, total: total, now: now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: 196, height: 196)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func controls(_ phase: CountdownRun.Phase, total: TimeInterval) -> some View {
        if phase == .idle {
            ClockPanelButton(title: tr("开始 \(CountdownRun.lengthText(total))"), fill: accent, ink: ink,
                             size: 15, height: 40) {
                start(duration: total)
            }
        } else {
            HStack(spacing: 8) {
                ClockPanelButton(title: tr("+1 分钟"), fill: nil, height: 40) { addMinute() }
                    .frame(width: 84)
                ClockPanelButton(title: primaryTitle(phase), fill: accent, ink: ink, size: 15, height: 40) {
                    primary(phase, duration: total)
                }
                if isRinging(phase) {
                    ClockPanelButton(title: tr("再来一次"), fill: nil, height: 40) { start(duration: total) }
                        .frame(width: 84)
                } else {
                    ClockPanelButton(title: tr("取消"), fill: nil, height: 40, action: cancel)
                        .frame(width: 84)
                }
            }
        }
    }

    /// 八个常用时长，点一下就开始；卡片上的三个右上角一个小圆点，上次用的描边。
    private func quickStart(_ config: WidgetConfig, total: TimeInterval) -> some View {
        let presets = Set(CountdownRun.presets(config))
        let last = Int((total / 60).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(tr("快速开始"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Circle().fill(Color.panelTertiary).frame(width: 5, height: 5)
                Text(tr("在卡片上"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                Spacer(minLength: 6)
                Button { withAnimation(.snappy(duration: 0.25)) { editingPresets = true } } label: {
                    Text(tr("调整卡片预设"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent.panelReadable)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(CountdownRun.quickMinutes(config), id: \.self) { minutes in
                    Button { start(duration: Double(minutes * 60)) } label: {
                        Text(CountdownRun.presetLabel(minutes))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                Capsule().fill(minutes == last ? accent.opacity(0.22) : .panelFill)
                                    .overlay {
                                        Capsule().strokeBorder(minutes == last ? accent.opacity(0.6) : .panelStroke,
                                                               lineWidth: 0.6)
                                    }
                            }
                            .overlay(alignment: .topTrailing) {
                                if presets.contains(minutes) {
                                    Circle().fill(Color.panelTertiary).frame(width: 5, height: 5)
                                        .padding(.top, 7).padding(.trailing, 9)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("开始 \(minutes) 分钟倒计时"))
                }
            }
        }
    }

    /// 自定义时长：加减号按档位走（1 分钟、5 分钟、15 分钟一档），最长 240 分钟。
    private func customRow(total: TimeInterval) -> some View {
        let minutes = custom ?? max(1, min(CountdownRun.presetRange.upperBound, Int((total / 60).rounded())))
        return HStack(spacing: 8) {
            Text(tr("自定义"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 0)
            roundStep("minus", enabled: minutes > CountdownRun.presetRange.lowerBound) {
                custom = CountdownRun.stepping(minutes, up: false)
            }
            Text(CountdownRun.lengthText(Double(minutes * 60)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 76)
                .contentTransition(.numericText())
            roundStep("plus", enabled: minutes < CountdownRun.presetRange.upperBound) {
                custom = CountdownRun.stepping(minutes, up: true)
            }
            Spacer(minLength: 0)
            ClockPanelButton(title: tr("开始"), fill: accent, ink: ink, height: 32) {
                start(duration: Double(minutes * 60))
            }
            .frame(width: 56)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .glassPane()
    }

    /// 卡片上的三个预设：加减号改分钟，点数字直接开始。
    private func presetEditor(_ config: WidgetConfig) -> some View {
        let presets = CountdownRun.presets(config)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("卡片上的预设"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer()
                Button { withAnimation(.snappy(duration: 0.25)) { editingPresets = false } } label: {
                    Text(tr("完成"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(presets.enumerated()), id: \.offset) { index, minutes in
                HStack(spacing: 10) {
                    Text(tr("第 \(index + 1) 个"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                    Spacer(minLength: 0)
                    roundStep("minus", enabled: minutes > CountdownRun.presetRange.lowerBound) {
                        setPreset(index, to: CountdownRun.stepping(minutes, up: false))
                    }
                    Button { start(duration: Double(minutes * 60)) } label: {
                        Text(CountdownRun.lengthText(Double(minutes * 60)))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.panelPrimary)
                            .frame(minWidth: 96)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("开始 \(minutes) 分钟倒计时"))
                    roundStep("plus", enabled: minutes < CountdownRun.presetRange.upperBound) {
                        setPreset(index, to: CountdownRun.stepping(minutes, up: true))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glassPane()
            }
        }
    }

    // MARK: 同时计时

    private func sectionHeader(_ title: String, canAdd: Bool, adding: Bool, add: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 6)
            if !adding {
                Button(action: add) {
                    Label(tr("添加"), systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(canAdd ? accent.panelReadable : .panelQuaternary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd || context.isPreview)
            }
        }
    }

    private func timersSection(_ config: WidgetConfig, now: Date) -> some View {
        let extras = context.isPreview ? [] : CountdownList.extras(config)
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(tr("同时计时"), canAdd: CountdownList.canAddTimer(config), adding: addingTimer) {
                timerName = ""
                timerMinutes = CountdownList.newTimerMinutes
                withAnimation(.snappy(duration: 0.25)) { addingTimer = true }
            }
            if addingTimer { timerEditor }
            if extras.isEmpty && !addingTimer {
                Text(tr("泡面、晾衣服、等会议可以一起计，各计各的。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(extras) { timer in
                timerRow(timer, now: now)
            }
        }
    }

    private var timerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("名字，比如泡面"), text: $timerName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(addTimer)
            HStack(spacing: 8) {
                roundStep("minus", enabled: timerMinutes > CountdownRun.presetRange.lowerBound) {
                    timerMinutes = CountdownRun.stepping(timerMinutes, up: false)
                }
                Text(CountdownRun.lengthText(Double(timerMinutes * 60)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .frame(width: 96)
                    .contentTransition(.numericText())
                roundStep("plus", enabled: timerMinutes < CountdownRun.presetRange.upperBound) {
                    timerMinutes = CountdownRun.stepping(timerMinutes, up: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ClockPanelButton(title: tr("开始"), fill: accent, ink: ink, action: addTimer)
                ClockPanelButton(title: tr("取消"), fill: nil) {
                    withAnimation(.snappy(duration: 0.25)) { addingTimer = false }
                }
            }
        }
        .padding(12)
        .glassPane()
    }

    /// 一行：名字和状态，右边剩余的大数字、开始暂停（到点时是“停”）和删除，底下细进度条。
    private func timerRow(_ timer: CountdownTimer, now: Date) -> some View {
        let phase = CountdownList.phase(timer, now: now)
        let (left, fraction) = Self.reading(phase, total: timer.duration)
        let ringing = isRinging(phase)
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    Text(rowStatus(phase, left: left, total: timer.duration, now: now))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ringing ? accent.panelReadable : .panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Spacer(minLength: 4)
                Text(ringing ? tr("时间到") : CountdownRun.remainingText(left))
                    .font(.system(size: ringing ? 17 : 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(phase == .idle ? Color.panelTertiary : Color.panelPrimary)
                    .rollingValue(Int(left.rounded(.up)))
                    .lineLimit(1)
                if ringing {
                    ClockPanelButton(title: tr("停"), fill: accent, ink: ink, height: 30) { stopTimer(timer.id) }
                        .frame(width: 48)
                } else {
                    rowGlyph(Self.isRunning(phase) ? "pause.fill" : "play.fill",
                             label: rowToggleLabel(phase)) { toggleTimer(timer.id) }
                }
                rowGlyph("xmark", label: tr("删除 \(timer.title)")) { removeTimer(timer.id) }
            }
            if phase != .idle {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.panelTrack)
                        Capsule().fill(accent)
                            .frame(width: max(3, geo.size.width * (ringing ? 1 : min(1, max(0, fraction)))))
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassPane()
    }

    private func rowGlyph(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .accessibilityLabel(label)
    }

    private func rowStatus(_ phase: CountdownRun.Phase, left: TimeInterval, total: TimeInterval, now: Date) -> String {
        switch phase {
        case .running:
            let ends = now.addingTimeInterval(left).formatted(.dateTime.hour().minute())
            return tr("\(ends) 结束")
        case .paused: return tr("已暂停")
        case .idle: return tr("共 \(CountdownRun.lengthText(total))")
        case .ringing(let since):
            let minutes = Int(since / 60)
            return minutes > 0 ? tr("已过 \(minutes) 分钟") : tr("共 \(CountdownRun.lengthText(total))")
        }
    }

    private static func isRunning(_ phase: CountdownRun.Phase) -> Bool {
        if case .running = phase { return true }
        return false
    }

    private func rowToggleLabel(_ phase: CountdownRun.Phase) -> String {
        switch phase {
        case .running: tr("暂停倒计时")
        case .paused: tr("继续倒计时")
        default: tr("开始")
        }
    }

    // MARK: 日期倒计时

    private func datesSection(_ config: WidgetConfig, now: Date) -> some View {
        let dates = context.isPreview ? [] : CountdownList.dates(config, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(tr("日期倒计时"), canAdd: CountdownList.canAddDate(config), adding: addingDate) {
                dateName = ""
                dateDay = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
                dateYearly = true
                withAnimation(.snappy(duration: 0.25)) { addingDate = true }
            }
            if addingDate { dateEditor }
            if dates.isEmpty && !addingDate {
                HStack(spacing: 10) {
                    if let image = PandaArt.image("pet-panda-idle") {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                    }
                    Text(tr("生日、纪念日、发布日，算到那天还有几天。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(dates) { item in
                dateRow(item, now: now)
            }
        }
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("名字，比如生日"), text: $dateName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(addDate)
            HStack(spacing: 8) {
                DatePicker("", selection: $dateDay, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .font(.system(size: 13))
                Spacer(minLength: 4)
                Toggle(isOn: $dateYearly) {
                    Text(tr("每年重复"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(accent)
            }
            HStack(spacing: 8) {
                ClockPanelButton(title: tr("保存"), fill: accent, ink: ink, action: addDate)
                ClockPanelButton(title: tr("取消"), fill: nil) {
                    withAnimation(.snappy(duration: 0.25)) { addingDate = false }
                }
            }
        }
        .padding(12)
        .glassPane()
    }

    /// 一行：名字和日期，右边还有几天；就是今天时小熊猫来庆祝。
    private func dateRow(_ item: CountdownDate, now: Date) -> some View {
        let days = CountdownList.daysLeft(item, now: now)
        return HStack(spacing: 10) {
            if days == 0, let image = PandaArt.image("pet-panda-cheer") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(days < 0 ? Color.panelTertiary : Color.panelPrimary)
                    .lineLimit(1)
                Text(CountdownList.dateText(item))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(CountdownList.daysText(days))
                .font(.system(size: days > 1 ? 17 : 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(days == 0 ? accent.panelReadable : (days < 0 ? Color.panelTertiary : Color.panelPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            rowGlyph("xmark", label: tr("删除 \(item.title)")) { removeDate(item.id) }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .glassPane()
    }

    private func roundStep(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color.panelPrimary : Color.panelQuaternary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || context.isPreview)
        .accessibilityLabel(symbol == "plus" ? tr("加一点") : tr("减一点"))
    }

    // MARK: Reading

    /// 还剩多少、走过了多少。
    private static func reading(_ phase: CountdownRun.Phase, total: TimeInterval) -> (TimeInterval, Double) {
        switch phase {
        case .idle: (total, 0)
        case .running(let left, let fraction), .paused(let left, let fraction): (left, fraction)
        case .ringing: (0, 1)
        }
    }

    private func isRinging(_ phase: CountdownRun.Phase) -> Bool {
        if case .ringing = phase { return true }
        return false
    }

    /// 环里第二行：跑着时几点结束，其余时候是总时长。
    private func caption(_ phase: CountdownRun.Phase, left: TimeInterval, total: TimeInterval, now: Date) -> String {
        let length = CountdownRun.lengthText(total)
        switch phase {
        case .running:
            let ends = now.addingTimeInterval(left).formatted(.dateTime.hour().minute())
            return tr("\(ends) 结束 · 共 \(length)")
        case .paused, .idle:
            return tr("共 \(length)")
        case .ringing(let since):
            let minutes = Int(since / 60)
            return minutes > 0 ? tr("已过 \(minutes) 分钟") : tr("共 \(length)")
        }
    }

    private func primaryTitle(_ phase: CountdownRun.Phase) -> String {
        switch phase {
        case .idle: tr("开始")
        case .running: tr("暂停")
        case .paused: tr("继续")
        case .ringing: tr("停")
        }
    }

    // MARK: Actions

    private func primary(_ phase: CountdownRun.Phase, duration: TimeInterval) {
        guard !context.isPreview else { return }
        switch phase {
        case .idle: start(duration: duration)
        case .running(let left, _):
            write { config in
                config.set("paused", .number(left))
                config.set("deadline", nil)
            }
        case .paused(let left, _):
            write { config in
                config.set("paused", nil)
                config.set("deadline", .number(Date.now.timeIntervalSince1970 + left))
            }
        case .ringing: cancel()
        }
    }

    private func start(duration: TimeInterval) {
        guard !context.isPreview, duration > 0 else { return }
        write { config in
            config.set("duration", .number(duration))
            config.set("paused", nil)
            config.set("deadline", .number(Date.now.timeIntervalSince1970 + duration))
        }
        custom = nil
    }

    private func addMinute() {
        guard !context.isPreview else { return }
        write { CountdownRun.adding(60, to: &$0, now: .now) }
    }

    private func cancel() {
        guard !context.isPreview else { return }
        write { config in
            config.set("paused", nil)
            config.set("deadline", nil)
        }
    }

    private func addTimer() {
        guard !context.isPreview else { return }
        let name = timerName
        let length = Double(timerMinutes * 60)
        write { _ = CountdownList.adding(name: name, duration: length, to: &$0, now: .now) }
        addingTimer = false
    }

    /// 没开始的开始，跑着的暂停，暂停的继续。
    private func toggleTimer(_ id: String) {
        guard !context.isPreview else { return }
        write { config in
            CountdownList.update(id, in: &config) { timer in
                let now = Date.now
                switch CountdownList.phase(timer, now: now) {
                case .idle, .ringing: timer = CountdownList.starting(timer, duration: timer.duration, now: now)
                case .running: timer = CountdownList.pausing(timer, now: now)
                case .paused: timer = CountdownList.resuming(timer, now: now)
                }
            }
        }
    }

    private func stopTimer(_ id: String) {
        guard !context.isPreview else { return }
        write { CountdownList.update(id, in: &$0) { $0 = CountdownList.stopping($0) } }
    }

    private func removeTimer(_ id: String) {
        guard !context.isPreview else { return }
        write { CountdownList.remove(id, in: &$0) }
    }

    private func addDate() {
        guard !context.isPreview else { return }
        let (name, day, yearly) = (dateName, dateDay, dateYearly)
        write { _ = CountdownList.addingDate(name: name, on: day, yearly: yearly, to: &$0) }
        addingDate = false
    }

    private func removeDate(_ id: String) {
        guard !context.isPreview else { return }
        write { CountdownList.removeDate(id, in: &$0) }
    }

    private func setPreset(_ index: Int, to minutes: Int) {
        guard !context.isPreview else { return }
        let list = CountdownRun.settingPreset(index, to: minutes, in: config)
        write { config in
            config.set(CountdownRun.presetsKey, .list(list.map { .string(String($0)) }))
        }
    }

    private func write(_ change: (inout WidgetConfig) -> Void) {
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance, change)
        }
    }
}
