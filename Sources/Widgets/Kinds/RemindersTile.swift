import EventKit
import SwiftUI

/// What is due today, on a card 58pt tall.
///
/// The tile is the glance and `RemindersDetail` is the backlog behind it, so
/// the two read the same thing the same way: everything incomplete and dated
/// up to the end of today, overdue told apart from merely due, and a list
/// filter by title that only narrows what is counted.
///
/// EventKit is read here rather than through a service because none exists for
/// reminders; the panel does the same, and both write through `ReminderSync`.
/// 卡片上能做的只有两件：点行前的圆圈完成，下一个提醒悬停时完成或推迟 1 小时，
/// 都直接写回系统“提醒事项”。Crucially nothing is *requested* from the tile:
/// a shelf being drawn must never raise a consent prompt, so the tile reports
/// the state it finds, and only a click (the lock note, or opening the panel)
/// asks for access.
struct RemindersTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var access = EKEventStore.authorizationStatus(for: .reminder)
    @State private var rows: [TileReminder] = []
    /// A fetch is async and the shelf can rebuild or reconfigure the tile while
    /// one is in flight; only the newest is allowed to land.
    @State private var generation = 0
    /// 刚点完成的，系统通知回来之前先从卡片上拿掉，免得圆圈点了没反应。
    @State private var finishing: Set<String> = []
    @Environment(\.widgetHovered) private var hovered

    private var store: EKEventStore { ReminderSync.store }

    /// 卡片上的圆圈和按钮能不能按：库里的示例不能，没权限时也不会画出来。
    private var interactive: Bool { !context.isPreview && access == .fullAccess }

    private var layout: String { instance.config.string("layout", default: "list") }

    /// The list the widget was configured for, by title. Empty - the catalog
    /// default - means every list.
    private var listFilter: String {
        instance.config.string("list").trimmingCharacters(in: .whitespaces)
    }

    /// The library has no store behind it, so it shows the reference sample.
    private var granted: Bool { context.isPreview || access == .fullAccess }

    private var items: [TileReminder] {
        context.isPreview ? Self.sample(now: context.now) : rows.filter { !finishing.contains($0.id) }
    }

    /// Overdue first, then the rest of today, each in due order.
    ///
    /// Concatenated rather than left to the due sort: an all-day reminder for
    /// today carries midnight, so a plain ascending sort files it above a timed
    /// one that is already late.
    private var ordered: [TileReminder] {
        let now = context.now
        return items.filter { $0.isOverdue(now) } + items.filter { !$0.isOverdue(now) }
    }

    private var overdueCount: Int { items.filter { $0.isOverdue(context.now) }.count }
    private var todayCount: Int { items.count - overdueCount }

    /// Layouts with little width: the side shelf's column, and the Today
    /// Overview card. Both drop captions to a stacked, centred form.
    private var narrow: Bool { context.position.isVertical || layout == "count" }

    var body: some View {
        WidgetSurface {
            if !granted {
                // 缺权限：小锁和「需要提醒事项权限 · 去开启」，点按去开启。
                PermissionLockNote(permission: TilePermission.name(for: WidgetKind.reminders.rawValue) ?? "提醒事项",
                                   compact: narrow, stacked: narrow, preview: context.isPreview)
                    .frame(maxWidth: .infinity, alignment: narrow ? .center : .leading)
            } else if items.isEmpty && layout != "count" {
                notice("checkmark.circle", emptyText, tint: Self.accent)
            } else if context.position.isVertical {
                column
            } else {
                switch layout {
                case "next": wideNext
                case "count": overview
                default: wideList
                }
            }
        }
        .onAppear { load() }
        .onChange(of: listFilter) { load() }
        // `now` ticks every second; re-reading the store that often would be
        // absurd, and the overdue split above is recomputed from `now` anyway.
        // Five minutes also carries the fetch window past midnight on its own.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 300) { load() }
        // A reminder ticked off in Reminders.app, or access granted in the
        // panel, both land here.
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
        // 带时刻的提醒到点时弹出卡片、轻响一声，由 `TimedAlertDriver` 在后台看着，
        // 扩展栏隐藏或这张卡片不在当前布局也照样弹。
    }

    // MARK: Wide layouts

    /// Up to three rows, each a dot, a title and when it was or is due. A
    /// fourth would not fit, so the last line counts what is left instead -
    /// the tile must never look like the whole of a backlog it has cut off.
    private var wideList: some View {
        let hidden = ordered.count > 3 ? ordered.count - 2 : 0
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(ordered.prefix(hidden > 0 ? 2 : 3)) { item in
                listRow(item)
            }
            if hidden > 0 {
                Text(tr("还有 \(hidden) 项"))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 圆圈、标题、时间。过期的圆圈和时间标红；点圆圈完成并写回系统。
    private func listRow(_ item: TileReminder) -> some View {
        let late = item.isOverdue(context.now)
        return HStack(spacing: 6) {
            checkCircle(item, late: late, size: 11)
            Text(item.title)
                .font(WidgetStyle.label(11))
                .foregroundStyle(WidgetStyle.primary)
            Spacer(minLength: 6)
            Text(stamp(item))
                .font(WidgetStyle.caption(10))
                .foregroundStyle(late ? Self.overdue : WidgetStyle.secondary)
                .monospacedDigit()
        }
        .lineLimit(1)
    }

    /// The single next thing: symbol left, title and its due line stacked on
    /// the right, in the idiom the weather tile uses. 第二行是“40 分钟后 · 15:00”
    /// 这样的倒计时；指针停在卡片上时换成“完成”“推迟 1 小时”两个按钮。
    private var wideNext: some View {
        let item = ordered[0]
        let late = item.isOverdue(context.now)
        let acting = hovered && interactive
        return HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge {
                Image(systemName: late ? "exclamationmark.circle.fill" : (item.isHighPriority ? "exclamationmark" : "checklist"))
                    .font(.system(size: 17, weight: item.isHighPriority && !late ? .bold : .regular))
                    .foregroundStyle(late ? Self.overdue : (item.isHighPriority ? Self.accent : WidgetStyle.primary))
            }
            if acting {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.primary)
                    HStack(spacing: 5) {
                        pill(tr("完成"), filled: true) { complete(item) }
                        pill(tr("推迟 1 小时"), filled: false) { snooze(item) }
                    }
                }
                .transition(.opacity)
                Spacer(minLength: 0)
            } else {
                nextText(item, late: late)
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .dockAnimation(.easeOut(duration: 0.15), value: acting)
    }

    @ViewBuilder
    private func nextText(_ item: TileReminder, late: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                // 高优先级由左边方底里的橙色“!”表示，和“提醒事项”App 的旗标一样。
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                Text(nextLine(item))
                    .font(.system(size: 12))
                    .foregroundStyle(late ? Self.overdue : Self.accent)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(10))
                .foregroundStyle(WidgetStyle.primary)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(WidgetStyle.primary.opacity(filled ? 0.18 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    // MARK: Today Overview
    //
    // 原来叫“数量”，layout 仍是 count，已经放好的卡片不受影响。两个大数字并排：
    // 左边已过期（有就标红），右边今天到期，中间一条细线；竖排扩展栏里上下摆。

    @ViewBuilder
    private var overview: some View {
        if context.position.isVertical {
            VStack(spacing: 4) {
                overviewFigure(overdueCount, tr("已过期"), late: overdueCount > 0, size: 18)
                overviewFigure(todayCount, tr("今天到期"), late: false, size: 18)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 0) {
                overviewFigure(overdueCount, tr("已过期"), late: overdueCount > 0, size: 26)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(WidgetStyle.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                overviewFigure(todayCount, tr("今天到期"), late: false, size: 26)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func overviewFigure(_ value: Int, _ label: String, late: Bool, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(WidgetStyle.value(size))
                .foregroundStyle(late ? Self.overdue : WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(value)
            Text(label)
                .font(WidgetStyle.caption(9))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Column
    //
    // 56pt of usable width. Times and list names do not survive it, so the
    // column keeps what identifies a reminder - its title - and lets the dot
    // carry whether it is late.

    @ViewBuilder
    private var column: some View {
        switch layout {
        case "next": columnNext
        case "count": overview
        default: columnList
        }
    }

    private var columnList: some View {
        let hidden = ordered.count > 3 ? ordered.count - 2 : 0
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(ordered.prefix(hidden > 0 ? 2 : 3)) { item in
                HStack(spacing: 5) {
                    checkCircle(item, late: item.isOverdue(context.now), size: 9)
                    Text(item.title)
                        .font(WidgetStyle.label(10))
                        .foregroundStyle(WidgetStyle.primary)
                    Spacer(minLength: 0)
                }
            }
            if hidden > 0 {
                Text(tr("还有 \(hidden) 项"))
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columnNext: some View {
        let item = ordered[0]
        let late = item.isOverdue(context.now)
        return VStack(spacing: 2) {
            Image(systemName: late ? "exclamationmark.circle.fill" : "checklist")
                .font(.system(size: 18))
                .foregroundStyle(late ? Self.overdue : Self.accent)
                .frame(height: 18)
            Text(item.title)
                .font(WidgetStyle.label(11))
                .foregroundStyle(WidgetStyle.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(ReminderTiming.relative(item.dueValue, now: context.now))
                .font(WidgetStyle.caption(10))
                .foregroundStyle(late ? Self.overdue : WidgetStyle.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .minimumScaleFactor(0.65)
    }

    // MARK: States with nothing to show

    // 缺权限时的那句话在 Core 的 `TilePermission`，和日历、邮件、废纸篓共用。

    private var emptyText: String { narrow ? tr("无到期事项") : tr("今天没有到期事项。") }

    @ViewBuilder
    private func notice(_ symbol: String, _ text: String, tint: Color) -> some View {
        if narrow {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                Text(text)
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .multilineTextAlignment(.center)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                    .frame(height: 20)
                Text(text)
                    .font(WidgetStyle.caption(12))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Pieces

    /// 行前的空心圆圈，过期的是红圈。有权限时是按钮，点一下完成并写回系统；
    /// 库里的示例只画不按，点卡片照旧是添加。
    @ViewBuilder
    private func checkCircle(_ item: TileReminder, late: Bool, size: CGFloat) -> some View {
        let ring = Circle()
            .strokeBorder(late ? Self.overdue : WidgetStyle.secondary, lineWidth: 1.2)
            .frame(width: size, height: size)
        if interactive {
            Button { complete(item) } label: {
                ring
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-3)
            .help(tr("完成“\(item.title)”"))
            .accessibilityLabel(tr("完成 \(item.title)"))
        } else {
            ring.accessibilityHidden(true)
        }
    }

    /// The tight form, for a row that already carries a title beside it: the
    /// time if it is today's, “昨天”, otherwise the day it slipped from.
    private func stamp(_ item: TileReminder) -> String {
        if let word = ReminderTiming.shortDay(item.dueValue, now: context.now) { return word }
        guard Calendar.current.isDate(item.due, inSameDayAs: context.now) else {
            return item.due.formatted(.dateTime.day().month(.abbreviated))
        }
        return item.due.formatted(date: .omitted, time: .shortened)
    }

    /// 下一个提醒的第二行：“40 分钟后 · 15:00”，再跟列表名，同一时刻的两条
    /// 靠列表分开。
    private func nextLine(_ item: TileReminder) -> String {
        let line = ReminderTiming.nextLine(item.dueValue, now: context.now,
                                           clock: item.due.formatted(date: .omitted, time: .shortened))
        return item.list.isEmpty ? line : "\(line) · \(item.list)"
    }

    // MARK: Writes

    private func complete(_ item: TileReminder) {
        guard interactive else { return }
        withAnimation(.snappy(duration: 0.25)) { _ = finishing.insert(item.id) }
        if !ReminderSync.complete(item.id) {
            withAnimation(.snappy(duration: 0.25)) { _ = finishing.remove(item.id) }
        }
    }

    private func snooze(_ item: TileReminder) {
        guard interactive else { return }
        ReminderSync.reschedule(item.id, to: ReminderTiming.snoozed(item.dueValue, now: context.now))
    }

    private static let overdue = Color(hex: PaletteColor.red.hex)
    private static let accent = Color(hex: WidgetCatalog.accentHex(.reminders) ?? PaletteColor.orange.hex)

    // MARK: Store

    /// Everything incomplete and dated up to the end of today, which is overdue
    /// and today's in one predicate. Reminders with no due date are not
    /// returned by a dated predicate, and the tile does not pretend otherwise:
    /// it counts what is *due*, exactly as the panel does.
    private func load() {
        guard !context.isPreview else { return }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != access {
            // A grant given in the detail panel leaves this store, built
            // before it, answering as if it had none until it is told to look
            // again.
            if status == .fullAccess { store.reset() }
            access = status
        }
        guard status == .fullAccess else {
            rows = []
            return
        }

        let lists = store.calendars(for: .reminder)
        // A filter naming a list that has since been deleted falls back to the
        // whole account: a predicate over no lists matches nothing, and an
        // empty tile would read as "nothing due".
        let scope = listFilter.isEmpty ? lists : lists.filter { $0.title == listFilter }
        let wanted = scope.isEmpty ? lists : scope
        guard !wanted.isEmpty,
              let end = Calendar.current.date(byAdding: .day, value: 1,
                                              to: Calendar.current.startOfDay(for: Date())) else {
            rows = []
            return
        }

        generation += 1
        let token = generation
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil,
                                                              ending: end,
                                                              calendars: wanted)
        Task { @MainActor in
            // Flattened inside the completion: an `EKReminder` is a live object
            // the store may mutate or invalidate, and it is not safe to carry
            // back across the hop.
            let fetched: [TileReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).compactMap(TileReminder.init))
                }
            }
            guard token == generation else { return }
            rows = fetched.sorted {
                $0.due == $1.due ? $0.title < $1.title : $0.due < $1.due
            }
            // 系统不再返回的已经完成落地，不用再藏；还在的可能是写回前发出的
            // 那次读取，接着藏到下一次通知。
            finishing = finishing.filter { id in fetched.contains { $0.id == id } }
        }
    }

    /// Two overdue and three due later today, so every layout has both halves
    /// of the count to draw. Anchored to `now` so the split is real wherever
    /// the library is opened.
    private static func sample(now: Date) -> [TileReminder] {
        [(-86_400.0, tr("续费域名"), tr("工作"), true),
         (-5_400.0, tr("回复小张"), tr("工作"), false),
         (3_600.0, tr("预订机票"), tr("旅行"), false),
         (9_000.0, tr("给植物浇水"), tr("家庭"), false),
         (16_200.0, tr("取快递"), tr("家庭"), false)]
            .enumerated()
            .map { index, item in
                TileReminder(id: "sample-\(index)",
                             title: item.1,
                             due: now.addingTimeInterval(item.0),
                             hasTime: true,
                             list: item.2,
                             isHighPriority: item.3)
            }
    }
}

/// One row, flattened off its `EKReminder` as the fetch returns.
private struct TileReminder: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var due: Date
    /// False for a reminder set for a day with no time of day, which is due all
    /// day and not at midnight.
    var hasTime: Bool
    var list: String
    var isHighPriority: Bool

    init(id: String, title: String, due: Date, hasTime: Bool, list: String, isHighPriority: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.list = list
        self.isHighPriority = isHighPriority
    }

    init?(_ reminder: EKReminder) {
        guard let parsed = ReminderTiming.due(from: reminder.dueDateComponents) else { return nil }
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: reminder.calendarItemIdentifier,
                  // An untitled reminder is still a real reminder; Reminders.app
                  // shows the row empty, which here would be a dot with nothing
                  // beside it.
                  title: title.isEmpty ? tr("新提醒事项") : title,
                  due: parsed.date,
                  hasTime: parsed.hasTime,
                  list: reminder.calendar?.title ?? "",
                  // EventKit's priority runs 1-9 with 0 for none; Reminders.app's
                  // own "High" flag is 1-4.
                  isHighPriority: (1...4).contains(reminder.priority))
    }

    /// A dated reminder is late the moment its time passes. One set for a day
    /// with no time is late only once that day is over.
    func isOverdue(_ now: Date) -> Bool {
        ReminderTiming.isOverdue(dueValue, now: now)
    }

    var dueValue: ReminderDue { ReminderDue(date: due, hasTime: hasTime) }
}
