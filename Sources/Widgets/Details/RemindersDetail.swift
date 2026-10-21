import AppKit
import EventKit
import SwiftUI

/// 今天要做的提醒事项，能直接改，改完写回系统“提醒事项”，经 iCloud 同步到 iPhone。
///
/// Like `CalendarDetail`, this talks to EventKit itself and keeps what it
/// finds in value types of its own; every write goes through `ReminderSync`,
/// the same store the card uses. Opening the panel is the user asking, so the
/// first time it opens without an answer it asks for access itself; once the
/// answer is no it says so in a line and offers System Settings.
///
/// 列出还没完成的：已过期、今天、明天、之后 7 天四段（改到明天或下周的那条
/// 换一段留着，不会一改就消失），可以：
/// - 点行前的圆圈完成；
/// - 点一行展开内联编辑：标题、日期和时刻（都可以不要）、优先级、列表，回车保存，
///   也能在这里删除；
/// - 右键推到明天、推到下周一、完成、删除；
/// - 右上角“＋ 新提醒”。
/// 小组件筛选了某个列表（config `list`，按标题）时只列那个列表，新提醒也放进去。
struct RemindersDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var access = EKEventStore.authorizationStatus(for: .reminder)
    @State private var rows: [DueReminder] = []
    /// List colours, resolved on the main actor when the fetch is started:
    /// an `EKCalendar` cannot be carried out of the fetch's completion, and a
    /// ring in a list's own colour is what tells two identical titles apart.
    @State private var tints: [String: Color] = [:]
    /// 能写的列表，编辑器里的“列表”菜单用。
    @State private var lists: [ListChoice] = []
    /// Fetches are async and the panel can be pointed at another widget while
    /// one is in flight; only the newest is allowed to land.
    @State private var generation = 0
    /// 正在编辑的那一条；`id` 为 nil 是新提醒。
    @State private var editing: Draft?
    /// 刚点完成的，系统通知回来之前先拿掉。
    @State private var finishing: Set<String> = []
    /// 一句临时提示：保存到了今天以外、写回失败。
    @State private var notice: String?
    /// 这次打开已经请求过权限，不再自动问第二次。
    @State private var asked = false
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: EKEventStore { ReminderSync.store }

    private var granted: Bool { access == .fullAccess }

    /// The list the widget was configured for, by title. Empty - the catalog
    /// default - means every list.
    private var listFilter: String {
        instance.config.string("list").trimmingCharacters(in: .whitespaces)
    }

    /// How many rows the panel will draw before it starts counting instead.
    ///
    /// A day's events are bounded; a backlog of overdue reminders is not, so
    /// the list scrolls inside a fixed height and is cut off after this many.
    private static let visibleRows = 20

    private struct ListChoice: Identifiable, Hashable {
        var id: String
        var title: String
    }

    /// 编辑器里的一份草稿，保存时才写回。
    private struct Draft: Equatable {
        var id: String?
        var title: String
        var hasDate: Bool
        var day: Date
        var hasTime: Bool
        var time: Date
        var priority: ReminderPriority
        var listID: String

        var isNew: Bool { id == nil }

        var due: ReminderDue? {
            hasDate ? ReminderTiming.combine(day: day, time: hasTime ? time : nil) : nil
        }
    }

    var body: some View {
        // Minute by minute, not from `context.now`: the chrome assigns this
        // view once, so the frozen tick would keep a reminder sitting under
        // "Today" long after its time had passed.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(now: timeline.date)
                // The fetch window is counted from today, so at midnight it
                // has moved on.
                .onChange(of: Calendar.current.startOfDay(for: timeline.date)) { _, _ in load() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            load()
            askOnFirstUse()
        }
        // The chrome swaps its root view rather than rebuilding it, so this
        // view survives being reopened on another widget.
        .onChange(of: instance.id) { _, _ in
            editing = nil
            load()
        }
        // 在“提醒事项”App 或 iPhone 上改过，或者这里写回之后。
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(listAnimation) { notice = nil }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let shown = rows.filter { !finishing.contains($0.id) }
        let sections = Self.sections(shown, now: now)
        let overdue = sections[.overdue] ?? []
        let today = sections[.today] ?? []

        // Red once anything is late, the widget's own colour otherwise: the
        // card says whether you are behind before a title is read.
        DetailCard {
            MeshBackdrop(color: overdue.isEmpty ? Self.fallbackTint : Self.red, fixed: !overdue.isEmpty)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if granted {
                    summary(overdue: overdue.count, today: today.count)
                    if let draft = editing, draft.isNew {
                        editor(draft, now: now)
                            .transition(.opacity)
                    }
                    if !shown.isEmpty {
                        list(sections, now: now)
                    }
                    if let notice {
                        Text(notice)
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                } else {
                    permission
                }
            }
            .animation(listAnimation, value: editing)
            .animation(listAnimation, value: shown.map(\.id))
        }
    }

    // MARK: Summary

    /// The two counts, which is what the sections below cannot say once the
    /// list is cut off, and the button that starts a new reminder.
    private func summary(overdue: Int, today: Int) -> some View {
        let total = overdue + today
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(total)")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(total)
                VStack(alignment: .leading, spacing: 0) {
                    Text(total == 0 ? tr("今天没有到期事项") : tr("项今晚前到期"))
                        .font(WidgetStyle.label(14))
                        .foregroundStyle(.panelPrimary)
                    // Which list this is a view of, when it is not all of them
                    // - otherwise the count reads as the whole account and is
                    // not.
                    if !listFilter.isEmpty {
                        Text(listFilter)
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(.panelSecondary)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    startNew()
                } label: {
                    Text(tr("＋ 新提醒"))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(panelTint.accent(or: Self.fallbackTint).panelReadable)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview || editing?.isNew == true)
                .help(tr("新建一条提醒事项，同步到 iPhone"))
            }
            .lineLimit(1)
            if total > 0 {
                HStack(spacing: 8) {
                    StatChip(label: tr("已过期"), value: "\(overdue)")
                    StatChip(label: tr("今天"), value: "\(today)")
                }
            }
        }
    }

    // MARK: List

    /// 每一段里的提醒，按到期先后；超出“之后 7 天”的不列。
    private static func sections(_ rows: [DueReminder],
                                 now: Date) -> [ReminderTiming.PanelSection: [DueReminder]] {
        var result: [ReminderTiming.PanelSection: [DueReminder]] = [:]
        for row in rows {
            guard let section = ReminderTiming.panelSection(row.dueValue, now: now) else { continue }
            result[section, default: []].append(row)
        }
        return result
    }

    /// Overdue first, then the rest of today, then tomorrow and the week
    /// after, each in due order.
    ///
    /// Labelled sections rather than one stream: "yesterday 09:00" and
    /// "18:00" sitting in the same list look like the same kind of thing, and
    /// the whole point of the panel is that they are not.
    @ViewBuilder
    private func list(_ sections: [ReminderTiming.PanelSection: [DueReminder]], now: Date) -> some View {
        // The cut falls on the overdue block first: what is already late
        // outranks what is merely coming, and today outranks next week.
        let cut = Self.cut(sections)
        let total = sections.values.reduce(0) { $0 + $1.count }
        let hidden = total - cut.values.reduce(0) { $0 + $1.count }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ReminderTiming.PanelSection.allCases, id: \.self) { part in
                    section(part.title, cut[part] ?? [],
                            tint: part == .overdue ? .panelPrimary : (part == .today ? .panelSecondary : .panelTertiary),
                            now: now)
                }
                if hidden > 0 {
                    Text(tr("“提醒事项”中还有 \(hidden) 项"))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
        }
        .frame(maxHeight: 380)
        .scrollIndicators(.never)
    }

    /// 最多画 `visibleRows` 行，按段的先后分。
    private static func cut(_ sections: [ReminderTiming.PanelSection: [DueReminder]])
        -> [ReminderTiming.PanelSection: [DueReminder]] {
        var left = visibleRows
        var result: [ReminderTiming.PanelSection: [DueReminder]] = [:]
        for part in ReminderTiming.PanelSection.allCases {
            let rows = Array((sections[part] ?? []).prefix(left))
            left -= rows.count
            result[part] = rows
        }
        return result
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [DueReminder], tint: Color, now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                ForEach(items) { item in
                    if let draft = editing, draft.id == item.id {
                        editor(draft, now: now)
                    } else {
                        row(item, now: now)
                    }
                }
            }
        }
    }

    private func row(_ item: DueReminder, now: Date) -> some View {
        let late = item.isOverdue(now)
        return HStack(alignment: .top, spacing: 9) {
            Button {
                complete(item)
            } label: {
                Circle()
                    .strokeBorder(late ? Self.red : (tints[item.listID] ?? Self.fallbackTint), lineWidth: 1.5)
                    .frame(width: 15, height: 15)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(tr("完成“\(item.title)”"))
            .accessibilityLabel(tr("完成 \(item.title)"))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    // Reminders.app's own marks, and the only ranking EventKit
                    // gives that a due-date sort throws away.
                    if item.priority != .none {
                        Text(item.priority.marks)
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
                    }
                    Text(item.title)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(WidgetStyle.primary)
                }
                Text(detail(item, now: now))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(late ? Self.red.panelReadable : WidgetStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPane(cornerRadius: 10)
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { beginEditing(item) }
        .help(tr("点按编辑，右键推迟"))
        .contextMenu { menu(item, now: now) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func menu(_ item: DueReminder, now: Date) -> some View {
        Button(tr("推到明天")) {
            reschedule(item, to: ReminderTiming.tomorrow(item.dueValue, now: now))
        }
        Button(tr("推到下周一")) {
            reschedule(item, to: ReminderTiming.nextMonday(item.dueValue, now: now))
        }
        Button(tr("推迟 1 小时")) {
            reschedule(item, to: ReminderTiming.snoozed(item.dueValue, now: now))
        }
        Divider()
        Button(tr("完成")) { complete(item) }
        Button(tr("编辑")) { beginEditing(item) }
        Divider()
        Button(tr("删除"), role: .destructive) { remove(item.id) }
    }

    /// When it was due, then which list it is on - two reminders at 09:00 are
    /// told apart by the list, never the other way round.
    private func detail(_ item: DueReminder, now: Date) -> String {
        let calendar = Calendar.current
        let when: String
        if !item.hasTime {
            when = calendar.isDate(item.due, inSameDayAs: now)
                ? tr("全天")
                : (ReminderTiming.shortDay(item.dueValue, now: now)
                   ?? item.due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        } else if calendar.isDate(item.due, inSameDayAs: now) {
            when = ReminderTiming.nextLine(item.dueValue, now: now,
                                           clock: item.due.formatted(date: .omitted, time: .shortened))
        } else {
            let day = ReminderTiming.shortDay(item.dueValue, now: now)
                ?? item.due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            when = "\(day) \(item.due.formatted(date: .omitted, time: .shortened))"
        }
        return item.list.isEmpty ? when : "\(when) · \(item.list)"
    }

    // MARK: Editor

    /// 展开的那一行：标题、日期、时刻、优先级、列表；回车保存。
    private func editor(_ current: Draft, now: Date) -> some View {
        let draft = Binding<Draft>(get: { editing ?? current }, set: { editing = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .strokeBorder(.panelTertiary, lineWidth: 1.5)
                    .frame(width: 15, height: 15)
                TextField("", text: draft.title, prompt: Text(tr("新提醒事项")))
                    .textFieldStyle(.plain)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                    .focused($titleFocused)
                    .onSubmit(save)
            }

            field(tr("日期")) {
                Toggle("", isOn: draft.hasDate)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(panelTint.control)
                    .controlSize(.mini)
                if current.hasDate {
                    DatePicker("", selection: draft.day, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
            if current.hasDate {
                field(tr("时间")) {
                    Toggle("", isOn: draft.hasTime)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(panelTint.control)
                        .controlSize(.mini)
                    if current.hasTime {
                        DatePicker("", selection: draft.time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                }
            }
            field(tr("优先级")) {
                Picker("", selection: draft.priority) {
                    ForEach(ReminderPriority.menuOrder, id: \.self) { level in
                        Text(level == .none ? level.title : "\(level.marks) \(level.title)").tag(level)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if !lists.isEmpty {
                field(tr("列表")) {
                    Picker("", selection: draft.listID) {
                        ForEach(lists) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Circle()
                        .fill(tints[current.listID] ?? Self.fallbackTint)
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 8) {
                Text(tr("回车保存"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelTertiary)
                if let id = current.id {
                    Text("·")
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelTertiary)
                    Button(tr("删除"), role: .destructive) { remove(id) }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(Self.red.panelReadable)
                }
                Spacer()
                Button(tr("取消")) { editing = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button(tr("保存"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                    .disabled(Self.clean(current.title) == nil)
            }
        }
        .controlSize(.small)
        .padding(12)
        .glassPane(cornerRadius: 10)
        .onAppear { titleFocused = true }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .frame(width: 52, alignment: .leading)
                .padding(.leading, 24)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    private func startNew() {
        guard !context.isPreview, granted else { return }
        let now = Date()
        let list = ReminderSync.defaultList(named: listFilter)
        editing = Draft(id: nil, title: "", hasDate: true,
                        day: Calendar.current.startOfDay(for: now),
                        hasTime: false, time: ReminderTiming.suggestedTime(now: now),
                        priority: .none, listID: list?.calendarIdentifier ?? lists.first?.id ?? "")
    }

    private func beginEditing(_ item: DueReminder) {
        guard !context.isPreview, granted else { return }
        let now = Date()
        editing = Draft(id: item.id, title: item.title, hasDate: true,
                        day: Calendar.current.startOfDay(for: item.due),
                        hasTime: item.hasTime,
                        time: item.hasTime ? item.due : ReminderTiming.suggestedTime(now: now),
                        priority: item.priority, listID: item.listID)
    }

    private func save() {
        guard let draft = editing, let title = Self.clean(draft.title) else { return }
        let due = draft.due
        let saved = ReminderSync.save(id: draft.id, title: title, due: due, priority: draft.priority,
                                      listID: draft.listID.isEmpty ? nil : draft.listID,
                                      fallbackList: listFilter)
        guard saved != nil else {
            notice = tr("没能写回“提醒事项”，请稍后再试。")
            return
        }
        editing = nil
        if !ReminderTiming.staysInPanel(due, now: Date()) {
            notice = tr("已保存到“提醒事项”。它不在之后 7 天内，所以不在这里显示。")
        }
        load()
    }

    private func complete(_ item: DueReminder) {
        guard !context.isPreview else { return }
        if editing?.id == item.id { editing = nil }
        finishing.insert(item.id)
        if !ReminderSync.complete(item.id) {
            finishing.remove(item.id)
            notice = tr("没能写回“提醒事项”，请稍后再试。")
        }
    }

    private func reschedule(_ item: DueReminder, to due: ReminderDue) {
        guard !context.isPreview else { return }
        if ReminderSync.reschedule(item.id, to: due) {
            if !ReminderTiming.staysInPanel(due, now: Date()) {
                notice = tr("已推迟“\(item.title)”。")
            }
        } else {
            notice = tr("没能写回“提醒事项”，请稍后再试。")
        }
    }

    private func remove(_ id: String) {
        guard !context.isPreview else { return }
        if editing?.id == id { editing = nil }
        finishing.insert(id)
        if !ReminderSync.remove(id) {
            finishing.remove(id)
            notice = tr("没能写回“提醒事项”，请稍后再试。")
        }
    }

    private static func clean(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var listAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)
    }

    // MARK: No access

    private var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(access == .notDetermined
                 ? tr("码头尚未获得访问你提醒事项的权限。")
                 : tr("码头的提醒事项访问权限已关闭。"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Once the answer is no, asking again returns it unchanged with no
            // prompt on screen, so the only button worth drawing is the one
            // that goes where the answer can be changed.
            if access == .notDetermined {
                action(tr("允许访问")) { request() }
            } else {
                action(tr("打开系统设置")) { openPrivacySettings() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ title: String, run: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            run()
        } label: {
            Text(title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.panelRaised).panelLift())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Store

    /// Everything incomplete and dated up to the end of the week after
    /// tomorrow (`ReminderTiming.panelEnd`): overdue, today, tomorrow and the
    /// next seven days in one predicate. Reminders with no due date are
    /// not returned by a dated predicate, and the panel does not pretend
    /// otherwise: it is a list of what is *due*.
    private func load() {
        guard !context.isPreview else { return }
        access = EKEventStore.authorizationStatus(for: .reminder)
        guard granted else {
            rows = []
            tints = [:]
            lists = []
            return
        }

        let all = store.calendars(for: .reminder)
        // Two lists can share a title across accounts, so first wins rather
        // than trapping on the duplicate key.
        tints = Dictionary(all.map { ($0.calendarIdentifier, Color(nsColor: $0.color ?? .controlAccentColor)) },
                           uniquingKeysWith: { first, _ in first })
        lists = ReminderSync.writableLists().map { ListChoice(id: $0.calendarIdentifier, title: $0.title) }
        // A filter naming a list that has since been deleted falls back to the
        // whole account: a predicate over no lists matches nothing, and an
        // empty panel would read as "nothing due".
        let scope = listFilter.isEmpty ? all : all.filter { $0.title == listFilter }
        let wanted = scope.isEmpty ? all : scope
        guard !wanted.isEmpty else {
            rows = []
            return
        }
        let end = ReminderTiming.panelEnd(now: Date())

        generation += 1
        let token = generation
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil,
                                                              ending: end,
                                                              calendars: wanted)
        Task { @MainActor in
            // Flattened inside the completion: an `EKReminder` is a live
            // object the store may mutate or invalidate, and it is not safe to
            // carry back across the hop.
            let fetched: [DueReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).compactMap(DueReminder.init))
                }
            }
            guard token == generation else { return }
            rows = fetched.sorted {
                $0.due == $1.due ? $0.title < $1.title : $0.due < $1.due
            }
            // 系统不再返回的已经落地，不用再藏。
            finishing = finishing.filter { id in fetched.contains { $0.id == id } }
            // 正在编辑的那条在别处被完成或删掉了，编辑器跟着收起。
            if let id = editing?.id, !fetched.contains(where: { $0.id == id }) { editing = nil }
        }
    }

    /// 第一次用到：面板是用户点开的，还没问过就直接请求一次，不用再点“允许访问”。
    private func askOnFirstUse() {
        guard !context.isPreview, !asked,
              EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else { return }
        asked = true
        request()
    }

    /// The consent prompt, run only from the panel, which the user opened.
    /// `NSRemindersFullAccessUsageDescription` is in Info.plist, which is what
    /// keeps this from terminating the app.
    private func request() {
        Task { @MainActor in
            // A store made here rather than the shared one: the request is an
            // async call out of the main actor, and the shared store is
            // isolated to it.
            _ = try? await EKEventStore().requestFullAccessToReminders()
            // The store built before the grant keeps answering as if it had
            // none until it is told to look again.
            store.reset()
            load()
        }
    }

    private func openPrivacySettings() {
        guard let url = WidgetTarget.settings("com.apple.preference.security?Privacy_Reminders").settingsURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    private static let red = Color(hex: PaletteColor.red.hex)

    /// A list with no colour of its own falls back to the widget's accent
    /// rather than to a colour no list actually uses.
    private static let fallbackTint = Color(hex: WidgetCatalog.accentHex(.reminders) ?? PaletteColor.orange.hex)
}

/// One row, flattened off its `EKReminder` as the fetch returns.
private struct DueReminder: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var due: Date
    /// False for a reminder set for a day with no time of day, which is due
    /// all day and not at midnight.
    var hasTime: Bool
    var list: String
    var listID: String
    var priority: ReminderPriority

    init?(_ reminder: EKReminder) {
        guard let parsed = ReminderTiming.due(from: reminder.dueDateComponents) else { return nil }
        self.id = reminder.calendarItemIdentifier
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // An untitled reminder is still a real reminder; Reminders.app shows
        // the row empty, which here would be a ring with nothing beside it.
        self.title = title.isEmpty ? tr("新提醒事项") : title
        self.due = parsed.date
        self.hasTime = parsed.hasTime
        self.list = reminder.calendar?.title ?? ""
        self.listID = reminder.calendar?.calendarIdentifier ?? ""
        self.priority = ReminderPriority(eventKit: reminder.priority)
    }

    var dueValue: ReminderDue { ReminderDue(date: due, hasTime: hasTime) }

    /// A dated reminder is late the moment its time passes. One set for a day
    /// with no time is late only once that day is over.
    func isOverdue(_ now: Date) -> Bool {
        ReminderTiming.isOverdue(dueValue, now: now)
    }
}
