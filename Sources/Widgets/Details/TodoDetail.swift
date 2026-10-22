import SwiftUI
import UniformTypeIdentifiers

/// 快速待办的展开面板（改版）：顶部进度、一个大输入框、今天 / 稍后 / 已完成三组。
///
/// - 输入框认自然语言时间（`TodoTimeParse`）：「明天 9 点交稿」里的「明天 9 点」标成
///   主题色，下面一行预览“明天 10/23 周五 09:00 提醒”，回车记成“交稿”。输入法选字
///   时不打断（见 `TodoInputField`）。认不出时间的进「稍后」。
/// - 顶部一行“今天还剩 3 件 · 已完成 5”和一根细进度条，替代原来的大标题和统计块。
/// - 分组不另外存：「今天」就是 `TodoItem.today`（替代原来最多 3 条的星标，不限条数），
///   拖进「今天」就是今天做。昨天没做完的每天第一次打开时自动排到今天最前面，截止
///   胶囊标红，不再弹顺延横幅。「已完成」默认折叠，右边「清空」。
/// - 每行只有圆形勾选、文字、截止胶囊（过期红、今天橙、以后灰）和重要的小红旗；
///   悬停才出现拖动把手、编辑和删除。右键：移到今天 / 稍后、重要、提醒我、转成
///   提醒事项（免费，逐条）、删除。
/// - 勾选时圆圈填色轻弹，约 0.4 秒后滑进「已完成」，可撤销；减少动态效果时直接换。
///   勾掉最后一件照旧跳出小熊猫。
/// - 底部「同步到系统『提醒事项』」开关（Pro，见 `TodoReminderSyncService`），没解锁
///   点了弹付费墙；打开后可以选列表。
/// - 文字、链接、文件照旧可以拖进面板记一条。
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
    /// 底部“已收起”（前几天做完的）展开着没有。
    @State private var archiveOpen = false
    /// 鼠标停在哪一行上：那一行才出现把手、编辑和删除。
    @State private var hovered: String?
    /// 刚勾上、正在播完成动效的几条（约 0.4 秒后才真的移进「已完成」）。
    @State private var completing: Set<String> = []
    /// 勾上那一下圆圈轻轻放大的几条。
    @State private var popping: Set<String> = []
    /// 拖动排序时停在哪儿（插入线画在那里）。
    @State private var dropSpot: TodoDropSpot?

    private var sync: TodoReminderSyncService { .shared }

    private var items: [TodoItem] {
        context.isPreview ? sample : QuickTodo.items(instance.config)
    }

    /// 小组件库里的示例：今天三条（一条昨天顺下来的、一条重要），稍后一条，做完一条。
    private var sample: [TodoItem] {
        let now = context.now
        let day = TodoDay.key(now)
        let yesterday = TodoDay.previous(day) ?? day
        return [
            TodoItem(id: "s1", text: tr("交电费"), today: true, addedDay: yesterday,
                     remindAt: now.addingTimeInterval(-20 * 3_600), todaySince: yesterday),
            TodoItem(id: "s2", text: tr("回复产品评审意见"), today: true, addedDay: day,
                     remindAt: now.addingTimeInterval(80 * 60), todaySince: day, important: true),
            TodoItem(id: "s3", text: tr("取快递"), today: true, addedDay: day, todaySince: day),
            TodoItem(id: "s4", text: tr("订周五的会议室"), addedDay: day,
                     remindAt: now.addingTimeInterval(2 * 86_400)),
            TodoItem(id: "s5", text: tr("回复产品评审"), done: true, addedDay: day, doneDay: day),
        ]
    }

    private var today: String { TodoDay.key(context.now) }
    private var unlocked: Bool { ProAccess.isUnlocked }

    var body: some View {
        let all = items
        let todayRows = QuickTodo.items(in: .today, of: all)
        let laterRows = QuickTodo.items(in: .later, of: all)
        let doneRows = QuickTodo.items(in: .done, of: all)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(QuickTodo.progress(all))
                inputSection
                if let notice {
                    noticeLine(notice)
                }
                if todayRows.isEmpty && laterRows.isEmpty {
                    emptyState(cleared: !doneRows.isEmpty)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            groupSection(.today, todayRows)
                            groupSection(.later, laterRows)
                        }
                    }
                    .frame(maxHeight: 340)
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
                    TodoUndoBar(step: step, more: undo.count - 1) { restore() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                syncFooter
            }
            // 拖着外面的东西停在面板上时把清单压暗，让“松手记一条待办”看得清。
            .opacity(targeted ? 0.3 : 1)
            .overlay {
                if let celebrateAt {
                    TodoCheer(startedAt: celebrateAt)
                        .frame(width: 220, height: 200)
                }
            }
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
            celebrateAt = nil
            // 卡片会在到点时清掉记号；面板也清一次，卡片恰好不在屏幕上时也不会卡住。
            if !context.isPreview { TodoLog.endCheer(instance) }
        }
    }

    // MARK: 顶部

    private func header(_ progress: TodoProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快速待办")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.panelPrimary)
            HStack(alignment: .firstTextBaseline) {
                Text(progress.line)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text(verbatim: "\(progress.done) / \(progress.total)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack)
                    Capsule()
                        .fill(accent.panelGraphic)
                        .frame(width: proxy.size.width * progress.fraction)
                }
            }
            .frame(height: 4)
            .animation(listAnimation, value: progress.fraction)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 输入

    private var parsed: TodoTimeParse? {
        TodoTimeParse.parse(draft, now: context.now)
    }

    private var canAdd: Bool { QuickTodo.clean(draft) != nil && !context.isPreview }

    private var inputSection: some View {
        let parse = parsed
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if draft.isEmpty {
                        Text("写一件事，回车添加，比如：明天 9 点交稿")
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
                        .foregroundStyle(canAdd ? Color.panelPrimary : Color.panelQuaternary)
                        .frame(width: 28, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.panelRaised).panelLift(canAdd))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .help(tr("添加待办"))
                .accessibilityLabel(tr("添加待办"))
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassPane(cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.panelGraphic.opacity(draft.isEmpty ? 0 : 0.6), lineWidth: 1)
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

    // MARK: 分组

    private func groupSection(_ group: TodoGroup, _ rows: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Text(verbatim: "\(rows.count)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(.rect)
            .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(TodoDropSpot(group: group, before: rows.first?.id)))
            .accessibilityAddTraits(.isHeader)

            if rows.isEmpty {
                emptyGroup(group)
            }
            ForEach(rows) { item in
                row(item, group: group)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                              removal: .opacity.combined(with: .move(edge: .bottom))))
            }
            if !rows.isEmpty {
                // 拖到这一组最后。
                insertionLine(TodoDropSpot(group: group, before: nil))
                    .frame(height: 8)
                    .contentShape(.rect)
                    .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(TodoDropSpot(group: group, before: nil)))
            }
        }
    }

    /// 一组空着时的一行虚线框：拖到这里放进来。
    private func emptyGroup(_ group: TodoGroup) -> some View {
        let spot = TodoDropSpot(group: group, before: nil)
        return Text(group == .today ? tr("把待办拖到这里，今天就做它") : tr("拖到这里，放到稍后再做"))
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(dropSpot == spot ? accent.panelGraphic : Color.panelSeparator,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect)
            .onDrop(of: [TodoRowDrag.type], delegate: rowDrop(spot))
    }

    /// 拖动排序的插入线，停在这个位置时才画。
    @ViewBuilder
    private func insertionLine(_ spot: TodoDropSpot) -> some View {
        ZStack {
            if dropSpot == spot {
                Capsule()
                    .fill(accent.panelGraphic)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity)
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
                withAnimation(animation) {
                    TodoLog.change(target) {
                        QuickTodo.moving(id, to: spot.group, before: spot.before, in: $0, today: day)
                    }
                }
            })
    }

    // MARK: 一行

    private func row(_ item: TodoItem, group: TodoGroup) -> some View {
        let isHovered = hovered == item.id && editing != item.id && !context.isPreview
        return VStack(alignment: .leading, spacing: 6) {
            rowLine(item, group: group, hovered: isHovered)
            if converting == item.id {
                convertPicker(item)
            }
            if reminding == item.id {
                reminderPicker(item)
            }
        }
        .padding(.leading, group == .done ? 10 : 4)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.panelRaised : Color.clear)
                .panelLift(isHovered)
        }
        .overlay(alignment: .top) {
            if group != .done {
                insertionLine(TodoDropSpot(group: group, before: item.id))
                    .offset(y: -2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .onHover { inside in
            if inside {
                hovered = item.id
            } else if hovered == item.id {
                hovered = nil
            }
        }
        .contextMenu { menu(item) }
        .modifier(RowDropModifier(enabled: group != .done,
                                  delegate: rowDrop(TodoDropSpot(group: group, before: item.id))))
    }

    private func rowLine(_ item: TodoItem, group: TodoGroup, hovered: Bool) -> some View {
        let checked = item.done || completing.contains(item.id)
        return HStack(spacing: 8) {
            if group != .done {
                dragHandle(item, visible: hovered)
            }
            checkButton(item, checked: checked)
            title(item, checked: checked)
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
            if !checked, let badge = QuickTodo.dueBadge(item, now: context.now) {
                dueCapsule(badge)
            }
            if item.important && !item.done {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.red.panelReadable)
                    .help(tr("重要"))
                    .accessibilityLabel(tr("重要"))
            }
            if hovered {
                hoverButton("pencil", help: tr("编辑")) { beginEditing(item) }
                hoverButton("trash", help: tr("删除")) { delete(item) }
            }
        }
        .frame(minHeight: 24)
    }

    /// 悬停才出现的拖动把手：拖进另一组就换组，拖进「今天」就是今天做。
    private func dragHandle(_ item: TodoItem, visible: Bool) -> some View {
        let id = item.id
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .frame(width: 16, height: 24)
            .contentShape(.rect)
            .opacity(visible ? 1 : 0)
            .onDrag {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: TodoRowDrag.type.identifier,
                                                    visibility: .ownProcess) { completion in
                    completion(Data(id.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                Text(item.text)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
            }
            .help(tr("拖动排序，拖进「今天」就是今天做"))
            .accessibilityHidden(true)
    }

    private func checkButton(_ item: TodoItem, checked: Bool) -> some View {
        let fill = accent.panelGraphic
        return Button {
            toggle(item)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.panelTertiary, lineWidth: 1.5)
                    .opacity(checked ? 0 : 1)
                Circle()
                    .fill(fill.opacity(item.done ? 0.7 : 1))
                    .opacity(checked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            .scaleEffect(popping.contains(item.id) ? 1.22 : 1)
            .frame(width: 24, height: 24)
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
                .font(.system(size: 14))
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
                .font(.system(size: 14))
                .foregroundStyle(checked ? Color.panelSecondary : Color.panelPrimary)
                .strikethrough(checked, color: .panelSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(count: 2) { beginEditing(item) }
                .help(tr("双击编辑"))
        }
    }

    /// 行尾的截止时间胶囊：过期红、今天橙、以后灰。
    private func dueCapsule(_ badge: TodoDueBadge) -> some View {
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
        return Text(badge.text)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(fill))
            .fixedSize()
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

    // MARK: 右键

    @ViewBuilder
    private func menu(_ item: TodoItem) -> some View {
        if !item.done {
            if item.today {
                Button("移到稍后") { move(item, to: .later) }
            } else {
                Button("移到今天") { move(item, to: .today) }
            }
            Button(item.important ? tr("取消重要") : tr("标为重要")) { toggleImportant(item) }
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

    private func move(_ item: TodoItem, to group: TodoGroup) {
        guard !context.isPreview else { return }
        let day = today
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.moving(item.id, to: group, before: nil, in: $0, today: day) }
        }
    }

    private func toggleImportant(_ item: TodoItem) {
        guard !context.isPreview else { return }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.togglingImportant(item.id, in: $0) }
        }
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
            Text("提醒时间")
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
        .padding(.leading, 28)
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
            Text("提醒日期")
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
            Button("转成提醒事项") { convert(item, due: convertDate) }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(accent.panelReadable)
        }
        .padding(.leading, 28)
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

    /// 没有要做的：小熊猫歇着。全做完了标题换成“都做完啦”。
    private func emptyState(cleared: Bool) -> some View {
        HStack(spacing: 14) {
            if let image = PandaArt.image("pet-panda-rest") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(cleared ? tr("都做完啦") : tr("清单空空的"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text("今天也辛苦啦，去喝口水歇一歇")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("输入框里写一件事，回车就记下")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: 已完成

    private func doneSection(_ rows: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(listAnimation) { doneOpen.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(.degrees(doneOpen ? 90 : 0))
                        Text(TodoGroup.done.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(rows.count)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.panelReadable)
                .help(tr("清除已完成"))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill))
            if doneOpen {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(rows) { item in
                            row(item, group: .done)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(archiveOpen ? 90 : 0))
                    Text(tr("已收起 \(shelved.count) 项"))
                        .font(WidgetStyle.label(13))
                    Spacer()
                    Text(tr("做完 \(QuickTodo.archiveDays) 天后清掉"))
                        .font(.system(size: 13))
                }
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 10)
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
        let on = enabled && unlocked && !context.isPreview
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(.panelSeparator)
                .frame(height: 0.5)
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Text("同步到系统「提醒事项」")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
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
                    .padding(.leading, 21)
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
        guard unlocked else {
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

    /// 勾上：圆圈填色轻弹，约 0.4 秒后滑进「已完成」（减少动态效果时直接换）。
    /// 勾掉一项会记进撤销栈；把已完成的重新打开不记。
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
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.25, bounce: 0.5)) { _ = popping.remove(id) }
            try? await Task.sleep(for: .milliseconds(250))
            commitToggle(id)
            completing.remove(id)
        }
    }

    private func commitToggle(_ id: String) {
        let current = QuickTodo.items(instance.config)
        guard let item = current.first(where: { $0.id == id }) else { return }
        let finishing = QuickTodo.finishesAll(toggling: id, in: current)
        let completingNow = !item.done
        withAnimation(listAnimation) { TodoLog.toggle(id, in: instance, cheering: finishing) }
        if completingNow { record { $0.recordCompletion(of: id, in: current) } }
        if finishing { celebrateAt = .now }
    }

    /// 删掉一条，几秒内可以撤销，放回原来的位置。
    private func delete(_ item: TodoItem) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        if editing == item.id { editing = nil }
        if hovered == item.id { hovered = nil }
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
