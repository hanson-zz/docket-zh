import SwiftUI
import UniformTypeIdentifiers

/// 快速待办的展开面板（v3，按 design/todo-v3 效果图，320pt 宽）。
///
/// - 顶上一个 48pt 的大输入框，左边橙色「＋」。认自然语言时间（`TodoTimeParse`，逻辑不变）：
///   「明天 9 点交稿」里的「明天 9 点」标成主题色，下面一行预览，回车记成“交稿”。输入法
///   选字时不打断（见 `TodoInputField`）。
/// - 下面是 28pt 的「今天」和「10月26日 周一 · 已完成 2 / 5」，右边一圈完成进度环，环里
///   坐着小熊猫，全部做完变绿。
/// - 今天、稍后各一张玻璃小卡，行高 44pt、正文 15pt、组标题 15pt 粗；「稍后」可以收起。
///   已完成折成底部一行，右边「清空」；前几天做完的照旧收进“已收起”，留 7 天。
/// - 五色标签（`TodoTag`）：行首细色条加同色圆圈。红色就是原来的「重要」（同步提醒事项时
///   照旧映射成旗标），免费；橙黄绿紫和按颜色筛选是 Pro，没解锁时点了弹付费墙，已设的
///   颜色照旧存着、画成没有颜色。悬停行尾「···」、右键、⌘1 到 ⌘5 设，⌘0 清除。
/// - 勾选：圆圈按标签色填满、轻弹一圈、划线，约 0.4 秒后沉到已完成；底部深色撤销条停
///   6 秒，⌘Z 也能撤销。减少动态效果时直接换。
/// - 拖动排序：悬停出把手，拖起来浮起带影子，目标位置让出一格橙色虚线空位，跨组照旧；
///   ⌥↑ / ⌥↓ 也能挪，⌘T 移到今天 / 稍后。键盘只在鼠标停着或点选了一行时生效，
///   输入法组字时不抢键（见 `TodoKeyCatcher`）。
/// - 「今天」一组清空（稍后有没有都算）：小熊猫欢呼加五色小彩点，写连续几天和最近
///   7 天的小圆点。
/// - 清单空空的：歇着的小熊猫和 4 个「试试这样写」，点一下只填进输入框。
/// - 重复待办（Pro）：右键或「···」设每天 / 每周 / 工作日，勾掉后按规则生成下一次。
/// - 照旧：截止胶囊（过期红、今天橙、以后灰，带提醒的有小闹钟）、链接和文件、右键菜单、
///   转成提醒事项（免费，逐条）、拖进来记一条、到点弹卡片、同步到提醒事项开关（Pro）。
///
/// 液态玻璃：颜色全用 PanelColors 的语义色，跟随浅色 / 深色，不强制深色。
struct TodoDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var editing: String?
    @State private var editDraft = ""
    @FocusState private var editFocus: String?
    /// 「今天」刚清空的那一刻：彩点从中间撒开。
    @State private var celebrateAt: Date?
    /// 最近几步删除和完成，撤销条按后进先出一步步退回。
    @State private var undo = TodoUndoStack()
    /// 每记一步换一个，撤销条从最后一次改动起再停几秒。
    @State private var undoToken = UUID()
    /// 拖着外面的文字、链接、文件停在面板上。
    @State private var targeted = false
    /// 正在挑日期转成提醒事项的那一条。
    @State private var converting: String?
    @State private var convertDate = Date()
    /// 转成提醒事项、同步没成功时的一句话。
    @State private var notice: String?
    @State private var noticeNeedsSettings = false
    /// 正在自定义提醒时间的那一条。
    @State private var reminding: String?
    @State private var remindDate = Date()
    /// 「已完成」展开着没有（默认折叠）。
    @State private var doneOpen = false
    /// 「稍后」展开着没有（默认展开）。
    @State private var laterOpen = true
    /// 底部“已收起”（前几天做完的）展开着没有。
    @State private var archiveOpen = false
    /// 鼠标停在哪一行上：那一行才出现把手、「···」、编辑和删除。
    @State private var hovered: String?
    /// 点选的那一行：鼠标移开后键盘照样作用在它上面。
    @State private var selected: String?
    /// 刚勾上、正在播完成动效的几条（约 0.4 秒后才真的移进「已完成」）。
    @State private var completing: Set<String> = []
    /// 勾上那一下圆圈轻轻放大、外面一圈淡色扩散的几条。
    @State private var popping: Set<String> = []
    /// 拖动排序时停在哪儿（那里让出一格空位）。
    @State private var dropSpot: TodoDropSpot?
    /// 正在被拖着的那一行（原位置淡掉）。
    @State private var dragging: String?
    /// 按颜色筛选（Pro），nil 是全部。
    @State private var tagFilter: TodoTag?

    private var sync: TodoReminderSyncService { .shared }

    private var items: [TodoItem] {
        context.isPreview ? sample : QuickTodo.items(instance.config)
    }

    /// 小组件库里的示例：今天三条（一条昨天顺下来的红色、一条橙色带提醒），稍后两条，做完两条。
    private var sample: [TodoItem] {
        let now = context.now
        let day = TodoDay.key(now)
        let yesterday = TodoDay.previous(day) ?? day
        return [
            TodoItem(id: "s1", text: tr("交电费"), today: true, addedDay: yesterday, todaySince: yesterday, tag: .red),
            TodoItem(id: "s2", text: tr("回复产品评审意见"), today: true, addedDay: day,
                     remindAt: now.addingTimeInterval(80 * 60), todaySince: day, tag: .orange),
            TodoItem(id: "s3", text: tr("取快递"), today: true, addedDay: day, todaySince: day),
            TodoItem(id: "s4", text: tr("订周五的会议室"), addedDay: day,
                     remindAt: now.addingTimeInterval(2 * 86_400), tag: .green),
            TodoItem(id: "s5", text: tr("读《置身事内》第 3 章"), addedDay: day, tag: .purple),
            TodoItem(id: "s6", text: tr("回复产品评审"), done: true, today: true, addedDay: day, doneDay: day),
            TodoItem(id: "s7", text: tr("订机票"), done: true, today: true, addedDay: day, doneDay: day),
        ]
    }

    private var today: String { TodoDay.key(context.now) }
    private var unlocked: Bool { context.isPreview || ProAccess.isUnlocked }

    var body: some View {
        let all = items
        let filter = ProLicenseGate.canFilterTodoTags(unlocked: unlocked) ? tagFilter : nil
        let todayRows = QuickTodo.filtered(QuickTodo.items(in: .today, of: all), by: filter, unlocked: unlocked)
        let laterRows = QuickTodo.filtered(QuickTodo.items(in: .later, of: all), by: filter, unlocked: unlocked)
        let doneRows = QuickTodo.items(in: .done, of: all)
        let cleared = QuickTodo.todayCleared(all, today: today) && filter == nil
        let nothingOpen = QuickTodo.open(all).isEmpty
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                inputSection
                if let notice {
                    noticeLine(notice)
                }
                hero(all, cleared: cleared)
                if hasTags(all) || tagFilter != nil {
                    filterBar
                }
                if nothingOpen && !cleared {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if cleared {
                                celebrationCard(all)
                            } else {
                                groupCard(.today, todayRows)
                            }
                            if !QuickTodo.items(in: .later, of: all).isEmpty {
                                laterSection(laterRows, hint: cleared)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 380)
                    .scrollIndicators(.never)
                }
                if !doneRows.isEmpty {
                    doneSection(doneRows)
                }
                let shelved = context.isPreview ? [] : QuickTodo.archive(instance.config)
                if !shelved.isEmpty {
                    archiveSection(shelved)
                }
                if let step = undo.last {
                    TodoUndoToast(step: step, more: undo.count - 1) { restore() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                syncFooter
            }
            // 拖着外面的东西停在面板上时把清单压暗，让“松手记一条待办”看得清。
            .opacity(targeted ? 0.3 : 1)
            .overlay {
                if targeted {
                    TodoDropHint()
                        .padding(18)
                        .glassPane(cornerRadius: 12)
                }
            }
            .dropTargetOutline(targeted, tint: .orange, corner: 12)
            .onDrop(of: TodoDropDelegate.types, delegate: TodoDropDelegate(
                enabled: !context.isPreview,
                targeted: { targeted = $0 },
                receive: { drops in
                    withAnimation(listAnimation) { TodoLog.add(drops, to: instance) }
                }))
            .background {
                if !context.isPreview {
                    TodoKeyCatcher { key in handle(key) }
                        .frame(width: 0, height: 0)
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            TodoLog.rollOver(instance, today: today)
        }
        .task(id: undoToken) {
            guard !undo.isEmpty else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(barAnimation) { undo.clear() }
        }
        .task(id: celebrateAt) {
            guard celebrateAt != nil else { return }
            try? await Task.sleep(for: .seconds(CheerMotion.duration))
            guard !Task.isCancelled else { return }
            // 卡片会在到点时清掉记号；面板也清一次，卡片恰好不在屏幕上时也不会卡住。
            if !context.isPreview { TodoLog.endCheer(instance) }
        }
    }

    private func hasTags(_ all: [TodoItem]) -> Bool {
        QuickTodo.open(all).contains { TodoTag.shown($0.tag, unlocked: unlocked) != nil }
    }

    // MARK: 顶部「今天」

    private func hero(_ all: [TodoItem], cleared: Bool) -> some View {
        let tally = QuickTodo.todayTally(all, today: today)
        let complete = tally.total > 0 && tally.done >= tally.total
        let date = TodoTimeText.heroDate(context.now)
        let line: String
        if complete {
            line = tr("\(date) · \(tally.done) 件全部完成")
        } else if tally.total == 0 {
            line = tr("\(date) · 今天还没有安排")
        } else {
            line = tr("\(date) · 已完成 \(tally.done) / \(tally.total)")
        }
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            TodoProgressRing(fraction: tally.total == 0 ? 0 : Double(tally.done) / Double(tally.total),
                             complete: complete, lineWidth: 5, tint: accent) {
                TodoPanda(name: cleared || complete ? "pet-panda-cheer" : "pet-panda-idle", size: 40)
                    .offset(y: -2)
            }
            .frame(width: 56, height: 56)
            .animation(listAnimation, value: tally.done)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("今天，\(line)"))
    }

    // MARK: 按颜色筛选（Pro）

    private var filterBar: some View {
        HStack(spacing: 6) {
            Text("按颜色筛选")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            if !ProLicenseGate.canFilterTodoTags(unlocked: unlocked) {
                ProBadge()
            }
            Spacer(minLength: 4)
            ForEach(TodoTag.allCases) { tag in
                let on = tagFilter == tag
                Button {
                    guard ProLicenseGate.canFilterTodoTags(unlocked: unlocked) else {
                        PaywallWindow.shared.show()
                        return
                    }
                    withAnimation(listAnimation) { tagFilter = on ? nil : tag }
                } label: {
                    Circle()
                        .fill(tag.graphic)
                        .frame(width: 12, height: 12)
                        .padding(3)
                        .overlay(Circle().strokeBorder(on ? tag.graphic : Color.clear, lineWidth: 1.5))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .help(tr("只看\(tag.colorName)"))
                .accessibilityLabel(tr("只看\(tag.colorName)"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            if tagFilter != nil {
                Button("全部") { withAnimation(listAnimation) { tagFilter = nil } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 输入

    private var parsed: TodoTimeParse? {
        TodoTimeParse.parse(draft, now: context.now)
    }

    private var canAdd: Bool { QuickTodo.clean(draft) != nil && !context.isPreview }

    private var inputSection: some View {
        let parse = parsed
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Self.orange)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    if draft.isEmpty {
                        Text("写一件事，比如 明天 9 点交稿")
                            .font(.system(size: TodoInputField.fontSize))
                            .foregroundStyle(.panelTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsHitTesting(false)
                    }
                    TodoInputField(text: $draft, placeholder: tr("添加待办"),
                                   highlight: parse.map { NSRange(location: $0.start, length: $0.length) },
                                   tint: highlightTint, enabled: !context.isPreview,
                                   autofocus: !context.isPreview, onSubmit: add)
                        .frame(height: 22)
                }
                Button(action: add) {
                    Image(systemName: "return")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canAdd ? Color.panelPrimary : Color.panelTertiary)
                        .frame(width: 28, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.panelFill))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .help(tr("添加待办"))
                .accessibilityLabel(tr("添加待办"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.panelRaised)
                    .panelLift()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(draft.isEmpty ? Color.panelStroke : accent.panelGraphic.opacity(0.7),
                                  lineWidth: draft.isEmpty ? 0.7 : 1.2)
            }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    if let parse {
                        Image(systemName: parse.remindAt == nil ? "sun.max" : "alarm")
                            .font(.system(size: 13, weight: .semibold))
                        Text(parse.preview(now: context.now))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 6)
                    Text("回车添加")
                        .foregroundStyle(.panelSecondary)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent.panelReadable)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .animation(barAnimation, value: draft.isEmpty)
    }

    /// 输入框里认出的时间片段的颜色：深色下原样，浅色下加深到看得清。
    private var highlightTint: NSColor {
        let base = NSColor(accent)
        return NSColor(name: nil) { appearance in
            let resolved = base.usingColorSpace(.sRGB) ?? base
            return appearance.panelIsDark ? resolved : NSColor.panelDeepened(resolved, minContrast: 5)
        }
    }

    private func add() {
        guard canAdd else { return }
        let text = draft
        withAnimation(listAnimation) { TodoLog.add(text, to: instance) }
        draft = ""
    }

    // MARK: 分组小卡

    private func groupHeader(_ group: TodoGroup, count: Int, collapsible: Bool) -> some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.panelPrimary)
            Text(verbatim: "\(count)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
            Spacer()
            if collapsible {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .rotationEffect(.degrees(laterOpen ? 0 : -90))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
        .contentShape(.rect)
        .onTapGesture {
            guard collapsible else { return }
            withAnimation(listAnimation) { laterOpen.toggle() }
        }
        .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(TodoDropSpot(group: group, before: nil)))
        .accessibilityAddTraits(collapsible ? [.isHeader, .isButton] : .isHeader)
        .accessibilityLabel(collapsible ? (laterOpen ? tr("收起稍后") : tr("展开稍后")) : group.title)
    }

    /// 「今天」：没有分组标题（顶上的大标题就是它），一张玻璃小卡。
    private func groupCard(_ group: TodoGroup, _ rows: [TodoItem]) -> some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                emptyGroup(group)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                if dropSpot == TodoDropSpot(group: group, before: item.id), dragging != item.id {
                    dropSlot(TodoDropSpot(group: group, before: item.id))
                }
                row(item, group: group, first: index == 0)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                              removal: .opacity.combined(with: .move(edge: .bottom))))
            }
            if !rows.isEmpty {
                let end = TodoDropSpot(group: group, before: nil)
                if dropSpot == end {
                    dropSlot(end)
                } else {
                    // 拖到这一组最后。
                    Color.clear
                        .frame(height: 6)
                        .contentShape(.rect)
                        .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(end))
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, rows.isEmpty ? 4 : 0)
        .glassPane(cornerRadius: 14)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: dropSpot)
    }

    private func laterSection(_ rows: [TodoItem], hint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            groupHeader(.later, count: rows.count, collapsible: true)
            if laterOpen {
                groupCard(.later, rows)
                    .transition(.opacity)
                if hint {
                    Text("还有劲？拖一件到今天")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.top, 4)
    }

    /// 一组空着时的一行虚线框：拖到这里放进来。
    private func emptyGroup(_ group: TodoGroup) -> some View {
        let spot = TodoDropSpot(group: group, before: nil)
        let text = tagFilter != nil ? tr("这个颜色没有待办")
            : (group == .today ? tr("把待办拖到这里，今天就做它") : tr("拖到这里，放到稍后再做"))
        return Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dropSpot == spot ? Self.orange.opacity(0.10) : Color.clear)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(dropSpot == spot ? Self.orange.panelGraphic : Color.panelSeparator,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .padding(.horizontal, 6)
            .contentShape(.rect)
            .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(spot))
    }

    /// 拖动排序时目标处让出来的一格：淡橙底、上下两道橙色虚线。
    private func dropSlot(_ spot: TodoDropSpot) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Self.orange.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Self.orange.panelGraphic.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
            .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(spot))
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func rowDrop(_ spot: TodoDropSpot) -> TodoRowDropDelegate {
        let target = instance
        let day = today
        let animation = listAnimation
        return TodoRowDropDelegate(
            spot: spot,
            enabled: !context.isPreview,
            hover: { dropSpot = $0 },
            leave: { left in if dropSpot == left { dropSpot = nil } },
            perform: { id, spot in
                dragging = nil
                withAnimation(animation) {
                    TodoLog.change(target) {
                        QuickTodo.moving(id, to: spot.group, before: spot.before, in: $0, today: day)
                    }
                }
            })
    }

    // MARK: 「今天」清空

    private func celebrationCard(_ all: [TodoItem]) -> some View {
        let streak = context.isPreview ? 3 : QuickTodo.streak(instance.config, today: today)
        let days = TodoStreak.lastWeek(today)
        let week = context.isPreview ? [false, false, false, false, true, true, true]
            : TodoStreak.week(instance.config, today: today)
        let green = TodoProgressRing<EmptyView>.green
        return VStack(spacing: 8) {
            ZStack {
                TodoConfetti(startedAt: celebrateAt)
                    .frame(width: 190, height: 110)
                TodoPanda(name: "pet-panda-cheer", size: 96)
            }
            .frame(height: 104)
            Text("今天清空啦！")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.panelPrimary)
            Text(streak > 0 ? tr("连续 \(streak) 天 · 去喝口水歇一歇") : tr("去喝口水歇一歇"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(green.panelReadable)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Rectangle()
                .fill(.panelSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.top, 2)
            TodoWeekDots(days: week, labels: TodoWeekDots.labels(days))
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassPane(cornerRadius: 14)
        .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(TodoDropSpot(group: .today, before: nil)))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    // MARK: 一行

    private static let rowHeight: CGFloat = 44

    private func row(_ item: TodoItem, group: TodoGroup, first: Bool = false) -> some View {
        let isHovered = hovered == item.id && editing != item.id && !context.isPreview
        let isSelected = selected == item.id && !context.isPreview
        return VStack(alignment: .leading, spacing: 4) {
            rowLine(item, group: group, hovered: isHovered)
                .frame(minHeight: Self.rowHeight - 8)
            if converting == item.id {
                convertPicker(item)
            }
            if reminding == item.id {
                reminderPicker(item)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: Self.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered || isSelected ? Color.panelRaised : Color.clear)
                .panelLift(isHovered)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .overlay(alignment: .top) {
            if !first && !isHovered && group != .done {
                Rectangle()
                    .fill(.panelSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, 46)
                    .padding(.trailing, 12)
                    .allowsHitTesting(false)
            }
        }
        .opacity(dragging == item.id ? 0.35 : 1)
        .contentShape(.rect)
        .onHover { inside in
            if inside {
                hovered = item.id
                // 拖到面板外面松手（没落到任何位置）时，回来一停就把原位置的淡色恢复。
                if dragging != nil { dragging = nil }
            } else if hovered == item.id {
                hovered = nil
            }
        }
        .onTapGesture { selected = selected == item.id ? nil : item.id }
        .contextMenu { menu(item) }
        .modifier(RowDropModifier(enabled: group != .done,
                                  delegate: rowDrop(TodoDropSpot(group: group, before: item.id))))
    }

    private func rowLine(_ item: TodoItem, group: TodoGroup, hovered: Bool) -> some View {
        let checked = item.done || completing.contains(item.id)
        let tag = TodoTag.shown(item.tag, unlocked: unlocked)
        return HStack(spacing: 8) {
            ZStack {
                if group != .done && hovered {
                    dragHandle(item)
                } else if let tag, !checked {
                    // 行首的细色条。
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tag.graphic)
                        .frame(width: 3, height: 20)
                }
            }
            .frame(width: 12, height: 28)
            checkButton(item, checked: checked, tag: tag)
            title(item, checked: checked)
            if item.repeatRule != nil, ProLicenseGate.canRepeatTodos(unlocked: unlocked), !item.done {
                Image(systemName: "repeat")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .help(item.repeatRule?.title ?? "")
                    .accessibilityLabel(tr("重复：\(item.repeatRule?.title ?? "")"))
            }
            if item.url != nil {
                Button {
                    TodoLinkOpener.open(item)
                } label: {
                    Image(systemName: TodoLinkOpener.symbol(item))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(item.url?.isFileURL == true ? tr("打开文件") : tr("打开链接"))
                .accessibilityLabel(tr("打开 \(item.text)"))
            }
            if !checked, !hovered, let badge = QuickTodo.dueBadge(item, now: context.now) {
                dueCapsule(badge, alarm: item.remindAt != nil)
            }
            if hovered {
                moreMenu(item)
                hoverButton("pencil", help: tr("编辑")) { beginEditing(item) }
                hoverButton("trash", help: tr("删除")) { delete(item) }
            }
        }
    }

    /// 悬停才出现的拖动把手：拖进另一组就换组，拖进「今天」就是今天做。
    private func dragHandle(_ item: TodoItem) -> some View {
        let id = item.id
        let tag = TodoTag.shown(item.tag, unlocked: unlocked)
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .frame(width: 14, height: 28)
            .contentShape(.rect)
            .onDrag {
                dragging = id
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: TodoRowDrag.type.identifier,
                                                    visibility: .ownProcess) { completion in
                    completion(Data(id.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                TodoDragPreview(text: item.text, tag: tag, link: item.url != nil)
            }
            .help(tr("拖动排序，拖进「今天」就是今天做"))
            .accessibilityHidden(true)
    }

    private func checkButton(_ item: TodoItem, checked: Bool, tag: TodoTag?) -> some View {
        // 圆圈是标签色描边，没有标签时灰；勾上时按标签色填满，没有标签时用主题色。
        let ring = tag?.graphic ?? Color.panelTertiary
        let fill = tag?.graphic ?? accent.panelGraphic
        let pop = popping.contains(item.id)
        return Button {
            toggle(item)
        } label: {
            ZStack {
                Circle()
                    .fill(fill.opacity(0.22))
                    .frame(width: 30, height: 30)
                    .scaleEffect(pop ? 1 : 0.6)
                    .opacity(pop ? 1 : 0)
                Circle()
                    .strokeBorder(ring, lineWidth: 1.6)
                    .frame(width: 18, height: 18)
                    .opacity(checked ? 0 : 1)
                Circle()
                    .fill(item.done ? fill.opacity(0.75) : fill)
                    .frame(width: 18, height: 18)
                    .opacity(checked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
            }
            .scaleEffect(pop ? 1.15 : 1)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview || completing.contains(item.id))
        .help(item.done ? tr("标为未完成") : tr("标为完成"))
        .accessibilityLabel(item.done ? tr("标为未完成") : tr("完成 \(item.text)"))
    }

    @ViewBuilder
    private func title(_ item: TodoItem, checked: Bool) -> some View {
        if editing == item.id {
            TextField("", text: $editDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.panelPrimary)
                .focused($editFocus, equals: item.id)
                .onSubmit { finishEditing(item.id) }
                .onExitCommand { editing = nil }
                .onChange(of: editFocus) { _, now in
                    if now != item.id, editing == item.id { finishEditing(item.id) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(item.text)
                .font(.system(size: 15))
                .foregroundStyle(checked ? Color.panelSecondary : Color.panelPrimary)
                .strikethrough(checked, color: .panelSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(count: 2) { beginEditing(item) }
                .help(tr("双击编辑"))
        }
    }

    /// 行尾的截止时间胶囊：过期红、今天橙、以后灰；设了提醒的胶囊里带个小闹钟。
    private func dueCapsule(_ badge: TodoDueBadge, alarm: Bool) -> some View {
        let ink: Color
        let fill: Color
        switch badge.tone {
        case .late:
            ink = Self.red.panelReadable(minContrast: 5.2)
            fill = Self.red.opacity(0.14)
        case .today:
            ink = Self.orange.panelReadable(minContrast: 5.2)
            fill = Self.orange.opacity(0.16)
        case .later:
            ink = .panelSecondary
            fill = .panelFill
        }
        return HStack(spacing: 3) {
            if alarm {
                Image(systemName: "alarm")
                    .font(.system(size: 13, weight: .medium))
                    .imageScale(.small)
            }
            Text(badge.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(fill))
        .fixedSize()
        .accessibilityLabel(alarm ? tr("\(badge.text) 提醒") : badge.text)
    }

    private func hoverButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// 悬停时行尾的「···」：颜色、重复、移到今天 / 稍后、提醒我。
    private func moreMenu(_ item: TodoItem) -> some View {
        Menu {
            if !item.done {
                Button(item.today ? tr("移到稍后") : tr("移到今天")) { move(item, to: item.today ? .later : .today) }
            }
            Menu("颜色") { tagItems(item) }
            if !item.done {
                Menu("重复") { repeatItems(item) }
                Menu("提醒我") { reminderItems(item) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("颜色、重复和更多"))
        .accessibilityLabel(tr("更多"))
    }

    // MARK: 右键

    @ViewBuilder
    private func menu(_ item: TodoItem) -> some View {
        if !item.done {
            if item.today {
                Button("移到稍后") { move(item, to: .later) }
            } else {
                Button("移到今天") { move(item, to: .today) }
            }
            Menu("颜色") { tagItems(item) }
            Menu("重复") { repeatItems(item) }
            Menu("提醒我") { reminderItems(item) }
        }
        if item.url != nil {
            Button(item.url?.isFileURL == true ? tr("打开文件") : tr("打开链接")) { TodoLinkOpener.open(item) }
        }
        Button("编辑") { beginEditing(item) }
        Divider()
        Menu("转成提醒事项") {
            Button("今天") { convert(item, due: Date()) }
            Button("明天") { convert(item, due: Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
            Button("选日期…") {
                convertDate = item.remindAt ?? Date()
                withAnimation(listAnimation) { converting = item.id }
            }
            Divider()
            Button("不设日期") { convert(item, due: nil) }
        }
        Divider()
        Button("删除", role: .destructive) { delete(item) }
    }

    /// 五个颜色和清除。没解锁时 Pro 四色后面写着 Pro，点了弹付费墙。
    @ViewBuilder
    private func tagItems(_ item: TodoItem) -> some View {
        ForEach(TodoTag.allCases) { tag in
            let locked = !ProLicenseGate.canTagTodo(tag, unlocked: unlocked)
            let label = locked ? "\(tag.title)  Pro" : tag.title
            Button {
                setTag(item, tag)
            } label: {
                if item.tag == tag && !locked {
                    Label(label, systemImage: "checkmark")
                } else {
                    Text(label)
                }
            }
            .keyboardShortcut(KeyEquivalent(Character("\(tag.shortcutNumber)")), modifiers: .command)
        }
        Divider()
        Button("清除颜色") { setTag(item, nil) }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(item.tag == nil)
    }

    @ViewBuilder
    private func repeatItems(_ item: TodoItem) -> some View {
        let locked = !ProLicenseGate.canRepeatTodos(unlocked: unlocked)
        ForEach(TodoRepeat.allCases) { rule in
            let label = locked ? "\(rule.title)  Pro" : rule.title
            Button {
                setRepeat(item, rule)
            } label: {
                if item.repeatRule == rule && !locked {
                    Label(label, systemImage: "checkmark")
                } else {
                    Text(label)
                }
            }
        }
        if item.repeatRule != nil {
            Divider()
            Button("不重复") { setRepeat(item, nil) }
        }
    }

    private func move(_ item: TodoItem, to group: TodoGroup) {
        guard !context.isPreview else { return }
        let day = today
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.moving(item.id, to: group, before: nil, in: $0, today: day) }
        }
    }

    /// 设颜色：Pro 四色没解锁时弹付费墙，存着的颜色不动。
    private func setTag(_ item: TodoItem, _ tag: TodoTag?) {
        guard !context.isPreview else { return }
        guard ProLicenseGate.canTagTodo(tag, unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.tagging(item.id, with: tag, in: $0) }
        }
    }

    /// 设重复（Pro）：没解锁时弹付费墙；取消重复一直可以。
    private func setRepeat(_ item: TodoItem, _ rule: TodoRepeat?) {
        guard !context.isPreview else { return }
        guard rule == nil || ProLicenseGate.canRepeatTodos(unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.repeating(item.id, with: rule, in: $0) }
        }
    }

    // MARK: 键盘

    /// 键盘作用在哪一行：鼠标停着的，否则点选的。正在改字时不接。
    private var keyRow: TodoItem? {
        guard editing == nil else { return nil }
        let id = hovered ?? selected
        return id.flatMap { id in QuickTodo.items(instance.config).first { $0.id == id } }
    }

    private func handle(_ key: TodoKey) -> Bool {
        guard !context.isPreview else { return false }
        if key == .undo {
            // 输入框里有字时 ⌘Z 留给输入框自己撤销。
            guard draft.isEmpty, editing == nil, !undo.isEmpty else { return false }
            restore()
            return true
        }
        guard let item = keyRow else { return false }
        switch key {
        case .tag(let number):
            guard let tag = TodoTag.shortcut(number) else { return false }
            setTag(item, item.tag == tag ? nil : tag)
        case .clearTag:
            setTag(item, nil)
        case .toggleToday:
            guard !item.done else { return false }
            move(item, to: item.today ? .later : .today)
        case .move(let step):
            guard !item.done else { return false }
            let day = today
            withAnimation(listAnimation) {
                TodoLog.change(instance) { QuickTodo.nudging(item.id, by: step, in: $0, today: day) }
            }
        case .undo:
            return false
        }
        return true
    }

    // MARK: 提醒时间

    @ViewBuilder
    private func reminderItems(_ item: TodoItem) -> some View {
        let now = Date()
        ForEach(TodoReminderChoice.available(now: now), id: \.self) { choice in
            Button(choice.title) { setReminder(item, at: choice.date(now: Date())) }
        }
        Button("自定义…") {
            remindDate = item.remindAt ?? TodoReminderChoice.inOneHour.date(now: Date()) ?? Date()
            withAnimation(listAnimation) { reminding = item.id }
        }
        if item.remindAt != nil {
            Divider()
            Button("清除提醒") { setReminder(item, at: nil) }
        }
    }

    private func reminderPicker(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            DatePicker("", selection: $remindDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.field)
                .controlSize(.small)
            Spacer(minLength: 0)
            Button("取消") { withAnimation(listAnimation) { reminding = nil } }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelSecondary)
            Button("设定") { setReminder(item, at: remindDate) }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(accent.panelReadable)
        }
        .padding(.leading, 46)
        .padding(.bottom, 4)
    }

    private func setReminder(_ item: TodoItem, at date: Date?) {
        guard !context.isPreview else { return }
        withAnimation(listAnimation) {
            reminding = nil
            TodoLog.change(instance) { QuickTodo.settingReminder(item.id, at: date, in: $0) }
        }
    }

    // MARK: 转成提醒事项（免费，逐条）

    private func convertPicker(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            DatePicker("", selection: $convertDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .controlSize(.small)
            Spacer(minLength: 0)
            Button("取消") { withAnimation(listAnimation) { converting = nil } }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelSecondary)
            Button("转过去") { convert(item, due: convertDate) }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(accent.panelReadable)
                .help(tr("转成提醒事项"))
        }
        .padding(.leading, 46)
        .padding(.bottom, 4)
    }

    /// 在系统提醒事项里建一条，成功后从快速待办里拿掉（可以撤销）。
    private func convert(_ item: TodoItem, due: Date?) {
        guard !context.isPreview else { return }
        Task { @MainActor in
            let outcome = await TodoReminderExport.export(item, due: due)
            switch outcome {
            case .saved:
                withAnimation(listAnimation) {
                    converting = nil
                    notice = nil
                }
                delete(item)
            case .denied:
                noticeNeedsSettings = true
                withAnimation(listAnimation) { notice = tr("需要提醒事项权限才能转过去，可以在系统设置里开启。") }
            case .failed(let reason):
                noticeNeedsSettings = false
                withAnimation(listAnimation) { notice = tr("没能转成提醒事项：\(reason)") }
            }
        }
    }

    private func noticeLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if noticeNeedsSettings {
                Button("去开启") { TodoReminderExport.openPrivacySettings() }
                    .buttonStyle(.plain)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(accent.panelReadable)
            }
            Button {
                withAnimation(listAnimation) { notice = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("关闭"))
        }
        .foregroundStyle(.panelSecondary)
    }

    // MARK: 空状态

    /// 一条要做的都没有：小熊猫歇着，下面 4 个「试试这样写」，点一下只填进输入框。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TodoPanda(name: "pet-panda-rest", size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("清单空空的")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Text("写一件事，回车就记下。时间写在句子里就行。")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text("试试这样写")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            FlowChips(spacing: 6) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        draft = example
                    } label: {
                        Text(example)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(.panelFill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                    .help(tr("填进输入框"))
                }
            }
            Text("点一个，填进输入框（不会直接记下）")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
        .padding(14)
        .glassPane(cornerRadius: 14)
    }

    private static var examples: [String] {
        [tr("明天 9 点交稿"), tr("周五 取快递"), tr("今晚 8 点健身"), tr("下周一 交周报")]
    }

    // MARK: 已完成

    private func doneSection(_ rows: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(listAnimation) { doneOpen.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.panelTertiary)
                        Text(TodoGroup.done.title)
                            .font(.system(size: 13, weight: .bold))
                        Text(verbatim: "\(rows.count)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .imageScale(.small)
                            .rotationEffect(.degrees(doneOpen ? 90 : 0))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.panelSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(doneOpen ? tr("收起已完成") : tr("展开已完成"))
                Button("清空") {
                    guard !context.isPreview else { return }
                    withAnimation(listAnimation) {
                        TodoLog.change(instance) { QuickTodo.clearingDone($0) }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent.panelReadable)
                .help(tr("清除已完成"))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill))
            if doneOpen {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { item in
                            row(item, group: .done, first: true)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
    }

    // MARK: 已收起

    /// 前几天做完的：第二天收进这里，点开能看、能恢复、能删，做完 7 天后自动清掉。
    private func archiveSection(_ shelved: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(listAnimation) { archiveOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("已收起 \(shelved.count) 项 · 做完 \(QuickTodo.archiveDays) 天后清掉"))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .imageScale(.small)
                        .rotationEffect(.degrees(archiveOpen ? 90 : 0))
                }
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(archiveOpen ? tr("收起已完成") : tr("展开已完成"))
            if archiveOpen {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(shelved) { item in
                            archivedRow(item)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
    }

    private func archivedRow(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent.panelGraphic.opacity(0.7))
            Text(item.text)
                .font(.system(size: 13))
                .strikethrough(color: .panelSecondary)
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(QuickTodo.archivedDayLabel(item, today: today))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
            Button {
                withAnimation(listAnimation) { TodoLog.restore(item.id, in: instance) }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            .buttonStyle(.plain)
            .help(tr("恢复成未完成"))
            .accessibilityLabel(tr("恢复 \(item.text)"))
            Button {
                withAnimation(listAnimation) { TodoLog.removeArchived(item.id, in: instance) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
            }
            .buttonStyle(.plain)
            .help(tr("删除"))
            .accessibilityLabel(tr("删除 \(item.text)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.panelFill))
    }

    // MARK: 同步到提醒事项（Pro）

    private var syncFooter: some View {
        let enabled = TodoReminderSync.isEnabled(instance.config)
        let on = enabled && ProAccess.isUnlocked && !context.isPreview
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(.panelSeparator)
                .frame(height: 0.5)
            HStack(spacing: 8) {
                Text("同步到系统「提醒事项」")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ProBadge()
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(get: { on }, set: { setSync($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(accent)
                    .disabled(context.isPreview)
                    .accessibilityLabel(tr("同步到系统「提醒事项」"))
            }
            if on {
                syncStatus
            }
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        if let owner = sync.owner(), owner.id != instance.id {
            Text("另一张快速待办卡片已在同步，这张先不同步")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch sync.problem {
            case .denied:
                HStack(spacing: 6) {
                    Text("需要提醒事项权限才能同步")
                        .foregroundStyle(.panelSecondary)
                    Button("去开启") { TodoReminderSyncService.openPrivacySettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                }
                .font(.system(size: 13))
            case .missingList:
                HStack(spacing: 6) {
                    Text("选的列表找不到了")
                        .foregroundStyle(.panelSecondary)
                    listMenu(title: tr("换一个列表"))
                }
                .font(.system(size: 13))
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("没能同步：\(reason)"))
                        .foregroundStyle(.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    listLine
                }
                .font(.system(size: 13))
            case nil:
                listLine
            }
        }
    }

    /// “双向同步 · 列表「工作」”，列表名点开能换。
    private var listLine: some View {
        HStack(spacing: 4) {
            Text("双向同步 ·")
                .foregroundStyle(.panelSecondary)
            listMenu(title: tr("列表「\(sync.listTitle(instance.config) ?? tr("默认"))」"))
        }
        .font(.system(size: 13))
    }

    private func listMenu(title: String) -> some View {
        Menu {
            let current = instance.config.string(TodoReminderSync.listKey)
            ForEach(sync.lists(), id: \.id) { list in
                Button {
                    sync.choose(list: list.id, for: instance)
                } label: {
                    if list.id == current {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.panelSecondary)
        .help(tr("换一个提醒事项列表：没做完的会在新列表里建一遍，原来列表里的不动"))
    }

    private func setSync(_ value: Bool) {
        guard !context.isPreview else { return }
        guard ProAccess.isUnlocked else {
            PaywallWindow.shared.show()
            return
        }
        if value {
            let target = instance
            Task { @MainActor in
                let granted = await TodoReminderSyncService.shared.enable(target)
                if !granted {
                    noticeNeedsSettings = true
                    withAnimation(listAnimation) { notice = tr("需要提醒事项权限才能同步，可以在系统设置里开启。") }
                }
            }
        } else {
            sync.disable(instance)
        }
    }

    // MARK: 动作

    private var listAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3) }
    private var barAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25) }

    /// 勾上：圆圈按标签色填满、外面一圈淡色轻弹、划线，约 0.4 秒后沉进「已完成」
    /// （减少动态效果时直接换）。勾掉一项会记进撤销栈；把已完成的重新打开不记。
    private func toggle(_ item: TodoItem) {
        guard !context.isPreview, !completing.contains(item.id) else { return }
        guard !item.done, !reduceMotion else {
            commitToggle(item.id)
            return
        }
        let id = item.id
        withAnimation(.spring(duration: 0.18, bounce: 0.4)) {
            _ = completing.insert(id)
            _ = popping.insert(id)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.24)) { _ = popping.remove(id) }
            try? await Task.sleep(for: .milliseconds(240))
            commitToggle(id)
            completing.remove(id)
        }
    }

    private func commitToggle(_ id: String) {
        let current = QuickTodo.items(instance.config)
        guard let item = current.first(where: { $0.id == id }) else { return }
        let clearing = QuickTodo.clearsToday(toggling: id, in: current)
        let completingNow = !item.done
        withAnimation(listAnimation) { TodoLog.toggle(id, in: instance, cheering: clearing) }
        if completingNow { record { $0.recordCompletion(of: id, in: current) } }
        if clearing { celebrateAt = .now }
        if selected == id { selected = nil }
    }

    /// 删掉一条，几秒内可以撤销，放回原来的位置。
    private func delete(_ item: TodoItem) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        if editing == item.id { editing = nil }
        if hovered == item.id { hovered = nil }
        if selected == item.id { selected = nil }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.removing(item.id, from: $0) }
        }
        record { $0.recordDeletion(of: item.id, in: current) }
    }

    private func record(_ change: (inout TodoUndoStack) -> Void) {
        withAnimation(barAnimation) { change(&undo) }
        undoToken = UUID()
    }

    /// 退回最近的一步，放回它原来的位置；栈里还有就继续显示撤销条。
    private func restore() {
        guard !context.isPreview, let step = undo.pop() else { return }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { TodoUndoStack.undoing(step, in: $0) }
        }
        undoToken = UUID()
    }

    private func beginEditing(_ item: TodoItem) {
        guard !context.isPreview else { return }
        editDraft = item.text
        editing = item.id
        editFocus = item.id
    }

    private func finishEditing(_ id: String) {
        let text = editDraft
        editing = nil
        TodoLog.change(instance) { QuickTodo.renaming(id, to: text, in: $0) }
    }

    private var accent: Color {
        panelTint.accent(or: WidgetCatalog.accentHex(.todo).map { Color(hex: $0) } ?? WidgetStyle.primary)
    }

    private static let red = Color(hex: "#FF3B30")
    private static let orange = Color(hex: PaletteColor.orange.hex)
}

// MARK: - 拖起来的一行

/// 拖起来的样子：一张浮起的小卡，带影子，左边把手和圆圈。
private struct TodoDragPreview: View {
    var text: String
    var tag: TodoTag?
    var link: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Circle()
                .strokeBorder(tag?.color ?? Color.secondary, lineWidth: 1.6)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if link {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 270, height: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
    }
}

/// 「试试这样写」几个胶囊：一行放不下就换行。
private struct FlowChips: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 280
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - 拖动排序

/// 面板里拖一行用的类型，只在本进程里认，外面的拖放（文字、链接、文件）不会把它当成新待办。
enum TodoRowDrag {
    static let type = UTType(exportedAs: "app.dockling.quicktodo.row")
}

/// 拖到哪一组、哪一条前面（`before` 为 nil 时放在这一组最后）。
struct TodoDropSpot: Hashable, Sendable {
    var group: TodoGroup
    var before: String?
}

/// 已完成的行不接拖放。
private struct RowDropModifier: ViewModifier {
    var enabled: Bool
    var delegate: TodoRowDropDelegate

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [TodoRowDrag.type], delegate: delegate)
        } else {
            content
        }
    }
}

@MainActor
struct TodoRowDropDelegate: DropDelegate {
    var spot: TodoDropSpot
    var enabled: Bool
    var hover: @MainActor (TodoDropSpot) -> Void
    var leave: @MainActor (TodoDropSpot) -> Void
    var perform: @MainActor @Sendable (String, TodoDropSpot) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: [TodoRowDrag.type])
    }

    func dropEntered(info: DropInfo) {
        guard enabled else { return }
        hover(spot)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: enabled ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        leave(spot)
    }

    func performDrop(info: DropInfo) -> Bool {
        leave(spot)
        guard enabled, let provider = info.itemProviders(for: [TodoRowDrag.type]).first else { return false }
        let spot = self.spot
        let perform = self.perform
        _ = provider.loadDataRepresentation(forTypeIdentifier: TodoRowDrag.type.identifier) { data, _ in
            guard let data, let id = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in perform(id, spot) }
        }
        return true
    }
}
