import SwiftUI

/// A few habits, each with the last seven days as dots and its streak.
///
/// The dot on the right is today; clicking it checks the habit in (or out
/// again). Everything else on the card belongs to the card's own click, which
/// opens the panel where habits are added, renamed and removed and a month
/// can be looked back over. See `HabitTracker` for the logic.
struct HabitTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var habits: [Habit] {
        context.isPreview ? HabitSamples.habits(today: context.now) : HabitTracker.habits(instance.config)
    }

    private var showsStreak: Bool { instance.config.bool("showStreak", default: true) }

    var body: some View {
        let all = habits
        let done = HabitTracker.doneToday(all, today: context.now)
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(all)
                } else if all.isEmpty {
                    empty
                } else if all.count == 1 {
                    single(all[0])
                } else {
                    rows(all)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("习惯打卡，\(HabitTracker.caption(done: done, total: all.count))"))
    }

    // MARK: Wide

    private var empty: some View {
        HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            }
            TileReading(value: tr("习惯打卡"), caption: HabitTracker.caption(done: 0, total: 0), valueSize: 15)
            Spacer(minLength: 0)
        }
    }

    /// One habit gets the whole card: its name and streak over bigger dots.
    private func single(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint(habit))
                Text(habit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsStreak { streakText(habit, size: 12) }
            }
            dots(habit, size: 12, spacing: 6)
        }
    }

    /// Up to three habits, one line each: name, seven dots, streak.
    private func rows(_ all: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(all.prefix(HabitTracker.tileRows)) { habit in
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: showsStreak ? 50 : 64, alignment: .leading)
                    dots(habit, size: 8, spacing: 3)
                    if showsStreak {
                        Spacer(minLength: 0)
                        streakText(habit, size: 10)
                    }
                }
                .frame(height: 15)
            }
        }
    }

    // MARK: Column

    /// 56pt across: the name (and streak) over seven small dots, up to four habits.
    @ViewBuilder
    private func column(_ all: [Habit]) -> some View {
        if all.isEmpty {
            VStack(spacing: 4) {
                TileBadge(size: WidgetStyle.badgeCompact) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary)
                }
                Text("添加习惯")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(all.prefix(4)) { habit in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 2) {
                            Text(habit.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WidgetStyle.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if showsStreak {
                                Spacer(minLength: 0)
                                Text("\(HabitTracker.streak(habit, today: context.now))")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(WidgetStyle.secondary)
                                    .monospacedDigit()
                            }
                        }
                        dots(habit, size: 5.5, spacing: 2)
                    }
                    .frame(height: 26)
                }
            }
        }
    }

    // MARK: Pieces

    private func streakText(_ habit: Habit, size: CGFloat) -> some View {
        let streak = HabitTracker.streak(habit, today: context.now)
        return Text(streak > 0 ? tr("\(streak) 天") : tr("0 天"))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(streak > 0 ? tint(habit) : WidgetStyle.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .help(tr("连续打卡 \(streak) 天"))
    }

    /// Seven dots, today last. Only today's dot is a control.
    private func dots(_ habit: Habit, size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(HabitTracker.week(habit, today: context.now), id: \.key) { day in
                if day.isToday {
                    Button {
                        guard !context.isPreview else { return }
                        withAnimation(.snappy(duration: 0.25)) {
                            HabitLog.tap(habit.id, day: day.date, in: instance)
                        }
                    } label: {
                        dot(day, habit: habit, size: size)
                            .padding(spacing / 2 + 2)
                            .contentShape(.rect)
                            .padding(-(spacing / 2 + 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                    .help(todayHelp(habit, done: day.done))
                    .accessibilityLabel(day.done ? tr("取消 \(habit.name) 今天的打卡") : tr("\(habit.name) 今天打卡"))
                } else {
                    dot(day, habit: habit, size: size)
                }
            }
        }
    }

    private func todayHelp(_ habit: Habit, done: Bool) -> String {
        if done { return tr("取消今天的打卡") }
        guard habit.goal > 1 else { return tr("今天打卡：\(habit.name)") }
        return tr("\(habit.name) 今天 \(HabitTracker.todayText(habit, today: context.now))，点一下加 1")
    }

    private func dot(_ day: HabitDay, habit: Habit, size: CGFloat) -> some View {
        let color = tint(habit)
        let progress = day.isToday && !day.done ? HabitTracker.progress(habit, on: day.date) : 0
        return Circle()
            .fill(day.done ? color : WidgetStyle.primary.opacity(0.13))
            .overlay {
                if day.isToday, !day.done {
                    Circle().strokeBorder(color, lineWidth: max(1, size / 7))
                }
            }
            .overlay {
                // 计数习惯今天做到一半：圆点里按比例填一块扇形。
                if progress > 0 {
                    HabitPie(fraction: progress)
                        .fill(color)
                }
            }
            .frame(width: size, height: size)
    }

    private func tint(_ habit: Habit) -> Color {
        HabitStyle.color(habit).mix(with: WidgetStyle.primary, by: 0.15)
    }
}

/// The writes both the tile and the panel make, from the instance's current
/// list so the two can never disagree.
@MainActor
enum HabitLog {
    static func change(_ instance: WidgetInstance, _ edit: ([Habit]) -> [Habit]) {
        WidgetWriter.write(instance) { config in
            HabitTracker.store(edit(HabitTracker.habits(config)), in: &config)
        }
    }

    static func toggle(_ id: String, day: Date, in instance: WidgetInstance) {
        // Checking off today (not unchecking, not filling in a past day) is
        // a treat for the pet.
        let wasDone = HabitTracker.habits(instance.config).first { $0.id == id }
            .map { HabitTracker.isDone($0, on: day) } ?? true
        change(instance) { HabitTracker.toggling(id, day: day, in: $0) }
        if !wasDone, HabitTracker.dayKey(day) == HabitTracker.dayKey(.now) {
            // Once per habit per day: unchecking and checking again is not a second treat.
            PetTreats.giveOnce(.habit, for: "\(id)|\(HabitTracker.dayKey(day))")
        }
    }

    /// 打卡按钮：目标 1 次时勾选或取消，目标多次时加一次，加满算完成。
    /// 只有今天从没完成变成完成的那一下才喂宠物。
    static func tap(_ id: String, day: Date, in instance: WidgetInstance) {
        let before = HabitTracker.habits(instance.config)
        let wasDone = before.first { $0.id == id }.map { HabitTracker.isDone($0, on: day) } ?? true
        let nowDone = HabitTracker.tapping(id, day: day, in: before).first { $0.id == id }
            .map { HabitTracker.isDone($0, on: day) } ?? false
        change(instance) { HabitTracker.tapping(id, day: day, in: $0) }
        if !wasDone, nowDone, HabitTracker.dayKey(day) == HabitTracker.dayKey(.now) {
            PetTreats.giveOnce(.habit, for: "\(id)|\(HabitTracker.dayKey(day))")
        }
    }
}

/// 习惯的图标颜色：设置过颜色就用它，没有就用小组件的强调色。
enum HabitStyle {
    static var accent: Color {
        Color(hex: WidgetCatalog.accentHex(.habit) ?? PaletteColor.green.hex)
    }

    static func color(_ habit: Habit) -> Color {
        habit.color.map { Color(hex: $0.hex) } ?? accent
    }
}

/// 从 12 点方向顺时针的一块扇形。
struct HabitPie: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(max(fraction, 0), 1)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// What the library and the screenshots show: three habits with a believable
/// fortnight behind them, anchored to the day being drawn.
enum HabitSamples {
    static func habits(today: Date) -> [Habit] {
        let calendar = HabitTracker.calendar
        func days(_ offsets: [Int]) -> Set<String> {
            Set(offsets.compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
                .map { HabitTracker.dayKey($0, calendar: calendar) })
        }
        return [
            Habit(id: "s1", name: tr("早起"), days: days([0, 1, 2, 3, 4, 6, 7, 8, 10, 11, 12, 13]),
                  icon: "sunrise.fill", color: .orange),
            Habit(id: "s2", name: tr("读书 30 分钟"), days: days([1, 2, 3, 5, 6, 9, 13, 14]),
                  icon: "book.fill", color: .indigo),
            Habit(id: "s3", name: tr("喝水"), days: days([2, 4, 7, 9, 11]), icon: "drop.fill", color: .blue,
                  goal: 8, unit: tr("杯"), counts: [HabitTracker.dayKey(today, calendar: calendar): 5]),
        ]
    }
}
