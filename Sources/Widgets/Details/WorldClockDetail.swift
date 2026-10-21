import AppKit
import SwiftUI

/// 世界时钟面板：每个城市一张卡，右上角一枚当地地标线稿。
///
/// 三个状态：
/// - 浏览：城市卡写名字、和此处差几个小时、时间大字、“周二 · 凌晨”，
///   底色是当地此刻的天空。点一张卡展开未来 12 小时的对照条（同一时间
///   只开一张），两行是同一时刻在两地的钟点，夏令时由时区规则自己算。
/// - 编辑：右上“编辑”进入。拖右侧把手排序，红色减号滑出“删除”再点才删，
///   至少留 1 个；底部“＋ 添加城市”，最多 12 个。排在前 3 个的就是卡片上显示的。
/// - 添加：共用的城市选择器（`WorldCityPicker`），点一行加到最后，回到编辑。
///
/// 城市列表存在 `cities`（见 `WorldClockList`），第一项同步回旧的 `zone`
/// 和 `city`，卡片、旧版本和截图工具都还能读。
struct WorldClockDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, edit, add }

    @State private var mode: Mode = .browse
    /// 展开 12 小时对照条的那张卡。
    @State private var expanded: String?
    /// 点了红色减号、正露出“删除”的那一行。
    @State private var pendingDelete: String?
    /// 正在拖的那一行和它的位移。
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0

    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: WorldCityPicker.amber) }
    private var accentInk: Color { panelTint.ink(or: Color(white: 0.1)) }

    private static let editRowHeight: CGFloat = 50
    private static let deleteWidth: CGFloat = 64

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var cities: [WorldCity] { WorldClockList.cities(current.config) }

    var body: some View {
        // 不能用 `context.now`：面板的 context 只在打开那一刻取一次。
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let now = tick.date
            let list = cities
            DetailCard {
                MeshBackdrop(color: Color(red: 0.37, green: 0.42, blue: 0.82))
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    header(list, now: now)
                    switch mode {
                    case .browse: browse(list, now: now)
                    case .edit: edit(list, now: now)
                    case .add: add(list)
                    }
                }
            }
        }
    }

    // MARK: 头部

    private func header(_ list: [WorldCity], now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(verbatim: subtitle(list, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            headerButton
        }
    }

    private var title: String {
        switch mode {
        case .browse: tr("世界时钟")
        case .edit: tr("编辑城市")
        case .add: tr("添加城市")
        }
    }

    private func subtitle(_ list: [WorldCity], now: Date) -> String {
        switch mode {
        case .browse: WorldClockText.header(time: ClockFormat.time(now, zone: .current), count: list.count)
        case .edit: tr("拖动把手调整顺序，卡片显示前 3 个")
        case .add: tr("点一行加到列表最后")
        }
    }

    /// 右上角：浏览时“编辑”，编辑时琥珀色“完成”，添加时“取消”。
    /// 小组件库的预览里不能写配置，不显示。
    @ViewBuilder
    private var headerButton: some View {
        if !context.isPreview {
            switch mode {
            case .browse:
                Button { switchTo(.edit) } label: {
                    Text(tr("编辑"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .glassPane(cornerRadius: 9)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("增删城市、调整顺序"))
            case .edit:
                Button { switchTo(.browse) } label: {
                    Text(tr("完成"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            case .add:
                Button { switchTo(.edit) } label: {
                    Text(tr("取消"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .frame(height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func switchTo(_ next: Mode) {
        // 添加城市要打字：先让面板成为 key，搜索框才接得住光标。
        if next == .add { WidgetDetailWindow.shared.focusField {} }
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            pendingDelete = nil
            dragging = nil
            dragOffset = 0
        }
    }

    // MARK: 浏览

    private func browse(_ list: [WorldCity], now: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(list) { city in
                WorldCityCard(city: city, now: now, expanded: expanded == city.id)
                    .contentShape(.rect(cornerRadius: 14))
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) {
                            expanded = expanded == city.id ? nil : city.id
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(tr("展开或收起未来 12 小时"))
            }
            Text(tr("点城市卡展开或收起未来 12 小时"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: 编辑

    private func edit(_ list: [WorldCity], now: Date) -> some View {
        let from = dragging.flatMap { id in list.firstIndex { $0.id == id } }
        let target = from.map {
            WorldClockList.dropIndex(from: $0, translation: dragOffset, rowHeight: Self.editRowHeight,
                                     count: list.count)
        }
        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    editRow(city, index: index, list: list, now: now)
                        .offset(y: rowShift(index, from: from, target: target))
                        .zIndex(city.id == dragging ? 1 : 0)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.panelStroke, lineWidth: 0.5)
                    }
            }

            addButton(list)

            Text(tr("最多 12 个城市，至少留 1 个"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
        }
    }

    /// 拖动时：被拖的那行跟着手走，经过的行让开一格。
    private func rowShift(_ index: Int, from: Int?, target: Int?) -> CGFloat {
        guard let from, let target else { return 0 }
        if index == from { return dragOffset }
        if from < target, (from + 1...target).contains(index) { return -Self.editRowHeight }
        if target < from, (target..<from).contains(index) { return Self.editRowHeight }
        return 0
    }

    private func editRow(_ city: WorldCity, index: Int, list: [WorldCity], now: Date) -> some View {
        let lifted = dragging == city.id
        let revealing = pendingDelete == city.id
        let canDelete = list.count > 1
        let zone = city.timeZone ?? .current
        return ZStack(alignment: .trailing) {
            if revealing {
                Button { delete(city, from: list) } label: {
                    Text(tr("删除"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: Self.deleteWidth, height: Self.editRowHeight)
                        .background(Color(red: 0.85, green: 0.18, blue: 0.13))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing))
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { pendingDelete = revealing ? nil : city.id }
                } label: {
                    ZStack {
                        Circle().fill(Color(red: 1, green: 0.27, blue: 0.23))
                        Capsule().fill(.white).frame(width: 9.6, height: 2.4)
                            .rotationEffect(.degrees(revealing ? 90 : 0))
                    }
                    .frame(width: 18, height: 18)
                    .opacity(canDelete ? 1 : 0.3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .help(canDelete ? tr("删除这个城市") : tr("至少留 1 个城市"))

                CityLandmarkBadge(city: city, now: now, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: city.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text(verbatim: WorldClockText.offsetLine(city, now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(ClockFormat.time(now, zone: zone))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)

                if !revealing {
                    handle(city, index: index, list: list, lifted: lifted)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, revealing ? 8 : 4)
            .frame(height: Self.editRowHeight)
            .offset(x: revealing ? -Self.deleteWidth : 0)
            .contentShape(.rect)
            .onTapGesture {
                if pendingDelete != nil { withAnimation(.snappy(duration: 0.22)) { pendingDelete = nil } }
            }
        }
        .frame(height: Self.editRowHeight)
        .clipped()
        .background {
            if lifted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.panelDynamic(dark: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.26, alpha: 1),
                                         light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            }
        }
        .overlay(alignment: .bottom) {
            if index < list.count - 1, !lifted {
                Rectangle().fill(.panelSeparator).frame(height: 0.5).padding(.leading, 70)
            }
        }
    }

    /// 右侧把手：按住拖动排序，松手时落到最近的一格。
    private func handle(_ city: WorldCity, index: Int, list: [WorldCity], lifted: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.panelPrimary.opacity(lifted ? 0.85 : 0.5))
            .frame(width: 32, height: Self.editRowHeight)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging != city.id {
                            dragging = city.id
                            pendingDelete = nil
                        }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let to = WorldClockList.dropIndex(from: index, translation: value.translation.height,
                                                          rowHeight: Self.editRowHeight, count: list.count)
                        save(WorldClockList.moving(from: index, to: to, in: list))
                        withAnimation(.snappy(duration: 0.2)) {
                            dragging = nil
                            dragOffset = 0
                        }
                    }
            )
            .help(tr("拖动调整顺序"))
            .accessibilityLabel(tr("调整\(city.name)的顺序"))
            .accessibilityAction(named: tr("上移")) {
                save(WorldClockList.moving(from: index, to: index - 1, in: list))
            }
            .accessibilityAction(named: tr("下移")) {
                save(WorldClockList.moving(from: index, to: index + 1, in: list))
            }
    }

    private func addButton(_ list: [WorldCity]) -> some View {
        let full = list.count >= WorldClockList.maxCount
        return Button { switchTo(.add) } label: {
            Text(full ? tr("已有 12 个城市") : tr("＋ 添加城市"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(full ? 0.45 : 0.92))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.panelFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.panelQuaternary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(full)
    }

    // MARK: 添加

    private func add(_ list: [WorldCity]) -> some View {
        WorldCityPicker(added: list, mode: .add, listHeight: 300) { picked in
            save(WorldClockList.adding(picked, to: list))
            switchTo(.edit)
        }
    }

    // MARK: 写回

    private func delete(_ city: WorldCity, from list: [WorldCity]) {
        guard let index = list.firstIndex(where: { $0.id == city.id }) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            save(WorldClockList.removing(at: index, from: list))
            pendingDelete = nil
            if expanded == city.id { expanded = nil }
        }
    }

    private func save(_ list: [WorldCity]) {
        guard !context.isPreview else { return }
        WidgetWriter.write(current) { WorldClockList.write(list, to: &$0) }
    }
}

// MARK: - 城市卡

/// 浏览态的一张城市卡：当地天空做底，右上角地标水印，左边名字和时差，
/// 右边时间大字和“周二 · 凌晨”。展开时下面接 12 小时对照条。
struct WorldCityCard: View {
    var city: WorldCity
    var now: Date
    var expanded: Bool

    private var zone: TimeZone { city.timeZone ?? .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: city.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text(verbatim: WorldClockText.offsetLine(city, now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    bigTime
                    Text(verbatim: WorldClockText.dayLine(zone, now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                // 地标水印在右上角，时间大字右边留出它的位置，不压在线稿上。
                .padding(.trailing, 58)
            }
            .padding(.leading, 14)
            .frame(height: 70)

            if expanded {
                Rectangle().fill(.panelSeparator).frame(height: 0.5)
                    .padding(.horizontal, 14)
                WorldClockStrip(zone: zone, name: city.name, now: now)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WorldCitySky(zone: zone, now: now) }
        .overlay(alignment: .topTrailing) {
            CityLandmarkMark(landmark: city.landmark, color: .panelQuaternary)
                .frame(width: 64, height: 64)
                .padding(.top, 3)
                .padding(.trailing, 2)
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.panelStroke, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    /// 时间大字；12 小时制的上午下午缩小放在后面，大字不被挤小。
    private var bigTime: some View {
        let parts = ClockFormat.compactTime(now, zone: zone)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: parts.time)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            if let meridiem = parts.meridiem {
                Text(verbatim: meridiem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
            }
        }
    }
}

/// 城市卡的底：当地此刻的天空色（和 `SkyBackdrop` 同一套颜色），夜里几颗星，
/// 不画日月弧线（卡片太矮）。
struct WorldCitySky: View {
    var zone: TimeZone
    var now: Date

    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hour = CityLandmarkBadge.hour(now, zone: zone)
        let night = !(6..<18).contains(hour)
        // 液态玻璃：天色只是玻璃上一层淡色（同 SkyBackdrop），保持暗色时还是压暗的实心天色。
        let colors = forcedDark
            ? SkyBackdrop.palette(hour)
            : SkyBackdrop.rawPalette(hour).map { $0.opacity(scheme == .light ? 0.26 : 0.38) }
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.white.opacity(0.05), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                if night {
                    ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                        Circle()
                            .fill(forcedDark ? Color.white.opacity(0.35) : Color.panelTertiary)
                            .frame(width: star.2, height: star.2)
                            .position(x: geo.size.width * star.0, y: min(geo.size.height, 70) * star.1)
                    }
                }
            }
        }
    }

    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.42, 0.18, 1.6), (0.55, 0.62, 1.2), (0.18, 0.86, 1.2), (0.66, 0.3, 1.4), (0.33, 0.5, 1.0),
    ]
}

// MARK: - 12 小时对照条

/// 上行此处、下行当地，同一时刻的钟点；当地 6 点到 18 点那几格打底。
///
/// 白天按钟点而不按日出：应用里不知道任意城市几点日出，标明“阴影为当地
/// 6 至 18 点”是诚实的，暗示日出时间不是。
struct WorldClockStrip: View {
    var zone: TimeZone
    var name: String
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Self.hours(from: now), id: \.self) { hour in
                    VStack(spacing: 4) {
                        Text(Self.hourLabel(hour, zone: .current))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelTertiary)
                        Text(Self.hourLabel(hour, zone: zone))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Self.isDaylight(hour, zone: zone)
                                          ? Color(red: 1, green: 0.85, blue: 0.5).opacity(0.22) : .clear)
                            }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                Text(tr("上行此处 · 下行\(name)"))
                Spacer(minLength: 0)
                Text(tr("阴影为当地 6 至 18 点"))
            }
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    /// 从此处的整点起 12 个小时，列和钟面上的整点对齐。
    static func hours(from now: Date) -> [Date] {
        let start = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<12).compactMap { Calendar.current.date(byAdding: .hour, value: $0, to: start) }
    }

    /// 只写钟点，像天气的逐时条：12 列放不下“下午 2 点”。
    static func hourLabel(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted))
        style.timeZone = zone
        return date.formatted(style)
    }

    static func isDaylight(_ date: Date, zone: TimeZone) -> Bool {
        WorldClockText.isDaytime(zone, now: date)
    }
}
