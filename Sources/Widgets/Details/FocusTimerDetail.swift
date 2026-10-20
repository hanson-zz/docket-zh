import SwiftUI

/// 专注计时面板，深色玻璃。浏览态：顶上写这一轮要做的事，中间大进度环（剩余、
/// 第几轮小点、共几分钟），暂停和重置，环境音一行（声音、音量、换），下面是今天的
/// 时间轴（每个完整的番茄一段，正在做的淡一点，白线是现在）和近七天统计，这两样
/// 收在“今天”一段里，默认收起，标题行写今天专注了多久。点“设置”在面板里
/// 直接调专注、短休息、长休息、几轮一组，点最近的任务名沿用，选开始专注时放的
/// 环境音、音量，休息时声音停不停、提不提醒起身。
///
/// 计时器全应用只有一个，所有操作都写 `TimerStateProvider.shared.state`，和卡片一样：
/// 暂停存下剩余的秒数，继续从屏幕上的数字接着走。番茄段见 `FocusDay`，环境音联动见
/// `FocusAmbientDriver`。近七天统计是 Pro，没解锁时只看今天，换成一行 Pro 提示。
struct FocusTimerDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用专注的橙。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var taskFocused: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter || context.isPreview }

    static let focusOrange = Color(hex: "#FF8A5B")
    static let focusInk = Color(hex: "#331002")
    private static let restGreen = Color(hex: "#5BD98A")
    private static let gold = Color(hex: "#F5C451")
    private static let base = Color(hex: "#1D1D21")

    private var accent: Color { panelTint.accent(or: Self.focusOrange) }
    private var ink: Color { panelTint.ink(or: Self.focusInk) }

    var body: some View {
        // 面板的 context 只在打开那一刻取一次，靠这个每秒刷新。
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
        .onAppear { draft = timerState(now: .now).task }
        // 面板关掉时输入框可能还没失去焦点，写了一半的任务名也记下。
        .onDisappear { commitDraft() }
    }

    // MARK: 数据

    /// 小组件库里的示例：专注中第 2 / 4 轮，还剩 18:42，和效果图一样。
    private func timerState(now: Date) -> TimerState {
        guard context.isPreview else { return TimerStateProvider.shared.state }
        var state = TimerState()
        state.completed = 1
        state.duration = 25 * 60
        state.deadline = now.addingTimeInterval(18 * 60 + 42)
        state.task = tr("写第二批面板说明")
        state.recentTasks = [tr("写第二批面板说明"), tr("回邮件"), tr("改图标"), tr("读论文")]
        state.ambient = AmbientSound.rain.rawValue
        return state
    }

    private func content(now: Date) -> some View {
        let state = timerState(now: now)
        return DetailCard {
            ZStack {
                Self.base
                RadialGradient(colors: [accent.opacity(0.13), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 220)
            }
        } content: {
            Group {
                if editing {
                    settings(state)
                } else {
                    browse(state, now: now)
                }
            }
            .animation(.snappy(duration: 0.2), value: editing)
        }
    }

    // MARK: 浏览

    private func browse(_ state: TimerState, now: Date) -> some View {
        let total = max(1, state.duration ?? Double(max(1, state.minutes) * 60))
        let left = Self.remaining(in: state, total: total, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            header(title: tr("专注计时"), subtitle: FocusDay.status(state, now: now)) {
                pillButton(tr("设置"), solid: false) {
                    commitDraft()
                    editing = true
                }
            }
            taskField
            ring(state, left: left, total: total)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                bigButton(primaryTitle(state, left: left), solid: true) { togglePrimary() }
                let untouched = state.deadline == nil && state.paused == nil && state.duration == nil
                bigButton(tr("重置"), solid: false) { reset() }
                    .disabled(untouched)
                    .opacity(untouched ? 0.4 : 1)
            }
            ambientRow(state)
            today(state, now: now)
        }
    }

    private func header<Trailing: View>(title: String, subtitle: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing()
        }
    }

    /// 这一轮要做的事：直接写，回车或点别处就记下。
    private var taskField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextField(tr("这一轮要做什么"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .focused($taskFocused)
                .onSubmit { commitDraft() }
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(taskFocused ? 0.1 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(taskFocused ? accent.opacity(0.9) : Color.white.opacity(0.14),
                                      lineWidth: taskFocused ? 1.2 : 0.6)
                }
        }
        .onChange(of: taskFocused) { _, focused in if !focused { commitDraft() } }
        .accessibilityLabel(tr("任务名"))
    }

    private func ring(_ state: TimerState, left: TimeInterval, total: TimeInterval) -> some View {
        let idle = state.deadline == nil && state.paused == nil
        let resting = state.phase != .focus
        let color = resting ? Self.restGreen : accent
        let round = FocusCycle.round(state)
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: idle ? 1 : min(1, max(0, left / total)))
                .stroke(color.opacity(idle ? 0.35 : 1), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                HStack(spacing: 9) {
                    ForEach(0..<FocusCycle.dotCount(state), id: \.self) { index in
                        Circle()
                            .fill(dotColor(index, round: round, resting: resting, color: color))
                            .frame(width: 9, height: 9)
                    }
                }
                Text(docketClockString(left))
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .rollingValue(Int(left.rounded(.up)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(tr("共 \(Int((total / 60).rounded())) 分钟"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: 158, height: 158)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("剩余 \(docketClockString(left))，\(FocusDay.status(state, now: .now))"))
    }

    /// 做完的轮是强调色，正在专注的这一轮白色，还没到的淡。
    private func dotColor(_ index: Int, round: Int, resting: Bool, color: Color) -> Color {
        if index < round - 1 { return color }
        if index == round - 1 { return resting ? color : Color.white.opacity(0.9) }
        return .white.opacity(0.22)
    }

    private func bigButton(_ title: String, solid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? ink : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if solid {
                        Capsule().fill(accent)
                    } else {
                        Capsule().fill(.white.opacity(0.12))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, solid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? ink : .white)
                .padding(.horizontal, solid ? 15 : 13)
                .frame(height: 28)
                .background {
                    if solid {
                        Capsule().fill(accent)
                    } else {
                        Capsule().fill(.white.opacity(0.12))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 环境音

    /// 环境音一行：选的声音（点一下去设置里换）、音量、“换”轮到下一种。
    private func ambientRow(_ state: TimerState) -> some View {
        let sound = FocusAmbient.sound(state)
        return HStack(spacing: 10) {
            Text(tr("环境音"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize()
            Button {
                commitDraft()
                editing = true
            } label: {
                Text(sound?.title ?? tr("不播放"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(sound == nil ? Color.white.opacity(0.7) : accent)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background {
                        Capsule().fill(sound == nil ? Color.white.opacity(0.08) : accent.opacity(0.2))
                            .overlay(Capsule().strokeBorder(sound == nil ? Color.white.opacity(0.14) : accent.opacity(0.8),
                                                            lineWidth: 0.8))
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(tr("开始专注时自动播放，点一下选别的声音"))
            Slider(value: volumeBinding(state), in: 0...100)
                .controlSize(.small)
                .tint(accent)
                .disabled(sound == nil || context.isPreview)
                .accessibilityLabel(tr("环境音音量"))
            Button {
                update { $0.ambient = FocusAmbient.next(after: $0.ambient).rawValue }
            } label: {
                Text(tr("换"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(minWidth: 24, minHeight: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("换下一种环境音"))
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .glassPane(cornerRadius: 12)
    }

    private func volumeBinding(_ state: TimerState) -> Binding<Double> {
        Binding(
            get: { Double(FocusAmbient.clampVolume(state.ambientVolume)) },
            set: { value in update { $0.ambientVolume = FocusAmbient.clampVolume(Int(value.rounded())) } })
    }

    // MARK: 今天

    private func today(_ state: TimerState, now: Date) -> some View {
        let lines = context.isPreview ? FocusSessionStore.sample(today: now) : FocusSessionStore.shared.lines
        let done = FocusDay.today(lines, now: now)
        let live = FocusDay.live(state, now: now)
        let segments = done + (live.map { [$0] } ?? [])
        let minutes: Int = context.isPreview
            ? Int(done.reduce(0) { $0 + $1.duration } / 60)
            : FocusLog.minutes(FocusLogStore.shared.lines)[HabitTracker.dayKey(now)] ?? 0
        // 面板统一限高后，今天的时间轴和近七天统计收进一段，默认收起：标题行
        // 总在，写着今天专注了多久；展开状态记住。
        return DetailFold(key: DetailPanelSections.foldKey(.timer, "today")) {
            HStack {
                Text(tr("今天"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 8)
                Text(FocusDay.focusedText(minutes: minutes))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(minutes > 0 ? accent : Color.white.opacity(0.62))
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                FocusDayTimeline(segments: segments, now: now, accent: accent)
                Text(FocusDay.footer(done: done.count, live: live != nil))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                history(now: now)
                    .padding(.top, 4)
            }
        }
    }

    /// 近七天统计：Pro 看报告，没解锁时一行提示，点一下弹付费墙。今天的照常看。
    @ViewBuilder
    private func history(now: Date) -> some View {
        if ProLicenseGate.canSeeFocusHistory(unlocked: unlocked) {
            FocusWeeklyReport(accent: accent, now: now, isPreview: context.isPreview)
        } else {
            Button { PaywallWindow.shared.show() } label: {
                HStack(spacing: 8) {
                    Text(tr("近七天专注统计"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(ProFeatures.badgeTitle)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Self.gold)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Self.gold.opacity(0.16))
                        .overlay(Capsule().strokeBorder(Self.gold.opacity(0.55), lineWidth: 0.6)))
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(.rect)
                .glassPane(cornerRadius: 12)
            }
            .buttonStyle(.plain)
            .help(tr("专注历史统计是码头 Pro 专属，免费版只看今天。点一下购买、输入激活码或开始试用。"))
        }
    }

    // MARK: 设置

    private func settings(_ state: TimerState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: tr("专注设置"), subtitle: tr("番茄时长 · 环境音")) {
                pillButton(tr("完成"), solid: true) { editing = false }
            }
            durations(state)

            recentTasks(state)

            sectionLabel(tr("开始专注时播放"))
            soundGrid(state)
            HStack(spacing: 10) {
                Text(tr("音量"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Slider(value: volumeBinding(state), in: 0...100)
                    .controlSize(.small)
                    .tint(accent)
                    .disabled(context.isPreview)
                    .accessibilityLabel(tr("环境音音量"))
            }
            toggleRow(tr("休息时声音停下"), isOn: state.quietOnBreak) { value in update { $0.quietOnBreak = value } }
            toggleRow(tr("休息时提醒起身"), isOn: state.standUp) { value in update { $0.standUp = value } }
        }
    }

    /// 专注、短休息、长休息和几轮一组，一行一个加减。
    private func durations(_ state: TimerState) -> some View {
        VStack(spacing: 0) {
            stepperRow(tr("专注"), text: tr("\(state.work) 分钟"),
                       minus: { $0.work = FocusDay.stepped($0.work, up: false, step: 5, range: FocusDay.workRange) },
                       plus: { $0.work = FocusDay.stepped($0.work, up: true, step: 5, range: FocusDay.workRange) },
                       canMinus: state.work > FocusDay.workRange.lowerBound,
                       canPlus: state.work < FocusDay.workRange.upperBound)
            divider
            stepperRow(tr("短休息"), text: tr("\(state.rest) 分钟"),
                       minus: { $0.rest = FocusDay.stepped($0.rest, up: false, step: 1, range: FocusDay.restRange) },
                       plus: { $0.rest = FocusDay.stepped($0.rest, up: true, step: 1, range: FocusDay.restRange) },
                       canMinus: state.rest > FocusDay.restRange.lowerBound,
                       canPlus: state.rest < FocusDay.restRange.upperBound)
            divider
            stepperRow(tr("长休息"), text: tr("\(state.longBreak) 分钟"),
                       minus: { $0.longBreak = FocusDay.stepped($0.longBreak, up: false, step: 5, range: FocusDay.longRange) },
                       plus: { $0.longBreak = FocusDay.stepped($0.longBreak, up: true, step: 5, range: FocusDay.longRange) },
                       canMinus: state.longBreak > FocusDay.longRange.lowerBound,
                       canPlus: state.longBreak < FocusDay.longRange.upperBound)
            divider
            stepperRow(tr("几轮一组"), text: tr("\(state.sessions) 轮"),
                       minus: { $0.sessions = FocusDay.stepped($0.sessions, up: false, step: 1, range: FocusDay.sessionsRange) },
                       plus: { $0.sessions = FocusDay.stepped($0.sessions, up: true, step: 1, range: FocusDay.sessionsRange) },
                       canMinus: state.sessions > FocusDay.sessionsRange.lowerBound,
                       canPlus: state.sessions < FocusDay.sessionsRange.upperBound)
        }
        .padding(.vertical, 2)
        .glassPane(cornerRadius: 12)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.horizontal, 14)
    }

    private func sectionLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
            Spacer(minLength: 8)
            if let trailing { Text(trailing) }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
    }

    private func stepperRow(_ label: String, text: String,
                            minus: @escaping (inout TimerState) -> Void,
                            plus: @escaping (inout TimerState) -> Void,
                            canMinus: Bool, canPlus: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", enabled: canMinus) { update(minus) }
                    .accessibilityLabel(tr("\(label)减少"))
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                stepButton("plus", enabled: canPlus) { update(plus) }
                    .accessibilityLabel(tr("\(label)增加"))
            }
            .frame(width: 132, height: 30)
            .background(Capsule().fill(.white.opacity(0.08))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6)))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.3))
                .frame(width: 34, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || context.isPreview)
    }

    /// 最近用过的任务名，点一下沿用；右键可以删。没有时写一句说明。
    private func recentTasks(_ state: TimerState) -> some View {
        let recent = state.recentTasks.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel(tr("最近的任务名"), trailing: recent.isEmpty ? nil : tr("点一下沿用"))
            if recent.isEmpty {
                Text(tr("在上面写下任务名，开始专注后会记在这里。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                CityChipFlow(spacing: 6) {
                    ForEach(recent, id: \.self) { task in
                        let chosen = task == state.task
                        Button {
                            draft = task
                            update { $0.task = task }
                        } label: {
                            Text(task)
                                .font(.system(size: 13, weight: chosen ? .bold : .semibold))
                                .foregroundStyle(chosen ? ink : Color.white.opacity(0.88))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .frame(maxWidth: 260)
                                .background {
                                    if chosen {
                                        Capsule().fill(accent)
                                    } else {
                                        Capsule().fill(.white.opacity(0.08))
                                            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(context.isPreview)
                        .contextMenu {
                            Button(tr("从最近中删除")) {
                                update { $0.recentTasks = FocusDay.forgetting(task, in: $0.recentTasks) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 七种环境音加“不播放”，四列两行。
    private func soundGrid(_ state: TimerState) -> some View {
        let choices: [AmbientSound?] = AmbientSound.allCases.map { Optional($0) } + [nil]
        let selected = FocusAmbient.sound(state)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, sound in
                let chosen = sound == selected
                Button {
                    update { $0.ambient = sound?.rawValue ?? "" }
                } label: {
                    Text(sound?.title ?? tr("不播放"))
                        .font(.system(size: 13, weight: chosen ? .bold : .semibold))
                        .foregroundStyle(chosen ? ink : Color.white.opacity(0.88))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(chosen ? accent : Color.white.opacity(0.08))
                                .overlay {
                                    if !chosen {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                                    }
                                }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
    }

    private func toggleRow(_ label: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
            Spacer(minLength: 8)
            Toggle(label, isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassPane(cornerRadius: 12)
    }

    // MARK: 按钮文字

    /// 到 0 的倒计时没什么可继续，写“开始”，按下去就是重新开始。
    private func primaryTitle(_ state: TimerState, left: TimeInterval) -> String {
        guard left > 0 else { return tr("开始") }
        if state.paused != nil { return tr("继续") }
        return state.deadline == nil ? tr("开始") : tr("暂停")
    }

    // MARK: 操作

    private func togglePrimary() {
        guard !context.isPreview else { return }
        commitDraft()
        var state = TimerStateProvider.shared.state
        let now = Date()
        let total = max(1, state.duration ?? Double(state.minutes * 60))
        let left = Self.remaining(in: state, total: total, now: now)
        if state.deadline != nil, left > 0 {
            state.paused = left
            state.deadline = nil
        } else {
            // 开始时把长度钉住，设置里改了时长也不会把正在走的倒计时缩放。
            state.duration = total
            state.deadline = now.addingTimeInterval(left > 0 ? left : total)
            state.paused = nil
            if state.phase == .focus {
                state.recentTasks = FocusDay.remembering(state.task, in: state.recentTasks)
            }
        }
        commit(state)
    }

    /// 连钉住的长度一起清掉，重置后用设置里现在的时长。
    private func reset() {
        guard !context.isPreview else { return }
        var state = TimerStateProvider.shared.state
        state.deadline = nil
        state.paused = nil
        state.duration = nil
        commit(state)
    }

    /// 输入框里的任务名记下来。和现在存的一样就不写。
    private func commitDraft() {
        guard !context.isPreview else { return }
        let clean = FocusDay.cleanTask(draft)
        if draft != clean { draft = clean }
        guard TimerStateProvider.shared.state.task != clean else { return }
        update { $0.task = clean }
    }

    private func update(_ change: (inout TimerState) -> Void) {
        guard !context.isPreview else { return }
        var state = TimerStateProvider.shared.state
        change(&state)
        guard state != TimerStateProvider.shared.state else { return }
        commit(state)
    }

    private func commit(_ state: TimerState) {
        withAnimation(.snappy(duration: 0.3)) { TimerStateProvider.shared.state = state }
        FocusAmbientDriver.shared.sync(state)
    }

    /// 暂停优先于结束时刻；两个都没有时是没开始，停在整段时长上。
    private static func remaining(in state: TimerState, total: TimeInterval, now: Date) -> TimeInterval {
        if let paused = state.paused { return max(0, min(paused, total)) }
        guard let deadline = state.deadline else { return total }
        return max(0, min(deadline.timeIntervalSince(now), total))
    }
}

// MARK: - 今天时间轴

/// 今天的番茄，一段一格，和久坐提醒的时间轴同一种画法：浅色底条，强调色的段，
/// 正在做的那段淡一点，白线是现在，下面整点刻度。默认 8 到 20 点，有更早更晚的往外扩。
struct FocusDayTimeline: View {
    var segments: [FocusDay.Segment]
    var now: Date
    var accent: Color

    private static let barHeight: CGFloat = 18

    var body: some View {
        let window = FocusDay.window(segments, now: now)
        return GeometryReader { geo in
            canvas(window: window, width: geo.size.width)
        }
        .frame(height: Self.barHeight + 34)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("今天完成 \(segments.filter { !$0.live }.count) 个番茄"))
    }

    private func canvas(window: ClosedRange<Int>, width: CGFloat) -> some View {
        let x = { (date: Date) -> CGFloat in CGFloat(FocusDay.fraction(date, window: window)) * width }
        let ticks = FocusDay.ticks(window)
        let span = CGFloat(max(1, window.upperBound - window.lowerBound))
        let nowX = x(now)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: width, height: Self.barHeight)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let left = x(segment.start), right = x(segment.end)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(segment.live ? 0.55 : 1))
                    .frame(width: max(2, right - left - 1.2), height: Self.barHeight)
                    .offset(x: left + 0.6)
                    .help(segment.task.isEmpty ? "" : segment.task)
            }
            Rectangle()
                .fill(.white)
                .frame(width: 1.6, height: Self.barHeight + 10)
                .offset(x: min(width - 0.8, max(0, nowX - 0.8)), y: -5)
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, hour in
                let raw = CGFloat(hour - window.lowerBound) / span * width
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 4)
                    .offset(x: min(width - 1, max(0, raw - 0.5)), y: Self.barHeight + 4)
                let text = "\(hour)"
                let half = CGFloat(text.count) * 13 * 0.3
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: index == 0 ? max(half, raw) : (index == ticks.count - 1 ? min(width - half, raw) : raw),
                              y: Self.barHeight + 20)
            }
        }
        .frame(width: width, height: Self.barHeight + 34, alignment: .topLeading)
    }
}
