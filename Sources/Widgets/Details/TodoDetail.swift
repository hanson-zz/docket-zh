import SwiftUI

/// The whole list: a field to add to it, a check per task, and a way to
/// sweep the finished ones away.
///
/// Return adds and keeps the caret in the field, so a run of tasks can be
/// typed one after another. Double-clicking a task's words edits them.
/// Dragging a row to the left deletes it, and deleting or checking a task can
/// be undone for a few seconds, the last five steps one at a time, each put
/// back where it was. Checking the last open task brings out the red panda.
///
/// 每一条可以设一个提醒时间（行尾的小闹钟或右键「提醒我」：1 小时后、今晚 20:00、
/// 明天 9:00 或自定义），到点从刘海下方弹出卡片。顺延到今天时，定在昨天以前的
/// 提醒挪到今天同一时刻，那个时刻已经过了就清掉。
///
/// 星标或右键把最多三条标为“今天三件事”，卡片上优先画它们。右键还能打开拖进来
/// 的链接或文件、转成系统提醒事项（这时才请求权限）。新的一天第一次打开时，
/// 昨天没做完的会在顶部问一句顺延到今天还是放弃。文字、链接、文件也可以直接
/// 拖进面板。
struct TodoDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var editing: String?
    @State private var editDraft = ""
    @FocusState private var focus: Field?
    @State private var celebrateAt: Date?
    /// 最近几步删除和完成，撤销条按后进先出一步步退回。
    @State private var undo = TodoUndoStack()
    /// 每记一步换一个，撤销条从最后一次改动起再停几秒。
    @State private var undoToken = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targeted = false
    /// 正在挑日期转成提醒事项的那一条。
    @State private var converting: String?
    @State private var convertDate = Date()
    /// 转成提醒事项没成功时的一句话。
    @State private var notice: String?
    @State private var noticeNeedsSettings = false
    /// 正在自定义提醒时间的那一条。
    /// 底部“已收起”展开着没有。
    @State private var archiveOpen = false
    @State private var reminding: String?
    @State private var remindDate = Date()

    private enum Field: Hashable {
        case add
        case edit(String)
    }

    private var items: [TodoItem] {
        if context.isPreview {
            return [TodoItem(id: "s1", text: tr("回复产品评审意见"), today: true),
                    TodoItem(id: "s2", text: tr("取快递"), today: true),
                    TodoItem(id: "s3", text: tr("订周五的会议室")),
                    TodoItem(id: "s4", text: tr("交电费"), done: true)]
        }
        return QuickTodo.items(instance.config)
    }

    private var showDone: Bool { instance.config.bool("showDone", default: true) }

    var body: some View {
        let all = items
        let open = QuickTodo.open(all)
        let done = all.filter(\.done)
        let shown = showDone ? open + done : open
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(open: open.count, done: done.count)
                let late = context.isPreview ? [] : QuickTodo.leftover(all, today: today)
                if !late.isEmpty {
                    leftoverBanner(count: late.count)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                addField
                if let notice {
                    noticeLine(notice)
                }
                if shown.isEmpty {
                    Text(all.isEmpty ? tr("清单是空的。输入一件事，按回车添加。") : tr("都做完了。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(shown) { item in
                                row(item)
                                    .swipeToDelete(enabled: !context.isPreview && editing != item.id) {
                                        delete(item, animated: false)
                                    }
                                    .transition(reduceMotion
                                                ? .opacity
                                                : .asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)),
                                                              removal: .opacity))
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .scrollIndicators(.never)
                }
                if !done.isEmpty {
                    HStack {
                        if !showDone {
                            Text(tr("已完成 \(done.count) 项（已隐藏）"))
                                .font(.system(size: 13))
                                .foregroundStyle(.panelTertiary)
                        }
                        Spacer()
                        Button("清除已完成") {
                            guard !context.isPreview else { return }
                            withAnimation(.snappy(duration: 0.3)) {
                                TodoLog.change(instance) { QuickTodo.clearingDone($0) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelPrimary)
                    }
                }
                let shelved = context.isPreview ? [] : QuickTodo.archive(instance.config)
                if !shelved.isEmpty {
                    archiveSection(shelved)
                }
                if let step = undo.last {
                    TodoUndoBar(step: step, more: undo.count - 1) { restore() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            // 拖着东西停在面板上时把清单压暗，让“松手记一条待办”看得清。
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
            focus = .add
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

    private func header(open: Int, done: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("随手记，不同步")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.panelSecondary)
                Text(open == 0 ? tr("全部完成") : tr("\(open) 项未完成"))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
            }
            Spacer()
            if done > 0 {
                StatChip(label: tr("已完成"), value: "\(done)")
                    .frame(width: 76)
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
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(archiveOpen ? 90 : 0))
                    Text(tr("已收起 \(shelved.count) 项"))
                        .font(WidgetStyle.label(13))
                    Spacer()
                    Text(tr("做完 \(QuickTodo.archiveDays) 天后清掉"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                }
                .foregroundStyle(.panelSecondary)
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
                .foregroundStyle(panelTint.accent(or: Color(hex: PaletteColor.orange.hex)).panelReadable.opacity(0.6))
            Text(item.text)
                .font(.system(size: 13))
                .strikethrough()
                .foregroundStyle(.panelTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(QuickTodo.archivedDayLabel(item, today: today))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.panelTertiary)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
            }
            .buttonStyle(.plain)
            .help(tr("删除"))
            .accessibilityLabel(tr("删除 \(item.text)"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.panelFill))
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.panelSecondary)
            TextField("", text: $draft, prompt: Text("添加待办，按回车"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .focused($focus, equals: .add)
                .onSubmit(add)
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .glassPane(cornerRadius: 10)
    }

    private func row(_ item: TodoItem) -> some View {
        let canMark = QuickTodo.canMarkToday(items)
        return VStack(alignment: .leading, spacing: 6) {
            rowLine(item, canMark: canMark)
            if converting == item.id {
                convertPicker(item)
            }
            if reminding == item.id {
                reminderPicker(item)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.panelFill.opacity(item.today && !item.done ? 1 : 0.55)))
        .contextMenu { menu(item, canMark: canMark) }
    }

    private func rowLine(_ item: TodoItem, canMark: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? panelTint.accent(or: Color(hex: PaletteColor.orange.hex)).panelReadable : .panelSecondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? tr("标为未完成") : tr("标为完成"))

            if editing == item.id {
                TextField("", text: $editDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary)
                    .focused($focus, equals: .edit(item.id))
                    .onSubmit { finishEditing(item.id) }
                    .onChange(of: focus) { _, now in
                        if now != .edit(item.id), editing == item.id { finishEditing(item.id) }
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary.opacity(item.done ? 0.45 : 0.95))
                    .strikethrough(item.done, color: .panelTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { beginEditing(item) }
                    .help("双击编辑")
            }

            if item.url != nil {
                Button {
                    TodoLinkOpener.open(item)
                } label: {
                    Image(systemName: TodoLinkOpener.symbol(item))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(item.url?.isFileURL == true ? tr("打开文件") : tr("打开链接"))
                .accessibilityLabel(tr("打开 \(item.text)"))
            }

            reminderButton(item)

            starButton(item, canMark: canMark)

            Button {
                delete(item, animated: true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("删除 \(item.text)"))
            .help("删除，也可以把这一行往左拖")
        }
    }

    // MARK: 今天三件事

    private func starButton(_ item: TodoItem, canMark: Bool) -> some View {
        let available = item.today || canMark
        return Button {
            markToday(item)
        } label: {
            Image(systemName: item.today ? "star.fill" : "star")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.today ? Color(hex: "#FFCC00").panelReadable : .panelPrimary.opacity(available ? 0.45 : 0.2))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!available || context.isPreview)
        .help(item.today ? tr("从今天三件事里拿掉")
              : (canMark ? tr("标为今天要做（最多 3 条）") : tr("今天三件事已经标满 3 条")))
        .accessibilityLabel(item.today ? tr("取消今天要做") : tr("标为今天要做"))
    }

    private func markToday(_ item: TodoItem) {
        guard !context.isPreview else { return }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { QuickTodo.togglingToday(item.id, in: $0) }
        }
    }

    @ViewBuilder
    private func menu(_ item: TodoItem, canMark: Bool) -> some View {
        if item.today {
            Button("从今天三件事里拿掉") { markToday(item) }
        } else {
            Button("标为今天要做") { markToday(item) }
                .disabled(!canMark || context.isPreview)
        }
        if item.url != nil {
            Button(item.url?.isFileURL == true ? tr("打开文件") : tr("打开链接")) { TodoLinkOpener.open(item) }
        }
        Menu("提醒我") { reminderItems(item) }
            .disabled(context.isPreview || item.done)
        Divider()
        Menu("转成提醒事项") {
            Button("今天") { convert(item, due: Date()) }
            Button("明天") { convert(item, due: Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
            Button("选日期…") {
                convertDate = Date()
                withAnimation(listAnimation) { converting = item.id }
            }
            Divider()
            Button("不设日期") { convert(item, due: nil) }
        }
        .disabled(context.isPreview)
        Divider()
        Button("删除", role: .destructive) { delete(item, animated: true) }
            .disabled(context.isPreview)
    }

    // MARK: 提醒时间

    /// 行尾的小闹钟：没设时是空心的，设了时带上时刻；点开是快捷选项。
    private func reminderButton(_ item: TodoItem) -> some View {
        Menu {
            reminderItems(item)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: item.remindAt == nil ? "alarm" : "alarm.fill")
                if let at = item.remindAt {
                    Text(QuickTodo.reminderLabel(at, now: context.now))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(item.remindAt == nil ? .panelTertiary : accent.panelReadable)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(context.isPreview || item.done)
        .help(item.remindAt.map { tr("\(QuickTodo.reminderLabel($0, now: context.now)) 提醒，点按修改") } ?? tr("设提醒时间，到点弹出卡片"))
        .accessibilityLabel(tr("提醒时间"))
    }

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
                .foregroundStyle(.panelPrimary)
        }
        .padding(.leading, 24)
    }

    private func setReminder(_ item: TodoItem, at date: Date?) {
        guard !context.isPreview else { return }
        withAnimation(listAnimation) {
            reminding = nil
            TodoLog.change(instance) { QuickTodo.settingReminder(item.id, at: date, in: $0) }
        }
    }

    // MARK: 转成提醒事项

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
                .foregroundStyle(.panelPrimary)
        }
        .padding(.leading, 24)
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
                delete(item, animated: true)
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
                    .foregroundStyle(.panelPrimary)
            }
            Button {
                withAnimation(listAnimation) { notice = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("关闭"))
        }
        .foregroundStyle(.panelSecondary)
    }

    // MARK: 当天清

    private var today: String { TodoDay.key(context.now) }

    /// 昨天没做完的：顺延到今天，或者放弃。
    private func leftoverBanner(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("昨天还有 \(count) 件没做完"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            HStack(spacing: 8) {
                Button {
                    let day = today
                    withAnimation(listAnimation) {
                        TodoLog.change(instance) { QuickTodo.carryingOver($0, today: day, now: .now) }
                    }
                } label: {
                    Text("顺延到今天")
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(panelTint.ink(or: .panelPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(panelTint.accent(or: .panelRaised)).panelLift(panelTint == nil))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    let day = today
                    withAnimation(listAnimation) {
                        TodoLog.change(instance) { QuickTodo.droppingLeftover($0, today: day) }
                    }
                } label: {
                    Text("放弃")
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.panelFill))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func add() {
        guard !context.isPreview, QuickTodo.clean(draft) != nil else { return }
        let text = draft
        withAnimation(.snappy(duration: 0.3)) {
            TodoLog.add(text, to: instance)
        }
        draft = ""
        focus = .add
    }

    private var listAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3) }
    private var barAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25) }

    /// 勾掉一项会记进撤销栈；把已完成的重新打开不记。
    private func toggle(_ item: TodoItem) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        let finishing = QuickTodo.finishesAll(toggling: item.id, in: current)
        let completing = current.first(where: { $0.id == item.id })?.done == false
        withAnimation(listAnimation) { TodoLog.toggle(item.id, in: instance, cheering: finishing) }
        if completing { record { $0.recordCompletion(of: item.id, in: current) } }
        if finishing { celebrateAt = .now }
    }

    /// Removes the task and offers it back for a few seconds. A swipe has
    /// already slid the row away, so it is not animated a second time.
    private func delete(_ item: TodoItem, animated: Bool) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        if editing == item.id { editing = nil }
        withAnimation(animated ? listAnimation : nil) {
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
        focus = .edit(item.id)
    }

    private func finishEditing(_ id: String) {
        let text = editDraft
        editing = nil
        TodoLog.change(instance) { QuickTodo.renaming(id, to: text, in: $0) }
    }

    private var accent: Color {
        panelTint.accent(or: WidgetCatalog.accentHex(.todo).map { Color(hex: $0) } ?? WidgetStyle.primary)
    }
}
