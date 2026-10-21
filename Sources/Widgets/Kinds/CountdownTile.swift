import SwiftUI

/// 倒计时：管“几分钟内”的事，泡面、晾衣服、等会议。
///
/// 三种样子，都由 `CountdownRun` 判断：
/// - 没开始：名字、“上次 5 分钟”，下面三个预设，点一个就开始，上次用的那个高亮。
///   预设在面板里改。
/// - 正在跑：大数字、“泡面 · 共 3 分钟”、一条细进度条，右边暂停。暂停后是继续和取消。
/// - 时间到：卡片变橙、左右晃一阵，点卡片任何地方就停。打开“减少动态效果”时
///   不晃，只变色。提示音和到点弹出的卡片由 `TimedAlertDriver` 管，扩展栏隐藏、
///   卡片不在当前布局也照样响。
///
/// 平时卡片的点按留给码头（打开面板），按钮都只有自己那么大；只有到点时整张卡片
/// 是“停”，这时候要的就是随手一点就安静。
///
/// 结束时刻存在小组件自己的配置里（`deadline`），重启后照样接着数。
///
/// 一张卡片可以同时跑几个计时器，还可以有几个日期倒计时（都在面板里加）。卡片只
/// 显示最近的一个（`CountdownList.focus`）：在响的、最快到点的、暂停的；计时器
/// 都没开始时头上写最近的那个日期还有几天，下面仍是三个预设。
struct CountdownTile: View {
    /// 颜色面板里选的主题色（`WidgetTintStyle`），选过颜色时原来写死的强调色跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 原来的强调色，选过颜色就换成选的。
    private var accent: Color { theme.chosen(or: Color.timerOrange, dark: scheme == .dark) }
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 设置里的“数字外观”选了折叠翻页。
    private var folding: Bool { FoldFlip.countdownLook(instance.config) == .fold }

    private var focus: CountdownList.Focus {
        if context.isPreview { return .idle }
        return CountdownList.focus(instance.config, now: context.now)
    }

    /// 卡片现在显示的计时器：最近的那个；都没开始时是第一个（三个预设开始的就是它）。
    private var timer: CountdownTimer {
        if case .timer(let timer) = focus { return timer }
        return CountdownList.main(instance.config)
    }

    private var phase: CountdownRun.Phase {
        if context.isPreview { return .idle }
        return CountdownList.phase(timer, now: context.now)
    }

    private var title: String { timer.title }

    /// 都没开始时最近的那个日期倒计时。
    private var nearestDate: (date: CountdownDate, days: Int)? {
        if case .date(let date, let days) = focus { return (date, days) }
        return nil
    }

    /// 除了显示的这个，还有几个计时器在跑或暂停。
    private var othersActive: Int {
        context.isPreview ? 0 : max(0, CountdownList.activeCount(instance.config, now: context.now) - 1)
    }

    var body: some View {
        let phase = self.phase
        Group {
            if case .ringing = phase {
                ringingCard(phase)
            } else {
                WidgetSurface {
                    if context.position.isVertical {
                        column(phase)
                    } else {
                        switch phase {
                        case .idle: idleRow
                        case .running(let left, let fraction): runningRow(left: left, fraction: fraction, paused: false)
                        case .paused(let left, let fraction): runningRow(left: left, fraction: fraction, paused: true)
                        case .ringing: EmptyView()
                        }
                    }
                }
            }
        }
    }

    // MARK: 横排（168 × 58）

    /// 名字和上次的时长一行，三个预设一行。
    private var idleRow: some View {
        let presets = CountdownRun.presets(instance.config)
        let last = CountdownRun.lastPresetIndex(instance.config)
        return VStack(alignment: .leading, spacing: 5) {
            if let nearest = nearestDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(nearest.date.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(CountdownList.daysText(nearest.days))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(tr("上次 \(CountdownRun.lengthText(CountdownRun.duration(instance.config)))"))
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetStyle.secondary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(spacing: 5) {
                ForEach(Array(presets.enumerated()), id: \.offset) { index, minutes in
                    TimerPill(title: CountdownRun.presetLabel(minutes), size: 13, height: 22,
                              tint: index == last ? accent : nil, minWidth: 40,
                              action: context.isPreview ? nil : { start(minutes: minutes) })
                        .accessibilityLabel(tr("开始 \(minutes) 分钟倒计时"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 大数字和说明，右边暂停（或继续、取消），底下一条细进度条。
    private func runningRow(left: TimeInterval, fraction: Double, paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    reading(left, size: 21, maxWidth: 96)
                    Text(runningCaption(paused: paused))
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if paused {
                    TileGlyph(symbol: "xmark", size: 10, tint: WidgetStyle.secondary,
                              action: context.isPreview ? nil : (cancel as () -> Void))
                        .accessibilityLabel(tr("取消倒计时"))
                }
                TileGlyph(symbol: paused ? "play.fill" : "pause.fill", size: 11, morphs: true,
                          action: context.isPreview ? nil : ((paused ? resume : pause) as () -> Void))
                    .accessibilityLabel(paused ? tr("继续倒计时") : tr("暂停倒计时"))
            }
            progressBar(fraction, height: 2.5)
        }
    }

    /// 到点：整张卡片是“停”按钮。
    private func ringingCard(_ phase: CountdownRun.Phase) -> some View {
        let shakes = CountdownRun.shakes(phase, reduceMotion: reduceMotion)
        return Button(action: stop) {
            WidgetSurface(fill: accent.opacity(0.32)) {
                if context.position.isVertical {
                    VStack(spacing: 3) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(tr("时间到"))
                            .font(.system(size: 14, weight: .heavy))
                        Text(tr("点一下停"))
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .foregroundStyle(WidgetStyle.primary)
                } else {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("时间到"))
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(WidgetStyle.primary)
                            Text(tr("\(title) \(CountdownRun.lengthText(timer.duration))"))
                                .font(.system(size: 13))
                                .foregroundStyle(WidgetStyle.primary.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 3) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WidgetStyle.primary.opacity(0.9))
                                .symbolEffect(.variableColor.iterative, isActive: shakes)
                            TimerPill(title: tr("点一下停"), size: 13, height: 20, action: nil)
                        }
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .timerShake(shakes)
        .accessibilityLabel(tr("时间到，点按停止"))
    }

    // MARK: 竖排（76 × 62）

    private func column(_ phase: CountdownRun.Phase) -> some View {
        VStack(spacing: 2) {
            switch phase {
            case .idle, .ringing:
                Text(nearestDate?.date.title ?? title)
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let nearest = nearestDate {
                    Text(CountdownList.daysShort(nearest.days))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // 竖排放不下三个，只放前两个；有日期倒计时时只放一个。
                VStack(spacing: 3) {
                    ForEach(CountdownRun.presets(instance.config).prefix(nearestDate == nil ? 2 : 1), id: \.self) { minutes in
                        TimerPill(title: CountdownRun.presetLabel(minutes), size: 10, height: 17, minWidth: 44,
                                  action: context.isPreview ? nil : { start(minutes: minutes) })
                    }
                }
            case .running(let left, let fraction):
                columnRun(left: left, fraction: fraction, paused: false)
            case .paused(let left, let fraction):
                columnRun(left: left, fraction: fraction, paused: true)
            }
        }
    }

    private func columnRun(left: TimeInterval, fraction: Double, paused: Bool) -> some View {
        VStack(spacing: 3) {
            reading(left, size: 17, maxWidth: 58)
            progressBar(fraction, height: 2)
                .padding(.horizontal, 4)
            TileGlyph(symbol: paused ? "play.fill" : "pause.fill", size: 9,
                      action: context.isPreview ? nil : ((paused ? resume : pause) as () -> Void))
        }
    }

    // MARK: 零件

    @ViewBuilder
    private func reading(_ left: TimeInterval, size: CGFloat, maxWidth: CGFloat) -> some View {
        if folding {
            FoldFlipText(text: docketClockString(left), size: size * 0.82, maxWidth: maxWidth)
        } else {
            Text(docketClockString(left))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
                .rollingValue(Int(left.rounded(.up)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func progressBar(_ fraction: Double, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.primary.opacity(0.12))
                Capsule().fill(accent)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    // MARK: 动作

    /// 跑着时的说明：“泡面 · 共 3 分钟”，暂停时“已暂停 · 泡面”；还有别的计时器在跑时
    /// 后面加“另 2 个”。
    private func runningCaption(paused: Bool) -> String {
        let base = paused ? tr("已暂停 · \(title)") : CountdownRun.runningCaption(name: timer.name, duration: timer.duration)
        return othersActive > 0 ? tr("\(base) · 另 \(othersActive) 个") : base
    }

    /// 改卡片上显示的那个计时器。
    private func change(_ id: String, _ transform: @escaping (CountdownTimer) -> CountdownTimer) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { config in
                CountdownList.update(id, in: &config) { $0 = transform($0) }
            }
        }
    }

    /// 点预设：第一个计时器记下这次的时长（下次高亮它），马上开始。
    private func start(minutes: Int) {
        let length = Double(minutes * 60)
        change(CountdownList.mainID) { CountdownList.starting($0, duration: length, now: .now) }
    }

    /// 暂停存下还剩多少，继续时从屏幕上的数接着数。
    private func pause() {
        change(timer.id) { CountdownList.pausing($0, now: .now) }
    }

    private func resume() {
        change(timer.id) { CountdownList.resuming($0, now: .now) }
    }

    private func cancel() {
        change(timer.id) { CountdownList.stopping($0) }
    }

    /// 时间到后点一下：回到没开始，三个预设回来。
    private func stop() {
        cancel()
    }
}
