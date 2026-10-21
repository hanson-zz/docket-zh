import AppKit
import SwiftUI

/// 习惯面板顶部的两列卡片：每个习惯一张，末尾一张“新建习惯”。
///
/// 卡片左上角是彩色圆形图标，右上角是今天的打卡按钮（计数习惯显示进度环），
/// 中间是名称和今天的状态，底部左边是大号的每日目标和单位，右边是最近十周的周格子
/// （像贡献图，一列一周，做满最深）。点卡片打开编辑弹层，
/// 右键可以编辑、上移、下移和删除。思路借鉴 Grow 的习惯卡片网格。
///
/// 没解锁 Pro 时免费 3 个：第 4 个起的卡片画淡、带小锁，点按弹付费墙，右键只能删除；
/// 满 3 个时“新建习惯”带 Pro 标识，点按弹付费墙。
struct HabitGrid: View {
    var habits: [Habit]
    var now: Date
    var isPreview: Bool
    var unlocked: Bool = true
    var onOpen: (HabitEditTarget) -> Void
    var onTap: (Habit) -> Void
    var onMove: (Habit, Int) -> Void
    var onDelete: (Habit) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                let locked = ProLicenseGate.isHabitLocked(at: index, unlocked: unlocked)
                // 没解锁时排序只在前 3 个里挪，免得把锁着的挪上来、把能用的挪下去。
                let lastMovable = unlocked ? habits.count - 1 : min(habits.count, ProFeatures.freeHabitLimit) - 1
                HabitCard(habit: habit, now: now, isPreview: isPreview, locked: locked, onTap: { onTap(habit) })
                    .contentShape(.rect(cornerRadius: 14))
                    .onTapGesture {
                        guard !isPreview else { return }
                        if locked { PaywallWindow.shared.show() } else { onOpen(.edit(habit.id)) }
                    }
                    .contextMenu {
                        if locked {
                            Button(ProLicenseGate.lockTitle, systemImage: "lock.fill") { PaywallWindow.shared.show() }
                        } else {
                            Button("编辑", systemImage: "pencil") { onOpen(.edit(habit.id)) }
                            Button("上移", systemImage: "arrow.up") { onMove(habit, -1) }
                                .disabled(index == 0)
                            Button("下移", systemImage: "arrow.down") { onMove(habit, 1) }
                                .disabled(index >= lastMovable)
                        }
                        Divider()
                        Button("删除…", systemImage: "trash", role: .destructive) { onDelete(habit) }
                    }
                    .help(locked ? tr("免费版可用 3 个习惯，这个只读。解锁码头 Pro 后可以继续打卡。")
                                 : tr("点按编辑，右键可排序或删除"))
            }
            if habits.count < HabitTracker.maxHabits {
                newCard
            }
        }
    }

    private var canAdd: Bool { ProLicenseGate.canAddHabit(count: habits.count, unlocked: unlocked) }

    private var newCard: some View {
        Button {
            guard !isPreview else { return }
            if canAdd { onOpen(.new) } else { PaywallWindow.shared.show() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: canAdd ? "plus" : "lock.fill")
                    .font(.system(size: canAdd ? 18 : 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.panelFill))
                Text("新建习惯")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                if !canAdd {
                    Text(tr("免费版 \(ProFeatures.freeHabitLimit) 个 · 解锁 Pro"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: ShelfColor.redPanda.hex).panelReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: HabitCard.height)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.panelQuaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
        .help(canAdd ? "" : tr("免费版可用 3 个习惯。解锁码头 Pro 后最多 8 个，还能看近七天报告。"))
        .accessibilityLabel("新建习惯")
    }
}

/// 打开编辑弹层的是新建还是某个已有的习惯。
enum HabitEditTarget: Hashable, Identifiable {
    case new
    case edit(String)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): id
        }
    }
}

/// 网格里的一张卡片。
struct HabitCard: View {
    var habit: Habit
    var now: Date
    var isPreview: Bool
    /// 没解锁时第 4 个起：画淡、右上角是小锁，不能打卡。
    var locked: Bool = false
    var onTap: () -> Void

    static let height: CGFloat = 136
    /// 卡片右下角的周格子画几周。
    static let weekCount = 10

    /// 最近几周每天做了多少，做满最深，做了一部分浅一些。
    private var weeks: [[ContributionGrid.Cell]] {
        ContributionGrid.columns(weeks: Self.weekCount, today: now, calendar: HabitTracker.calendar,
                                 count: { HabitTracker.count(habit, on: $0) },
                                 level: { ContributionGrid.level(count: $0, goal: habit.goal) })
    }

    var body: some View {
        let color = HabitStyle.color(habit)
        let done = HabitTracker.isDone(habit, on: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                HabitIconBadge(icon: habit.iconName, color: color, size: 30)
                Spacer(minLength: 4)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex).opacity(0.85)))
                        .accessibilityLabel(ProLicenseGate.lockTitle)
                } else {
                    checkButton(color: color, done: done)
                }
            }
            Text(habit.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .padding(.top, 4)
            Text(HabitTracker.todayText(habit, today: now))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(done ? color.mix(with: .white, by: 0.35).panelReadable : .panelTertiary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(habit.goal)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                    Text(tr("\(habit.unitName)/天"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ContributionGridView(columns: weeks, color: color, cell: 4, spacing: 1.5, unit: habit.unitName)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .opacity(locked ? 0.55 : 1)
        .glassPane(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("\(habit.name)，\(HabitTracker.goalText(habit))，今天\(HabitTracker.todayText(habit, today: now))"))
    }

    /// 右上角的今天打卡：目标 1 次是勾选圈，多次是进度环加次数。
    private func checkButton(color: Color, done: Bool) -> some View {
        let progress = HabitTracker.progress(habit, on: now)
        return Button {
            guard !isPreview else { return }
            onTap()
        } label: {
            ZStack {
                Circle().stroke(.panelStroke, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Circle().fill(color)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if habit.goal > 1 {
                    Text("\(HabitTracker.count(habit, on: now))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                }
            }
            .frame(width: 26, height: 26)
            .padding(4)
            .contentShape(.rect)
            .padding(-4)
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
        .help(done ? tr("取消今天的打卡") : (habit.goal > 1 ? tr("加 1 \(habit.unitName)") : tr("今天打卡")))
        .accessibilityLabel(done ? tr("取消 \(habit.name) 今天的打卡") : tr("\(habit.name) 今天打卡"))
    }
}

/// 彩色圆形里的白色图标。
struct HabitIconBadge: View {
    var icon: String
    var color: Color
    var size: CGFloat

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
    }
}

// MARK: - Editor

/// 点卡片或“新建习惯”弹出的编辑层：名称、图标、颜色、每日目标和单位。
/// 新建时顶部有模板，一点即加。
struct HabitEditor: View {
    var target: HabitEditTarget
    var habits: [Habit]
    var onAddTemplate: (HabitTemplate) -> Void
    var onSave: (_ name: String, _ icon: String?, _ color: PaletteColor?, _ goal: Int, _ unit: String?) -> Void
    var onDelete: (Habit) -> Void
    var onClose: () -> Void

    @State private var name = ""
    @State private var icon = Habit.defaultIcon
    @State private var color: PaletteColor = .green
    @State private var goal = 1
    @State private var unit = ""
    @FocusState private var nameFocused: Bool

    private var original: Habit? {
        guard case .edit(let id) = target else { return nil }
        return habits.first { $0.id == id }
    }

    private var isNew: Bool { original == nil }
    private var isFull: Bool { habits.count >= HabitTracker.maxHabits }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isNew ? tr("新建习惯") : tr("编辑习惯"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.panelFill))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("取消")
                .accessibilityLabel("取消")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isNew { templates }
                    nameRow
                    section(tr("图标")) { iconGrid }
                    section(tr("颜色")) { colorRow }
                    section(tr("每日目标")) { goalRow }
                }
                .padding(.bottom, 14)
            }
            // 面板是深色的，系统“始终显示滚动条”或接了鼠标时，滚动条会画成一根
            // 浅色竖条压在右侧图标和颜色上。改为不画滚动条，底部淡出提示还能往下滚。
            .scrollIndicators(.never)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                }
            }

            HStack {
                if let original {
                    Button(role: .destructive) {
                        onDelete(original)
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(Color.red.mix(with: .white, by: 0.25).panelReadable)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    save()
                } label: {
                    Text(isNew ? tr("添加") : tr("完成"))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(hex: color.hex).opacity(canSave ? 0.9 : 0.3)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.panelDynamic(dark: NSColor(white: 0.13, alpha: 0.97),
                                         light: NSColor(white: 0.97, alpha: 0.97)))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        }
        .onAppear(perform: load)
    }

    // MARK: Pieces

    private var templates: some View {
        section(isFull ? tr("从模板添加（已满 \(HabitTracker.maxHabits) 个）") : tr("从模板添加")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(HabitTracker.templates) { template in
                    Button {
                        onAddTemplate(template)
                    } label: {
                        VStack(spacing: 4) {
                            HabitIconBadge(icon: template.icon, color: Color(hex: template.color.hex), size: 24)
                            Text(template.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.panelPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .glassPane(cornerRadius: 9)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFull)
                    .help(template.goal > 1 ? tr("\(template.name)，每天 \(template.goal) \(template.unit ?? Habit.defaultUnit)") : template.name)
                }
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            HabitIconBadge(icon: icon, color: Color(hex: color.hex), size: 34)
            TextField("", text: $name, prompt: Text(isNew ? tr("自己起个名字，比如“晚饭后散步”") : tr("名称")))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .focused($nameFocused)
                .onSubmit(save)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .glassPane(cornerRadius: 9)
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(Array(HabitTracker.icons.enumerated()), id: \.element) { index, symbol in
                Button {
                    icon = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(symbol == icon ? Color.white : .panelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(symbol == icon ? Color(hex: color.hex).opacity(0.85) : .panelFill)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("图标 \(index + 1)"))
                .accessibilityAddTraits(symbol == icon ? .isSelected : [])
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 0) {
            ForEach(HabitTracker.colors, id: \.self) { swatch in
                Button {
                    color = swatch
                } label: {
                    Circle()
                        .fill(Color(hex: swatch.hex))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if swatch == color {
                                Circle().strokeBorder(.panelPrimary, lineWidth: 2)
                                    .padding(-4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(HabitTracker.colorName(swatch))
                .accessibilityLabel(HabitTracker.colorName(swatch))
                .accessibilityAddTraits(swatch == color ? .isSelected : [])
            }
        }
    }

    private var goalRow: some View {
        HStack(spacing: 8) {
            Text("每天")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            Stepper(value: $goal, in: 1...HabitTracker.maxGoal) {
                Text("\(goal)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
            }
            TextField("", text: $unit, prompt: Text(Habit.defaultUnit))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .multilineTextAlignment(.center)
                .frame(width: 48, height: 26)
                .glassPane(cornerRadius: 7)
                .onChange(of: unit) { _, value in
                    if value.count > HabitTracker.maxUnitLength {
                        unit = String(value.prefix(HabitTracker.maxUnitLength))
                    }
                }
                .help("单位，比如杯、页、公里，空着就是“次”")
            Spacer(minLength: 0)
            Text(goal == 1 ? tr("勾选即完成") : tr("点 \(goal) 下完成"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .lineLimit(1)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.panelTertiary)
            content()
        }
    }

    // MARK: State

    private var canSave: Bool {
        HabitTracker.clean(name) != nil && (!isNew || !isFull)
    }

    private func load() {
        if let original {
            name = original.name
            icon = original.iconName
            color = original.color ?? .green
            goal = original.goal
            unit = original.unit ?? ""
        } else {
            nameFocused = true
        }
    }

    /// 没动过的默认图标和默认颜色仍然存成“未设置”，旧存档保持原来的样子。
    private func save() {
        guard canSave else { return }
        let keepsDefaultIcon = icon == Habit.defaultIcon && original?.icon == nil
        let keepsDefaultColor = color == .green && original?.color == nil
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        onSave(name, keepsDefaultIcon ? nil : icon, keepsDefaultColor ? nil : color, goal,
               trimmedUnit.isEmpty ? nil : trimmedUnit)
    }
}
