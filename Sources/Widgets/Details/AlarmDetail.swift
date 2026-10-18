import SwiftUI

/// 闹钟面板：一张列表管今天的全部闹钟。加、删、开关、改时间和名字。
///
/// 卡片上只放得下下一个和后面一行小字，这里把每个都列出来：时间、名字、
/// 还有多久，右边一个开关。正在响的那个排在最上面，带“稍后”和“关掉”。
/// 读写的都是 `AlarmBook`，和卡片同一份配置，旧的单个闹钟第一次改动时写成列表。
struct AlarmDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing: String?
    @State private var draftName = ""
    @State private var draftTime = Date()

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
            ZStack(alignment: .topTrailing) {
                MeshBackdrop(color: Color(red: 0.16, green: 0.14, blue: 0.42))
                Circle()
                    .fill(RadialGradient(colors: [Color.timerOrange.opacity(headline?.enabled == true ? 0.45 : 0), .clear],
                                         center: .center, startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .offset(x: 70, y: -80)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(headline, config: config, now: now)

                if let ringing { ringingRow(ringing.item) }

                VStack(spacing: 6) {
                    ForEach(items) { item in
                        if editing == item.id {
                            editor(item)
                        } else {
                            row(item, config: config, now: now)
                        }
                    }
                }

                HStack {
                    Button(action: add) {
                        Label(tr("添加闹钟"), systemImage: "plus")
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(items.count >= AlarmBook.maxAlarms)
                    Spacer()
                    Text(tr("只管今天，每天到点响"))
                        .font(WidgetStyle.label(10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: Pieces

    private func header(_ headline: AlarmItem?, config: WidgetConfig, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline.map { $0.enabled ? tr("下一个 · \($0.title)") : tr("全部已关闭") } ?? tr("还没有闹钟"))
                .font(WidgetStyle.label(13))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            if let headline {
                let at = AlarmBook.nextRing(headline, config: config, now: now)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(AlarmBook.clockText(at))
                        .font(.system(size: 54, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                    if headline.enabled {
                        Text(AlarmBook.untilText(at, now: now))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(Color.timerOrange)
                    }
                }
                .opacity(headline.enabled ? 1 : 0.55)
            }
        }
    }

    private func ringingRow(_ item: AlarmItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .foregroundStyle(Color.timerOrange)
            Text(tr("\(item.time) \(item.title) 正在响"))
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            ClockPanelButton(title: tr("稍后 \(AlarmBook.snoozeMinutes) 分钟"), fill: nil) {
                write { AlarmBook.snooze(item.id, in: &$0, now: .now) }
            }
            .frame(width: 104)
            ClockPanelButton(title: tr("关掉"), fill: Color.timerOrange) {
                write { AlarmBook.dismiss(item.id, in: &$0, now: .now) }
            }
            .frame(width: 64)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.timerOrange.opacity(0.2)))
    }

    private func row(_ item: AlarmItem, config: WidgetConfig, now: Date) -> some View {
        HStack(spacing: 10) {
            Button { beginEditing(item) } label: {
                HStack(spacing: 10) {
                    Text(item.time)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(item.enabled ? 1 : 0.45))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(.white.opacity(item.enabled ? 0.92 : 0.45))
                            .lineLimit(1)
                        if item.enabled {
                            Text(AlarmBook.untilText(AlarmBook.nextRing(item, config: config, now: now), now: now))
                                .font(WidgetStyle.label(10))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点按修改时间和名字"))

            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { on in write { AlarmBook.setEnabled(item.id, on, in: &$0) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.timerOrange)
                .labelsHidden()
                .accessibilityLabel(tr("开关 \(item.time) 的闹钟"))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .glassPane()
    }

    private func editor(_ item: AlarmItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                TextField(tr("做什么"), text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save(item) }
            }
            HStack(spacing: 8) {
                ClockPanelButton(title: tr("保存"), fill: Color.timerOrange) { save(item) }
                ClockPanelButton(title: tr("取消"), fill: nil) { editing = nil }
                ClockPanelButton(title: tr("删除"), fill: nil) { delete(item) }
            }
        }
        .padding(10)
        .glassPane()
    }

    // MARK: Actions

    private func beginEditing(_ item: AlarmItem) {
        guard !context.isPreview else { return }
        draftName = item.name
        draftTime = AlarmBook.at(item.minutes, on: .now, calendar: .current)
        editing = item.id
    }

    private func save(_ item: AlarmItem) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        write { config in
            var list = AlarmBook.items(config)
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
            list[index].minutes = minutes
            list[index].name = name
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

    /// 新闹钟放在一小时后的整点，名字空着，马上打开编辑。
    private func add() {
        guard !context.isPreview else { return }
        let parts = Calendar.current.dateComponents([.hour], from: .now)
        let minutes = (((parts.hour ?? 8) + 1) % 24) * 60
        var created: AlarmItem?
        write { config in
            var list = AlarmBook.items(config)
            let item = AlarmItem(id: AlarmBook.newID(existing: list), minutes: minutes, name: "")
            list.append(item)
            created = item
            AlarmBook.store(list, in: &config)
        }
        if let created { beginEditing(created) }
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
