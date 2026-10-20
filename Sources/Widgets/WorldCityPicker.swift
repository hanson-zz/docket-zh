import SwiftUI

// MARK: - 共用的城市选择器

/// 选城市：搜索框（中文、英文、拼音、国家、时区标识都认）、常用城市、
/// 结果列表。三处共用：世界时钟面板的“添加城市”、时钟面板换城市、
/// 设置窗口里的世界时钟。
///
/// 结果行是地标小图、中英文名、国家、当地时间；已经在列表里的打勾。
/// 内置表没有的仍可以选系统时区，显示“系统时区”和地球图标。
struct WorldCityPicker: View {
    enum Mode {
        /// 加到列表最后：已添加的打勾，点了没反应（世界时钟面板）。
        case add
        /// 换掉 `current` 那一格：`current` 打勾，别的格已有的城市打勾不能选（时钟面板）。
        case replace
        /// 点一下加入，再点一下移出（设置窗口）。
        case toggle
    }

    /// 已经在列表里的城市。
    var added: [WorldCity]
    var mode: Mode = .add
    /// `replace` 时被换的那座城市。
    var current: WorldCity? = nil
    /// 结果列表的高度，超出滚动。
    var listHeight: CGFloat = 288
    /// 打开时光标直接在搜索框里。
    var autofocus = true
    var onPick: (WorldCity) -> Void

    @State private var query = ""
    @FocusState private var searching: Bool
    @Environment(\.panelTint) private var panelTint

    static let amber = Color(red: 0.96, green: 0.65, blue: 0.14)
    private var accent: Color { panelTint.accent(or: Self.amber) }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            TimelineView(.everyMinute) { tick in
                let results = WorldCities.search(query)
                VStack(alignment: .leading, spacing: 12) {
                    if trimmed.isEmpty, !commonChoices.isEmpty {
                        commonSection
                    }
                    sectionTitle(trimmed.isEmpty ? tr("全部城市") : tr("搜索结果 · \(results.count)"))
                    if results.isEmpty {
                        Text(tr("没有找到，试试英文名或时区，例如 Kathmandu"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Divider().opacity(0.5).padding(.leading, 52)
                                    }
                                    row(item, now: tick.date)
                                }
                            }
                        }
                        .frame(height: listHeight)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        }
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    }
                    Text(tr("中文、英文、拼音、国家、时区标识都能搜"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            if autofocus {
                // 弹层出现之后再给焦点，否则窗口还没准备好，光标落不进去。
                DispatchQueue.main.async { searching = true }
            }
        }
    }

    // MARK: 搜索框

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(tr("搜索城市、国家或时区"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searching)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("清除"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(searching ? accent.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: 常用城市

    /// 常用城市里还没添加的，最多十个。
    private var commonChoices: [WorldCity] {
        WorldCities.common
            .filter { !isAdded($0) && $0.id != current?.id }
            .prefix(10)
            .map { $0 }
    }

    private var commonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("常用城市"))
            CityChipFlow(spacing: 6) {
                ForEach(commonChoices) { city in
                    Button { onPick(city) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(verbatim: city.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("添加\(city.name)"))
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: 结果行

    private func isAdded(_ city: WorldCity) -> Bool {
        WorldClockList.contains(city, in: added)
    }

    /// 打勾：在列表里，或者是正在换的那一格。
    private func isChecked(_ city: WorldCity) -> Bool {
        isAdded(city) || city.id == current?.id
    }

    /// 能不能点：加和换的模式里已有的城市不能再选（不重复）；设置窗口里可以点掉。
    private func isEnabled(_ city: WorldCity) -> Bool {
        switch mode {
        case .add, .replace: !isChecked(city)
        case .toggle: true
        }
    }

    private func row(_ item: WorldCity, now: Date) -> some View {
        let checked = isChecked(item)
        let zone = item.timeZone ?? .current
        let day = WorldClockTile.dayHint(now, zone: zone)
        return Button { onPick(item) } label: {
            HStack(spacing: 10) {
                CityLandmarkBadge(city: item, now: now, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: item.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let subtitle = englishSubtitle(item) {
                            Text(verbatim: subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(verbatim: [item.region.isEmpty ? item.zone : item.region, day]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(ClockFormat.time(now, zone: zone))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .monospacedDigit()
                    .lineLimit(1)
                trailing(checked)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled(item))
        .accessibilityLabel("\(item.name)，\(item.region.isEmpty ? item.zone : item.region)")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    /// 名字后面的小字：内置城市写英文名（英文界面名字本身就是英文，不重复），
    /// 系统时区写时区标识。
    private func englishSubtitle(_ item: WorldCity) -> String? {
        if item.isBuiltIn { return item.english == item.name ? nil : item.english }
        return item.zone == item.name ? nil : item.zone
    }

    @ViewBuilder
    private func trailing(_ checked: Bool) -> some View {
        if checked {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
    }

    /// 写回单城市的旧键 `zone` 和 `city`（只给还没换到列表的地方用）。
    static func apply(_ city: WorldCity, to config: inout WidgetConfig) {
        config.set(WorldClockList.zoneKey, .string(city.zone))
        config.set(WorldClockList.cityKey, .string(city.name))
    }
}

// MARK: - 地标小图

/// 当地天空色的小方块，里面画城市的地标；系统时区画地球。
/// 用在添加城市的结果行、编辑态的行和卡片上两个城市时的小图标。
struct CityLandmarkBadge: View {
    var city: WorldCity
    var now: Date
    var size: CGFloat = 32
    /// 地标的不透明度：列表里 70%，卡片小图标 85%。
    var inkOpacity: Double = 0.7

    var body: some View {
        let zone = city.timeZone ?? .current
        let corner = size * 0.25
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(SkyBackdrop.palette(Self.hour(now, zone: zone)).first ?? .gray)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            if city.isBuiltIn {
                CityLandmarkMark(landmark: city.landmark, color: .white.opacity(inkOpacity),
                                 lineWidth: size < 26 ? 0.8 : 0.9)
                    .padding(size * 0.07)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.55, weight: .light))
                    .foregroundStyle(.white.opacity(inkOpacity))
            }
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, .dark)
    }

    static func hour(_ now: Date, zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }
}

// MARK: - 常用城市的换行排列

/// 胶囊按各自宽度从左往右排，放不下换行。
struct CityChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let needed = rows[rows.count - 1].isEmpty ? size.width : used + spacing + size.width
            if needed > width, !rows[rows.count - 1].isEmpty {
                rows.append([index])
                used = size.width
            } else {
                rows[rows.count - 1].append(index)
                used = needed
            }
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? sizes.reduce(0) { $0 + $1.width + spacing }
        let lines = rows(sizes, width: width)
        let height = lines.reduce(0) { total, line in
            total + (line.map { sizes[$0].height }.max() ?? 0)
        } + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for line in rows(sizes, width: bounds.width) {
            let height = line.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in line {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += height + spacing
        }
    }
}
