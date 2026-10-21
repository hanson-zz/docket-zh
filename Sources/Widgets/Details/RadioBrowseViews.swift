import SwiftUI

// 收音机「找台」改版的界面零件：搜索页和世界页共用的电台行、加载更多、小熊猫空状态，
// 以及整个“世界”页（点阵地图 / 国家列表 / 某国的台）。判断和解析在 Core/RadioBrowse.swift。

/// 面板传下来的颜色：字色、强调色、压在深底上的强调字色、实心按钮上的深色字。
struct RadioBrowseStyle {
    var fg: Color
    var accent: Color
    var accentText: Color
    var ink: Color

    /// 地图上的点光：灯阵皮肤的暖黄，选中的国家更亮一档；不用大面积蓝光。
    static let lamp = Color(hex: "#FFC845")
    static let lampHot = Color(hex: "#FFE6A6")
    static let lampInk = Color(hex: "#1A1408")

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(L10n.interfaceLocale))
    }
}

/// 一行电台：点名字添加并收听，右边 + 加入收藏（已收藏是对勾）。`showsPlay` 时左边多一个播放圆钮。
struct RadioListingRow: View {
    var listing: RadioListing
    var saved: Bool
    var style: RadioBrowseStyle
    var showsPlay = false
    var background = true
    var onListen: () -> Void
    var onFavourite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onListen) {
                HStack(spacing: 8) {
                    if showsPlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(style.fg.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(style.fg.opacity(0.1)))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: listing.station.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(style.fg.opacity(0.95))
                            .lineLimit(1)
                        Text(verbatim: listing.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(style.fg.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("添加并收听"))

            Button {
                guard !saved else { return }
                onFavourite()
            } label: {
                Image(systemName: saved ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(saved ? style.accentText : style.fg.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(style.fg.opacity(saved ? 0 : 0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved ? tr("已在收藏中") : tr("加入收藏"))
        }
        .padding(.horizontal, background ? 8 : 0)
        .padding(.vertical, 5)
        .background {
            if background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.fg.opacity(0.05))
            }
        }
    }
}

/// 列表底部“加载更多（已显示 30 / 约 426）”：虚线框；正在取时转圈。
struct RadioLoadMoreButton: View {
    var shown: Int
    var total: Int?
    var loading: Bool
    var style: RadioBrowseStyle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading { ProgressView().controlSize(.mini) }
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.fg.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style.fg.opacity(0.22), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private var title: String {
        let count = RadioBrowseStyle.number(shown)
        if let total, total > shown {
            return tr("加载更多（已显示 \(count) / 约 \(RadioBrowseStyle.number(total))）")
        }
        return tr("加载更多（已显示 \(count)）")
    }
}

/// 小熊猫空状态：休息的小熊猫、一行标题、一行说明，可带一个实心按钮。
struct RadioPandaNote: View {
    var title: String
    var line: String
    var style: RadioBrowseStyle
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let image = PandaArt.image("pet-panda-rest") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(style.fg)
                    .lineLimit(1)
                Text(verbatim: line)
                    .font(.system(size: 13))
                    .foregroundStyle(style.fg.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if let button, let action {
                    Button(action: action) {
                        Text(verbatim: button)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(style.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Capsule().fill(style.accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .glassPane(cornerRadius: 12)
    }
}

/// 两段的小切换（地图 / 列表）：选中那段白底深色字。
struct RadioTwoSegment<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    var style: RadioBrowseStyle

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let value = options[index].0
                let title = options[index].1
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? RadioBrowseStyle.lampInk : style.fg.opacity(0.72))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 24)
                        .background { if on { Capsule().fill(.white.opacity(0.9)) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(style.fg.opacity(0.07)))
        .overlay(Capsule().strokeBorder(style.fg.opacity(0.1), lineWidth: 0.5))
    }
}

// MARK: - World

/// “世界”页：顶上地图 / 列表切换。地图点中一个国家，下面列它最热的几个台；
/// “全部”或列表里点一个国家，进入那国的热门台（可加载更多、可只看中文台）。
/// 请求只在这一页显示时发，离开（包括关掉面板）就取消。
struct RadioWorldPage: View {
    var favourites: [RadioStation]
    var style: RadioBrowseStyle
    var isPreview: Bool
    var onListen: (RadioStation) -> Void
    var onFavourite: (RadioStation) -> Void

    enum Mode: String { case map, list }

    private var store: RadioWorldStore { RadioWorldStore.shared }

    @AppStorage("radio.world.mode") private var storedMode = Mode.map.rawValue
    @State private var selected: String? = "CN"
    @State private var preview: [RadioListing] = []
    @State private var previewFor: String?
    @State private var previewLoading = false
    @State private var previewFailed = false
    @State private var previewTask: Task<Void, Never>?

    @State private var openCountry: String?
    @State private var chineseOnly = false
    @State private var countryListings: [RadioListing] = []
    @State private var countryPage = 0
    @State private var countryMore = false
    @State private var countryLoading = false
    @State private var countryFailed = false
    @State private var countryLoaded = false
    @State private var countryTask: Task<Void, Never>?

    @State private var listQuery = ""
    @State private var order: RadioCountries.Order = .count

    private var mode: Mode {
        // 地图资源读不出来时只有列表。
        store.map == nil ? .list : (Mode(rawValue: storedMode) ?? .map)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let code = openCountry {
                countryScreen(code)
            } else {
                head
                if mode == .map, let map = store.map {
                    mapPane(map)
                    legend
                    countryCard
                } else {
                    countryList
                }
            }
        }
        .onAppear {
            guard !isPreview else { return }
            store.refreshIfStale()
            if mode == .map { loadPreview() }
        }
        .onDisappear {
            previewTask?.cancel()
            countryTask?.cancel()
            previewTask = nil
            countryTask = nil
            previewLoading = false
            countryLoading = false
            store.cancel()
        }
        .onChange(of: store.countries.count) { _, _ in
            if mode == .map, !previewLoading, previewFor != selected { loadPreview() }
        }
    }

    private var counts: [String: Int] { store.counts }

    // MARK: Head

    private var head: some View {
        HStack(spacing: 8) {
            if store.map != nil {
                RadioTwoSegment(options: [(Mode.map, tr("地图")), (Mode.list, tr("列表"))],
                                selection: Binding(get: { mode }, set: { new in
                                    storedMode = new.rawValue
                                    if new == .map { loadPreview() }
                                }), style: style)
            }
            Spacer(minLength: 4)
            if store.loading && store.countries.isEmpty {
                ProgressView().controlSize(.mini)
            } else if !store.countries.isEmpty {
                let totals = RadioCountries.totals(store.countries)
                Text(verbatim: tr("\(totals.regions) 个地区 · 约 \(RadioBrowseStyle.number(totals.stations)) 台"))
                    .font(.system(size: 13))
                    .foregroundStyle(style.fg.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
    }

    // MARK: Map

    private func mapPane(_ map: RadioWorldMap) -> some View {
        let ratio = CGFloat(map.cols) / CGFloat(map.rows)
        let counts = self.counts
        let chosen = selected
        return GeometryReader { geo in
            let width = geo.size.width
            let pitch = width / CGFloat(map.cols)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    if let chosen, let centre = map.centre(of: chosen) {
                        let c = CGPoint(x: centre.col * pitch, y: centre.row * pitch)
                        let r: CGFloat = 30
                        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                     with: .radialGradient(Gradient(colors: [Color(hex: "#FFB347").opacity(0.32),
                                                                             Color(hex: "#FFB347").opacity(0)]),
                                                           center: c, startRadius: 0, endRadius: r))
                    }
                    for dot in map.dots {
                        let x = (CGFloat(dot.col) + 0.5) * pitch
                        let y = (CGFloat(dot.row) + 0.5) * pitch
                        let color: Color
                        let radius: CGFloat
                        if let code = dot.code, code == chosen {
                            color = RadioBrowseStyle.lampHot
                            radius = pitch * 0.42
                        } else {
                            switch RadioCountries.tier(dot.code.flatMap { counts[$0] } ?? 0) {
                            case 3: color = RadioBrowseStyle.lamp.opacity(0.95); radius = pitch * 0.34
                            case 2: color = RadioBrowseStyle.lamp.opacity(0.58); radius = pitch * 0.34
                            case 1: color = RadioBrowseStyle.lamp.opacity(0.3); radius = pitch * 0.34
                            default: color = .white.opacity(0.11); radius = pitch * 0.3
                            }
                        }
                        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                            width: radius * 2, height: radius * 2)), with: .color(color))
                    }
                }
                if let chosen, let centre = map.centre(of: chosen) {
                    let name = RadioCountries.name(chosen)
                    Text(verbatim: name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RadioBrowseStyle.lampInk)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(RadioBrowseStyle.lampHot))
                        .position(x: min(max(centre.col * pitch, 30), width - 30),
                                  y: max(centre.top * pitch - 8, 10))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { point in
                guard !isPreview else { return }
                let cell = map.cell(at: (Double(point.x), Double(point.y)), width: Double(width))
                guard let code = map.nearestCountry(col: cell.col, row: cell.row, counts: counts) else { return }
                if code != selected {
                    selected = code
                    loadPreview()
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
        .accessibilityLabel(tr("世界电台地图"))
        .accessibilityHint(tr("点亮着的国家看它的热门电台；列表里也能找"))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(RadioBrowseStyle.lamp.opacity(0.95), tr("500 台以上"))
            legendItem(RadioBrowseStyle.lamp.opacity(0.58), "50-499")
            legendItem(RadioBrowseStyle.lamp.opacity(0.3), "1-49")
            legendItem(.white.opacity(0.11), tr("暂无"))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(verbatim: title)
                .font(.system(size: 13))
                .foregroundStyle(style.fg.opacity(0.62))
        }
    }

    @ViewBuilder private var countryCard: some View {
        if let code = selected {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    countryTitle(code)
                    Spacer(minLength: 4)
                    Button {
                        open(code)
                    } label: {
                        Text(verbatim: tr("全部 ›"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(style.fg.opacity(0.9))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(style.fg.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if previewLoading && preview.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        .frame(height: 60)
                } else if previewFailed {
                    note(tr("连不上电台目录，请检查网络后再试。"))
                } else if preview.isEmpty && previewFor == code {
                    note(tr("这个国家还没有台"))
                } else {
                    ForEach(preview) { item in
                        RadioListingRow(listing: item, saved: saved(item), style: style, showsPlay: true,
                                        background: false,
                                        onListen: { onListen(item.station) },
                                        onFavourite: { onFavourite(item.station) })
                    }
                }
            }
            .padding(10)
            .glassPane(cornerRadius: 14)
        } else {
            note(tr("点地图上亮着的点，看看那里在播什么。"))
        }
    }

    private func countryTitle(_ code: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: RadioCountries.flag(code))
                .font(.system(size: 18))
            Text(verbatim: titleText(code))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(style.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func titleText(_ code: String) -> String {
        let name = RadioCountries.name(code, fallback: store.countries.first { $0.code == code }?.englishName ?? "")
        guard let count = counts[code] else { return name }
        return tr("\(name) · 约 \(RadioBrowseStyle.number(count)) 台")
    }

    // MARK: List

    private var countryList: some View {
        let list = RadioCountries.ordered(RadioCountries.filter(store.countries, query: listQuery), by: order)
        let top = store.countries.first?.count ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(style.fg.opacity(0.62))
                    TextField("", text: $listQuery, prompt: Text("搜国家或地区"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(style.fg)
                        .disabled(isPreview)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassPane(cornerRadius: 9)
                Menu {
                    ForEach(RadioCountries.Order.allCases, id: \.self) { option in
                        Button {
                            order = option
                        } label: {
                            if option == order {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(order.title)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(style.fg.opacity(0.85))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(style.fg.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if store.countries.isEmpty {
                if store.loading {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 60)
                } else {
                    note(tr("连不上电台目录，请检查网络后再试。"))
                }
            } else if list.isEmpty {
                RadioPandaNote(title: tr("没有找到"), line: tr("换个国名试试，比如“日本”或“Japan”。"), style: style)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { rank, country in
                            countryRow(country, rank: rank + 1, top: top)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .scrollIndicators(.never)
            }
        }
    }

    private func countryRow(_ country: RadioCountry, rank: Int, top: Int) -> some View {
        let on = country.code == selected
        let tier = RadioCountries.tier(country.count)
        return Button {
            guard !isPreview else { return }
            selected = country.code
            open(country.code)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: "\(rank)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(style.fg.opacity(0.45))
                    .frame(width: 26, alignment: .center)
                Text(verbatim: RadioCountries.flag(country.code))
                    .font(.system(size: 16))
                Text(verbatim: RadioCountries.name(country.code, fallback: country.englishName))
                    .font(.system(size: 13, weight: on ? .bold : .medium))
                    .foregroundStyle(style.fg.opacity(on ? 1 : 0.92))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(style.fg.opacity(0.07))
                    .frame(width: 72, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(RadioBrowseStyle.lamp.opacity(tier == 3 ? 0.9 : tier == 2 ? 0.55 : 0.3))
                            .frame(width: max(3, 72 * RadioCountries.barFraction(country.count, max: top)), height: 5)
                    }
                Text(verbatim: tr("约 \(RadioBrowseStyle.number(country.count))"))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(style.fg.opacity(on ? 0.95 : 0.75))
                    .lineLimit(1)
                    .frame(minWidth: 62, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .frame(height: 31)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(RadioBrowseStyle.lamp.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(RadioBrowseStyle.lamp.opacity(0.45), lineWidth: 0.8)
                        }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: One country

    private func countryScreen(_ code: String) -> some View {
        let total = RadioBrowse.knownTotal(RadioSearch(country: code, chineseOnly: chineseOnly), counts: counts)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    countryTask?.cancel()
                    countryTask = nil
                    countryLoading = false
                    openCountry = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(style.fg.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(style.fg.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("返回"))
                countryTitle(code)
                Spacer(minLength: 4)
                Button {
                    chineseOnly.toggle()
                    loadCountry(code, page: 0)
                } label: {
                    Text(verbatim: tr("只看中文台"))
                        .font(.system(size: 13, weight: chineseOnly ? .bold : .semibold))
                        .foregroundStyle(chineseOnly ? style.ink : style.fg.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(chineseOnly ? style.accent : style.fg.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chineseOnly ? .isSelected : [])
            }
            if countryLoading && countryListings.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 80)
            } else if countryFailed && countryListings.isEmpty {
                note(tr("连不上电台目录，请检查网络后再试。"))
            } else if countryLoaded && countryListings.isEmpty {
                let name = RadioCountries.name(code)
                if chineseOnly {
                    RadioPandaNote(title: tr("\(name) · 0 个中文台"), line: tr("这个国家还没有中文台"), style: style,
                                   button: tr("看全部台")) {
                        chineseOnly = false
                        loadCountry(code, page: 0)
                    }
                } else {
                    RadioPandaNote(title: tr("\(name) · 0 台"), line: tr("这个国家还没有台"), style: style)
                }
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(countryListings) { item in
                            RadioListingRow(listing: item, saved: saved(item), style: style,
                                            onListen: { onListen(item.station) },
                                            onFavourite: { onFavourite(item.station) })
                        }
                        if countryMore {
                            RadioLoadMoreButton(shown: countryListings.count, total: total,
                                                loading: countryLoading, style: style) {
                                loadCountry(code, page: countryPage + 1)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .frame(maxHeight: 330)
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: Loading

    private func saved(_ item: RadioListing) -> Bool {
        favourites.contains { $0.matches(item.station) }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .foregroundStyle(style.fg.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func open(_ code: String) {
        guard !isPreview else { return }
        openCountry = code
        chineseOnly = false
        loadCountry(code, page: 0)
    }

    /// 地图下面那张卡片：这个国家收听最多的几个台。
    private func loadPreview() {
        guard !isPreview, let code = selected else { return }
        previewTask?.cancel()
        previewFor = nil
        preview = []
        previewFailed = false
        previewLoading = true
        let search = RadioSearch(country: code)
        previewTask = Task {
            let answer = await RadioBrowseService.page(search, page: 0, shown: [], limit: RadioBrowse.previewCount)
            guard !Task.isCancelled, selected == code else { return }
            previewLoading = false
            previewFailed = answer == nil
            preview = Array((answer?.listings ?? []).prefix(RadioBrowse.previewCount))
            previewFor = code
        }
    }

    /// 某国的热门台；`page` 为 0 是重新开始，否则接在后面。
    private func loadCountry(_ code: String, page: Int) {
        guard !isPreview else { return }
        countryTask?.cancel()
        let search = RadioSearch(country: code, chineseOnly: chineseOnly)
        let shown = page == 0 ? [] : countryListings
        if page == 0 {
            countryListings = []
            countryLoaded = false
            countryMore = false
        }
        countryFailed = false
        countryLoading = true
        countryTask = Task {
            let answer = await RadioBrowseService.page(search, page: page, shown: shown)
            guard !Task.isCancelled, openCountry == code else { return }
            countryLoading = false
            countryLoaded = true
            if let answer {
                countryListings = answer.listings
                countryMore = answer.more
                countryPage = page
            } else {
                countryFailed = true
            }
        }
    }
}
