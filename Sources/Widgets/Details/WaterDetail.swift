import SwiftUI

/// The day's water: the red panda big, filling toward the goal, with what to
/// drink and how much, today's glasses, the last week and this month, and
/// the goal itself.
///
/// The top half is always there: the character, the tally, the drink chips
/// and the amounts, because logging is what the panel is opened for. The
/// rest sits under three tabs so the panel stays the height of its
/// neighbours: 今天 (the list, with undo), 统计 (seven bars and the month's
/// dots) and 设置 (the character, the goal, the weight suggestion and the
/// reminder hours).
struct WaterDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Tab: Hashable { case today, history, goal }

    @State private var tab: Tab = .today
    @State private var drink: DrinkType = .water
    @State private var customAmount = ""
    @State private var editingCustom = false
    @State private var weightText = ""
    @State private var confirmReset = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case amount, weight }

    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    private var accent: Color { WaterStyle.water }
    private var ounces: Bool { WaterIntake.usesOunces(instance.config) }

    private var days: [WaterDay] {
        context.isPreview ? WaterSamples.days(today: context.now) : WaterIntake.days(instance.config)
    }

    var body: some View {
        // A schedule rather than `context.now`, which is frozen for as long
        // as the panel is open: the day can roll over
        // under an open panel.
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            content(now: context.isPreview ? context.now : tick.date)
        }
        .onAppear {
            let weight = instance.config.double("weight")
            if weight > 0 { weightText = weight.formatted(.number.precision(.fractionLength(0...1))) }
        }
    }

    private func content(now: Date) -> some View {
        let all = days
        let goal = WaterIntake.goal(instance.config)
        let today = WaterIntake.today(all, goal: goal, now: now)
        let streak = WaterIntake.streak(all, goal: goal, today: now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                hero(today, streak: streak)
                drinkChips
                if drink == .custom { factorRow }
                amounts
                Picker("", selection: $tab) {
                    Text("今天").tag(Tab.today)
                    Text("统计").tag(Tab.history)
                    Text("设置").tag(Tab.goal)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                switch tab {
                case .today: entries(today, all: all, now: now)
                case .history: history(all, goal: goal, now: now, streak: streak)
                case .goal: goalSettings(goal)
                }

                WaterWeeklyReport(days: all, goal: goal, ounces: ounces, accent: accent, now: now)
            }
        }
        .animation(.snappy(duration: 0.25), value: tab)
        .animation(.snappy(duration: 0.25), value: drink)
    }

    // MARK: Hero

    private func hero(_ today: WaterDay, streak: Int) -> some View {
        let level = WaterIntake.progress(total: today.total, goal: today.goal)
        let done = today.isMet
        return HStack(alignment: .center, spacing: 14) {
            // Its own animation clock, only while the panel is open: the
            // tile's surface stands still, the panel's moves.
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: context.isPreview)) { tick in
                WaterPanda(character: WaterCharacter.shown(instance.config,
                                                           unlocked: Supporter.isUnlocked || context.isPreview),
                           mood: context.isPreview ? .idle : WaterMood.at(tick.date, config: instance.config),
                           level: level,
                           phase: context.isPreview ? 0.3 : tick.date.timeIntervalSinceReferenceDate,
                           celebrating: done, height: 104)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("今天喝水")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(WaterIntake.percent(total: today.total, goal: today.goal))%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .rollingValue(today.total)
                Text(WaterIntake.tally(total: today.total, goal: today.goal, ounces: ounces))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                Text(done ? "达标啦！小熊猫喝饱了" : WaterIntake.remainingLine(total: today.total, goal: today.goal, ounces: ounces))
                    .font(.system(size: 11))
                    .foregroundStyle(done ? accent.mix(with: .white, by: 0.4) : .white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Label("\(streak) 天", systemImage: "flame.fill")
                .font(WidgetStyle.label(11))
                .foregroundStyle(streak > 0 ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.45))
                .monospacedDigit()
                .help("连续达标 \(streak) 天")
        }
    }

    // MARK: Drinks and amounts

    private var drinkChips: some View {
        HStack(spacing: 4) {
            ForEach(DrinkType.allCases) { type in
                let selected = drink == type
                Button {
                    drink = type
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: type.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(height: 15)
                        Text(type.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? accent.opacity(0.75) : Color.white.opacity(0.08)))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(type == .custom ? "自定义饮品，计入比例可调" : "\(type.title)：按 \(Int((type.factor * 100).rounded()))% 计入")
            }
        }
    }

    private var factor: Double {
        drink == .custom ? WaterIntake.customFactor(instance.config) : drink.factor
    }

    private var factorRow: some View {
        let current = WaterIntake.customFactor(instance.config)
        return Stepper(value: Binding(
            get: { current },
            set: { value in
                guard !context.isPreview else { return }
                WaterLog.set("customFactor", .number(WaterIntake.clampFactor(value)), in: instance)
            }), in: 0.1...1.5, step: 0.1) {
                Text("计入比例 \(Int((current * 100).rounded()))%")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .controlSize(.small)
    }

    private var amounts: some View {
        HStack(spacing: 6) {
            if editingCustom {
                HStack(spacing: 6) {
                    TextField("", text: $customAmount, prompt: Text("毫升"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($focus, equals: .amount)
                        .onSubmit(addCustom)
                    Button("添加", action: addCustom)
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white)
                        .disabled(Int(customAmount) == nil)
                    Button {
                        editingCustom = false
                        customAmount = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .glassPane(cornerRadius: 10)
            } else {
                ForEach(WaterIntake.quickAmounts, id: \.self) { amount in
                    amountButton(title: "+\(WaterIntake.figure(amount, ounces: ounces))") { log(amount) }
                }
                amountButton(title: "自定义") {
                    editingCustom = true
                    focus = .amount
                }
            }
        }
    }

    private func amountButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(.white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    private func log(_ amount: Int) {
        guard !context.isPreview else { return }
        let type = drink
        let share = factor
        withAnimation(.snappy(duration: 0.35)) {
            WaterLog.drink(type, amount: amount, factor: share, in: instance)
        }
    }

    private func addCustom() {
        let typed = Int(customAmount.trimmingCharacters(in: .whitespaces)) ?? 0
        guard typed > 0 else { return }
        // Typed in the unit on show.
        let millilitres = ounces ? Int((Double(typed) * WaterIntake.millilitresPerOunce).rounded()) : typed
        log(min(5000, millilitres))
        customAmount = ""
        editingCustom = false
    }

    // MARK: 今天

    private func entries(_ today: WaterDay, all: [WaterDay], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            schedule(all, now: now)
            HStack {
                Text("\(today.entries.count) 杯")
                    .font(WidgetStyle.label(11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.3)) { WaterLog.undo(instance) }
                } label: {
                    Label("撤销上一杯", systemImage: "arrow.uturn.backward")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(.white.opacity(today.entries.isEmpty ? 0.3 : 0.85))
                }
                .buttonStyle(.plain)
                .disabled(today.entries.isEmpty || context.isPreview)
            }
            if today.entries.isEmpty {
                Text("今天还没喝水。点上面的按钮记一杯，小熊猫就开始装水了。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(today.entries.enumerated().reversed()), id: \.offset) { index, entry in
                            entryRow(entry, index: index)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .scrollIndicators(.automatic)
            }
        }
    }

    // MARK: When

    /// What the old 喝水提醒 showed and the tally does not: when the last
    /// glass went in, and when the next reminder is due, or how long it has
    /// been overdue (the notification only ever says it once).
    private func schedule(_ all: [WaterDay], now: Date) -> some View {
        HStack(spacing: 8) {
            StatChip(label: "上次喝水", value: lastDrinkLine(all, now: now))
            StatChip(label: "下次提醒", value: dueLine(now: now))
        }
    }

    private func lastDrinkLine(_ all: [WaterDay], now: Date) -> String {
        if context.isPreview { return "14:20，40 分钟前" }
        guard let last = WaterIntake.lastDrink(all),
              WaterIntake.calendar.isDate(last, inSameDayAs: now) else { return "今天还没喝" }
        let since = max(0, now.timeIntervalSince(last))
        return since < 60 ? "\(Self.clock(last))，刚刚" : "\(Self.clock(last))，\(Self.spelled(since))前"
    }

    private func dueLine(now: Date) -> String {
        if context.isPreview { return "15:20" }
        switch WaterReminder.due(instance.config, now: now) {
        case .off: return "已关闭"
        case .met(let next): return "达标啦，明天 \(Self.clock(next))"
        case .upcoming(let at):
            let day = WaterIntake.calendar.isDate(at, inSameDayAs: now) ? "" : "明天 "
            return "\(day)\(Self.clock(at))"
        case .overdue(let seconds):
            return seconds >= 60 ? "已超时 \(Self.spelled(seconds))" : "该喝水了"
        }
    }

    private static func clock(_ date: Date) -> String {
        PostureSchedule.clock(WaterIntake.calendar.component(.hour, from: date) * 60
                              + WaterIntake.calendar.component(.minute, from: date))
    }

    /// "45 分钟", "1 小时 30 分钟": a span, not a ticking countdown.
    private static func spelled(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(max(1, minutes)) 分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }

    private func entryRow(_ entry: WaterEntry, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(entry.clock)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            Image(systemName: entry.type.symbol)
                .font(.system(size: 11))
                .foregroundStyle(accent.mix(with: .white, by: 0.35))
                .frame(width: 16)
            Text(entry.type.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Text(WaterIntake.amount(entry.amount, ounces: ounces))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
            if entry.effective != entry.amount {
                Text("计 \(WaterIntake.figure(entry.effective, ounces: ounces))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
            Button {
                guard !context.isPreview else { return }
                withAnimation(.snappy(duration: 0.25)) { WaterLog.remove(at: index, in: instance) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help("删除这一杯")
            .accessibilityLabel("删除 \(entry.clock) 的\(entry.type.title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassPane(cornerRadius: 9)
    }

    // MARK: 统计

    private func history(_ all: [WaterDay], goal: Int, now: Date, streak: Int) -> some View {
        let week = WaterIntake.lastDays(all, goal: goal, today: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatChip(label: "连续达标", value: "\(streak) 天")
                StatChip(label: "本月达标", value: "\(WaterIntake.metCount(all, goal: goal, month: now, today: now)) 天")
                StatChip(label: "7 天平均", value: WaterIntake.amount(week.reduce(0) { $0 + $1.total } / max(1, week.count), ounces: ounces))
            }
            bars(week)
            month(all, goal: goal, now: now)
        }
    }

    /// The last seven days as bars, today last, with the goal as a line.
    private func bars(_ week: [WaterDayReading]) -> some View {
        let height: CGFloat = 70
        return VStack(spacing: 4) {
            ZStack(alignment: .top) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week, id: \.key) { day in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.isMet ? accent.opacity(0.9) : Color.white.opacity(day.total > 0 ? 0.35 : 0.1))
                            .frame(height: max(3, height * day.fraction))
                            .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
                            .overlay(alignment: .top) {
                                if day.isToday {
                                    Circle().fill(.white).frame(width: 4, height: 4).offset(y: -7)
                                        .opacity(day.fraction > 0.9 ? 0 : 1)
                                }
                            }
                            .help("\(day.date.formatted(.dateTime.month().day()))：\(WaterIntake.amount(day.total, ounces: ounces))")
                    }
                }
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: 0.5)
                    .overlay(alignment: .trailing) {
                        Text("目标")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .offset(y: -7)
                    }
            }
            .frame(height: height)
            HStack(spacing: 8) {
                ForEach(week, id: \.key) { day in
                    Text(day.isToday ? "今" : Self.weekdays[weekdayIndex(day.date)])
                        .font(.system(size: 9, weight: day.isToday ? .bold : .semibold))
                        .foregroundStyle(.white.opacity(day.isToday ? 0.9 : 0.5))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    /// 0 for Monday through 6 for Sunday.
    private func weekdayIndex(_ date: Date) -> Int {
        let calendar = WaterIntake.calendar
        return (calendar.component(.weekday, from: date) - 2 + 7) % 7
    }

    /// This month, a dot per day: filled where the goal was met, a ring
    /// filled partway where some water went in.
    private func month(_ all: [WaterDay], goal: Int, now: Date) -> some View {
        let weeks = WaterIntake.monthGrid(all, goal: goal, month: now, today: now)
        let cell: CGFloat = 16
        return VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.year().month(.wide)))
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        Group {
                            if let day = weeks[row][column] {
                                dot(day, size: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func dot(_ day: WaterDayReading, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(day.isMet ? accent.opacity(0.9) : Color.white.opacity(day.isFuture ? 0.03 : 0.08))
            if !day.isMet, day.total > 0 {
                Circle()
                    .trim(from: 0, to: day.fraction)
                    .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
            if day.isToday {
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
            Text("\(day.day)")
                .font(.system(size: 7.5, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(.white.opacity(day.isMet ? 1 : (day.isFuture ? 0.25 : 0.6)))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .help(day.isFuture ? "" : WaterIntake.amount(day.total, ounces: ounces))
    }

    // MARK: 目标

    private func goalSettings(_ goal: Int) -> some View {
        let weight = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let suggestion = weight.flatMap { WaterIntake.suggestedGoal(weightKilograms: $0) }
        let reminder = WaterReminder(config: instance.config)
        return VStack(alignment: .leading, spacing: 10) {
            characterPicker

            Stepper(value: Binding(
                get: { goal },
                set: { value in
                    guard !context.isPreview else { return }
                    WaterLog.setGoal(value, in: instance)
                }), in: WaterIntake.goalRange, step: 100) {
                    HStack {
                        Text("每日目标")
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(WaterIntake.amount(goal, ounces: ounces))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .glassPane(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("体重")
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white.opacity(0.85))
                    TextField("", text: $weightText, prompt: Text("60"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                        .focused($focus, equals: .weight)
                        .onSubmit { saveWeight(weight) }
                    Text("公斤")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        guard let suggestion, !context.isPreview else { return }
                        saveWeight(weight)
                        WaterLog.setGoal(suggestion, in: instance)
                    } label: {
                        Text(suggestion.map { "设为 \(WaterIntake.amount($0, ounces: ounces))" } ?? "按体重建议")
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(.white.opacity(suggestion == nil ? 0.4 : 1))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(suggestion == nil ? Color.white.opacity(0.08) : accent.opacity(0.7)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(suggestion == nil || suggestion == goal || context.isPreview)
                }
                Text("建议量按体重 x \(WaterIntake.millilitresPerKilogram) 毫升估算，只作参考。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(10)
            .glassPane(cornerRadius: 10)

            reminderSettings(reminder)

            Button {
                confirmReset = true
            } label: {
                Label("复位喝水设置", systemImage: "arrow.counterclockwise")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .glassPane(cornerRadius: 10)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .confirmationDialog("复位喝水设置？", isPresented: $confirmReset) {
                Button("复位", role: .destructive) {
                    WaterLog.resetSettings(in: instance)
                    weightText = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("每日目标、体重、提醒间隔、时段和下次提醒恢复默认，喝水记录、角色和单位保留。")
            }

            Text("达标后当天不再提醒，刚喝过水也会顺延。一杯的容量和单位可以在设置的小组件页里改。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 提醒

    private func reminderSettings(_ reminder: WaterReminder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingRow("提醒") {
                Picker("", selection: Binding(
                    get: { reminder.every },
                    set: { value in
                        guard !context.isPreview else { return }
                        WaterLog.set("remindEvery", .string(String(value)), in: instance)
                    })) {
                        ForEach(WaterIntake.reminderChoices, id: \.self) { value in
                            Text(value == 0 ? "关闭" : "每 \(value) 分钟").tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
            }
            settingRow("时段") {
                HStack(spacing: 4) {
                    timePicker(reminder.start, key: "start")
                    Text("到").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    timePicker(reminder.end % 1440, key: "end")
                }
            }
            if reminder.every > 0 {
                nextReminderRow
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var nextReminderRow: some View {
        let now = Date.now
        let picked = WaterReminder.override(instance.config, now: now)
        let shown = WaterReminder.next(instance.config, now: now) ?? now
        let calendar = WaterIntake.calendar
        let minutes = calendar.component(.hour, from: shown) * 60 + calendar.component(.minute, from: shown)
        return VStack(alignment: .leading, spacing: 6) {
            settingRow("下次提醒") {
                HStack(spacing: 6) {
                    if !calendar.isDate(shown, inSameDayAs: now) {
                        Text("明天").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    DatePicker("", selection: Binding(
                        get: { Self.date(minutes: minutes) },
                        set: { date in
                            let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
                            pickNext(WaterReminder.pickedTime(minutes: m, now: .now))
                        }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                ForEach([15, 30, 60], id: \.self) { delay in
                    chip(delay == 60 ? "1 小时后" : "\(delay) 分钟后") {
                        pickNext(Date.now.addingTimeInterval(TimeInterval(delay * 60)))
                    }
                }
                Spacer(minLength: 0)
                if picked != nil {
                    chip("恢复自动") {
                        guard !context.isPreview else { return }
                        WaterLog.set(WaterReminder.overrideKey, nil, in: instance)
                    }
                }
            }
        }
    }

    private func pickNext(_ date: Date) {
        guard !context.isPreview else { return }
        WaterLog.set(WaterReminder.overrideKey, .number(date.timeIntervalSince1970), in: instance)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            content()
        }
        .controlSize(.small)
    }

    private func timePicker(_ minutes: Int, key: String) -> some View {
        DatePicker("", selection: Binding(
            get: { Self.date(minutes: minutes) },
            set: { date in
                guard !context.isPreview else { return }
                let calendar = WaterIntake.calendar
                let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
                WaterLog.set(key, .string(PostureSchedule.clock(m)), in: instance)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
            .disabled(context.isPreview)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    /// Today at `minutes` after midnight, for a time-only picker.
    private static func date(minutes: Int) -> Date {
        WaterIntake.calendar.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Six faces in a row; the chosen one sits on the accent.
    private var characterPicker: some View {
        let chosen = WaterCharacter.shown(instance.config, unlocked: Supporter.isUnlocked || context.isPreview)
        return VStack(alignment: .leading, spacing: 6) {
            Text("角色")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(WaterCharacter.allCases) { character in
                    let selected = character == chosen
                    let locked = character.isSupporterOnly && !Supporter.isUnlocked && !context.isPreview
                    Button {
                        guard !context.isPreview else { return }
                        if locked { SponsorWindow.shared.show(); return }
                        withAnimation(.snappy(duration: 0.25)) {
                            WaterLog.set("character", .string(character.rawValue), in: instance)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            WaterPanda(character: character, mood: .idle, level: 1, height: 26)
                                .frame(height: 28)
                                .opacity(locked ? 0.55 : 1)
                                .overlay(alignment: .topTrailing) {
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(2.5)
                                            .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
                                    }
                                }
                            Text(character.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? accent.opacity(0.75) : Color.white.opacity(0.08)))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                    .help(locked ? "\(character.title)（赞助者专属）" : character.title)
                    .accessibilityLabel(locked ? "角色：\(character.title)，赞助者专属" : "角色：\(character.title)")
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func saveWeight(_ weight: Double?) {
        guard !context.isPreview, let weight, (20...250).contains(weight) else { return }
        WaterLog.set("weight", .number(weight), in: instance)
    }
}
