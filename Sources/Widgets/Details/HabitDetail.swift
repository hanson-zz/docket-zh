import SwiftUI

/// Every habit with this month as a heatmap: a square per day, filled where
/// it was done. Click a square to check that day in or out, which is how a
/// missed check-in is put right. A field at the top adds a habit;
/// double-clicking a name renames it and the cross removes it.
struct HabitDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var editing: String?
    @State private var editDraft = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case add
        case edit(String)
    }

    private var habits: [Habit] {
        context.isPreview ? HabitSamples.habits(today: context.now) : HabitTracker.habits(instance.config)
    }

    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        let all = habits
        let done = HabitTracker.doneToday(all, today: context.now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(done: done, total: all.count)
                if all.count < HabitTracker.maxHabits { addField }
                if all.isEmpty {
                    Text("还没有习惯。输入一个，比如“早起”或“读书 30 分钟”，按回车添加。")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(all) { habit in card(habit) }
                        }
                    }
                    .frame(maxHeight: 420)
                    .scrollIndicators(.automatic)

                    HabitWeeklyReport(habits: all, accent: accent, now: context.now)
                }
            }
        }
        .onAppear { if !context.isPreview, habits.isEmpty { focus = .add } }
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

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: $draft, prompt: Text("添加习惯，按回车"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($focus, equals: .add)
                .onSubmit(add)
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .glassPane(cornerRadius: 10)
    }

    // MARK: One habit

    private func card(_ habit: Habit) -> some View {
        let streak = HabitTracker.streak(habit, today: context.now)
        let todayDone = HabitTracker.isDone(habit, on: context.now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if editing == habit.id {
                    TextField("", text: $editDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($focus, equals: .edit(habit.id))
                        .onSubmit { finishEditing(habit.id) }
                        .onChange(of: focus) { _, now in
                            if now != .edit(habit.id), editing == habit.id { finishEditing(habit.id) }
                        }
                } else {
                    Text(habit.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .contentShape(.rect)
                        .onTapGesture(count: 2) { beginEditing(habit) }
                        .help("双击改名")
                }
                Spacer(minLength: 4)
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        HabitLog.toggle(habit.id, day: context.now, in: instance)
                    }
                } label: {
                    Label(todayDone ? "今天已打卡" : "今天打卡",
                          systemImage: todayDone ? "checkmark.circle.fill" : "circle")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(todayDone ? Color.white : Color.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(todayDone ? accent.opacity(0.75) : Color.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        HabitLog.change(instance) { HabitTracker.removing(habit.id, from: $0) }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("删除这个习惯和它的记录")
                .accessibilityLabel("删除 \(habit.name)")
            }

            HStack(alignment: .top, spacing: 12) {
                heatmap(habit)
                VStack(alignment: .leading, spacing: 6) {
                    StatChip(label: "连续", value: "\(streak) 天")
                    StatChip(label: "本月", value: "\(HabitTracker.doneCount(habit, month: context.now)) 天")
                    StatChip(label: "最长", value: "\(HabitTracker.longestStreak(habit)) 天")
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
                        .fill(day.done ? accent.opacity(0.85) : Color.white.opacity(day.isFuture ? 0.03 : 0.08))
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
        .help(day.isFuture ? "" : (day.done ? "取消这天的打卡" : "补打这天的卡"))
    }

    // MARK: Editing

    private func add() {
        guard !context.isPreview, HabitTracker.clean(draft) != nil else { return }
        let name = draft
        withAnimation(.snappy(duration: 0.3)) {
            HabitLog.change(instance) { HabitTracker.adding(name, to: $0) }
        }
        draft = ""
        focus = .add
    }

    private func beginEditing(_ habit: Habit) {
        guard !context.isPreview else { return }
        editDraft = habit.name
        editing = habit.id
        focus = .edit(habit.id)
    }

    private func finishEditing(_ id: String) {
        let name = editDraft
        editing = nil
        HabitLog.change(instance) { HabitTracker.renaming(id, to: name, in: $0) }
    }

    private var accent: Color {
        Color(hex: WidgetCatalog.accentHex(.habit) ?? PaletteColor.green.hex)
    }
}
