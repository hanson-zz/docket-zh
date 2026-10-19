import SwiftUI

/// 倒计时面板：大圆环里的剩余时间，开始、暂停、取消，卡片上三个预设在这里改。
///
/// 状态全部来自 `CountdownRun`，和卡片读同样的键（`deadline`、`paused`、
/// `duration`、`presets`），所以面板和卡片不会说两样。时间到了还没人点停时，
/// 面板上的主按钮就是“停”。
struct CountdownDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // 面板的 context 只在打开那一刻取一次，靠这个每秒刷新。
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private func content(now: Date) -> some View {
        let total = CountdownRun.duration(instance.config)
        let phase: CountdownRun.Phase = context.isPreview ? .idle : CountdownRun.phase(instance.config, now: now)
        let (left, fraction) = Self.reading(phase, total: total)

        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, 1 - fraction)))
                        .stroke(panelTint.accent(or: .white.opacity(0.8)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(isRinging(phase) ? tr("时间到") : docketClockString(left))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetStyle.primary)
                            .rollingValue(Int(left.rounded(.up)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(caption(phase, duration: total))
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 22)
                }
                .frame(width: 176, height: 176)
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    ClockPanelButton(title: primaryTitle(phase), fill: panelTint.accent(or: .white.opacity(0.24)),
                                     ink: panelTint.ink(or: .white)) {
                        primary(phase, duration: total)
                    }
                    ClockPanelButton(title: tr("取消"), fill: nil, action: cancel)
                        .disabled(phase == .idle)
                        .opacity(phase == .idle ? 0.4 : 1)
                }

                presetEditor
            }
        }
    }

    /// The countdown's catalog colour, the one its tile is drawn in.
    private var accent: Color {
        panelTint.accent(or: Color(hex: WidgetCatalog.accentHex(.countdown) ?? PaletteColor.indigo.hex))
    }

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

    // MARK: Pieces

    /// 卡片上的三个预设：点数字开始，加减号改分钟。
    private var presetEditor: some View {
        let presets = CountdownRun.presets(instance.config)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("卡片上的预设"))
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 6) {
                ForEach(Array(presets.enumerated()), id: \.offset) { index, minutes in
                    HStack(spacing: 2) {
                        stepButton("minus", enabled: minutes > CountdownRun.presetRange.lowerBound) {
                            setPreset(index, to: minutes - step(minutes, down: true))
                        }
                        Button { start(duration: Double(minutes * 60)) } label: {
                            Text(CountdownRun.presetLabel(minutes))
                                .font(WidgetStyle.label(11))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("开始 \(minutes) 分钟倒计时"))
                        stepButton("plus", enabled: minutes < CountdownRun.presetRange.upperBound) {
                            setPreset(index, to: minutes + step(minutes, down: false))
                        }
                    }
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.8 : 0.3))
                .frame(width: 16, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? tr("加一点") : tr("减一点"))
    }

    /// 10 分钟以内一分钟一档，再往上五分钟一档。
    private func step(_ minutes: Int, down: Bool) -> Int {
        (down ? minutes > 10 : minutes >= 10) ? 5 : 1
    }

    private func caption(_ phase: CountdownRun.Phase, duration: TimeInterval) -> String {
        let name = instance.config.string("name")
        let title = name.isEmpty ? tr("倒计时") : name
        switch phase {
        case .idle:
            return "\(title) · \(CountdownRun.lengthText(duration))"
        case .paused:
            return tr("已暂停 · \(title)")
        case .ringing:
            return tr("\(title) \(CountdownRun.lengthText(duration))")
        case .running(let left, _):
            let ends = Date.now.addingTimeInterval(left).formatted(.dateTime.hour().minute())
            return tr("\(title) · \(ends) 结束")
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
        let list = CountdownRun.settingPreset(index, to: minutes, in: instance.config)
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
