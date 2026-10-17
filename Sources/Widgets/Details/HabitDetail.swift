import SwiftUI

/// 上面是两列习惯卡片（见 `HabitGrid`）：点卡片编辑名称、图标、颜色和每日目标，
/// 末尾的卡片新建习惯（有模板一点即加），右键可排序和删除。下面是每个习惯这个月
/// 的热力图：一天一格，做到了就填色，点一格补打或取消那天的卡。
struct HabitDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editor: HabitEditTarget?
    @State private var pendingDelete: Habit?

    private var habits: [Habit] {
        context.isPreview ? HabitSamples.habits(today: context.now) : HabitTracker.habits(instance.config)
    }

    private static let weekdays = [tr("一"), tr("二"), tr("三"), tr("四"), tr("五"), tr("六"), tr("日")]

    var body: some View {
        let all = habits
        let done = HabitTracker.doneToday(all, today: context.now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(done: done, total: all.count)
                ScrollView {
                    list(all)
                }
                .frame(maxHeight: 420)
                .scrollIndicators(.never)

                if !all.isEmpty {
                    HabitWeeklyReport(habits: all, accent: accent, now: context.now)
                }
            }
            .frame(minHeight: editor == nil ? nil : 470, alignment: .top)
            .overlay { editorLayer(all) }
            .animation(.snappy(duration: 0.2), value: editor)
        }
        .confirmationDialog(deleteTitle, isPresented: deleteShown) {
            Button("删除", role: .destructive) {
                if let habit = pendingDelete { delete(habit) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("这个习惯和它的全部打卡记录都会删除，不能恢复。")
        }
    }

    // MARK: Grid and month

    private func list(_ all: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HabitGrid(habits: all, now: context.now, isPreview: context.isPreview,
                      onOpen: { editor = $0 },
                      onTap: { tap($0) },
                      onMove: { habit, offset in move(habit, by: offset) },
                      onDelete: { pendingDelete = $0 })
            if all.isEmpty {
                Text("还没有习惯。点“新建习惯”，可以从早起、阅读、喝水等模板一键添加，也可以自己起名字。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("本月记录")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
                ForEach(all) { habit in card(habit) }
            }
        }
    }

    @ViewBuilder
    private func editorLayer(_ all: [Habit]) -> some View {
        if let target = editor {
            ZStack {
                Color.black.opacity(0.35)
                    .padding(-16)
                    .contentShape(.rect)
                    .onTapGesture { editor = nil }
                HabitEditor(target: target, habits: all,
                            onAddTemplate: { addTemplate($0) },
                            onSave: { name, icon, color, goal, unit in
                                save(target, name: name, icon: icon, color: color, goal: goal, unit: unit)
                            },
                            onDelete: { pendingDelete = $0 },
                            onClose: { editor = nil })
                    .id(target)
            }
            .transition(.opacity)
        }
    }

    private var deleteTitle: String { tr("删除“\(pendingDelete?.name ?? "")”？") }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func header(done: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("习惯打卡")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(HabitTracker.caption(done: done, total: total))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer()
            Text(context.now.formatted(.dateTime.year().month(.wide)))
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: One habit

    private func card(_ habit: Habit) -> some View {
        let streak = HabitTracker.streak(habit, today: context.now)
        let todayDone = HabitTracker.isDone(habit, on: context.now)
        let color = HabitStyle.color(habit)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HabitIconBadge(icon: habit.iconName, color: color, size: 22)
                Text(habit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentShape(.rect)
                    .onTapGesture { if !context.isPreview { editor = .edit(habit.id) } }
                    .help("点按编辑")
                Spacer(minLength: 4)
                Button {
                    tap(habit)
                } label: {
                    Label(todayLabel(habit, done: todayDone),
                          systemImage: todayDone ? "checkmark.circle.fill" : (habit.goal > 1 ? "plus.circle" : "circle"))
                        .font(WidgetStyle.label(11))
                        .monospacedDigit()
                        .foregroundStyle(todayDone ? Color.white : Color.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(todayDone ? color.opacity(0.75) : Color.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 12) {
                heatmap(habit)
                VStack(alignment: .leading, spacing: 6) {
                    StatChip(label: tr("连续"), value: tr("\(streak) 天"))
                    StatChip(label: tr("本月"), value: tr("\(HabitTracker.doneCount(habit, month: context.now)) 天"))
                    StatChip(label: tr("最长"), value: tr("\(HabitTracker.longestStreak(habit)) 天"))
                }
                .frame(width: 70)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    /// The month, Monday first, a square per day.
    private func heatmap(_ habit: Habit) -> some View {
        let weeks = HabitTracker.monthGrid(habit, month: context.now, today: context.now)
        let cell: CGFloat = 22
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: cell)
                }
            }
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = weeks[row][column] {
                            square(habit, day, size: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func square(_ habit: Habit, _ day: HabitDay, size: CGFloat) -> some View {
        Button {
            guard !context.isPreview, !day.isFuture else { return }
            withAnimation(.snappy(duration: 0.2)) {
                HabitLog.toggle(habit.id, day: day.date, in: instance)
            }
        } label: {
            Text("\(day.day)")
                .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(day.done ? 1 : (day.isFuture ? 0.25 : 0.6)))
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(day.done ? HabitStyle.color(habit).opacity(0.85) : Color.white.opacity(day.isFuture ? 0.03 : 0.08))
                }
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture || context.isPreview)
        .help(day.isFuture ? "" : (day.done ? tr("取消这天的打卡") : tr("补打这天的卡")))
    }

    // MARK: Editing

    private func todayLabel(_ habit: Habit, done: Bool) -> String {
        if done { return tr("今天已打卡") }
        guard habit.goal > 1 else { return tr("今天打卡") }
        return "\(HabitTracker.count(habit, on: context.now))/\(habit.goal) \(habit.unitName)"
    }

    private func tap(_ habit: Habit) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.25)) {
            HabitLog.tap(habit.id, day: context.now, in: instance)
        }
    }

    private func save(_ target: HabitEditTarget, name: String, icon: String?, color: PaletteColor?,
                      goal: Int, unit: String?) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.3)) {
            switch target {
            case .new:
                HabitLog.change(instance) {
                    HabitTracker.adding(name, icon: icon, color: color, goal: goal, unit: unit, to: $0)
                }
            case .edit(let id):
                HabitLog.change(instance) {
                    HabitTracker.updating(id, name: name, icon: icon, color: color, goal: goal, unit: unit, in: $0)
                }
            }
        }
        editor = nil
    }

    private func addTemplate(_ template: HabitTemplate) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.3)) {
            HabitLog.change(instance) { HabitTracker.adding(template, to: $0) }
        }
        editor = nil
    }

    private func move(_ habit: Habit, by offset: Int) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.25)) {
            HabitLog.change(instance) { HabitTracker.moving(habit.id, by: offset, in: $0) }
        }
    }

    private func delete(_ habit: Habit) {
        guard !context.isPreview else { return }
        if editor == .edit(habit.id) { editor = nil }
        withAnimation(.snappy(duration: 0.25)) {
            HabitLog.change(instance) { HabitTracker.removing(habit.id, from: $0) }
        }
    }

    private var accent: Color {
        Color(hex: WidgetCatalog.accentHex(.habit) ?? PaletteColor.green.hex)
    }
}
