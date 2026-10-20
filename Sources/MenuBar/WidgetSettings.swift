import SwiftUI

/// Settings for the widgets actually on the shelf.
///
/// Built from each kind's catalog defaults rather than hand-written per kind:
/// the type of a default decides its control, so every widget gets settings
/// and a new one gets them for free. The Widgets tab previously claimed each
/// widget "keeps its own settings" on the Dock, which was not true anywhere -
/// the twenty-odd show/hide options in the catalog had no UI at all.
struct WidgetSettingsSections: View {
    @Binding var state: PersistedState

    /// Which widget is being edited. `nil` means "whichever is first", which
    /// is also where a selection goes when its widget leaves the shelf.
    @State private var selection: UUID?

    /// 正在选城市的世界时钟。
    @State private var cityPickerFor: UUID?

    var body: some View {
        if instances.isEmpty {
            Section("小组件") {
                Label("程序坞上还没有小组件，点按末端的 + 按钮即可添加。",
                      systemImage: "square.grid.2x2")
                    .foregroundStyle(.secondary)
            }
        } else if configurable.isEmpty {
            Section("小组件") {
                Label("程序坞上的小组件没有可调整的设置。",
                      systemImage: "square.grid.2x2")
                    .foregroundStyle(.secondary)
            }
        } else {
            // One widget at a time, chosen here.
            //
            // Every widget's sections used to be stacked into one scroll,
            // which put four widgets and twenty-odd controls in a column and
            // made finding the one you meant a hunt. The shelf is a row of
            // separate things and its settings should be too.
            Section("小组件") {
                Picker("小组件", selection: Binding(
                    get: { chosen?.instance.id },
                    set: { selection = $0 })) {
                    ForEach(configurable, id: \.instance.id) { pair in
                        Text(sectionTitle(for: pair)).tag(Optional(pair.instance.id))
                    }
                }
            }

            if let pair = chosen {
                // Numbered only when there is more than one of a kind. Two
                // Sticky Notes produced two headings both called "Sticky
                // Note", with nothing to say which note each one edited.
                if !pair.entry.variants.isEmpty || !options(for: pair.entry, pair.instance).isEmpty {
                    Section(sectionTitle(for: pair)) {
                        if !pair.entry.variants.isEmpty {
                            stylePicker(pair.entry, pair.instance)
                        }
                        ForEach(options(for: pair.entry, pair.instance), id: \.self) { key in
                            control(key, entry: pair.entry, instance: pair.instance)
                        }
                    }
                }
                if pair.instance.kind == .battery {
                    batteryAlertSection(pair.instance)
                }
                if WidgetTint.offersColor(pair.instance.kind) || WidgetTint.offersBackground(pair.instance.kind) {
                    Section("颜色与背景") {
                        WidgetTintPicker(instance: pair.instance) { change in
                            write(pair.instance, change)
                        }
                    }
                }
                displaySection(pair.instance)
            }
        }
    }

    /// The selected widget, or the first one.
    ///
    /// Resolved rather than stored, so deleting the selected widget, or
    /// switching to a profile that does not have it, falls back instead of
    /// showing an empty pane with a picker that has nothing selected.
    private var chosen: (instance: WidgetInstance, entry: WidgetCatalog.Entry)? {
        let all = configurable
        if let selection, let match = all.first(where: { $0.instance.id == selection }) {
            return match
        }
        return all.first
    }

    // MARK: Model

    private var profileIndex: Int? {
        guard let id = state.customDock.profileID else { return nil }
        return state.profiles.firstIndex { $0.id == id }
    }

    private var instances: [WidgetInstance] {
        guard let index = profileIndex else { return [] }
        return state.profiles[index].items.compactMap(\.widget)
    }

    /// Only widgets that actually have something to configure.
    ///
    /// A section with nothing in it draws as a lone heading, which reads as a
    /// control that failed to load rather than a widget with no options.
    private var configurable: [(instance: WidgetInstance, entry: WidgetCatalog.Entry)] {
        instances.compactMap { instance in
            guard let entry = WidgetCatalog.entry(instance.kind) else { return nil }
            // Every widget now has at least its display options, so every
            // widget on the shelf is listed.
            return (instance, entry)
        }
    }

    private func write(_ instance: WidgetInstance, _ change: (inout WidgetConfig) -> Void) {
        guard let p = profileIndex,
              let i = state.profiles[p].items.firstIndex(where: { $0.id == instance.id })
        else { return }
        var updated = instance
        change(&updated.config)
        state.profiles[p].items[i] = .widget(updated)
    }

    /// "Sticky Note" alone, or "Sticky Note 1" and "Sticky Note 2" when there
    /// are several. Ordinal rather than identifier: a UUID in a heading tells
    /// nobody anything, and the order matches the shelf.
    private func sectionTitle(for pair: (instance: WidgetInstance, entry: WidgetCatalog.Entry)) -> String {
        let sameKind = configurable.filter { $0.entry.kind == pair.entry.kind }
        guard sameKind.count > 1,
              let n = sameKind.firstIndex(where: { $0.instance.id == pair.instance.id })
        else { return pair.entry.name }
        return "\(pair.entry.name) \(n + 1)"
    }

    /// Everything configurable except `layout`, which the style picker owns,
    /// and anything the current layout makes meaningless.
    ///
    /// Offering an option that does nothing is the same defect as offering
    /// one nothing reads: it accepts a change and produces none.
    private func options(for entry: WidgetCatalog.Entry,
                         _ instance: WidgetInstance) -> [String] {
        WidgetCatalog.configurableKeys(entry.kind).filter {
            WidgetCatalog.applies($0, to: instance.config, kind: entry.kind)
        }
    }

    // MARK: Battery reminders

    @ViewBuilder
    private func batteryAlertSection(_ instance: WidgetInstance) -> some View {
        let settings = BatteryAlertSettings(config: instance.config)
        Section("电池提醒") {
            LabeledContent("充电到") {
                HStack(spacing: 12) {
                    ForEach(BatteryAlertSettings.chargeChoices, id: \.self) { level in
                        levelToggle(level, in: settings.charge, key: BatteryAlertSettings.chargeKey, instance)
                    }
                }
            }
            LabeledContent("电量低于") {
                HStack(spacing: 12) {
                    ForEach(BatteryAlertSettings.lowChoices, id: \.self) { level in
                        levelToggle(level, in: settings.low, key: BatteryAlertSettings.lowKey, instance)
                    }
                }
            }
            Toggle(tr("蓝牙设备电量低于 \(BatteryAlertSettings.accessoryLevel)%"), isOn: Binding(
                get: { settings.accessory },
                set: { on in write(instance) { $0.set(BatteryAlertSettings.accessoryKey, .bool(on)) } }))
            Toggle("充满后仍插着电超过 2 小时", isOn: Binding(
                get: { settings.full },
                set: { on in write(instance) { $0.set(BatteryAlertSettings.fullKey, .bool(on)) } }))
            Toggle(tr("电池温度高于 \(Int(BatteryAlertSettings.hotCelsius))°C"), isOn: Binding(
                get: { settings.hot },
                set: { on in write(instance) { $0.set(BatteryAlertSettings.hotKey, .bool(on)) } }))
            VStack(alignment: .leading, spacing: 4) {
                NotificationsOffNote(active: NotificationAccess.batteryUsesNotifications(
                    levels: settings.charge.count + settings.low.count,
                    extras: [settings.accessory, settings.full, settings.hot]))
                Text("每一档每次充电或放电只提醒一次，发通知时电池卡片会闪一下。蓝牙设备包括 AirPods、妙控键盘、鼠标和触控板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func levelToggle(_ level: Int, in selected: Set<Int>, key: String,
                             _ instance: WidgetInstance) -> some View {
        Toggle("\(level)%", isOn: Binding(
            get: { selected.contains(level) },
            set: { on in
                var levels = selected
                if on { levels.insert(level) } else { levels.remove(level) }
                write(instance) { $0.set(key, BatteryAlertSettings.encode(levels)) }
            }))
            .toggleStyle(.checkbox)
    }

    // MARK: Display

    /// How the widget sits on the shelf, the same for every kind.
    @ViewBuilder
    private func displaySection(_ instance: WidgetInstance) -> some View {
        Section("显示") {
            Picker("显示条件", selection: Binding(
                get: { WidgetVisibility.mode(instance.config) },
                set: { mode in write(instance) { $0.set(WidgetVisibility.modeKey, .string(mode.rawValue)) } })) {
                ForEach(WidgetVisibility.modes(for: instance.kind), id: \.self) { mode in
                    Text(mode == .conditional
                         ? (WidgetVisibility.conditionTitle(instance.kind, config: instance.config) ?? mode.title)
                         : mode.title)
                        .tag(mode)
                }
            }
            if instance.kind == .battery, WidgetVisibility.mode(instance.config) == .conditional {
                Picker("电量阈值", selection: Binding(
                    get: { WidgetVisibility.batteryThreshold(instance.config) },
                    set: { value in write(instance) { $0.set(WidgetVisibility.thresholdKey, .number(Double(value))) } })) {
                    ForEach(WidgetVisibility.thresholdChoices, id: \.self) { value in
                        Text(value >= 100 ? tr("任意电量") : tr("不高于 \(value)%")).tag(value)
                    }
                }
            }
            if WidgetVisibility.mode(instance.config) != .always {
                Text("被隐藏的小组件可以在扩展栏的右键菜单或菜单栏的“已隐藏的小组件”中恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(
                get: { WidgetPlate.isHidden(instance.config) },
                set: { on in write(instance) { $0.set(WidgetPlate.key, .bool(on)) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("隐藏背景和边框")
                    Text("只去掉小组件自己的卡片，便签纸色和封面等内容保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Controls

    /// Keyed on the variant's title, not its layout.
    ///
    /// A variant may declare more than `layout` (喝水 picks a character too),
    /// so tagging by layout could give two rows the same tag and the picker
    /// could neither tell them apart nor show the right one.
    private func stylePicker(_ entry: WidgetCatalog.Entry, _ instance: WidgetInstance) -> some View {
        let currentIsPro = entry.variants.first { $0.title == selectedVariant(entry, instance) }
            .map { ProFeatures.isProStyle(entry.kind, $0.overrides) } ?? false
        return Picker(selection: Binding(
            get: { selectedVariant(entry, instance) },
            set: { title in
                guard let variant = entry.variants.first(where: { $0.title == title }) else { return }
                if !ProLicenseGate.canChoose(entry.kind, variant.overrides, unlocked: ProAccess.isUnlocked) {
                    PaywallWindow.shared.show()
                    return
                }
                write(instance) { config in
                    for (key, value) in variant.overrides { config.set(key, value) }
                }
            })) {
                // 菜单项里放不下胶囊，Pro 样式在名字后标“（Pro 专属）”；
                // 选中的是 Pro 样式时，“样式”旁边固定显示 Pro 标识。
                ForEach(entry.variants.indices, id: \.self) { index in
                    let variant = entry.variants[index]
                    Text(ProFeatures.menuTitle(variant.title, isPro: ProFeatures.isProStyle(entry.kind, variant.overrides)))
                        .tag(variant.title)
                }
            } label: {
                ProLabel(title: tr("样式"), isPro: currentIsPro)
            }
    }

    /// The variant whose every override the widget currently matches.
    private func selectedVariant(_ entry: WidgetCatalog.Entry,
                                 _ instance: WidgetInstance) -> String {
        WidgetCatalog.variantTitle(matching: instance.config, kind: entry.kind) ?? ""
    }

    @ViewBuilder
    private func control(_ key: String, entry: WidgetCatalog.Entry,
                         instance: WidgetInstance) -> some View {
        if entry.kind == .world, key == "zone" {
            // 时区不再手打：从可搜索的城市列表里选，城市名一起写好。
            worldCityControl(instance)
        } else if entry.kind == .stock || entry.kind == .watchlist, key == "symbols" || key == "groups" {
            // 代码框下面两个快捷项：黄金、白银（Yahoo 的 GC=F、SI=F）。
            plainControl(key, entry: entry, instance: instance)
            metalShortcuts(instance)
        } else {
            plainControl(key, entry: entry, instance: instance)
        }
    }

    /// “＋ 黄金”“＋ 白银”：自选股有分组时加进卡片上正在看的分组，否则加在代码列表最后。
    private func metalShortcuts(_ instance: WidgetInstance) -> some View {
        LabeledContent("快捷添加") {
            HStack(spacing: 6) {
                ForEach(PreciousMetal.allCases, id: \.self) { metal in
                    Button(tr("＋ \(metal.title)")) {
                        let isWatchlist = instance.kind == .watchlist
                        write(instance) { config in
                            config = StockBoard.adding(metal.symbol, to: config, watchlist: isWatchlist)
                        }
                    }
                }
            }
        }
        .help(tr("黄金、白银用国际期货价，默认按美元兑人民币汇率换算成元/克。"))
    }

    /// 世界时钟的“选择城市”：按钮上是现在的城市和时区，点开是城市列表。
    private func worldCityControl(_ instance: WidgetInstance) -> some View {
        let zone = instance.config.string("zone", default: "Europe/London")
        let city = instance.config.string("city", default: tr("伦敦"))
        return LabeledContent("城市与时区") {
            Button {
                cityPickerFor = instance.id
            } label: {
                Text("\(city) · \(zone)")
                    .lineLimit(1)
            }
            .popover(isPresented: Binding(
                get: { cityPickerFor == instance.id },
                set: { if !$0 { cityPickerFor = nil } })) {
                WorldCityPicker(zone: zone, city: city) { picked in
                    write(instance) { WorldCityPicker.apply(picked, to: &$0) }
                    cityPickerFor = nil
                }
                .padding(12)
                .frame(width: 320)
            }
        }
    }

    @ViewBuilder
    private func plainControl(_ key: String, entry: WidgetCatalog.Entry,
                              instance: WidgetInstance) -> some View {
        switch entry.defaults.values[key] {
        // Every read here passes the catalog's default. Without it a widget
        // saved before a key existed showed false, or empty, rather than what
        // it is actually running with, so the control disagreed with the tile
        // until it was touched.
        case .bool(let fallback):
            if NotificationAccess.isNotificationSwitch(kind: entry.kind.rawValue, key: key) {
                // 发通知的开关：系统通知被关时在开关下面提示去开启。
                Toggle(isOn: Binding(
                    get: { instance.config.bool(key, default: fallback) },
                    set: { on in write(instance) { $0.set(key, .bool(on)) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.label(key, kind: entry.kind))
                        NotificationsOffNote(active: instance.config.bool(key, default: fallback))
                    }
                }
            } else {
                Toggle(Self.label(key, kind: entry.kind), isOn: Binding(
                    get: { instance.config.bool(key, default: fallback) },
                    set: { on in write(instance) { $0.set(key, .bool(on)) } }))
            }

        case .number(let fallback):
            Stepper(value: Binding(
                get: { instance.config.double(key, default: fallback) },
                set: { value in write(instance) { $0.set(key, .number(value)) } }),
                in: Self.range(key, kind: entry.kind), step: Self.step(key, kind: entry.kind)) {
                    LabeledContent(Self.label(key, kind: entry.kind)) {
                        Text(Self.format(key, instance.config.double(key, default: fallback), kind: entry.kind))
                    }
                }

        case .string(let fallback):
            // A picker where the value is one of a known set. A text field
            // there let the user type anything, and anything unrecognised fell
            // through to the default silently, so the setting looked broken
            // rather than rejected.
            if let choices = Self.stringChoices(entry.kind, key) {
                // A supporter-locked choice (a 喝水 character) still opens the
                // sponsor window instead of being written, as the style picker
                // does for the clock faces. Every Pro choice (those, and 液态)
                // is marked “（Pro 专属）”, and the label carries the badge
                // while a Pro value is selected.
                let current = instance.config.string(key, default: fallback)
                Picker(selection: Binding(
                    get: { instance.config.string(key, default: fallback) },
                    set: { value in
                        if !ProLicenseGate.canChoose(entry.kind, [key: .string(value)], unlocked: ProAccess.isUnlocked) {
                            PaywallWindow.shared.show()
                            return
                        }
                        // 喝水的柴犬、橘猫没达标够天数：不弹付费墙，也不写。
                        if Self.waterCharacterHint(entry.kind, key: key, value: value, config: instance.config) != nil {
                            return
                        }
                        write(instance) { $0.set(key, .string(value)) }
                    })) {
                    ForEach(choices, id: \.value) { choice in
                        let title = ProFeatures.menuTitle(choice.title,
                                                          isPro: ProFeatures.isProChoice(kind: entry.kind, key: key, value: choice.value))
                        let hint = Self.waterCharacterHint(entry.kind, key: key, value: choice.value, config: instance.config)
                        Text(hint.map { tr("\(title)（\($0)）") } ?? title)
                            .tag(choice.value)
                    }
                } label: {
                    ProLabel(title: Self.label(key, kind: entry.kind),
                             isPro: ProFeatures.isProChoice(kind: entry.kind, key: key, value: current))
                }
            } else {
                // Bordered, and in a LabeledContent rather than carrying its
                // own label. A bare TextField in a grouped Form draws as
                // right-aligned text with no box, so a city already set
                // looked like stray text and an empty one looked like
                // nothing at all. Giving it the label puts the field
                // immediately after it, left of where every picker and
                // toggle in the same form sits; LabeledContent lines it up
                // with them instead.
                LabeledContent(Self.label(key, kind: entry.kind)) {
                    TextField("", text: Binding(
                        get: { instance.config.string(key, default: fallback) },
                        set: { text in write(instance) { $0.set(key, .string(text)) } }),
                        prompt: Text(Self.prompt(key)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 180)
                }
            }

        case .list(let fallback):
            if let choices = Self.choices[key] {
                // Named, because a bare run of toggles under "Style" does
                // not say what it selects: four switches reading CPU,
                // Memory, Disk, Battery could as easily be turning the
                // readings off as choosing which to show.
                Text(Self.groupLabel(key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Which of a fixed set: one toggle each.
                ForEach(choices, id: \.value) { choice in
                    Toggle(isOn: Binding(
                        get: { instance.config.strings(key, default: Self.strings(fallback))
                                .contains(choice.value) },
                        set: { on in
                            // 快速开关的 Pro 工具没解锁时勾不上，弹付费墙；取消勾选不拦。
                            if on, !ProLicenseGate.canEnableListChoice(key: key, value: choice.value,
                                                                       unlocked: ProAccess.isUnlocked) {
                                PaywallWindow.shared.show()
                                return
                            }
                            var list = instance.config.strings(key, default: Self.strings(fallback))
                            if on { if !list.contains(choice.value) { list.append(choice.value) } }
                            else { list.removeAll { $0 == choice.value } }
                            // Never leave it with nothing to show.
                            guard !list.isEmpty else { return }
                            write(instance) { $0.set(key, .list(list.map { .string($0) })) }
                        })) {
                        // 快速开关里的 Pro 工具旁固定显示 Pro 标识。
                        ProLabel(title: choice.title,
                                 isPro: ProFeatures.isProListChoice(key: key, value: choice.value))
                    }
                }
            } else {
                // Open-ended, so it is typed rather than chosen. This branch
                // did not exist, which is why a watchlist could never be
                // edited: `symbols` is read by three views and was written by
                // nothing at all.
                LabeledContent(Self.label(key, kind: entry.kind)) {
                    TextField("", text: Binding(
                        get: { instance.config.strings(key, default: Self.strings(fallback))
                                .joined(separator: ", ") },
                        set: { text in
                            let list = text.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            // An empty field is a half-finished edit, not a
                            // request for a widget with nothing in it. 提醒、
                            // 分组和持仓本来就可以一条都没有，清空就是删光。
                            guard !list.isEmpty || Self.mayBeEmpty(key) else { return }
                            write(instance) { $0.set(key, .list(list.map { .string($0) })) }
                        }),
                        prompt: Text(Self.prompt(key)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 180)
                }
                .help("用逗号分隔。")
            }

        case .none:
            EmptyView()
        }
    }

    // MARK: Presentation

    /// The catalog's default for a list key, as plain strings.
    static func strings(_ values: [WidgetConfig.Value]) -> [String] {
        values.compactMap { if case .string(let text) = $0 { text } else { nil } }
    }

    private func stringValue(_ value: WidgetConfig.Value) -> String {
        if case .string(let text) = value { return text }
        return ""
    }

    /// "showCallButton" -> "Show Call Button", except where splitting the
    /// key gives a label that states a value rather than a choice.
    ///
    /// `fahrenheit` was the clearest case: a switch labelled with one of the
    /// two units it picks between says nothing about what "off" means.
    /// Deriving labels is still the rule, and this is the short list of keys
    /// the rule reads badly for.
    private static let labels: [String: String] = [
        "fahrenheit": tr("以华氏度显示温度"),
        "city": tr("城市"),
        "cities": tr("城市列表（最多 3 个）"),
        "skip": tr("快进/快退秒数"),
        "mini": tr("紧凑布局"),
        "chart": tr("显示图表"),
        "expanded": tr("加宽显示"),
        "name": tr("名称"),
        "text": tr("便签内容"),
        "zone": tr("时区"),
        "symbols": tr("股票代码列表"),
        // 中文本地化分支：为其余选项补充中文标签，避免回退到英文键名。
        "symbol": tr("股票代码"),
        "duration": tr("时长"),
        "presets": tr("预设时长"),
        "time": tr("时间"),
        "list": tr("列表"),
        "allDay": tr("显示全天日程"),
        "calendars": tr("日历"),
        "color": tr("颜色"),
        "period": tr("时段"),
        "display": tr("显示内容"),
        "previous": tr("显示“上一首”按钮"),
        "next": tr("显示“下一首”按钮"),
        "backward": tr("显示“后退”按钮"),
        "forward": tr("显示“快进”按钮"),
        "spotify": "Spotify",
        "apple": tr("Apple 音乐"),
        "netease": tr("网易云音乐"),
        "xiaoyuzhou": tr("小宇宙"),
        "browsers": tr("浏览器标签页"),
        "devices": tr("设备"),
        "bluetooth": tr("显示蓝牙设备（耳机、鼠标、触控板等）"),
        "metrics": tr("读数"),
        "folder": tr("文件夹"),
        "interval": tr("切换间隔"),
        "shuffle": tr("随机顺序"),
        "emoji": tr("常用表情"),
        "engine": tr("搜索引擎"),
        "allScreens": tr("应用到所有显示器"),
        "links": tr("网址"),
        "repo": tr("仓库"),
        "repos": tr("仓库列表"),
        "rings": tr("圆环"),
        "start": tr("开始时间"),
        "end": tr("结束时间"),
        "notify": tr("发送通知"),
        "show": tr("圆环显示"),
        "alertAt": tr("首次提醒阈值"),
        "notifyDone": tr("任务完成时通知"),
        "extras": tr("显示 Spark 与代码审查额度"),
        "showDone": tr("显示已完成的待办"),
        "sounds": tr("声音"),
        "volume": tr("音量"),
        "showTerm": tr("显示节气"),
        "seconds": tr("显示秒（数字类样式）"),
        "workAlert": tr("调休上班提醒"),
        "workAlertLead": tr("提醒提前"),
        "flies": tr("垃圾多了招来苍蝇"),
        "threshold": tr("苍蝇出现的大小"),
        "pasteOnClick": tr("点按后直接粘贴（需要辅助功能权限）"),
        "actions": tr("开关"),
        "showStreak": tr("显示连续打卡天数"),
        "showRing": tr("显示日历页（单个样式）"),
        "coins": tr("币种（BTC、ETH 等代码，或 CoinGecko ID）"),
        "currency": tr("计价货币"),
        "colors": tr("涨跌颜色"),
        "goal": tr("每日目标"),
        "cupSize": tr("一杯的容量（卡片上的 +）"),
        "remindEvery": tr("喝水提醒"),
        "unit": tr("单位"),
        "character": tr("角色形象"),
        "clickAction": tr("点按卡片时"),
        "autoDirection": tr("智能方向（中文译成英语，其他译成中文）"),
        "workdays": tr("工作日"),
        "payday": tr("发薪日"),
        "income": tr("每天的收入"),
        "more": tr("显示更多"),
        "font": tr("字体"),
        "tint": tr("背景随状态变色（上班橙、下班绿、周末蓝）"),
        "holidays": tr("按法定节假日和调休"),
    ]

    /// Where one key means something different in one widget: `interval`
    /// is the photo frame's seconds between pictures but GitHub's minutes
    /// between checks.
    private static let kindLabels: [String: String] = [
        "github.interval": tr("检查间隔"),
        "github.notify": tr("有新议题、拉取请求或评论时通知"),
        "github.repos": tr("关注的项目（最多 \(GitHubWatch.maxRepos) 个）"),
        "podcast.notify": tr("有新单集时通知"),
        "posture.goal": tr("每天起身目标"),
        // 「算」只写了一种币种时：是「默认换成」那种就换成常用币种，否则换成「默认换成」。
        "calculator.currencyFrom": tr("常用币种（输入本币时换成它）"),
        "calculator.currencyTo": tr("默认换成（只写一种币种时）"),
        "battery.look": tr("外观"),
        "countdown.look": tr("数字外观"),
        "countdown.sound": tr("到点响提示音"),
        "alarm.sound": tr("响铃时出声"),
        "slacker.start": tr("上班时间"),
        "slacker.end": tr("下班时间（要晚于上班时间）"),
        "slacker.look": tr("外观"),
        "timer.look": tr("外观"),
        "ai-usage.look": tr("外观"),
        "perfect-day.look": tr("外观"),
        "water.dryUp": tr("很久没喝水时角色渴成骷髅"),
        "progress.liquidMotion": tr("水面动效（波纹和气泡）"),
        "stock.symbols": tr("股票代码（多只时轮播）"),
        "stock.symbol": tr("正在显示的代码"),
        "stock.alerts": tr("到价提醒（AAPL>237 是涨到，AAPL<220 是跌到）"),
        "stock.rotate": tr("多只时每 10 秒自动轮播"),
        "watchlist.groups": tr("分组（科技=NVDA TSLA，一组一项）"),
        "watchlist.holdings": tr("持仓（NVDA 100，填了才显示今日盈亏）"),
        "watchlist.sort": tr("排序"),
        "stock.metalUnit": tr("黄金白银单位"),
        "watchlist.metalUnit": tr("黄金白银单位"),
        "weather.caption": tr("副标题"),
        "weather.days": tr("天数"),
    ]

    static func label(_ key: String) -> String {
        labels[key] ?? WidgetCatalog.optionLabel(key)
    }

    static func label(_ key: String, kind: WidgetKind) -> String {
        // 时钟的子选项（大小、粗细、表盘、卡片、翻法）名字在样式注册表里。
        if kind == .clock, let option = ClockStyles.option(key) { return option.title }
        return kindLabels["\(kind.rawValue).\(key)"] ?? label(key)
    }

    /// What a run of toggles is choosing between.
    private static let groupLabels: [String: String] = [
        "metrics": tr("要显示的读数"),
        "sources": tr("要读取的播放器"),
        "devices": tr("要显示的设备"),
        "rings": tr("要显示的圆环"),
        "sounds": tr("要混合的声音"),
        "actions": tr("要显示的开关"),
        "workdays": tr("工作日"),
        "more": tr("显示更多（卡片下方的小格）"),
    ]

    static func groupLabel(_ key: String) -> String {
        groupLabels[key] ?? tr("显示")
    }

    static func prompt(_ key: String) -> String {
        switch key {
        case "city": tr("当前位置")
        case "cities": tr("北京, 上海, 广州")
        case "folder": tr("图片")
        case "links": tr("标题 网址, …")
        case "repo": tr("用户/仓库")
        case "repos": tr("用户/仓库, 用户/仓库")
        case "start": "09:00"
        case "end": "18:00"
        case "coins": "BTC, ETH, SOL"
        case "alerts": "AAPL>237, AAPL<220"
        case "groups": tr("科技=NVDA TSLA, A股=600519.SS")
        case "holdings": "NVDA 100, AAPL 50"
        default: ""
        }
    }

    static func range(_ key: String, kind: WidgetKind? = nil) -> ClosedRange<Double> {
        // 久坐提醒的 goal 是每天起身几次，不是喝水的毫升。
        if kind == .posture, key == PostureTrack.goalKey {
            return Double(PostureTrack.goalRange.lowerBound)...Double(PostureTrack.goalRange.upperBound)
        }
        switch key {
        case "duration": 60...14_400
        case "skip": 5...60
        case "interval": 5...3_600
        case "alertAt": 50...95
        case "volume": 0...100
        case "goal": Double(WaterIntake.goalRange.lowerBound)...Double(WaterIntake.goalRange.upperBound)
        case "cupSize": Double(WaterIntake.cupRange.lowerBound)...Double(WaterIntake.cupRange.upperBound)
        case "payday": Double(SlackerClock.paydayRange.lowerBound)...Double(SlackerClock.paydayRange.upperBound)
        case "income": SlackerClock.incomeRange
        default: 0...1_000
        }
    }

    static func step(_ key: String, kind: WidgetKind? = nil) -> Double {
        if kind == .posture, key == PostureTrack.goalKey { return 1 }
        switch key {
        case "duration": 300
        case "goal": 100
        case "cupSize": 50
        case "payday": 1
        case "income": SlackerClock.incomeStep
        default: 5
        }
    }

    static func format(_ key: String, _ value: Double, kind: WidgetKind? = nil) -> String {
        if kind == .posture, key == PostureTrack.goalKey { return tr("每天 \(Int(value)) 次") }
        if key == "alertAt" || key == "volume" { return "\(Int(value))%" }
        if key == "goal" || key == "cupSize" { return tr("\(Int(value)) 毫升") }
        if key == "payday" { return tr("每月 \(Int(value)) 日") }
        if key == "income" { return tr("\(Int(value)) 元") }
        guard key == "duration" else { return tr("\(Int(value)) 秒") }
        let minutes = Int(value) / 60
        return minutes >= 60 ? tr("\(minutes / 60) 小时 \(minutes % 60) 分钟") : tr("\(minutes) 分钟")
    }

    /// The fixed sets behind the list-valued options.
    static let choices: [String: [(title: String, value: String)]] = [
        "metrics": [("CPU", "cpu"), (tr("内存"), "memory"),
                    (tr("磁盘"), "disk"), (tr("电池"), "battery")],
        "devices": [(tr("这台 Mac"), "mac"), ("AirPods", "pods"),
                    (tr("AirPods 充电盒"), "case"), (tr("键盘"), "keyboard")],
        "rings": [(tr("存储空间"), "storage"), (tr("电池"), "battery"),
                  ("CPU", "cpu"), (tr("内存"), "memory")],
        "sounds": AmbientSound.allCases.map { ($0.title, $0.rawValue) },
        "actions": QuickToggle.allCases.map { ($0.title, $0.rawValue) },
        "workdays": SlackerClock.weekdayChoices,
        "more": SlackerClock.Item.allCases.map { ($0.title, $0.rawValue) },
    ]

    /// String options that are really a choice from a fixed set.
    ///
    /// Without this every one of them got a free-text field, so the only way
    /// to discover a valid value was to read the source, and a typo silently
    /// fell through to the default with nothing said.
    ///
    /// Keyed by kind and key together, because the same name means different
    /// things in different widgets: `period` is day/month/year in Time
    /// Progress and a chart range in Stocks. The existing list table is keyed
    /// on the name alone, which works only because no two widgets have yet
    /// collided there.
    ///
    /// Only sets that were read out of the code that consumes them. A key
    /// missing here keeps its text field, which is the honest fallback.
    static let stringChoices: [String: [(title: String, value: String)]] = [
        "network.display": [(tr("两者"), "both"), (tr("下载"), "download"), (tr("上传"), "upload")],
        "battery.look": BatteryLook.allCases.map { ($0.title, $0.rawValue) },
        "progress.period": TimeProgress.Period.allCases.map { ($0.title, $0.rawValue) },
        "notes.color": PaperColor.picker.map { ($0.title, $0.rawValue) },
        "ai-usage.show": [(tr("已用"), "used"), (tr("剩余"), "remaining")],
        "search.engine": SearchSites.builtIn.map { ($0.title, $0.id) },
        "calculator.currencyFrom": CurrencyNames.common.map { ("\($0.name) \($0.code)", $0.code) },
        "calculator.currencyTo": CurrencyNames.common.map { ("\($0.name) \($0.code)", $0.code) },
        "lunar.workAlertLead": LunarCard.leadChoices.map { (tr("\($0) 天"), "\($0)") },
        "trash.threshold": TrashFlies.thresholds.map { ($0.label, $0.value) },
        "crypto.currency": [(tr("人民币 CNY"), "cny"), (tr("美元 USD"), "usd")],
        "crypto.colors": ChangeColors.allCases.map { ($0.title, $0.rawValue) },
        "stock.colors": ChangeColors.allCases.map { ($0.title, $0.rawValue) },
        "watchlist.colors": ChangeColors.allCases.map { ($0.title, $0.rawValue) },
        "stock.metalUnit": PreciousMetal.DisplayUnit.allCases.map { ($0.title, $0.rawValue) },
        "watchlist.metalUnit": PreciousMetal.DisplayUnit.allCases.map { ($0.title, $0.rawValue) },
        "watchlist.sort": StockBoard.Order.allCases.map { ($0.title, $0.rawValue) },
        "water.remindEvery": WaterIntake.reminderChoices.map { ($0 == 0 ? tr("关闭") : tr("每 \($0) 分钟"), "\($0)") },
        "water.unit": [(tr("毫升"), "ml"), (tr("盎司"), "oz")],
        "water.character": WaterCharacter.allCases.map { ($0.title, $0.rawValue) },
        "pet.character": WaterCharacter.allCases.map { ($0.title, $0.rawValue) },
        "translate.clickAction": Translate.ClickAction.allCases.map { ($0.title, $0.rawValue) },
        "github.interval": GitHubWatch.intervalChoices.map { (tr("每 \($0) 分钟"), "\($0)") },
        "slacker.font": SlackerClock.FontChoice.allCases.map { ($0.title, $0.rawValue) },
        "slacker.look": SlackerClock.Look.allCases.map { ($0.title, $0.rawValue) },
        "timer.look": LiquidMotion.TimerLook.allCases.map { ($0.title, $0.rawValue) },
        "ai-usage.look": LiquidLooks.CodexLook.allCases.map { ($0.title, $0.rawValue) },
        "perfect-day.look": LiquidLooks.BasketLook.allCases.map { ($0.title, $0.rawValue) },
        "countdown.look": FoldFlip.CountdownLook.allCases.map { ($0.title, $0.rawValue) },
        "weather.caption": WeatherStyle.Caption.allCases.map { ($0.title, $0.rawValue) },
        "weather.days": WeatherStyle.dayChoices.map { (tr("\($0) 天"), "\($0)") },
    ]

    /// “再达标 3 天解锁” for a 喝水 character still to be earned, nil for
    /// everything else (Pro unlocks it too).
    static func waterCharacterHint(_ kind: WidgetKind, key: String, value: String,
                                   config: WidgetConfig) -> String? {
        guard kind == .water, key == "character", let character = WaterCharacter(rawValue: value),
              case .locked(let left) = WaterCharacter.access(character, config: config, pro: ProAccess.isUnlocked)
        else { return nil }
        return WaterCharacter.unlockHint(daysLeft: left)
    }

    static func stringChoices(_ kind: WidgetKind, _ key: String)
        -> [(title: String, value: String)]? {
        if kind == .clock, let option = ClockStyles.option(key) {
            return option.choices.map { (title: $0.title, value: $0.value) }
        }
        return stringChoices["\(kind.rawValue).\(key)"]
    }

    private static func optionLabel(_ raw: String) -> String {
        raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Open-ended lists, edited as text rather than chosen from a set.
    ///
    /// `symbols` is the reason this exists: it is read by three views and was
    /// written by nothing, so a watchlist was whatever it shipped as, for
    /// ever. A fixed set is impossible here because the set is every ticker
    /// there is.
    static func mayBeEmpty(_ key: String) -> Bool {
        ["alerts", "groups", "holdings"].contains(key)
    }

    static func isFreeformList(_ key: String) -> Bool {
        choices[key] == nil
    }
}
