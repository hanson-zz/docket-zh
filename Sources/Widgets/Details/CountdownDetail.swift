import AppKit
import SwiftUI

/// 倒计时面板：头上名字和状态，中间一个大进度环写剩余和几点结束，
/// 下面主按钮居中，再往下是“快速开始”八个常用时长和自定义时长。
///
/// 状态全部来自 `CountdownRun`，和卡片读同样的键（`deadline`、`paused`、
/// `duration`、`presets`），所以面板和卡片不会说两样。时间到了还没人点停时，
/// 环里换成小熊猫和“时间到”，主按钮是“停”。卡片上的三个预设在“调整卡片预设”里改。
struct CountdownDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    /// 自定义时长（分钟）；没动过时跟着上次的时长。
    @State private var custom: Int?
    @State private var editingPresets = false

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
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let state = CountdownRun.stateText(phase) {
                Text(state)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
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
                .stroke(.white.opacity(0.10), lineWidth: 7)
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
                        .foregroundStyle(.white)
                } else {
                    Text(CountdownRun.remainingText(left))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .rollingValue(Int(left.rounded(.up)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(caption(phase, left: left, total: total, now: now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
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
                    .foregroundStyle(.white.opacity(0.6))
                Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
                Text(tr("在卡片上"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 6)
                Button { withAnimation(.snappy(duration: 0.25)) { editingPresets = true } } label: {
                    Text(tr("调整卡片预设"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
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
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                Capsule().fill(minutes == last ? accent.opacity(0.22) : .white.opacity(0.09))
                                    .overlay {
                                        Capsule().strokeBorder(minutes == last ? accent.opacity(0.6) : .white.opacity(0.14),
                                                               lineWidth: 0.6)
                                    }
                            }
                            .overlay(alignment: .topTrailing) {
                                if presets.contains(minutes) {
                                    Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
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
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            roundStep("minus", enabled: minutes > CountdownRun.presetRange.lowerBound) {
                custom = CountdownRun.stepping(minutes, up: false)
            }
            Text(CountdownRun.lengthText(Double(minutes * 60)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { withAnimation(.snappy(duration: 0.25)) { editingPresets = false } } label: {
                    Text(tr("完成"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(presets.enumerated()), id: \.offset) { index, minutes in
                HStack(spacing: 10) {
                    Text(tr("第 \(index + 1) 个"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    roundStep("minus", enabled: minutes > CountdownRun.presetRange.lowerBound) {
                        setPreset(index, to: CountdownRun.stepping(minutes, up: false))
                    }
                    Button { start(duration: Double(minutes * 60)) } label: {
                        Text(CountdownRun.lengthText(Double(minutes * 60)))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
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

    private func roundStep(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.12)))
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
