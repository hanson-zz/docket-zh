import SwiftUI

// MARK: - 桌面卡片 · 时间组：专注计时、倒计时、闹钟
//
// 入口和共用零件见 DesktopCardsTime.swift。

// MARK: - 专注计时

/// 专注计时：整个码头一个计时器（`TimerStateProvider`），两边同一份。环随这一段走空，
/// 环心大字剩余时间；开始 / 暂停直接点，中号大号加重置，大号再写正在做的事和今天专注了多久。
/// 颜色跟扩展栏卡片：颜色面板选过用选的，否则设置里的专注颜色。液态外观画液态水。
struct TimeDeskFocusCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private func tint(_ state: TimerState) -> Color {
        guard let palette = WidgetTint.timerPalette(WidgetTint.shownChoice(widget.config, unlocked: ProAccess.isUnlocked),
                                                     session: state.color) else { return .accentColor }
        return Color(code: WidgetTint.readable(palette.main, dark: scheme == .dark))
    }

    private var title: String { WidgetCatalog.entry(.timer)?.name ?? tr("专注计时") }

    var body: some View {
        let state = TimerStateProvider.shared.state
        let remaining = DesktopTimeCards.focusRemaining(state, now: now)
        let left = remaining.left
        let total = remaining.total
        let running = left > 0 && state.paused == nil && state.deadline != nil
        let standUp = FocusCycle.showsStandUp(state)
        let color = standUp ? Color.timerGreen : tint(state)
        switch size {
        case .small:
            ZStack {
                dial(state, left: left, total: total, color: color, running: running, lineWidth: 9)
                    .frame(width: 118, height: 118)
                VStack(spacing: 2) {
                    Text(docketClockString(left))
                        .font(timeDeskNumber(28))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(standUp ? tr("站起来走走") : state.phase.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 90)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                TimeDeskRoundButton(symbol: running ? "pause.fill" : "play.fill",
                                    label: running ? tr("暂停专注计时") : tr("开始专注计时"),
                                    diameter: 34, prominent: true) { toggle() }
                    .padding(10)
            }
        case .medium:
            HStack(spacing: 18) {
                ZStack {
                    dial(state, left: left, total: total, color: color, running: running, lineWidth: 9)
                    roundDots(state, color: color)
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(FocusCycle.caption(state))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(standUp ? Color.timerGreen.panelReadable : Color.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(docketClockString(left))
                        .font(timeDeskNumber(42))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        TimeDeskPill(title: primaryTitle(state, left: left), symbol: running ? "pause.fill" : "play.fill",
                                     prominent: true) { toggle() }
                        TimeDeskRoundButton(symbol: "arrow.counterclockwise", label: tr("重置"), diameter: 32) { reset() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesktopCardsTime.inset(size))
        case .large:
            VStack(spacing: 12) {
                TimeDeskHeader(symbol: "timer", title: title, tint: color) {
                    Text(FocusCycle.caption(state))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(standUp ? Color.timerGreen.panelReadable : Color.panelSecondary)
                        .lineLimit(1)
                }
                ZStack {
                    dial(state, left: left, total: total, color: color, running: running, lineWidth: 12)
                    VStack(spacing: 4) {
                        Text(docketClockString(left))
                            .font(timeDeskNumber(44))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(taskLine(state, standUp: standUp))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        roundDots(state, color: color)
                            .padding(.top, 2)
                    }
                    .frame(width: 132)
                }
                .frame(width: 172, height: 172)
                HStack(spacing: 8) {
                    TimeDeskPill(title: tr("重置"), symbol: "arrow.counterclockwise", height: 36) { reset() }
                    TimeDeskPill(title: primaryTitle(state, left: left), symbol: running ? "pause.fill" : "play.fill",
                                 prominent: true, height: 36) { toggle() }
                }
                Text(todayLine())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    @ViewBuilder
    private func dial(_ state: TimerState, left: TimeInterval, total: TimeInterval, color: Color,
                      running: Bool, lineWidth: CGFloat) -> some View {
        if LiquidMotion.timerLook(widget.config) == .liquid {
            let golden = LiquidMotion.timerGolden(secondsSinceEnd: state.deadline.map { now.timeIntervalSince($0) })
            LiquidWater(level: LiquidMotion.timerLevel(remaining: left, total: total),
                        tint: color, shape: .circle, visible: true,
                        still: !running && !golden, golden: golden)
                .opacity(0.9)
        } else {
            TimeDeskRing(fraction: left / total, tint: color, lineWidth: lineWidth)
        }
    }

    /// 第几轮：一组几轮就几颗，做到第几轮亮到第几颗。
    private func roundDots(_ state: TimerState, color: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<FocusCycle.dotCount(state), id: \.self) { index in
                Circle()
                    .fill(index < FocusCycle.litDots(state) ? color.panelGraphic : Color.panelTrack)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func primaryTitle(_ state: TimerState, left: TimeInterval) -> String {
        guard left > 0 else { return tr("开始") }
        if state.paused != nil { return tr("继续") }
        return state.deadline == nil ? tr("开始") : tr("暂停")
    }

    private func taskLine(_ state: TimerState, standUp: Bool) -> String {
        if standUp { return tr("站起来走走") }
        let task = state.task.trimmingCharacters(in: .whitespacesAndNewlines)
        return task.isEmpty ? state.phase.label : task
    }

    private func todayLine() -> String {
        let minutes = FocusLog.minutes(FocusLogStore.shared.lines)[HabitTracker.dayKey(now)] ?? 0
        return tr("今天") + " " + FocusDay.focusedText(minutes: minutes)
    }

    private func toggle() {
        commit(DesktopTimeCards.focusToggled(TimerStateProvider.shared.state, now: .now))
    }

    private func reset() {
        commit(DesktopTimeCards.focusReset(TimerStateProvider.shared.state))
    }

    private func commit(_ state: TimerState) {
        withAnimation(.snappy(duration: 0.3)) { TimerStateProvider.shared.state = state }
        FocusAmbientDriver.shared.sync(state)
    }
}

// MARK: - 倒计时

/// 倒计时：没开始时预设一点就开始（上次用的高亮），跑着大数字 + 进度 + 暂停，
/// 到点整张卡片变色、点一下停。大号下面再列别的计时器和日期倒计时。
struct TimeDeskCountdownCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        DesktopCardsTime.accent(widget, own: Color.timerOrange, dark: scheme == .dark)
    }

    private var focus: CountdownList.Focus { CountdownList.focus(widget.config, now: now) }

    private var timer: CountdownTimer {
        if case .timer(let timer) = focus { return timer }
        return CountdownList.main(widget.config)
    }

    private var nearestDate: (date: CountdownDate, days: Int)? {
        if case .date(let date, let days) = focus { return (date, days) }
        return nil
    }

    private var lastLine: String {
        tr("上次 \(CountdownRun.lengthText(CountdownRun.duration(widget.config)))")
    }

    var body: some View {
        let timer = self.timer
        let phase = CountdownList.phase(timer, now: now)
        if case .ringing = phase {
            ringing(timer, phase: phase)
        } else {
            switch size {
            case .small: small(timer, phase: phase)
            case .medium: medium(timer, phase: phase)
            case .large: large(timer, phase: phase)
            }
        }
    }

    // MARK: 小号

    @ViewBuilder
    private func small(_ timer: CountdownTimer, phase: CountdownRun.Phase) -> some View {
        VStack(spacing: 8) {
            TimeDeskHeader(symbol: "hourglass", title: timer.title, tint: accent)
            switch phase {
            case .running(let left, let fraction), .paused(let left, let fraction):
                let paused = isPaused(phase)
                Spacer(minLength: 0)
                Text(docketClockString(left))
                    .font(timeDeskNumber(38))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary.opacity(paused ? 0.6 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                TimeDeskBar(fraction: fraction, tint: accent, height: 5)
                Spacer(minLength: 0)
                TimeDeskPill(title: paused ? tr("继续") : tr("暂停"), symbol: paused ? "play.fill" : "pause.fill",
                             prominent: !paused, height: 34) { paused ? resume(timer) : pause(timer) }
            default:
                if let nearest = nearestDate {
                    dateLine(nearest)
                } else {
                    Text(lastLine)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                presets(columns: 2, rowsLimit: 2, height: 32)
            }
        }
        .padding(DesktopCardsTime.inset(.small))
    }

    // MARK: 中号

    @ViewBuilder
    private func medium(_ timer: CountdownTimer, phase: CountdownRun.Phase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .running(let left, let fraction), .paused(let left, let fraction):
                running(timer, left: left, fraction: fraction, paused: isPaused(phase), figure: 40)
            default:
                TimeDeskHeader(symbol: "hourglass", title: timer.title, tint: accent) {
                    if let nearest = nearestDate {
                        Text("\(nearest.date.title) · \(CountdownList.daysText(nearest.days))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(lastLine)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(tr("点一个就开始"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                presets(columns: 3, rowsLimit: 1, height: 46)
            }
        }
        .padding(DesktopCardsTime.inset(.medium))
    }

    /// 跑着 / 暂停：说明、大数字、进度条、操作一排（暂停或继续、+1 分、取消）。
    private func running(_ timer: CountdownTimer, left: TimeInterval, fraction: Double, paused: Bool,
                         figure: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TimeDeskHeader(symbol: "hourglass", title: timer.title, tint: accent) {
                Text(paused ? tr("已暂停") : tr("共 \(CountdownRun.lengthText(timer.duration))"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(paused ? accent.panelReadable : Color.panelSecondary)
                    .lineLimit(1)
            }
            Text(docketClockString(left))
                .font(timeDeskNumber(figure))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary.opacity(paused ? 0.6 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            TimeDeskBar(fraction: fraction, tint: accent, height: 6)
            HStack(spacing: 8) {
                TimeDeskPill(title: paused ? tr("继续") : tr("暂停"), symbol: paused ? "play.fill" : "pause.fill",
                             prominent: true) { paused ? resume(timer) : pause(timer) }
                TimeDeskPill(title: tr("+1 分")) { change(timer.id) { CountdownList.adding(60, to: $0, now: .now) } }
                TimeDeskPill(title: tr("取消")) { change(timer.id) { CountdownList.stopping($0) } }
            }
        }
    }

    // MARK: 大号

    @ViewBuilder
    private func large(_ timer: CountdownTimer, phase: CountdownRun.Phase) -> some View {
        let rows = DesktopTimeCards.countdownRows(widget.config, now: now, shown: timer.id,
                                                  limit: DesktopTimeCards.rows(.countdown, .large))
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .running(let left, let fraction), .paused(let left, let fraction):
                running(timer, left: left, fraction: fraction, paused: isPaused(phase), figure: 52)
            default:
                TimeDeskHeader(symbol: "hourglass", title: timer.title, tint: accent) {
                    Text(lastLine)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
                Text(tr("点一个就开始"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                presets(columns: 3, rowsLimit: 1, height: 52)
            }
            TimeDeskRule()
            if rows.isEmpty {
                Text(tr("在面板里可以再加计时器和日期倒计时"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows, id: \.id) { row in otherRow(row) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(DesktopCardsTime.inset(.large))
    }

    @ViewBuilder
    private func otherRow(_ row: DesktopTimeCards.CountdownRow) -> some View {
        switch row {
        case .timer(let item):
            let phase = CountdownList.phase(item, now: now)
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                switch phase {
                case .running(let left, _), .paused(let left, _):
                    let paused = isPaused(phase)
                    Text(docketClockString(left))
                        .font(timeDeskNumber(17))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary.opacity(paused ? 0.6 : 1))
                    TimeDeskRoundButton(symbol: paused ? "play.fill" : "pause.fill",
                                        label: paused ? tr("继续倒计时") : tr("暂停倒计时"), diameter: 30) {
                        paused ? resume(item) : pause(item)
                    }
                case .ringing:
                    TimeDeskPill(title: tr("停"), highlight: accent, height: 30) {
                        change(item.id) { CountdownList.stopping($0) }
                    }
                    .frame(width: 64)
                case .idle:
                    Text(CountdownRun.lengthText(item.duration))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                    TimeDeskRoundButton(symbol: "play.fill", label: tr("开始倒计时"), diameter: 30) {
                        change(item.id) { CountdownList.starting($0, duration: $0.duration, now: .now) }
                    }
                }
            }
            .frame(height: 34)
        case .date(let item, let days):
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(CountdownList.dateText(item))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Text(CountdownList.daysText(days))
                    .font(timeDeskNumber(17))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
            }
            .frame(height: 34)
        }
    }

    // MARK: 到点

    /// 整张卡片是「停」：主题色淡底，大字「时间到」，减少动态效果时不晃。
    private func ringing(_ timer: CountdownTimer, phase: CountdownRun.Phase) -> some View {
        let shakes = CountdownRun.shakes(phase, reduceMotion: reduceMotion)
        return Button { change(timer.id) { CountdownList.stopping($0) } } label: {
            VStack(spacing: size == .small ? 6 : 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: size == .small ? 24 : 32, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
                    .symbolEffect(.variableColor.iterative, isActive: shakes)
                Text(tr("时间到"))
                    .font(.system(size: size == .small ? 26 : 38, weight: .heavy))
                    .foregroundStyle(Color.panelPrimary)
                Text(verbatim: "\(timer.title) \(CountdownRun.lengthText(timer.duration))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                Text(tr("点一下停"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.panelOnPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.panelPrimary))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(accent.opacity(scheme == .dark ? 0.26 : 0.2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .timerShake(shakes)
        .accessibilityLabel(tr("时间到，点按停止"))
    }

    // MARK: 零件

    private func isPaused(_ phase: CountdownRun.Phase) -> Bool {
        if case .paused = phase { return true }
        return false
    }

    private func dateLine(_ nearest: (date: CountdownDate, days: Int)) -> some View {
        HStack(spacing: 4) {
            Text(nearest.date.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(CountdownList.daysShort(nearest.days))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
        }
    }

    /// 预设按钮：上次用的那个高亮。
    private func presets(columns: Int, rowsLimit: Int, height: CGFloat) -> some View {
        let list = Array(CountdownRun.presets(widget.config).prefix(columns * rowsLimit))
        let last = CountdownRun.lastPresetIndex(widget.config)
        let grid = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        return LazyVGrid(columns: grid, spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, minutes in
                TimeDeskPill(title: CountdownRun.presetLabel(minutes), highlight: index == last ? accent : nil,
                             height: height, fontSize: height > 40 ? 17 : 14) {
                    change(CountdownList.mainID) {
                        CountdownList.starting($0, duration: Double(minutes * 60), now: .now)
                    }
                }
                .accessibilityLabel(tr("开始 \(minutes) 分钟倒计时"))
            }
        }
    }

    private func pause(_ timer: CountdownTimer) { change(timer.id) { CountdownList.pausing($0, now: .now) } }
    private func resume(_ timer: CountdownTimer) { change(timer.id) { CountdownList.resuming($0, now: .now) } }

    private func change(_ id: String, _ transform: @escaping (CountdownTimer) -> CountdownTimer) {
        DesktopCardsTime.write(widget) { config in
            CountdownList.update(id, in: &config) { $0 = transform($0) }
        }
    }
}

// MARK: - 闹钟

/// 闹钟：下一个最醒目（大字时刻、名字、还有多久），铃铛点一下开关它。中号右边后面两个，
/// 大号列出其余闹钟，每个带开关。正在响时稍后和关掉直接在卡片上按。
struct TimeDeskAlarmCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        DesktopCardsTime.accent(widget, own: Color.timerOrange, dark: scheme == .dark)
    }

    private var config: WidgetConfig { widget.config }

    var body: some View {
        if let ringing = AlarmBook.ringing(config, now: now) {
            ringingView(ringing.item)
        } else if AlarmBook.items(config).isEmpty {
            TimeDeskEmpty(symbol: "alarm", title: tr("还没有闹钟"), hint: tr("在扩展栏的闹钟面板里添加"))
        } else {
            let headline = AlarmBook.headline(config, now: now)
            switch size {
            case .small:
                VStack(alignment: .leading, spacing: 6) {
                    bell(headline, diameter: 34)
                    Spacer(minLength: 0)
                    if let headline { hero(headline, figure: 36, compact: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesktopCardsTime.inset(size))
            case .medium:
                let rows = DesktopTimeCards.alarmRows(config, now: now, limit: DesktopTimeCards.rows(.alarm, .medium),
                                                      excluding: headline?.id)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        bell(headline, diameter: 34)
                        if let headline { hero(headline, figure: 38, compact: false) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !rows.isEmpty {
                        TimeDeskRule(vertical: true).padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("接下来"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelSecondary)
                            ForEach(rows, id: \.item.id) { row in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.item.time)
                                        .font(timeDeskNumber(19))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.panelPrimary)
                                    Text(row.item.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.panelSecondary)
                                        .lineLimit(1)
                                }
                                .opacity(row.live ? 1 : 0.5)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 112, alignment: .leading)
                    }
                }
                .padding(DesktopCardsTime.inset(size))
            case .large:
                let rows = DesktopTimeCards.alarmRows(config, now: now, limit: DesktopTimeCards.rows(.alarm, .large),
                                                      excluding: headline?.id)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        if let headline { hero(headline, figure: 50, compact: false) }
                        Spacer(minLength: 8)
                        bell(headline, diameter: 40)
                    }
                    TimeDeskRule()
                    if rows.isEmpty {
                        Text(tr("只有这一个闹钟"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(rows, id: \.item.id) { row in alarmRow(row) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(DesktopCardsTime.inset(size))
            }
        }
    }

    /// 核心：时刻大字、名字、还有多久（关着写已关闭）。
    private func hero(_ item: AlarmItem, figure: CGFloat, compact: Bool) -> some View {
        let live = AlarmBook.isLive(item, config: config, now: now)
        let at = AlarmBook.nextRing(item, config: config, now: now)
        return VStack(alignment: .leading, spacing: 2) {
            Text(AlarmBook.clockText(at))
                .font(timeDeskNumber(figure))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(item.title)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(live ? AlarmBook.untilText(at, now: now) : tr("已关闭"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(live ? accent.panelReadable : Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .opacity(live ? 1 : 0.6)
    }

    /// 铃铛：开着是主题色铃铛，关着是划掉的灰铃铛，点它开关核心那个。
    @ViewBuilder
    private func bell(_ headline: AlarmItem?, diameter: CGFloat) -> some View {
        if let headline {
            let live = AlarmBook.isLive(headline, config: config, now: now)
            Button { setEnabled(headline, !live) } label: {
                Image(systemName: live ? "alarm.fill" : "alarm.slash.fill")
                    .font(.system(size: diameter * 0.45, weight: .semibold))
                    .foregroundStyle(live ? accent.panelReadable : Color.panelSecondary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(live ? accent.opacity(0.16) : Color.panelFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(live ? tr("关闭") : tr("开启"))
            .accessibilityLabel(tr("\(live ? tr("关闭") : tr("开启")) \(headline.time) 的闹钟"))
        }
    }

    private func alarmRow(_ row: DesktopTimeCards.AlarmRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.item.time)
                        .font(timeDeskNumber(22))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                    Text(row.item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                }
                Text(AlarmBook.repeatText(row.item.repeats, minutes: row.item.minutes, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
            .opacity(row.live ? 1 : 0.5)
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { row.live }, set: { setEnabled(row.item, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(accent)
                .accessibilityLabel(tr("\(row.live ? tr("关闭") : tr("开启")) \(row.item.time) 的闹钟"))
        }
        .frame(height: 44)
    }

    private func ringingView(_ item: AlarmItem) -> some View {
        VStack(spacing: size == .small ? 5 : 10) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: size == .small ? 20 : 30, weight: .semibold))
                .foregroundStyle(accent.panelReadable)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(item.time)
                .font(timeDeskNumber(size == .small ? 30 : 46))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
            Text(item.title)
                .font(.system(size: size == .small ? 13 : 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            HStack(spacing: size == .small ? 6 : 8) {
                TimeDeskPill(title: size == .small ? tr("稍后") : tr("稍后 \(AlarmBook.snoozeMinutes) 分钟"),
                             height: size == .small ? 32 : 36) {
                    write { AlarmBook.snooze(item.id, in: &$0, now: .now) }
                }
                TimeDeskPill(title: tr("关掉"), prominent: true, height: size == .small ? 32 : 36) {
                    write { AlarmBook.dismiss(item.id, in: &$0, now: .now) }
                }
            }
        }
        .padding(DesktopCardsTime.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(accent.opacity(scheme == .dark ? 0.26 : 0.2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("\(item.time) \(item.title) 正在响"))
    }

    private func setEnabled(_ item: AlarmItem, _ on: Bool) {
        write { AlarmBook.setEnabled(item.id, on, in: &$0, now: .now) }
    }

    /// 旧的单个闹钟第一次改动时顺手写成列表（同扩展栏卡片）。
    private func write(_ change: @escaping (inout WidgetConfig) -> Void) {
        DesktopCardsTime.write(widget) { config in
            if AlarmBook.isLegacy(config) { AlarmBook.store(AlarmBook.items(config), in: &config) }
            change(&config)
        }
    }
}
