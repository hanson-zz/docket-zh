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
                Section(sectionTitle(for: pair)) {
                    if !pair.entry.variants.isEmpty {
                        stylePicker(pair.entry, pair.instance)
                    }
                    ForEach(options(for: pair.entry, pair.instance), id: \.self) { key in
                        control(key, entry: pair.entry, instance: pair.instance)
                    }
                }
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
            let hasControls = !entry.variants.isEmpty || !options(for: entry, instance).isEmpty
            return hasControls ? (instance, entry) : nil
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

    // MARK: Controls

    /// Keyed on the variant's title, not its layout.
    ///
    /// "Numbers" and "Numbers + graph" are both `layout: "numbers"` and differ
    /// only by `chart`, so tagging by layout gave two rows the same tag and
    /// the picker could neither tell them apart nor show the right one.
    private func stylePicker(_ entry: WidgetCatalog.Entry, _ instance: WidgetInstance) -> some View {
        Picker("样式", selection: Binding(
            get: { selectedVariant(entry, instance) },
            set: { title in
                guard let variant = entry.variants.first(where: { $0.title == title }) else { return }
                write(instance) { config in
                    for (key, value) in variant.overrides { config.set(key, value) }
                }
            })) {
                ForEach(entry.variants.indices, id: \.self) { index in
                    Text(entry.variants[index].title).tag(entry.variants[index].title)
                }
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
        switch entry.defaults.values[key] {
        // Every read here passes the catalog's default. Without it a widget
        // saved before a key existed showed false, or empty, rather than what
        // it is actually running with, so the control disagreed with the tile
        // until it was touched.
        case .bool(let fallback):
            Toggle(Self.label(key), isOn: Binding(
                get: { instance.config.bool(key, default: fallback) },
                set: { on in write(instance) { $0.set(key, .bool(on)) } }))

        case .number(let fallback):
            Stepper(value: Binding(
                get: { instance.config.double(key, default: fallback) },
                set: { value in write(instance) { $0.set(key, .number(value)) } }),
                in: Self.range(key), step: Self.step(key)) {
                    LabeledContent(Self.label(key)) {
                        Text(Self.format(key, instance.config.double(key, default: fallback)))
                    }
                }

        case .string(let fallback):
            // A picker where the value is one of a known set. A text field
            // there let the user type anything, and anything unrecognised fell
            // through to the default silently, so the setting looked broken
            // rather than rejected.
            if let choices = Self.stringChoices(entry.kind, key) {
                Picker(Self.label(key), selection: Binding(
                    get: { instance.config.string(key, default: fallback) },
                    set: { value in write(instance) { $0.set(key, .string(value)) } })) {
                    ForEach(choices, id: \.value) { Text($0.title).tag($0.value) }
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
                LabeledContent(Self.label(key)) {
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
                    Toggle(choice.title, isOn: Binding(
                        get: { instance.config.strings(key, default: Self.strings(fallback))
                                .contains(choice.value) },
                        set: { on in
                            var list = instance.config.strings(key, default: Self.strings(fallback))
                            if on { if !list.contains(choice.value) { list.append(choice.value) } }
                            else { list.removeAll { $0 == choice.value } }
                            // Never leave it with nothing to show.
                            guard !list.isEmpty else { return }
                            write(instance) { $0.set(key, .list(list.map { .string($0) })) }
                        }))
                }
            } else {
                // Open-ended, so it is typed rather than chosen. This branch
                // did not exist, which is why a watchlist could never be
                // edited: `symbols` is read by three views and was written by
                // nothing at all.
                LabeledContent(Self.label(key)) {
                    TextField("", text: Binding(
                        get: { instance.config.strings(key, default: Self.strings(fallback))
                                .joined(separator: ", ") },
                        set: { text in
                            let list = text.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            // An empty field is a half-finished edit, not a
                            // request for a widget with nothing in it.
                            guard !list.isEmpty else { return }
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
        "fahrenheit": "以华氏度显示温度",
        "city": "城市",
        "skip": "快进/快退秒数",
        "mini": "紧凑布局",
        "chart": "显示图表",
        "expanded": "加宽显示",
        "name": "名称",
        "text": "便签内容",
        "zone": "时区",
        "symbols": "股票代码列表",
        // 中文本地化分支：为其余选项补充中文标签，避免回退到英文键名。
        "symbol": "股票代码",
        "duration": "时长",
        "presets": "预设时长",
        "time": "时间",
        "list": "列表",
        "allDay": "显示全天日程",
        "calendars": "日历",
        "color": "颜色",
        "period": "时段",
        "display": "显示内容",
        "previous": "显示“上一首”按钮",
        "next": "显示“下一首”按钮",
        "backward": "显示“后退”按钮",
        "forward": "显示“快进”按钮",
        "spotify": "Spotify",
        "apple": "Apple 音乐",
        "browsers": "浏览器标签页",
        "devices": "设备",
        "metrics": "读数",
        "folder": "文件夹",
        "interval": "切换间隔",
        "shuffle": "随机顺序",
        "emoji": "常用表情",
        "engine": "搜索引擎",
        "allScreens": "应用到所有显示器",
        "links": "网址",
    ]

    static func label(_ key: String) -> String {
        labels[key] ?? WidgetCatalog.optionLabel(key)
    }

    /// What a run of toggles is choosing between.
    private static let groupLabels: [String: String] = [
        "metrics": "要显示的读数",
        "sources": "要读取的播放器",
        "devices": "要显示的设备",
    ]

    static func groupLabel(_ key: String) -> String {
        groupLabels[key] ?? "显示"
    }

    static func prompt(_ key: String) -> String {
        switch key {
        case "city": "当前位置"
        case "folder": "图片"
        case "links": "标题 网址, …"
        default: ""
        }
    }

    static func range(_ key: String) -> ClosedRange<Double> {
        switch key {
        case "duration": 60...14_400
        case "skip": 5...60
        case "interval": 5...3_600
        default: 0...1_000
        }
    }

    static func step(_ key: String) -> Double {
        key == "duration" ? 300 : 5
    }

    static func format(_ key: String, _ value: Double) -> String {
        guard key == "duration" else { return "\(Int(value)) 秒" }
        let minutes = Int(value) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    /// The fixed sets behind the list-valued options.
    static let choices: [String: [(title: String, value: String)]] = [
        "metrics": [("CPU", "cpu"), ("内存", "memory"),
                    ("磁盘", "disk"), ("电池", "battery")],
        "devices": [("这台 Mac", "mac"), ("AirPods", "pods"),
                    ("AirPods 充电盒", "case"), ("键盘", "keyboard")],
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
        "network.display": [("两者", "both"), ("下载", "download"), ("上传", "upload")],
        "progress.period": [("日", "day"), ("月", "month"), ("年", "year")],
        "notes.color": PaperColor.picker.map { (docketColourName($0.rawValue), $0.rawValue) },
        "search.engine": SearchEngine.allCases.map { ($0.title, $0.rawValue) },
    ]

    static func stringChoices(_ kind: WidgetKind, _ key: String)
        -> [(title: String, value: String)]? {
        stringChoices["\(kind.rawValue).\(key)"]
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
    static func isFreeformList(_ key: String) -> Bool {
        choices[key] == nil
    }
}
