import AppKit
import SwiftUI

/// 闹钟面板：头上下一个闹钟的大时间和“X 小时 Y 分钟后响”，下面一条今天的
/// 24 小时时间轴，快速加一次性闹钟的几颗按钮，再往下是全部闹钟。
///
/// 每行大号时间、名字、重复日（七个小圆点和“工作日”这类说明），右边开关；
/// 点一行展开编辑：时间、名字、哪几天响或只响一次，删除也在这里。重复还可以选
/// “法定工作日”：法定节假日不响、调休上班的周末照响，放假安排和农历、时间进度同一份。
/// 正在响的那个排在最上面，带“稍后”和“关掉”。读写的都是 `AlarmBook`，
/// 和卡片同一份配置，旧的单个闹钟第一次改动时写成列表。
struct AlarmDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint

    /// 闹钟的强调色：原来的计时橙，颜色面板里选了颜色就换成选的。
    private var accent: Color { panelTint.accent(or: Color.timerOrange) }
    /// 橙色实心按钮上的深字。
    private var ink: Color { panelTint.ink(or: CountdownDetail.orangeInk) }
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing: String?
    @State private var draftName = ""
    @State private var draftTime = Date()
    @State private var draftDays: Set<Int> = Set(1...7)
    @State private var draftOnce = false
    /// 法定工作日：跳过法定节假日，调休上班照响。
    @State private var draftLegal = false

    /// 快速加：从现在起多少分钟后响一次。
    private static let quickMinutes = [15, 30, 60]

    var body: some View {
        // 面板的 context 只在打开那一刻取一次，靠这个每秒刷新还有多久。
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private var config: WidgetConfig {
        (WidgetWriter.current(instance.id) ?? instance).config
    }

    private func content(now: Date) -> some View {
        let config = config
        let items = AlarmBook.items(config)
        let ringing = context.isPreview ? nil : AlarmBook.ringing(config, now: now)
        let headline = AlarmBook.headline(config, now: now)

        return DetailCard {
            MeshBackdrop(color: Color.timerOrange)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(headline, config: config, now: now)

                if let ringing { ringingRow(ringing.item) }

                if items.isEmpty {
                    PandaEmptyState(empty: .alarm, title: tr("添加闹钟"), panel: true, action: add)
                } else {
                    timeline(items, config: config, now: now)
                }

                quickAdd(full: items.count >= AlarmBook.maxAlarms)

                VStack(spacing: 6) {
                    ForEach(items) { item in
                        if editing == item.id {
                            editor(item)
                        } else {
                            row(item, config: config, now: now)
                        }
                    }
                }
            }
        }
    }

    // MARK: Header

    private func header(_ headline: AlarmItem?, config: WidgetConfig, now: Date) -> some View {
        let live = headline.map { AlarmBook.isLive($0, config: config, now: now) } ?? false
        let title: String
        if let headline {
            title = live ? tr("下一个 · \(headline.title)") : tr("全部已关闭")
        } else {
            title = tr("还没有闹钟")
        }
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                if let headline {
                    let at = AlarmBook.nextRing(headline, config: config, now: now)
                    Text(live ? AlarmBook.clockText(at) : headline.time)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .opacity(live ? 1 : 0.5)
                    if live {
                        Text(AlarmBook.ringsInText(at, now: now))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if live, let image = PandaArt.image("pet-panda-rest") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
    }

    private func ringingRow(_ item: AlarmItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(accent)
                Text(tr("\(item.time) \(item.title) 正在响"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                ClockPanelButton(title: tr("稍后 \(AlarmBook.snoozeMinutes) 分钟"), fill: nil) {
                    write { AlarmBook.snooze(item.id, in: &$0, now: .now) }
                }
                ClockPanelButton(title: tr("关掉"), fill: accent, ink: ink) {
                    write { AlarmBook.dismiss(item.id, in: &$0, now: .now) }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.18)))
    }

    // MARK: Timeline

    /// 今天 0 点到 24 点：走过的一段亮一点，现在一根白线，今天会响的开着的闹钟是橙点，
    /// 关着的是空心圈。
    private func timeline(_ items: [AlarmItem], config: WidgetConfig, now: Date) -> some View {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let marks = AlarmBook.today(config, now: now)
        let off = items.filter { !$0.enabled && AlarmBook.rings($0.repeats, on: now) }.map(\.minutes)
        let left = marks.filter { $0.minutes > nowMinutes }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("今天"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(left > 0 ? tr("还有 \(left) 个要响") : tr("今天没有要响的了"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (minutes: Int) -> CGFloat in width * CGFloat(minutes) / 1440 }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12)).frame(height: 5)
                    Capsule().fill(.white.opacity(0.28)).frame(width: max(5, x(nowMinutes)), height: 5)
                    ForEach(Array(off.enumerated()), id: \.offset) { _, minutes in
                        Circle()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1.2)
                            .background(Circle().fill(MeshBackdrop.graphite))
                            .frame(width: 8, height: 8)
                            .offset(x: x(minutes) - 4)
                    }
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                        Circle()
                            .fill(accent.opacity(mark.minutes < nowMinutes ? 0.45 : 1))
                            .overlay(Circle().strokeBorder(MeshBackdrop.graphite, lineWidth: 1.5))
                            .frame(width: 11, height: 11)
                            .offset(x: x(mark.minutes) - 5.5)
                            .help("\(PostureSchedule.clock(mark.minutes)) \(mark.item.title)")
                    }
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.95))
                        .frame(width: 2, height: 16)
                        .offset(x: x(nowMinutes) - 1)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    if hour > 0 { Spacer(minLength: 0) }
                    Text(verbatim: "\(hour)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassPane()
        .accessibilityElement(children: .combine)
    }

    // MARK: Quick add

    private func quickAdd(full: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Self.quickMinutes, id: \.self) { minutes in
                ClockPanelButton(title: minutes < 60 ? tr("+\(minutes) 分钟") : tr("+\(minutes / 60) 小时"),
                                 fill: nil, height: 32) {
                    quickAdd(after: minutes)
                }
                .help(tr("加一个只响一次的闹钟"))
            }
            ClockPanelButton(title: tr("新闹钟"), fill: accent, ink: ink, height: 32, action: add)
        }
        .disabled(full || context.isPreview)
        .opacity(full ? 0.4 : 1)
    }

    // MARK: Rows

    private func row(_ item: AlarmItem, config: WidgetConfig, now: Date) -> some View {
        let live = AlarmBook.isLive(item, config: config, now: now)
        return HStack(spacing: 12) {
            Button { beginEditing(item) } label: {
                HStack(spacing: 12) {
                    Text(item.time)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(live ? 1 : 0.42))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(live ? 0.95 : 0.42))
                            .lineLimit(1)
                        repeatLine(item, live: live, now: now)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点按修改时间、名字和重复"))

            Toggle("", isOn: Binding(
                get: { live },
                set: { on in write { AlarmBook.setEnabled(item.id, on, in: &$0, now: .now) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(accent)
                .labelsHidden()
                .accessibilityLabel(tr("开关 \(item.time) 的闹钟"))
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .glassPane()
    }

    /// 名字下面一行：重复的是七个小圆点加说明，只响一次的是“仅今天”这类。
    @ViewBuilder
    private func repeatLine(_ item: AlarmItem, live: Bool, now: Date) -> some View {
        let text = AlarmBook.repeatText(item.repeats, minutes: item.minutes, now: now)
        if item.repeats.isOnce {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(live ? accent : .white.opacity(0.4))
                .lineLimit(1)
        } else {
            HStack(spacing: 7) {
                HStack(spacing: 3.5) {
                    ForEach(1...7, id: \.self) { day in
                        let on = item.repeats.days.contains(day)
                        Circle()
                            .fill(on && live ? accent : .white.opacity(on ? 0.45 : 0.16))
                            .frame(width: 5, height: 5)
                    }
                }
                .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(live ? 0.6 : 0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: Editor

    private func editor(_ item: AlarmItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .font(.system(size: 15))
                TextField(tr("做什么"), text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { save(item) }
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = !draftOnce && draftDays.contains(day)
                    Button { toggleDay(day) } label: {
                        Text(AlarmBook.weekdayShort(day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? ink : .white.opacity(draftOnce ? 0.35 : 0.85))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(on ? accent : .white.opacity(0.1)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AlarmBook.weekdayName(day))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            HStack(spacing: 6) {
                ruleChip(tr("每天"), selected: !draftOnce && draftDays.count == 7) { setRule(Set(1...7)) }
                ruleChip(tr("工作日"), selected: !draftOnce && !draftLegal && draftDays == [1, 2, 3, 4, 5]) {
                    setRule([1, 2, 3, 4, 5])
                }
                ruleChip(tr("周末"), selected: !draftOnce && draftDays == [6, 7]) { setRule([6, 7]) }
                ruleChip(tr("仅一次"), selected: draftOnce) {
                    draftOnce = true
                    draftLegal = false
                }
            }

            HStack(spacing: 8) {
                ruleChip(tr("法定工作日"), selected: !draftOnce && draftLegal) {
                    draftOnce = false
                    draftLegal = true
                    draftDays = [1, 2, 3, 4, 5]
                }
                .frame(width: 104)
                Text(tr("跳过法定节假日，调休上班照响"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(draftLegal && !draftOnce ? 0.8 : 0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ClockPanelButton(title: tr("保存"), fill: accent, ink: ink) { save(item) }
                ClockPanelButton(title: tr("取消"), fill: nil) { editing = nil }
                ClockPanelButton(title: tr("删除"), fill: nil) { delete(item) }
            }
        }
        .padding(12)
        .glassPane()
    }

    private func ruleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    Capsule().fill(selected ? accent.opacity(0.22) : .white.opacity(0.08))
                        .overlay {
                            Capsule().strokeBorder(selected ? accent.opacity(0.6) : .white.opacity(0.12), lineWidth: 0.6)
                        }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func beginEditing(_ item: AlarmItem) {
        guard !context.isPreview else { return }
        draftName = item.name
        draftTime = AlarmBook.at(item.minutes, on: .now, calendar: .current)
        draftOnce = item.repeats.isOnce
        draftLegal = item.repeats.isLegalWorkdays
        draftDays = item.repeats.isOnce ? Set(1...7) : item.repeats.days
        editing = item.id
    }

    /// 点一天：选上或去掉；至少留一天。从“仅一次”点过来时只选这一天。
    private func toggleDay(_ day: Int) {
        draftLegal = false
        if draftOnce {
            draftOnce = false
            draftDays = [day]
            return
        }
        if draftDays.contains(day) {
            if draftDays.count > 1 { draftDays.remove(day) }
        } else {
            draftDays.insert(day)
        }
    }

    private func setRule(_ days: Set<Int>) {
        draftOnce = false
        draftLegal = false
        draftDays = days
    }

    private func save(_ item: AlarmItem) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule: AlarmRepeat = draftOnce ? AlarmBook.onceDay(for: minutes, now: .now)
            : draftLegal ? .legalWorkdays : .weekdays(draftDays)
        write { config in
            var list = AlarmBook.items(config)
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
            list[index].minutes = minutes
            list[index].name = name
            list[index].repeats = rule
            // 改成只响一次，就是要它响：开关一起打开。
            if rule.isOnce { list[index].enabled = true }
            AlarmBook.store(list, in: &config)
        }
        editing = nil
    }

    private func delete(_ item: AlarmItem) {
        write { config in
            AlarmBook.store(AlarmBook.items(config).filter { $0.id != item.id }, in: &config)
        }
        editing = nil
    }

    /// 新闹钟放在一小时后的整点，名字空着，每天响，马上打开编辑。
    private func add() {
        guard !context.isPreview else { return }
        let parts = Calendar.current.dateComponents([.hour], from: .now)
        let minutes = (((parts.hour ?? 8) + 1) % 24) * 60
        var created: AlarmItem?
        write { config in
            var list = AlarmBook.items(config)
            guard list.count < AlarmBook.maxAlarms else { return }
            let item = AlarmItem(id: AlarmBook.newID(existing: list), minutes: minutes, name: "")
            list.append(item)
            created = item
            AlarmBook.store(list, in: &config)
        }
        if let created { beginEditing(created) }
    }

    /// 快速加一个只响一次的闹钟：从现在起几分钟后，名字空着。
    private func quickAdd(after minutes: Int) {
        guard !context.isPreview else { return }
        let quick = AlarmBook.quickOnce(after: minutes, now: .now)
        write { config in
            var list = AlarmBook.items(config)
            guard list.count < AlarmBook.maxAlarms else { return }
            list.append(AlarmItem(id: AlarmBook.newID(existing: list), minutes: quick.minutes, name: "",
                                  repeats: quick.repeats))
            AlarmBook.store(list, in: &config)
        }
    }

    /// 旧的单个闹钟第一次改动时顺手写成列表。
    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        let current = WidgetWriter.current(instance.id) ?? instance
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { config in
                if AlarmBook.isLegacy(config) { AlarmBook.store(AlarmBook.items(config), in: &config) }
                change(&config)
            }
        }
    }
}
