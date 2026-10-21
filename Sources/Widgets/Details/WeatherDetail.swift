import SwiftUI
import AppKit

/// 天气面板，320pt 宽、液态玻璃（跟随浅色/深色）。两个状态：
///
/// - 浏览：城市名（当前位置标出来）、城市切换圆点和“城市”按钮；当前温度大字、
///   天气和今天最高最低；下面分页（顶部分段，记住切到的那页）：今天是 2 小时
///   降水条和一句“约 40 分钟后有雨，持续半小时”，和风、湿度、日出、日落；指数是
///   生活指数三格（穿衣、紫外线、空气质量，可关）；逐小时是接下来 12 小时（横向
///   滚动，打开时停在现在；按住左右拖，大字和天色跟着那一小时走）；7 天是未来 7 天。
/// - 城市：搜索添加（内置城市表，表里没有的走天气自己的地图查找）、拖把手排序、
///   左滑或右键删除，下面是面板显示开关（降水提示、生活指数、°F）。
///
/// 第 1 个城市就是卡片的 `city`，数据照旧来自 MET（当前、逐小时）和 Open-Meteo
/// （每日）。第 2 个城市起是 Pro，数据全部来自 Open-Meteo，因为共用的 MET 位置只有
/// 一个；没解锁时列表不删，只显示第 1 个。降水条、紫外线和空气质量来自
/// Open-Meteo（`WeatherExtrasService`），接口失败时这几块藏起来，别的不受影响。
///
/// 多城市样式的面板保持原样：每个城市一行，读数和今天的范围。
struct WeatherDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, edit }

    @State private var mode: Mode = .browse
    /// 正在看第几个城市（在能看的城市里数）。
    @State private var page = 0
    /// 拖动逐小时预报时手指所在的位置（小数下标），松手回到 nil，也就是“现在”。
    @State private var scrub: Double?
    /// 浏览态记住的分页（今天、指数、逐小时、7 天），见 `BrowsePage`。
    @AppStorage(DetailPanelSections.pageKey(.weather)) private var storedPage = ""

    // 城市编辑
    @State private var query = ""
    @State private var lookingUp = false
    @State private var lookupFailed = false
    @State private var pendingDelete: String?
    @State private var swipeRow: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var searching: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let accent = Color(hex: "#7CC8F2")
    private static let accentInk = Color(hex: "#05263A")
    private static let rangeFill = Color(hex: "#F2C46B")
    private static let deleteRed = Color(hex: "#FF6B5A")
    private static let deleteInk = Color(hex: "#330B05")
    /// 拖起、左滑时那一行要盖住下面的删除按钮，用实心底：深色下原来的 #34343a，浅色下近白。
    private static let liftedRow = Color.panelDynamic(
        dark: NSColor(srgbRed: 0.204, green: 0.204, blue: 0.227, alpha: 1),
        light: NSColor(srgbRed: 0.972, green: 0.972, blue: 0.98, alpha: 1))
    private static let rowHeight: CGFloat = 52
    private static let rowSpacing: CGFloat = 6
    private static let deleteWidth: CGFloat = 76
    private static let hourCount = 12
    /// 逐小时一列的宽度：面板里看得到 6 列多一点，露出的半列提示后面还能滑。
    private static let hourColumn: CGFloat = 46
    private static let dayCount = 7

    private var unlocked: Bool { licenseUnlocked || supporter || context.isPreview }

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { current.config }

    var body: some View {
        DetailCard {
            // 液态玻璃打底（跟随浅色/深色），天气的天空只淡淡透一点；拖动逐小时时换成
            // 那个小时的天气，并按离日出日落多远变暗或泛暖色。
            let symbol = scrubbedHour?.symbolName ?? shownWeather?.symbolName ?? "cloud.fill"
            ZStack {
                WeatherBackdrop(symbol: symbol)
                    .opacity(0.65)
                    .id(symbol)
                    .transition(.opacity)
                skyTint
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: symbol)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if layout == WeatherStyle.citiesLayout {
                    citiesList
                    attribution
                } else if mode == .edit {
                    editor
                } else {
                    browse
                }
            }
        }
        .task(id: placeKey) { await loadForecast() }
        .task(id: extrasKey) { await loadExtras() }
    }

    // MARK: - 城市和数据

    private var layout: String { WeatherStyle.layout(config) }

    /// 面板的城市列表；第 1 个是卡片的 `city`，空字符串是当前位置。
    private var places: [String] {
        context.isPreview ? Self.samplePlaces : WeatherPlaces.list(config)
    }

    /// 能切换到的城市：没解锁时只有第 1 个。
    private var visiblePlaces: [String] { WeatherPlaces.visible(places, unlocked: unlocked) }

    private var selected: Int { min(max(0, page), max(0, visiblePlaces.count - 1)) }
    private var isPrimary: Bool { selected == 0 }
    private var selectedEntry: String { visiblePlaces.indices.contains(selected) ? visiblePlaces[selected] : "" }

    /// 列表里的一项显示成什么名字：当前位置换成定位到的城市。
    private func displayName(_ entry: String) -> String {
        if !entry.isEmpty { return entry }
        if context.isPreview { return Self.sampleCity }
        return LocationService.shared.city ?? ""
    }

    private var city: String { displayName(selectedEntry) }

    private var fahrenheit: Bool { config.bool("fahrenheit") }
    private var showRain: Bool { config.bool(WeatherPanel.showRainKey, default: true) }
    private var showIndices: Bool { config.bool(WeatherPanel.showIndicesKey, default: true) }

    /// 选中城市的坐标：第 1 个是共用的天气位置，其余是这里自己查到的。
    private var coordinate: WeatherService.Coordinate? {
        if context.isPreview { return nil }
        if isPrimary { return WeatherService.shared.place }
        return WeatherExtrasService.shared.place(city: city)
    }

    private var nowcast: WeatherNowcast? {
        if context.isPreview { return Self.sampleNowcast(context.now) }
        return coordinate.flatMap { WeatherExtrasService.shared.nowcast(at: $0) }
    }

    private var aqi: Int? {
        if context.isPreview { return 62 }
        return coordinate.flatMap { WeatherExtrasService.shared.aqi(at: $0) }
    }

    private var shownWeather: WeatherNow? {
        if context.isPreview { return Self.sample }
        if isPrimary { return WeatherService.shared.current }
        return nowcast.flatMap { WeatherExtrasService.now(from: $0) }
    }

    private var hours: [WeatherHour] {
        if context.isPreview { return Self.sampleHours(from: context.now) }
        if isPrimary { return Array(WeatherService.shared.hourly.prefix(Self.hourCount)) }
        return nowcast.map { WeatherExtrasService.hours(from: $0, now: context.now, limit: Self.hourCount) } ?? []
    }

    private var forecast: DailyForecast? {
        if context.isPreview { return WeatherTile.sampleForecast(now: context.now) }
        return coordinate.flatMap { ForecastService.shared.forecast(at: $0) }
    }

    private var days: [DailyForecast.Day] {
        forecast?.upcoming(now: context.now, limit: Self.dayCount) ?? []
    }

    /// 日出日落、逐小时的钟点按这个地方自己的时钟。
    private var sunPlace: WeatherSun.Place? {
        if context.isPreview || isPrimary { return WeatherSun.place(preview: context.isPreview) }
        guard let found = coordinate else { return nil }
        return WeatherSun.Place(lat: found.lat, lon: found.lon,
                                zone: found.zone.flatMap(TimeZone.init(identifier:)) ?? .current)
    }

    private var zone: TimeZone { sunPlace?.zone ?? .current }

    // MARK: Loading

    /// Changes when the shared place moves, so the daily list follows it.
    private var placeKey: String {
        if layout == WeatherStyle.citiesLayout { return cities.joined(separator: ",") }
        guard let place = WeatherService.shared.place else { return "" }
        return DailyForecast.cacheKey(lat: place.lat, lon: place.lon)
    }

    private var extrasKey: String {
        guard layout != WeatherStyle.citiesLayout else { return "" }
        return "\(selected)|\(city)|\(placeKey)"
    }

    private func loadForecast() async {
        guard !context.isPreview else { return }
        if layout == WeatherStyle.citiesLayout {
            await ForecastService.shared.load(cities: cities)
        } else if let place = WeatherService.shared.place {
            await ForecastService.shared.refresh(place)
        }
    }

    /// 第 1 个城市补降水和空气质量；第 2 个起连当前天气、逐小时和每日一起取。
    private func loadExtras() async {
        guard !context.isPreview, layout != WeatherStyle.citiesLayout else { return }
        if isPrimary {
            if let place = WeatherService.shared.place {
                await WeatherExtrasService.shared.refresh(place)
            }
        } else if !city.isEmpty {
            await WeatherExtrasService.shared.load(city: city)
        }
    }

    // MARK: - 浏览

    private var browse: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if city.isEmpty {
                    noPlace
                } else if let weather = shownWeather {
                    hero(weather)
                } else {
                    unavailable
                }
            }
            .contentShape(.rect)
            .gesture(citySwipe)

            if !city.isEmpty, shownWeather != nil {
                if isPrimary, offlineNow {
                    ReconnectStateView(title: tr("离线"), detail: tr("这次没连上天气服务，显示的是上次的数据"),
                                       loading: WeatherService.shared.fetching, style: .compact,
                                       retry: retryWeather)
                }
            }
            // 面板统一限高后，大字下面分页：今天（降水、风和湿度、日出日落）、
            // 生活指数、逐小时、7 天。切到的那页记住。拖逐小时时上面的大字照旧跟着走。
            let pages = browsePages
            if let page = shownPage(pages) {
                if pages.count > 1 {
                    DetailSegmented(pages: pages, title: { $0.title }, selected: page) { picked in
                        storedPage = picked.rawValue
                    }
                }
                switch page {
                case .today:
                    if let weather = shownWeather {
                        if showRain { rainCard }
                        stats(weather)
                    }
                case .indices:
                    if let weather = shownWeather { indices(weather) }
                case .hours: hourly
                case .days: dayList
                }
            }
            attribution
        }
    }

    /// 浏览态大字下面的分页。
    private enum BrowsePage: String, CaseIterable {
        case today, indices, hours, days

        var title: String {
            switch self {
            case .today: tr("今天")
            case .indices: tr("指数")
            case .hours: tr("逐小时")
            case .days: tr("7 天")
            }
        }
    }

    /// 有数据的那几页：没定位到城市或没读到天气时只剩 7 天（也可能一页都没有）。
    private var browsePages: [BrowsePage] {
        var pages: [BrowsePage] = []
        if !city.isEmpty, shownWeather != nil {
            pages.append(.today)
            if showIndices { pages.append(.indices) }
            if !hours.isEmpty { pages.append(.hours) }
        }
        if !days.isEmpty { pages.append(.days) }
        return pages
    }

    private func shownPage(_ pages: [BrowsePage]) -> BrowsePage? {
        DetailPanelSections.page(stored: storedPage, available: pages)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: city.isEmpty ? tr("天气") : city)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if selectedEntry.isEmpty, !city.isEmpty {
                        Text(tr("当前位置"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                    }
                }
                if visiblePlaces.count > 1 { dots }
            }
            Spacer(minLength: 0)
            if !context.isPreview {
                Button { switchTo(.edit) } label: {
                    Text(tr("城市"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .glassPane(cornerRadius: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("搜索添加城市、调整顺序、面板显示什么"))
            }
        }
    }

    /// 城市切换圆点，点一下切过去。
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(visiblePlaces.indices, id: \.self) { index in
                Button { show(index) } label: {
                    Circle()
                        .fill(index == selected ? Color.panelPrimary : Color.panelQuaternary)
                        .frame(width: 6.4, height: 6.4)
                        .padding(2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayName(visiblePlaces[index]))
            }
        }
    }

    /// 在城市名和大字上左右滑换城市；逐小时那一排的拖动不受影响。
    private var citySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { drag in
                let dx = drag.translation.width
                guard abs(dx) > 40, abs(dx) > abs(drag.translation.height) * 1.5 else { return }
                show(selected + (dx < 0 ? 1 : -1))
            }
    }

    private func show(_ index: Int) {
        guard visiblePlaces.indices.contains(index), index != selected else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            page = index
            scrub = nil
        }
    }

    // MARK: Now

    private func hero(_ weather: WeatherNow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 拖动时大数字跟着手指走，在相邻两小时之间平滑过渡。
            temperature(scrubbedTemperature ?? weather.temperatureC)
            VStack(alignment: .leading, spacing: 4) {
                if let hour = scrubbedHour {
                    Text(tr("\(hourLabel(hour.date)) 的预报"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                } else {
                    Text(weather.condition)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                }
                if let today = forecast?.today(now: context.now) {
                    Text(tr("最高 \(degrees(today.highC)) 最低 \(degrees(today.lowC))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: scrubbedHour?.symbolName ?? weather.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 36))
                .frame(width: 48)
        }
    }

    /// Big figure with a lighter degree mark, as on the tile.
    private func temperature(_ celsius: Double) -> some View {
        let reading = Int(converted(celsius).rounded())
        return HStack(alignment: .top, spacing: 0) {
            Text("\(reading)")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .rollingValue(reading)
            Text("°")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.panelPrimary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: 2 小时降水

    /// 分钟级降水没取到（Open-Meteo 失败或还没回来）时整块不画。
    @ViewBuilder private var rainCard: some View {
        let slots = nowcast?.slots ?? []
        if let status = RainOutlook.status(slots, now: context.now) {
            let bars = RainOutlook.bars(slots, now: context.now)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: status == .dry ? "cloud.fill" : "cloud.rain.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.panelPrimary, Self.accent)
                        .font(.system(size: 15))
                    Text(RainOutlook.headline(status))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 4)
                    Text(RainOutlook.detail(status))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(.panelSeparator).frame(height: 0.8)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { _, slot in
                            let level = RainOutlook.level(slot.mm)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(level > 0 ? Self.accent.panelReadable : .panelTrack)
                                .frame(height: max(2, level * 36))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // 现在的位置。
                    Rectangle().fill(.panelPrimary).frame(width: 1.4, height: 42)
                }
                .frame(height: 42)
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                    ForEach(Array(RainOutlook.axisLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
            }
            .padding(12)
            .glassPane()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(RainOutlook.sentence(status))
        }
    }

    // MARK: 生活指数

    /// 穿衣按温度总能写；紫外线和空气质量没取到的那一格不画。
    private func indices(_ weather: WeatherNow) -> some View {
        let uv = nowcast?.uvIndex(now: context.now)
        return HStack(alignment: .top, spacing: 6) {
            indexCell(tr("穿衣"), value: WeatherIndex.clothing(celsius: weather.temperatureC), detail: "")
            if let uv {
                indexCell(tr("紫外线"), value: WeatherIndex.uvLevel(uv), detail: WeatherIndex.uvDetail(uv))
            }
            if let aqi {
                // 数值是美国 AQI 刻度，标签直接写明，免得和国内的指数混着看。
                indexCell(tr("AQI（美标）"), value: WeatherIndex.aqiLevel(aqi), detail: "\(aqi)",
                          warm: WeatherIndex.aqiIsPolluted(aqi))
                    .accessibilityLabel(tr("空气质量") + " " + WeatherIndex.aqiLevel(aqi) + " · "
                                        + tr("AQI（美标）") + " \(aqi)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func indexCell(_ label: String, value: String, detail: String, warm: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标签和小字固定 13pt 不缩；只有档位大字放不下时才缩一点。
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(warm ? Color(hex: "#FFB35C").panelReadable : .panelPrimary)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPane()
        .accessibilityElement(children: .combine)
    }

    // MARK: Wind, humidity, sun

    private func stats(_ weather: WeatherNow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let speed = weather.windSpeed {
                stat(tr("风"), WeatherIndex.windShort(speed: speed, from: weather.windFrom ?? 0))
                    .help(Wind.summary(speed: speed, from: weather.windFrom ?? 0))
            }
            if let humidity = weather.humidity {
                stat(tr("湿度"), "\(Int(humidity.rounded()))%")
            }
            switch sunToday {
            case .normal(let rise, let set)?:
                let note = WeatherSun.localNote(zone, at: rise)
                stat(tr("日出"), WeatherSun.time(rise, zone: zone))
                    .help(note.isEmpty ? "" : tr("日出") + note)
                stat(tr("日落"), WeatherSun.time(set, zone: zone))
                    .help(note.isEmpty ? "" : tr("日落") + note)
            case .polarDay?:
                stat(tr("日照"), tr("极昼"))
            case .polarNight?:
                stat(tr("日照"), tr("极夜"))
            case nil:
                EmptyView()
            }
        }
    }

    private var sunToday: SunTimes.Day? {
        guard let place = sunPlace else { return nil }
        return SunTimes.on(context.now, latitude: place.lat, longitude: place.lon, zone: place.zone)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .rollingValue(value)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Hours

    /// 接下来 12 小时：钟点、天气图标、温度折线、降水，一列一小时，横向滚动。
    ///
    /// 打开时停在现在这一小时；双指横扫（或 Shift 加滚轮）看后面的小时。
    /// 按住在这一排上左右拖，就像拨时间轴：手指下的那一小时亮起来，
    /// 上面的大数字、天气和天空都换成那个时刻，拖到边上会跟着滚，松手回到现在。
    private var hourly: some View {
        let shown = hours
        let column = Self.hourColumn
        let width = column * CGFloat(shown.count)
        let now = context.now
        let nowIndex = HourScrub.nowIndex(starts: shown.map(\.date.timeIntervalSinceReferenceDate),
                                          now: now.timeIntervalSinceReferenceDate)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(shown.indices, id: \.self) { index in
                            let hour = shown[index]
                            let current = index == nowIndex && hour.date <= now
                            Text(current ? tr("现在") : hourShort(hour.date))
                                .font(.system(size: 13, weight: current ? .semibold : .medium))
                                .foregroundStyle(current ? .panelPrimary : .panelSecondary)
                                .frame(width: column)
                                .id(index)
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(shown.indices, id: \.self) { index in
                            Image(systemName: shown[index].symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 16))
                                .frame(width: column, height: 22)
                        }
                    }
                    temperatureLine(shown)
                        .frame(width: width, height: 56)
                    HStack(spacing: 0) {
                        ForEach(shown.indices, id: \.self) { index in
                            let rain = rainText(shown[index])
                            Text(rain.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(rain.wet ? Self.accent.panelReadable : .panelSecondary)
                                .frame(width: column)
                        }
                    }
                }
                .lineLimit(1)
                .padding(.vertical, 4)
                .frame(width: width)
                .background(alignment: .leading) { scrubMarker(column: column) }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard shown.count > 1 else { return }
                            scrub = HourScrub.position(x: drag.location.x, width: width, count: shown.count)
                        }
                        .onEnded { _ in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
                                scrub = nil
                            }
                        }
                )
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo(nowIndex, anchor: .leading) }
            .onChange(of: selected) { proxy.scrollTo(nowIndex, anchor: .leading) }
            .onChange(of: scrubIndex) { _, index in
                // 拖到看得见的边上时，把手指下那一小时滚进来。
                guard let index else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(index) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("左右拖动查看每小时的天气，双指横扫看后面的小时"))
    }

    private var scrubIndex: Int? {
        guard let scrub, !hours.isEmpty else { return nil }
        return HourScrub.index(position: scrub, count: hours.count)
    }

    /// 温度折线：点上面写温度。
    private func temperatureLine(_ shown: [WeatherHour]) -> some View {
        GeometryReader { geo in
            let column = geo.size.width / CGFloat(max(1, shown.count))
            let temperatures = shown.map(\.temperatureC)
            let low = temperatures.min() ?? 0
            let high = temperatures.max() ?? 0
            let span = max(1, high - low)
            let points: [CGPoint] = shown.enumerated().map { index, hour in
                let y = 50 - (hour.temperatureC - low) / span * 24
                return CGPoint(x: column * (CGFloat(index) + 0.5), y: y)
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(.panelTertiary, lineWidth: 1.6)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle().fill(.panelPrimary).frame(width: 6, height: 6).position(point)
                    Text(degrees(shown[index].temperatureC))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: point.x, y: point.y - 14)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 那一小时的降水：有降水概率时写百分比（10% 以下写“无雨”），没有时按雨量写“有雨”或“无雨”。
    private func rainText(_ hour: WeatherHour) -> (text: String, wet: Bool) {
        if let chance = nowcast?.precipitationChance(hourStarting: hour.date) {
            let percent = Int(chance.rounded())
            return percent >= 10 ? ("\(percent)%", true) : (tr("无雨"), false)
        }
        return hour.precipitationMM >= WeatherStyle.rainThresholdMM ? (tr("有雨"), true) : (tr("无雨"), false)
    }

    /// 跟着手指滑动的亮块，落在两小时之间时也跟着停在中间。
    @ViewBuilder private func scrubMarker(column: CGFloat) -> some View {
        if let scrub, hours.count > 1 {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.panelSelected)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.5)
                }
                .frame(width: column)
                .offset(x: column * CGFloat(scrub))
                .transition(.opacity)
        }
    }

    // MARK: Scrub

    /// 手指下最近的那一小时。
    private var scrubbedHour: WeatherHour? {
        guard let scrub, !hours.isEmpty, layout != WeatherStyle.citiesLayout, mode == .browse else { return nil }
        return hours[HourScrub.index(position: scrub, count: hours.count)]
    }

    /// 在相邻两小时之间插值的温度。
    private var scrubbedTemperature: Double? {
        guard let scrub, layout != WeatherStyle.citiesLayout, mode == .browse else { return nil }
        return HourScrub.interpolate(hours.map(\.temperatureC), at: scrub)
    }

    /// 手指所在的时刻（同样在两小时之间插值），天色按它来算。
    private var scrubbedDate: Date? {
        guard let scrub, layout != WeatherStyle.citiesLayout, mode == .browse else { return nil }
        let stamps = hours.map(\.date.timeIntervalSinceReferenceDate)
        return HourScrub.interpolate(stamps, at: scrub).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    /// 叠在天空上的夜色和朝霞晚霞。不拖的时候完全透明。
    @ViewBuilder private var skyTint: some View {
        let shade = scrubbedDate.flatMap(skyShade) ?? (night: 0, glow: 0)
        ZStack {
            // 浅色玻璃上深字，夜色只压一点，免得字看不清。
            Color(red: 0.03, green: 0.04, blue: 0.14)
                .opacity(shade.night * (scheme == .light ? 0.12 : 0.45))
            LinearGradient(colors: [.clear, Color(red: 1, green: 0.55, blue: 0.25)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(shade.glow * 0.25)
        }
        .allowsHitTesting(false)
    }

    /// 那个时刻在当地离日出日落多远。极昼全亮，极夜全暗，算不出来时不加色。
    private func skyShade(_ date: Date) -> (night: Double, glow: Double)? {
        guard let place = sunPlace,
              let day = SunTimes.on(date, latitude: place.lat, longitude: place.lon, zone: place.zone)
        else { return nil }
        switch day {
        case .normal(let rise, let set):
            return (HourScrub.night(at: date, rise: rise, set: set), HourScrub.glow(at: date, rise: rise, set: set))
        case .polarDay:
            return (0, 0)
        case .polarNight:
            return (1, 0)
        }
    }

    /// “14:00”，按那个地方自己的时钟。
    private func hourLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = zone
        return date.formatted(style)
    }

    /// 逐小时那一排的“11 时”。
    private func hourShort(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return tr("\(calendar.component(.hour, from: date)) 时")
    }

    // MARK: Days

    /// 一天一行：星期、天气、降水概率、最低、范围条（按这几天的刻度）、最高。
    private var dayList: some View {
        let today = forecast?.todayKey(now: context.now) ?? ""
        let scale = DailyForecast.scale(days)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(days, id: \.key) { day in
                HStack(spacing: 8) {
                    Text(DailyForecast.weekdayLabel(day.key, today: today))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: WMOWeather.symbol(day.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                        .frame(width: 22)
                    Text(rainChance(day))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.accent.panelReadable)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .leading)
                    Text(degrees(day.lowC))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                    rangeBar(day, scale: scale)
                    Text(degrees(day.highC))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 32)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(DailyForecast.weekdayLabel(day.key, today: today))，"
                                    + "\(WMOWeather.condition(day.code))，"
                                    + tr("最低 \(degrees(day.lowC))，最高 \(degrees(day.highC))"))
            }
        }
    }

    /// Only worth a figure from 20% up; below that the column stays empty.
    private func rainChance(_ day: DailyForecast.Day) -> String {
        guard let chance = day.precipitationChance, chance >= 20 else { return "" }
        return "\(Int(chance.rounded()))%"
    }

    private func rangeBar(_ day: DailyForecast.Day, scale: (low: Double, high: Double)?) -> some View {
        let fractions: (start: Double, end: Double) = scale.map {
            DailyForecast.rangeFractions(low: day.lowC, high: day.highC, scaleLow: $0.low, scaleHigh: $0.high)
        } ?? (0, 1)
        return GeometryReader { proxy in
            let width = proxy.size.width
            let length = max(5, width * (fractions.end - fractions.start))
            Capsule()
                .fill(.panelTrack)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Self.rangeFill)
                        .frame(width: length)
                        .offset(x: min(width * fractions.start, width - length))
                }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: Attribution

    /// CC BY 4.0 asks for this wherever the data is shown, and the tile is too
    /// small to carry it. 第 2 个城市起只用了 Open-Meteo。
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 2) {
            if layout != WeatherStyle.citiesLayout, isPrimary {
                Text(WeatherService.attribution)
            }
            Text(WeatherService.forecastAttribution)
        }
        .font(.system(size: 13))
        .foregroundStyle(.panelTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 城市编辑

    private func switchTo(_ next: Mode) {
        // 要打字：先让面板成为 key，搜索框才接得住光标。
        if next == .edit { WidgetDetailWindow.shared.focusField {} }
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            query = ""
            lookupFailed = false
            pendingDelete = nil
            swipeRow = nil
            swipeOffset = 0
            dragging = nil
            dragOffset = 0
            scrub = nil
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("城市"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Text(tr("拖动排序 · 左滑删除"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                Spacer(minLength: 0)
                Button { switchTo(.browse) } label: {
                    Text(tr("完成"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Self.accentInk)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(Capsule().fill(Self.accent))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            searchField
            if !trimmedQuery.isEmpty { results }

            sectionTitle(tr("我的城市 \(places.count)"))
            cityRows
            Text(tr("第 2 个城市起需要 Pro；面板上左右滑切换"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionTitle(tr("面板显示"))
            displayToggles
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .padding(.top, 2)
    }

    // MARK: 搜索

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelSecondary)
            TextField(tr("搜索城市"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.panelPrimary)
                .focused($searching)
                .onSubmit { lookUp(trimmedQuery) }
                .onChange(of: query) { lookupFailed = false }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.panelTertiary)
                }
                .buttonStyle(.plain)
                .help(tr("清除"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.panelFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(searching ? Self.accent.opacity(0.85) : .panelStroke, lineWidth: 1)
        }
        .onAppear { DispatchQueue.main.async { searching = true } }
    }

    /// 内置城市表里对得上的（最多 4 个），加一行“在地图上查找”给表里没有的地方。
    private var matches: [WorldCity] {
        Array(WorldCities.search(trimmedQuery, systemZones: []).filter(\.isBuiltIn).prefix(4))
    }

    private var results: some View {
        let found = matches
        let exact = found.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
        return VStack(spacing: 0) {
            ForEach(Array(found.enumerated()), id: \.element.id) { index, item in
                resultRow(name: item.name, detail: item.region, primary: index == 0) { add(item.name) }
            }
            if !exact {
                resultRow(name: trimmedQuery,
                          detail: lookingUp ? tr("正在查找…") : (lookupFailed ? tr("没找到这个地方") : tr("在地图上查找")),
                          primary: found.isEmpty) { lookUp(trimmedQuery) }
            }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.6)
                }
        }
    }

    private func resultRow(name: String, detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        let added = WeatherPlaces.contains(name, in: places)
        let full = places.count >= WeatherPlaces.maxCount
        return HStack(spacing: 8) {
            Text(verbatim: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Text(verbatim: detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 4)
            Button(action: action) {
                Text(added ? tr("已添加") : tr("添加"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primary && !added ? Self.accentInk : .panelPrimary.opacity(added ? 0.5 : 0.92))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background {
                        if primary, !added {
                            Capsule().fill(Self.accent)
                        } else {
                            Capsule().fill(.panelFill)
                                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(added || full || lookingUp)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    /// 表里没有的地方：用天气自己的地图查找确认能找到再加，找不到就说一声。
    private func lookUp(_ name: String) {
        guard !name.isEmpty, !lookingUp, !context.isPreview else { return }
        if let known = matches.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            add(known.name)
            return
        }
        guard gateAdding() else { return }
        lookingUp = true
        lookupFailed = false
        Task {
            let found = await WeatherService.shared.coordinate(for: name)
            lookingUp = false
            if found == nil {
                lookupFailed = true
            } else {
                add(name)
            }
        }
    }

    /// 第 2 个城市起是 Pro：没解锁时弹付费墙，不加。
    private func gateAdding() -> Bool {
        guard ProLicenseGate.canAddWeatherCity(count: places.count, unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return false
        }
        return true
    }

    private func add(_ name: String) {
        guard !context.isPreview, WeatherPlaces.canAdd(name, to: places), gateAdding() else { return }
        save(WeatherPlaces.adding(name, to: places))
        query = ""
    }

    // MARK: 我的城市

    private var cityRows: some View {
        let list = places
        let from = dragging.flatMap { name in list.firstIndex(of: name) }
        let target = from.map {
            WeatherPlaces.dropIndex(from: $0, translation: dragOffset,
                                    rowHeight: Self.rowHeight + Self.rowSpacing, count: list.count)
        }
        return VStack(spacing: Self.rowSpacing) {
            ForEach(Array(list.enumerated()), id: \.element) { index, entry in
                cityRow(entry, index: index, list: list)
                    .offset(y: rowShift(index, from: from, target: target))
                    .zIndex(entry == dragging ? 1 : 0)
            }
        }
    }

    /// 拖动时：被拖的那行跟着手走，经过的行让开一格。
    private func rowShift(_ index: Int, from: Int?, target: Int?) -> CGFloat {
        guard let from, let target else { return 0 }
        let step = Self.rowHeight + Self.rowSpacing
        if index == from { return dragOffset }
        if from < target, (from + 1...target).contains(index) { return -step }
        if target < from, (target..<from).contains(index) { return step }
        return 0
    }

    private func cityRow(_ entry: String, index: Int, list: [String]) -> some View {
        let revealing = pendingDelete == entry
        let canDelete = list.count > 1
        let locked = ProLicenseGate.isWeatherCityLocked(at: index, unlocked: unlocked)
        let lifted = dragging == entry
        let offset: CGFloat = revealing ? -Self.deleteWidth : (swipeRow == entry ? min(0, swipeOffset) : 0)
        return ZStack(alignment: .trailing) {
            if canDelete {
                Button { delete(at: index, from: list) } label: {
                    Text(tr("删除"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Self.deleteInk)
                        .frame(width: Self.deleteWidth + 12, height: Self.rowHeight)
                        .padding(.leading, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.deleteRed))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(offset < 0 ? 1 : 0)
            }
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelPrimary.opacity(lifted ? 0.9 : 0.55))
                    .frame(width: 24, height: Self.rowHeight)
                    .contentShape(.rect)
                    .gesture(reorder(entry, index: index, list: list))
                    .help(tr("拖动调整顺序"))
                    .accessibilityLabel(tr("调整\(displayName(entry))的顺序"))
                    .accessibilityAction(named: tr("上移")) {
                        save(WeatherPlaces.moving(from: index, to: index - 1, in: list))
                    }
                    .accessibilityAction(named: tr("下移")) {
                        save(WeatherPlaces.moving(from: index, to: index + 1, in: list))
                    }
                Text(verbatim: displayName(entry).isEmpty ? tr("正在定位…") : displayName(entry))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                if entry.isEmpty {
                    Text(tr("当前位置"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(.panelFill))
                }
                if locked { ProBadge() }
                Spacer(minLength: 4)
                Text(rowReading(entry, index: index))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary.opacity(locked ? 0.5 : 1))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: Self.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(lifted || offset < 0 ? Self.liftedRow : .panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(lifted ? Self.accent.opacity(0.6) : .panelStroke, lineWidth: 0.6)
                    }
                    .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 6, y: 4)
            }
            .offset(x: offset)
            .contentShape(.rect)
            .gesture(swipe(entry, canDelete: canDelete))
            .onTapGesture {
                if pendingDelete != nil {
                    withAnimation(.snappy(duration: 0.22)) { pendingDelete = nil }
                } else if locked {
                    PaywallWindow.shared.show()
                }
            }
            .contextMenu {
                if canDelete {
                    Button(tr("删除"), role: .destructive) { delete(at: index, from: list) }
                }
            }
        }
        .frame(height: Self.rowHeight)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    /// 列表右边的“小雨 18°”：第 1 个读 MET，其余读 Open-Meteo，取过才有。
    private func rowReading(_ entry: String, index: Int) -> String {
        let reading: WeatherNow?
        if context.isPreview {
            reading = index == 0 ? Self.sample : nil
        } else if index == 0 {
            reading = WeatherService.shared.current
        } else {
            let name = displayName(entry)
            reading = WeatherExtrasService.shared.place(city: name)
                .flatMap { WeatherExtrasService.shared.nowcast(at: $0) }
                .flatMap { WeatherExtrasService.now(from: $0) }
        }
        guard let reading else { return "" }
        return "\(reading.condition)  \(degrees(reading.temperatureC))"
    }

    /// 左滑露出“删除”，再点才删；滑得不够就弹回去。
    private func swipe(_ entry: String, canDelete: Bool) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                guard canDelete, dragging == nil, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                swipeRow = entry
                swipeOffset = drag.translation.width + (pendingDelete == entry ? -Self.deleteWidth : 0)
            }
            .onEnded { _ in
                guard canDelete, swipeRow == entry else { return }
                let reveal = swipeOffset < -Self.deleteWidth / 2
                withAnimation(.snappy(duration: 0.22)) {
                    pendingDelete = reveal ? entry : nil
                    swipeRow = nil
                    swipeOffset = 0
                }
            }
    }

    /// 左边把手：按住拖动排序，松手时落到最近的一格。
    private func reorder(_ entry: String, index: Int, list: [String]) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragging != entry {
                    dragging = entry
                    pendingDelete = nil
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let to = WeatherPlaces.dropIndex(from: index, translation: value.translation.height,
                                                 rowHeight: Self.rowHeight + Self.rowSpacing, count: list.count)
                save(WeatherPlaces.moving(from: index, to: to, in: list))
                withAnimation(.snappy(duration: 0.2)) {
                    dragging = nil
                    dragOffset = 0
                }
            }
    }

    private func delete(at index: Int, from list: [String]) {
        withAnimation(.snappy(duration: 0.22)) {
            save(WeatherPlaces.removing(at: index, from: list))
            pendingDelete = nil
        }
    }

    // MARK: 面板显示

    private var displayToggles: some View {
        let rows: [(String, String, Bool)] = [
            (tr("2 小时降水提示"), WeatherPanel.showRainKey, true),
            (tr("生活指数"), WeatherPanel.showIndicesKey, true),
            (tr("温度用 °F"), "fahrenheit", false),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Toggle(isOn: Binding(
                    get: { config.bool(row.1, default: row.2) },
                    set: { value in
                        guard !context.isPreview else { return }
                        WidgetWriter.write(current) { $0.set(row.1, .bool(value)) }
                    }
                )) {
                    Text(row.0)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                }
                .toggleStyle(.switch)
                .tint(Self.accent)
                .padding(.horizontal, 14)
                .frame(height: 46)
                if index < rows.count - 1 {
                    Rectangle().fill(.panelSeparator).frame(height: 0.5).padding(.horizontal, 14)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.5)
                }
        }
    }

    // MARK: 写回

    private func save(_ list: [String]) {
        guard !context.isPreview else { return }
        let before = places.first
        WidgetWriter.write(current) { WeatherPlaces.write(list, to: &$0) }
        page = 0
        // 第 1 个城市换了：共用的天气位置跟过去，卡片也会在下次刷新时跟上。
        if let first = list.first, first != before {
            if first.isEmpty { LocationService.shared.start() }
            let name = displayName(first)
            if !name.isEmpty { Task { await WeatherService.shared.setLocation(city: name) } }
        }
    }

    // MARK: - 多城市样式

    private var cities: [String] {
        WeatherLayout.cities(config.strings("cities", default: WeatherLayout.defaultCities))
    }

    /// The multi-city card's panel: each place with its reading now and
    /// today's range. The shared city is not this card's, so it is not shown.
    private var citiesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                let place: DailyForecast? = context.isPreview
                    ? WeatherTile.sampleCityForecast(index, now: context.now)
                    : ForecastService.shared.forecast(city: city)
                let today = place?.today(now: context.now)
                HStack(spacing: 10) {
                    Image(systemName: place?.current.map { WMOWeather.symbol($0.code, isDay: $0.isDay) }
                          ?? "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 18))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                        Text(place?.current.map { WMOWeather.condition($0.code) } ?? tr("暂无数据"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(place?.current.map { degrees($0.temperatureC) } ?? "--°")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.panelPrimary)
                            .monospacedDigit()
                        Text(today.map { tr("最高 \(degrees($0.highC)) 最低 \(degrees($0.lowC))") } ?? " ")
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(10)
                .glassPane()
            }
        }
    }

    // MARK: - Empty states

    /// Nothing typed and nothing from CoreLocation - which, as the README
    /// records, is the usual outcome for an app that never becomes frontmost.
    private var noPlace: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(locating ? tr("正在定位…") : tr("未设置城市"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Text(locating
                 ? tr("正在等待获取你的位置。点右上角“城市”添加一个城市即可跳过定位。")
                 : tr("点右上角“城市”搜索添加一个城市。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locating: Bool {
        guard !context.isPreview else { return false }
        let service = LocationService.shared
        return !service.denied && !service.unavailable
    }

    /// A missing reading is either a first fetch still in flight or one that
    /// failed with nothing cached behind it. 没连上时换成共用的插头状态，
    /// 可以点“重新连接”；还在读的时候显示“暂无数据”。
    @ViewBuilder private var unavailable: some View {
        if isPrimary, offlineNow {
            ReconnectStateView(title: tr("连不上天气服务"),
                               detail: tr("\(city) 暂无数据，可能是网络断开了。"),
                               loading: WeatherService.shared.fetching,
                               retry: retryWeather)
        } else {
            Text(tr("暂无数据。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
    }

    /// 天气服务最近一次没连上。示例卡片永远在线。
    private var offlineNow: Bool {
        !context.isPreview && WeatherService.shared.offline
    }

    private func retryWeather() {
        guard !context.isPreview else { return }
        Task { await WeatherService.shared.retry() }
    }

    // MARK: Units

    private func degrees(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))°"
    }

    private func converted(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    // MARK: - Sample
    //
    // The library has no live data. The tile's own sample is private to it,
    // and these numbers only have to agree with it by eye.

    private static let sampleCity = tr("奥斯陆")
    private static let samplePlaces = ["", tr("北京"), tr("深圳")]

    private static let sample = WeatherNow(temperatureC: 18,
                                           symbolName: "cloud.sun.fill",
                                           condition: tr("多云"),
                                           windSpeed: 4.2, windFrom: 45, humidity: 62)

    private static func sampleHours(from date: Date) -> [WeatherHour] {
        let temperatures: [Double] = [18, 19, 19, 17, 16, 16, 15, 14, 14, 13, 13, 12]
        let symbols = ["cloud.sun.fill", "sun.max.fill", "cloud.sun.fill", "cloud.rain.fill",
                       "cloud.fill", "cloud.fill", "cloud.moon.fill", "moon.stars.fill",
                       "moon.stars.fill", "moon.fill", "cloud.moon.fill", "moon.fill"]
        let rain: [Double] = [0, 0, 0, 0.6, 0.2, 0, 0, 0, 0, 0, 0, 0]
        return temperatures.indices.map { index in
            WeatherHour(date: date.addingTimeInterval(Double(index + 1) * 3600),
                        temperatureC: temperatures[index],
                        symbolName: symbols[index],
                        precipitationMM: rain[index])
        }
    }

    /// 示例：约 40 分钟后有雨，持续半小时；紫外线指数 2。
    private static func sampleNowcast(_ now: Date) -> WeatherNowcast {
        let mm: [Double] = [0, 0, 0, 0.4, 0.7, 0, 0, 0, 0]
        let slots = mm.enumerated().map { index, value in
            RainOutlook.Slot(start: now.addingTimeInterval(-5 * 60 + Double(index) * 900), mm: value)
        }
        return WeatherNowcast(hours: [WeatherNowcast.Hour(time: now.addingTimeInterval(-600), uvIndex: 2)],
                              slots: slots)
    }
}
