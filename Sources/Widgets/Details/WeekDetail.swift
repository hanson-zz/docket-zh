import AppKit
import EventKit
import SwiftUI

/// The whole week, a day at a time: Monday to Sunday, each with its events in
/// order and today marked. Like the Calendar panel it asks for access only
/// when the user clicks for it, and offers the calendar filter the widget's
/// `calendars` option holds.
struct WeekDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var access = EKEventStore.authorizationStatus(for: .event)
    @State private var entries: [WeekEntry] = []
    @State private var sources: [WeekSource] = []
    /// The filter as the panel has it, since a config write does not come
    /// back into an open panel. `nil` means "read the config".
    @State private var picked: Set<String>?

    private var chosen: Set<String> { picked ?? Set(instance.config.strings("calendars")) }
    private var showsAllDay: Bool { instance.config.bool("allDay", default: true) }
    private var granted: Bool { context.isPreview || access == .fullAccess }

    private var week: [WeekDay] {
        let all = context.isPreview ? WeekEvents.samples(now: context.now) : entries
        return WeekAgenda.days(all, now: context.now, includeAllDay: showsAllDay)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WeekEvents.accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                heading
                if granted { list } else { permission }
            }
        }
        .onAppear { load() }
        .onChange(of: instance.id) { _, _ in
            picked = nil
            load()
        }
        .onChange(of: WeekAgenda.weekStart(context.now)) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    // MARK: Heading

    private var heading: some View {
        let days = week
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("本周 · \(WeekAgenda.rangeTitle(context.now))"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.7))
                Text(granted ? tr("\(WeekAgenda.total(days)) 个日程") : tr("一周日程"))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if !context.isPreview, access == .fullAccess, sources.count > 1 { picker }
        }
    }

    private var picker: some View {
        Menu {
            Button("所有日历") { apply([]) }
            Divider()
            ForEach(sources) { source in
                Toggle(source.title, isOn: Binding(
                    get: { chosen.isEmpty || chosen.contains(source.id) },
                    set: { _ in toggle(source) }))
            }
        } label: {
            Text("日历…")
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.14), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Days

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(week) { day in dayBlock(day) }
            }
        }
        .frame(maxHeight: 440)
        .scrollIndicators(.automatic)
    }

    private func dayBlock(_ day: WeekDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(WeekAgenda.dayTitle(day))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(day.isToday ? WeekEvents.accent : .white)
                Text(day.date.formatted(.dateTime.month(.defaultDigits).day()))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                if day.count > 0 {
                    Text(tr("\(day.count) 个"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
            }
            if day.entries.isEmpty {
                Text("没有日程")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(day.entries) { entry in row(entry, on: day) }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(day.isToday ? 0.12 : 0.05))
        }
    }

    private func row(_ entry: WeekEntry, on day: WeekDay) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(entry.colorHex.isEmpty ? WeekEvents.accent : Color(hex: entry.colorHex))
                .frame(width: 3.5, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                Text(detail(entry, on: day))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(!entry.isAllDay && entry.end <= context.now ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    /// "09:30 至 10:15 · 工作", "全天 · 个人", or for something that began
    /// on an earlier day, "接上一天".
    private func detail(_ entry: WeekEntry, on day: WeekDay) -> String {
        let time: String
        if entry.isAllDay {
            time = tr("全天")
        } else if entry.start < day.date {
            time = tr("接上一天，至 \(clock(entry.end))")
        } else {
            time = tr("\(clock(entry.start)) 至 \(clock(entry.end))")
        }
        return entry.calendar.isEmpty ? time : "\(time) · \(entry.calendar)"
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: No access

    private var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(access == .notDetermined
                 ? tr("码头尚未获得访问你日历的权限。")
                 : tr("码头的日历访问权限已关闭。"))
                .font(WidgetStyle.caption(12))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if access == .notDetermined { request() } else { openPrivacySettings() }
            } label: {
                Text(access == .notDetermined ? tr("允许访问") : tr("打开系统设置"))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Store

    private func load() {
        guard !context.isPreview else { return }
        access = EKEventStore.authorizationStatus(for: .event)
        guard access == .fullAccess else {
            entries = []
            sources = []
            return
        }
        sources = WeekEvents.calendars().map(WeekSource.init)
        entries = WeekEvents.read(WeekAgenda.interval(context.now), chosen: chosen)
    }

    private func request() {
        Task { @MainActor in
            // A fresh store for the request, as the Calendar panel does: the
            // shared one is isolated to the main actor and the call is async.
            _ = try? await EKEventStore().requestFullAccessToEvents()
            WeekEvents.store.reset()
            load()
        }
    }

    private func openPrivacySettings() {
        guard let url = WidgetTarget.settings("com.apple.preference.security?Privacy_Calendars").settingsURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Filter

    private func toggle(_ source: WeekSource) {
        var wanted = chosen.isEmpty ? Set(sources.map(\.id)) : chosen
        if wanted.contains(source.id) { wanted.remove(source.id) } else { wanted.insert(source.id) }
        apply(wanted.count == sources.count ? [] : sources.map(\.id).filter(wanted.contains))
    }

    private func apply(_ identifiers: [String]) {
        guard !context.isPreview else { return }
        picked = Set(identifiers)
        WidgetWriter.write(instance) { config in
            config.set("calendars", .list(identifiers.map(WidgetConfig.Value.string)))
        }
        load()
    }
}

/// A calendar the account offers, for the filter menu.
private struct WeekSource: Identifiable, Hashable {
    var id: String
    var title: String

    init(_ calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
    }
}
