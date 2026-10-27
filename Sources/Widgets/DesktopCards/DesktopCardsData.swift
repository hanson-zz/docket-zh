import AppKit
import SwiftUI
@preconcurrency import Translation

// MARK: - 桌面卡片 · 数据组
//
// 天气、加密货币、自选股、股票、GitHub、Codex 用量、邮件、「算」、翻译、取色器、表情符号
// 钉在桌面时的专属布局：小 160×160 一个核心读数 + 最多一个操作，中 340×160 核心 + 几条次要
// 信息或一排操作，大 340×340 核心 + 列表 / 图表 / 操作区，都不截断、不滚动。
//
// 数据和扩展栏是同一份：读的是同一个服务（WeatherService、CryptoService、StockService…）
// 和同一份卡片配置，改动走 `WidgetWriter`。每档列几条、溢出、挑哪个额度在 Core 的
// `DesktopCardsDataPlan`。卡片底是 `DesktopCard` 的液态玻璃，这里只画内容，颜色全用面板
// 语义色（panelPrimary…），浅色深色都看得清；主题色从环境的 `panelTint` 取。

@MainActor
enum DesktopCardsData {
    /// 本组的入口：不归本组或这一档沿用原来的画法时返回 nil。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsDataPlan.handles(widget.kind) else { return nil }
        switch widget.kind {
        case .weather: return AnyView(DCWeatherCard(widget: widget, size: size, now: now))
        case .crypto: return AnyView(DCCryptoCard(widget: widget, size: size, now: now))
        case .watchlist: return AnyView(DCWatchlistCard(widget: widget, size: size, now: now))
        case .stock: return AnyView(DCStockCard(widget: widget, size: size, now: now))
        case .github: return AnyView(DCGitHubCard(widget: widget, size: size, now: now))
        case .aiUsage: return AnyView(DCCodexCard(widget: widget, size: size, now: now))
        case .mail: return AnyView(DCMailCard(widget: widget, size: size, now: now))
        // 「算」小号沿用直接输入（DesktopQuickCalc）。
        case .calculator: return size == .small ? nil : AnyView(DCCalcCard(widget: widget, size: size))
        case .translate: return AnyView(DCTranslateCard(widget: widget, size: size))
        case .colorPicker: return AnyView(DCColorCard(widget: widget, size: size))
        case .emoji: return AnyView(DCEmojiCard(widget: widget, size: size))
        default: return nil
        }
    }
}

// MARK: - 共用小件

/// 卡片四周的内边距。
private let dcPad: CGFloat = 14

/// 左上角的小标题：图标 + 名字（13pt 次级色），右边可放一个尾巴。
private struct DCTitle<Trailing: View>: View {
    var symbol: String
    var text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundStyle(Color.panelSecondary)
    }
}

extension DCTitle where Trailing == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}

/// 一块薄玻璃底（列表行、输入框、结果框）。
private struct DCPane: ViewModifier {
    var corner: CGFloat = 12
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.panelStroke, lineWidth: 0.5)
                }
        }
    }
}

private extension View {
    func dcPane(_ corner: CGFloat = 12) -> some View { modifier(DCPane(corner: corner)) }
}

/// 胶囊按钮：图标 + 字，至少 30 高，好点。`prominent` 时是实心主题色（白字），否则是浮起的白块。
private struct DCButton: View {
    var title: String
    var symbol: String?
    var prominent = false
    var action: () -> Void

    @Environment(\.panelTint) private var panelTint

    var body: some View {
        let accent = panelTint.accent(or: Color(hex: ShelfColor.redPanda.hex))
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(prominent ? panelTint.ink(or: .white) : Color.panelPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background {
                if prominent {
                    Capsule().fill(accent)
                } else {
                    Capsule().fill(Color.panelRaised).panelLift()
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// 圆形图标按钮（吸管、拷贝、粘贴）。
private struct DCIconButton: View {
    var symbol: String
    var help: String
    var size: CGFloat = 32
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.panelRaised).panelLift())
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 自己画的进度圆环：轨道 + 弧 + 中间的字。
private struct DCRing<Label: View>: View {
    var fraction: Double
    var tint: Color
    var diameter: CGFloat
    var line: CGFloat
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.panelTrack, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 「还有 N 条」那一格。
private struct DCMore: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 天气

/// 小：城市、大图标和温度、天气和最高最低。中：左边读数，右边接下来 4 小时。
/// 大：读数 + 湿度风力，6 小时一排，下面 4 天预报带温度条。
private struct DCWeatherCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var service: WeatherService { WeatherService.shared }
    private var weather: WeatherNow? { service.current }
    private var fahrenheit: Bool { widget.config.bool("fahrenheit") }

    private var city: String {
        let stored = widget.config.string("city").trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty { return stored }
        return LocationService.shared.city ?? ""
    }

    private var place: String {
        if !city.isEmpty { return city }
        let location = LocationService.shared
        return (location.denied || location.unavailable) ? tr("设置城市…") : tr("正在定位…")
    }

    private var forecast: DailyForecast? {
        service.place.flatMap { ForecastService.shared.forecast(at: $0) }
    }

    private var today: DailyForecast.Day? { forecast?.upcoming(now: now, limit: 1).first }

    private func degrees(_ celsius: Double) -> String {
        "\(Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded()))°"
    }

    private var highLow: String? {
        guard let today else { return nil }
        return "\(degrees(today.highC)) / \(degrees(today.lowC))"
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .task(id: Int(now.timeIntervalSince1970) / 900) {
            await service.refresh()
            if let place = service.place { await ForecastService.shared.refresh(place) }
        }
    }

    /// 扩展栏上的天气卡片会自己取；这张卡片的天气卡片在文件夹里没画出来时，这里接上。
    /// 共享地点已经有天气时不去改它（多张天气卡片以最后设的城市为准，和扩展栏一样）。
    private func load() async {
        if service.current == nil {
            if widget.config.string("city").trimmingCharacters(in: .whitespaces).isEmpty {
                LocationService.shared.start()
            }
            if !city.isEmpty { await service.setLocation(city: city) }
        }
        if let place = service.place { await ForecastService.shared.refresh(place) }
    }

    private func icon(_ name: String?, size: CGFloat) -> some View {
        Image(systemName: name ?? "cloud.sun.fill")
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .frame(height: size)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            DCTitle(symbol: "location.fill", text: place)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 8) {
                icon(weather?.symbolName, size: 34)
                Text(weather.map { degrees($0.temperatureC) } ?? "--°")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(weather?.condition ?? "-")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let highLow {
                Text(highLow)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DCTitle(symbol: "location.fill", text: place)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    icon(weather?.symbolName, size: 28)
                    Text(weather.map { degrees($0.temperatureC) } ?? "--°")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text([weather?.condition, highLow].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 140, alignment: .leading)
            hourStrip(count: DesktopCardsDataPlan.rows(.weather, size: .medium))
                .frame(maxHeight: .infinity)
                .dcPane()
        }
    }

    private func hourStrip(count: Int) -> some View {
        let hours = Array(service.hourly.prefix(count))
        return HStack(spacing: 0) {
            if hours.isEmpty {
                Text(tr("正在读取…"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(hours, id: \.date) { hour in
                VStack(spacing: 6) {
                    Text(hour.date.formatted(.dateTime.hour()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .monospacedDigit()
                    icon(hour.symbolName, size: 18)
                    Text(degrees(hour.temperatureC))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private var details: [String] {
        var parts: [String] = []
        if let humidity = weather?.humidity { parts.append(tr("湿度") + " \(Int(humidity.rounded()))%") }
        if let speed = weather?.windSpeed {
            let force = Wind.beaufort(speed)
            parts.append(force == 0 ? tr("无风") : tr("\(Wind.direction(weather?.windFrom ?? 0)) \(force) 级"))
        }
        return parts
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            DCTitle(symbol: "location.fill", text: place)
            HStack(alignment: .center, spacing: 10) {
                icon(weather?.symbolName, size: 44)
                Text(weather.map { degrees($0.temperatureC) } ?? "--°")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather?.condition ?? "-")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                    if let highLow {
                        Text(highLow)
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                    }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            hourStrip(count: DesktopCardsDataPlan.rows(.weather, size: .large))
                .dcPane()
            dayList
        }
    }

    @ViewBuilder private var dayList: some View {
        let days = forecast?.upcoming(now: now, limit: DesktopCardsDataPlan.weatherDays) ?? []
        let todayKey = forecast?.todayKey(now: now) ?? ""
        let scale = DailyForecast.scale(days)
        VStack(spacing: 0) {
            ForEach(days, id: \.key) { day in
                HStack(spacing: 10) {
                    Text(DailyForecast.weekdayLabel(day.key, today: todayKey))
                        .font(.system(size: 13, weight: day.key == todayKey ? .bold : .medium))
                        .foregroundStyle(Color.panelPrimary)
                        .frame(width: 44, alignment: .leading)
                    icon(WMOWeather.symbol(day.code), size: 16)
                        .frame(width: 24)
                    Text(degrees(day.lowC))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                    rangeBar(day, scale: scale)
                    Text(degrees(day.highC))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .leading)
                }
                .lineLimit(1)
                .frame(height: 26)
            }
        }
    }

    private func rangeBar(_ day: DailyForecast.Day, scale: (low: Double, high: Double)?) -> some View {
        let span = DesktopCardsDataPlan.rangeBar(low: day.lowC, high: day.highC,
                                                 scaleLow: scale?.low ?? day.lowC,
                                                 scaleHigh: scale?.high ?? day.highC)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "#5AC8FA"), Color(hex: "#FF9F0A")],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * CGFloat(span.end - span.start)))
                    .offset(x: geo.size.width * CGFloat(span.start))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - 加密货币

/// 小：第一个币的价格、24 小时涨跌和 7 天走势。中：3 个币一行一个。大：6 个币加更新时间。
private struct DCCryptoCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private var ids: [String] { CryptoMarket.coinIDs(widget.config) }
    private var currency: String { CryptoMarket.currency(widget.config) }
    private var colors: ChangeColors { ChangeColors.from(widget.config) }
    private var stale: Bool { CryptoService.shared.isStale(currency) }

    private func quote(_ id: String) -> CryptoQuote? { CryptoService.shared.quote(id, currency: currency) }

    private func ink(_ change: Double?) -> Color {
        CryptoInk.color(CryptoMarket.tone(change, colors: colors), scheme: scheme)
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: list(DesktopCardsDataPlan.rows(.crypto, size: .medium), rowHeight: 40)
            case .large: large
            }
        }
        .opacity(stale ? OfflineQuote.staleOpacity : 1)
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(currency):\(ids.joined(separator: ","))") {
            CryptoService.shared.track(ids, currency: currency)
        }
    }

    private func badge(_ id: String, _ quote: CryptoQuote?, size: CGFloat) -> some View {
        let symbol = CryptoMarket.label(id: id, quote: quote)
        return Text(CryptoMarket.badgeLetter(symbol))
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: CryptoMarket.badgeHex(symbol))))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var small: some View {
        if let id = ids.first {
            let quote = quote(id)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    badge(id, quote, size: 22)
                    Text(CryptoMarket.label(id: id, quote: quote))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Spacer(minLength: 0)
                    ChangeChip(percent: quote?.change24h, colors: colors, size: 13)
                }
                Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .rollingValue(quote?.price)
                Spacer(minLength: 0)
                MiniTrend(samples: quote?.sparkline ?? [], tint: ink(quote?.change7d),
                          baseline: quote?.sparkline.first, lineWidth: 1.6)
                    .frame(height: 34)
                HStack {
                    Text(tr("7 天"))
                    Spacer(minLength: 0)
                    Text(CryptoMarket.changeText(quote?.change7d))
                        .foregroundStyle(ink(quote?.change7d).panelReadable)
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
            }
        } else {
            DCTitle(symbol: "bitcoinsign.circle", text: tr("加密货币"))
        }
    }

    private func row(_ id: String, height: CGFloat) -> some View {
        let quote = quote(id)
        return HStack(spacing: 8) {
            badge(id, quote, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(CryptoMarket.label(id: id, quote: quote))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(CryptoWatch.displayName(id: id, fallback: quote?.name))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
            }
            .lineLimit(1)
            .frame(width: 84, alignment: .leading)
            MiniTrend(samples: quote?.sparkline ?? [], tint: ink(quote?.change7d),
                      baseline: quote?.sparkline.first, lineWidth: 1.3)
                .frame(height: 20)
            Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .rollingValue(quote?.price)
            ChangeChip(percent: quote?.change24h, colors: colors, size: 13, minWidth: 60, minimumScale: 1)
                .layoutPriority(1)
        }
        .frame(height: height)
    }

    private func list(_ capacity: Int, rowHeight: CGFloat) -> some View {
        let fit = DesktopCardsDataPlan.overflow(count: ids.count, capacity: capacity)
        return VStack(spacing: 4) {
            ForEach(Array(ids.prefix(fit.shown)), id: \.self) { id in row(id, height: rowHeight) }
            if fit.hidden > 0 { DCMore(text: tr("还有 \(fit.hidden) 个")).frame(height: rowHeight) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            DCTitle(symbol: "bitcoinsign.circle", text: tr("加密货币") + " · " + currency.uppercased()) {
                if stale {
                    OfflineQuoteText(fetched: CryptoService.shared.updated(currency), now: now, stacked: false)
                } else if let updated = CryptoService.shared.updated(currency) {
                    Text(updated.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13))
                        .monospacedDigit()
                }
            }
            list(DesktopCardsDataPlan.rows(.crypto, size: .large), rowHeight: 40)
        }
    }
}

// MARK: - 自选股

/// 小：涨跌统计和比例条，排前两只。中：分组名（点了换组）、统计、今日盈亏，一列 3 只。
/// 大：同样的头，一列 7 只带名字和当日走势。
private struct DCWatchlistCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme

    private var group: StockBoard.Group { StockBoard.currentGroup(widget.config) }
    private var groupCount: Int { StockBoard.groups(widget.config).count }
    private var unit: PreciousMetal.DisplayUnit { .from(widget.config) }
    private var colors: ChangeColors { StockBoard.colors(widget.config) }

    private func quote(_ symbol: String) -> StockQuote? {
        StockDisplay.quote(symbol, preview: false, unit: unit)
    }

    private var symbols: [String] {
        var percents: [String: Double] = [:]
        for symbol in group.symbols { if let q = quote(symbol) { percents[symbol] = q.changePercent } }
        return StockBoard.sorted(group.symbols, percents: percents, order: .from(widget.config))
    }

    private var breadth: StockBoard.Breadth { StockBoard.breadth(symbols.map { quote($0)?.changePercent }) }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: StockDisplay.tracked(group.symbols, unit: unit)) {
            StockService.shared.track(StockDisplay.tracked(group.symbols, unit: unit))
        }
    }

    private var breadthLine: some View {
        HStack(spacing: 6) {
            Text(tr("涨 \(breadth.up)"))
                .foregroundStyle(StockInk.color(rising: true, colors: colors, scheme: scheme).panelReadable)
            Text(tr("跌 \(breadth.down)"))
                .foregroundStyle(StockInk.color(rising: false, colors: colors, scheme: scheme).panelReadable)
        }
        .font(.system(size: 15, weight: .bold))
        .monospacedDigit()
        .lineLimit(1)
    }

    /// 分组名：多个分组时点一下换下一个。
    @ViewBuilder private var groupChip: some View {
        let label = HStack(spacing: 4) {
            Text(group.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            if groupCount > 1 {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(Color.panelPrimary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.panelRaised).panelLift())
        if groupCount > 1 {
            Button { nextGroup() } label: { label.contentShape(.capsule) }
                .buttonStyle(.plain)
                .help(tr("点一下换下一个分组"))
                .accessibilityLabel(tr("换下一个分组"))
        } else {
            label
        }
    }

    @ViewBuilder private var profit: some View {
        let holdings = StockBoard.holdings(widget.config)
        let positions: [StockBoard.Position] = symbols.compactMap { symbol in
            guard let quote = quote(symbol), !quote.stale else { return nil }
            let label = StockDisplay.unitLabel(symbol, preview: false, unit: unit)
            let currency = label == PreciousMetal.DisplayUnit.cnyPerGram.title ? "CNY" : quote.currency
            return StockBoard.Position(symbol: symbol, price: quote.price, change: quote.change, currency: currency)
        }
        if !holdings.isEmpty, let first = StockBoard.todayProfit(positions, holdings: holdings).first {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(tr("今日"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                Text(StockBoard.profitText(first))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(StockInk.color(first.amount, colors: colors, scheme: scheme).panelReadable)
            }
            .lineLimit(1)
        }
    }

    private func row(_ symbol: String, named: Bool, trend: Bool = true) -> some View {
        let quote = quote(symbol)
        let ink = StockInk.color(quote?.changePercent, colors: colors, scheme: scheme)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(StockBoard.displaySymbol(symbol))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                if named {
                    Text(StockDisplay.subtitle(symbol, quote: quote, preview: false, unit: unit))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .lineLimit(1)
            .frame(width: named ? 92 : 52, alignment: .leading)
            if trend {
                MiniTrend(samples: quote?.history ?? [], tint: ink, baseline: quote?.previousClose, lineWidth: 1.3)
                    .frame(height: 18)
            } else {
                Spacer(minLength: 0)
            }
            Text(StockBoard.priceText(quote?.price))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            ChangeChip(percent: quote?.changePercent, colors: colors, size: 13, minWidth: 58, minimumScale: 1)
                .layoutPriority(1)
        }
        .opacity(quote?.stale == true ? OfflineQuote.staleOpacity : 1)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            DCTitle(symbol: "chart.line.uptrend.xyaxis", text: group.name)
            breadthLine
            BreadthBar(breadth: breadth, colors: colors, height: 5)
            Spacer(minLength: 0)
            ForEach(Array(symbols.prefix(DesktopCardsDataPlan.rows(.watchlist, size: .small))), id: \.self) { symbol in
                HStack(spacing: 6) {
                    Text(StockBoard.displaySymbol(symbol))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ChangeChip(percent: quote(symbol)?.changePercent, colors: colors, size: 13, minimumScale: 1)
                }
                .frame(height: 24)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            groupChip
            breadthLine
            Spacer(minLength: 0)
            profit
        }
    }

    /// 中号一列 3 只：代码、当日走势、现价、涨跌色块（两列放不下现价）。
    private var medium: some View {
        let fit = DesktopCardsDataPlan.overflow(count: symbols.count,
                                                capacity: DesktopCardsDataPlan.rows(.watchlist, size: .medium))
        return VStack(alignment: .leading, spacing: 6) {
            header
            BreadthBar(breadth: breadth, colors: colors, height: 4)
            VStack(spacing: 2) {
                ForEach(Array(symbols.prefix(fit.shown)), id: \.self) { symbol in
                    row(symbol, named: false, trend: true).frame(height: 26)
                }
                if fit.hidden > 0 { DCMore(text: StockBoard.moreText(fit.hidden)).frame(height: 26) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var large: some View {
        let fit = DesktopCardsDataPlan.overflow(count: symbols.count,
                                                capacity: DesktopCardsDataPlan.rows(.watchlist, size: .large))
        return VStack(alignment: .leading, spacing: 8) {
            header
            BreadthBar(breadth: breadth, colors: colors, height: 4)
            VStack(spacing: 2) {
                ForEach(Array(symbols.prefix(fit.shown)), id: \.self) { symbol in
                    row(symbol, named: true).frame(height: 34)
                }
                if fit.hidden > 0 { DCMore(text: StockBoard.moreText(fit.hidden)).frame(height: 30) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func nextGroup() {
        let current = WidgetWriter.current(widget.id) ?? widget
        let next = StockBoard.nextGroupName(current.config)
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { $0.set("group", .string(next)) }
        }
    }
}

// MARK: - 股票

/// 小：代码、价格、涨跌和一小段分时。中：左边读数，右边分时带昨收虚线和成交量。
/// 大：读数、大分时、昨收 / 成交量 / 提醒距离，下面一排轮播的几只（点一下换过去）。
private struct DCStockCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme
    @State private var picked: String?

    private var rotation: [String] { StockBoard.rotation(widget.config) }
    private var unit: PreciousMetal.DisplayUnit { .from(widget.config) }
    private var colors: ChangeColors { StockBoard.colors(widget.config) }

    private var symbol: String {
        let list = rotation
        if let picked, list.contains(picked) { return picked }
        let saved = StockBoard.normalised(widget.config.string("symbol", default: ""))
        return list.contains(saved) ? saved : (list.first ?? saved)
    }

    private func quote(_ symbol: String) -> StockQuote? {
        StockDisplay.quote(symbol, preview: false, unit: unit)
    }

    private var alert: StockBoard.Alert? {
        let rate = StockDisplay.usdToCny(preview: false)
        let alerts = StockBoard.alerts(widget.config).filter {
            PreciousMetal.canCheck($0, config: widget.config, usdToCny: rate)
        }
        return StockBoard.nearestAlert(for: symbol, price: quote(symbol)?.price, in: alerts)
    }

    var body: some View {
        let quote = quote(symbol)
        Group {
            switch size {
            case .small: small(quote)
            case .medium: medium(quote)
            case .large: large(quote)
            }
        }
        .opacity(quote?.stale == true ? OfflineQuote.staleOpacity : 1)
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: StockDisplay.tracked(rotation, unit: unit)) {
            StockService.shared.track(StockDisplay.tracked(rotation, unit: unit))
        }
    }

    private func ink(_ quote: StockQuote?) -> Color {
        StockInk.color(quote?.changePercent, colors: colors, scheme: scheme)
    }

    private func chart(_ quote: StockQuote?, volume: Bool) -> some View {
        IntradayChart(quote: quote, tint: ink(quote), alert: alert?.price, showsVolume: volume,
                      upInk: StockInk.color(rising: true, colors: colors, scheme: scheme),
                      downInk: StockInk.color(rising: false, colors: colors, scheme: scheme),
                      lineWidth: 1.6, guide: .panelSecondary)
    }

    private func name(_ quote: StockQuote?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(StockBoard.displaySymbol(symbol))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
            Text(StockDisplay.subtitle(symbol, quote: quote, preview: false, unit: unit))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
        }
        .lineLimit(1)
    }

    private func price(_ quote: StockQuote?, size points: CGFloat) -> some View {
        Text(StockBoard.priceText(quote?.price))
            .font(.system(size: points, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .rollingValue(StockBoard.priceText(quote?.price))
    }

    private func change(_ quote: StockQuote?) -> some View {
        HStack(spacing: 6) {
            ChangeChip(percent: quote?.changePercent, colors: colors, size: 13, minimumScale: 1)
            Text(StockBoard.changeText(quote?.change))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink(quote).panelReadable)
                .lineLimit(1)
        }
    }

    private func small(_ quote: StockQuote?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            name(quote)
            price(quote, size: 28)
            change(quote)
            Spacer(minLength: 0)
            chart(quote, volume: false).frame(height: 30)
        }
    }

    private func medium(_ quote: StockQuote?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                name(quote)
                Spacer(minLength: 0)
                price(quote, size: 30)
                change(quote)
            }
            .frame(width: 130, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                chart(quote, volume: true)
                if let alert {
                    Text(StockBoard.distanceText(alert, price: quote?.price))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(StockInk.alert.panelReadable)
                        .lineLimit(1)
                }
            }
        }
    }

    private func large(_ quote: StockQuote?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                name(quote)
                Spacer(minLength: 0)
                if quote?.stale == true {
                    OfflineQuoteText(fetched: quote?.fetchedAt, now: now, stacked: false)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                price(quote, size: 40)
                change(quote)
            }
            chart(quote, volume: true).frame(height: 120)
            HStack(spacing: 8) {
                stat(tr("昨收"), StockBoard.priceText(quote?.previousClose))
                stat(tr("成交量"), StockBoard.volumeText(quote?.volume))
                if let alert {
                    stat(tr("提醒"), StockBoard.distanceText(alert, price: quote?.price))
                }
            }
            if rotation.count > 1 { picker }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .minimumScaleFactor(0.8)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dcPane(10)
    }

    /// 轮播的几只：点一下换到那一只（只换这张桌面卡片，扩展栏照旧轮播）。
    private var picker: some View {
        let shown = Array(rotation.prefix(DesktopCardsDataPlan.rows(.stock, size: .large)))
        return HStack(spacing: 6) {
            ForEach(shown, id: \.self) { item in
                let selected = item == symbol
                Button { withAnimation(.snappy(duration: 0.2)) { picked = item } } label: {
                    VStack(spacing: 1) {
                        Text(StockBoard.displaySymbol(item))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.panelPrimary)
                        Text(StockBoard.percentText(quote(item)?.changePercent))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ink(quote(item)).panelReadable)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.panelSelected : Color.panelFill)
                    }
                    .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - GitHub

/// 小：星标总数和新反馈。中：左边总数，右边 3 个仓库各自的星标和新反馈。
/// 大：总数、议题 / PR / 通知三格，4 个仓库带反馈摘要，有新反馈时「全部已读」。
private struct DCGitHubCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var service: GitHubService { GitHubService.shared }
    private var repos: [String] { GitHubWatch.repos(widget.config) }
    private var stats: [GitHubStats] { repos.compactMap { service.stats(for: $0) } }
    private var stars: Int? { stats.isEmpty ? nil : stats.reduce(0) { $0 + $1.stars } }
    private var newCount: Int { service.totalFeedback(repos) }

    private var issues: Int { stats.reduce(0) { $0 + ($1.openIssues ?? $1.openIssuesAndPulls) } }
    private var pulls: Int? {
        stats.allSatisfy { $0.openPulls != nil } ? stats.reduce(0) { $0 + ($1.openPulls ?? 0) } : nil
    }

    private var caption: String {
        if stats.isEmpty { return repos.lazy.compactMap { service.error(for: $0) }.first ?? tr("正在读取…") }
        if newCount > 0 { return tr("\(newCount) 条新反馈") }
        return tr("没有新反馈")
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service.refreshAll(repos) }
        .onChange(of: repos) { _, new in service.refreshAll(new) }
    }

    private var starLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: "#F5B400"))
            Text(stars.map { GitHubStats.short($0) } ?? "-")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .rollingValue(stars ?? 0)
        }
    }

    private var feedbackPill: some View {
        Text(caption)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(newCount > 0 ? Color.white : Color.panelSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, newCount > 0 ? 10 : 0)
            .frame(height: 24)
            .background { if newCount > 0 { Capsule().fill(Color(hex: "#E5484D")) } }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            DCTitle(symbol: "chevron.left.forwardslash.chevron.right", text: GitHubWatch.tileTitle(repos))
            Spacer(minLength: 0)
            starLine
            Spacer(minLength: 0)
            feedbackPill
        }
    }

    private func repoRow(_ slug: String, detailed: Bool) -> some View {
        let stat = service.stats(for: slug)
        let feedback = service.feedback(for: slug)
        let name = slug.split(separator: "/").last.map(String.init) ?? slug
        return Button {
            if let url = stat?.htmlURL ?? URL(string: "https://github.com/\(slug)") { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .truncationMode(.middle)
                    if detailed {
                        Text(feedback.total > 0 ? feedback.summary : service.error(for: slug) ?? feedback.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if feedback.total > 0 {
                    Text(GitHubWatch.badgeText(feedback.total) ?? "")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Capsule().fill(Color(hex: "#E5484D")))
                }
                Text("★ " + (stat.map { GitHubStats.short($0.stars) } ?? "-"))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dcPane(10)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(tr("在浏览器中打开"))
    }

    private var medium: some View {
        let fit = DesktopCardsDataPlan.overflow(count: repos.count,
                                                capacity: DesktopCardsDataPlan.rows(.github, size: .medium))
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                DCTitle(symbol: "chevron.left.forwardslash.chevron.right", text: "GitHub")
                Spacer(minLength: 0)
                starLine
                Spacer(minLength: 0)
                feedbackPill
            }
            .frame(width: 120, alignment: .leading)
            VStack(spacing: 6) {
                ForEach(Array(repos.prefix(fit.shown)), id: \.self) { slug in repoRow(slug, detailed: false) }
                if fit.hidden > 0 { DCMore(text: tr("还有 \(fit.hidden) 个")) }
            }
        }
    }

    private func counter(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 48)
        .dcPane(10)
    }

    private var large: some View {
        let fit = DesktopCardsDataPlan.overflow(count: repos.count,
                                                capacity: DesktopCardsDataPlan.rows(.github, size: .large))
        return VStack(alignment: .leading, spacing: 10) {
            DCTitle(symbol: "chevron.left.forwardslash.chevron.right", text: GitHubWatch.tileTitle(repos)) {
                if newCount > 0 {
                    DCButton(title: tr("全部已读"), symbol: "checkmark") { service.markAllRead(repos) }
                }
            }
            HStack(alignment: .center) {
                starLine
                Spacer(minLength: 0)
                feedbackPill
            }
            HStack(spacing: 8) {
                counter(tr("议题"), GitHubStats.short(issues))
                counter("PR", pulls.map { GitHubStats.short($0) } ?? "-")
                counter(tr("通知"), service.notifications.map { GitHubStats.short($0) } ?? "-")
            }
            VStack(spacing: 6) {
                ForEach(Array(repos.prefix(fit.shown)), id: \.self) { slug in
                    repoRow(slug, detailed: true).frame(height: 40)
                }
                if fit.hidden > 0 { DCMore(text: tr("还有 \(fit.hidden) 个")).frame(height: 24) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Codex 用量

/// 小：状态和用掉最多的额度一个大圆环。中：小熊猫、状态、项目和正在做什么，右边两条额度。
/// 大：同样的头，两个大圆环带重置时间，最近 14 天用量柱和进行中的会话。
private struct DCCodexCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetTint) private var theme

    private var service: CodexService { CodexService.shared }
    private var report: CodexUsageReport? { service.report }
    private var windows: [CodexLimitWindow] { report?.ringWindows ?? [] }
    private var activity: CodexActivity { service.activity }
    private var lead: CodexSession? { CodexSessionList.lead(service.sessions) }
    private var showsRemaining: Bool { widget.config.string("show", default: "used") == "remaining" }
    private var stale: Bool { report?.isStale(now: now) == true }

    private func tint(_ used: Double) -> Color {
        if let theme, theme.isChosen, used < 0.7 { return theme.main(dark: scheme == .dark) }
        return CodexStyle.tint(used: used)
    }

    private func shown(_ w: CodexLimitWindow) -> Double { showsRemaining ? w.remainingFraction : w.usedFraction }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            service.configure(widget.config)
            service.startActivity()
            service.refresh()
        }
        .task(id: Int(now.timeIntervalSince1970) / 300) { service.refresh() }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle().fill(CodexStyle.color(activity)).frame(width: 9, height: 9)
            Text(activity.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CodexStyle.text(activity, dark: scheme == .dark))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex \(activity.title)")
    }

    private func reset(_ w: CodexLimitWindow) -> String {
        guard let resets = w.resetsAt else { return showsRemaining ? tr("剩余") : tr("已用") }
        return CodexCard.resetShort(resets.timeIntervalSince(now))
    }

    private func ring(_ w: CodexLimitWindow, diameter: CGFloat) -> some View {
        DCRing(fraction: shown(w), tint: tint(w.usedFraction).panelGraphic, diameter: diameter,
               line: diameter > 70 ? 8 : 6) {
            VStack(spacing: 0) {
                Text("\(Int((shown(w) * 100).rounded()))")
                    .font(.system(size: diameter * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                Text("%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
            }
        }
        .opacity(stale ? 0.55 : 1)
    }

    private var problemText: String { service.problem.map(CodexStyle.short) ?? tr("正在读取…") }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            status
            if let index = DesktopCardsDataPlan.featuredWindow(usedFractions: windows.map(\.usedFraction)) {
                let w = windows[index]
                HStack(spacing: 10) {
                    ring(w, diameter: 66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CodexCard.label(w))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary)
                        Text(reset(w))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                Text(problemText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(lead?.project ?? "Codex")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var who: some View {
        HStack(spacing: 10) {
            CodexPanda(activity: activity, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                status
                Text(lead?.project ?? (activity == .idle ? tr("没有进行中的会话") : "Codex"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let doing = lead?.doing?.text ?? service.problem.map(CodexStyle.short), !doing.isEmpty {
                    Text(doing)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func bar(_ w: CodexLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(CodexCard.label(w))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                Spacer(minLength: 2)
                Text(GaugeReading.percent(shown(w)))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.panelTrack)
                    Capsule().fill(tint(w.usedFraction).panelGraphic)
                        .frame(width: max(8, geo.size.width * CGFloat(shown(w))))
                }
            }
            .frame(height: 8)
            Text(reset(w))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color.panelSecondary)
        }
        .lineLimit(1)
        .opacity(stale ? 0.55 : 1)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            who.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                if windows.isEmpty {
                    Text(problemText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(3)
                } else {
                    ForEach(windows) { w in bar(w) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            who
            HStack(spacing: 10) {
                if windows.isEmpty {
                    Text(problemText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(windows) { w in
                        VStack(spacing: 6) {
                            ring(w, diameter: 78)
                            Text(CodexCard.label(w))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelPrimary)
                            Text(reset(w))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Color.panelSecondary)
                        }
                        .lineLimit(1)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .dcPane()
                    }
                }
            }
            usage
            sessions
            Spacer(minLength: 0)
        }
    }

    /// 最近 14 天每天的 token，按最多的一天归一。
    private var usage: some View {
        let bars = DesktopCardsDataPlan.usageBars((report?.daily ?? []).map(\.tokens), count: 14)
        return VStack(alignment: .leading, spacing: 4) {
            Text(tr("最近 14 天"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bars.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == bars.count - 1 ? CodexStyle.color(.working) : Color.panelTertiary)
                        .frame(height: max(3, 28 * CGFloat(bars[index])))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28, alignment: .bottom)
        }
    }

    @ViewBuilder private var sessions: some View {
        let list = Array(CodexSessionList.sorted(service.sessions).prefix(DesktopCardsDataPlan.rows(.aiUsage, size: .large)))
        ForEach(list, id: \.id) { session in
            HStack(spacing: 8) {
                Circle().fill(CodexStyle.color(session.state)).frame(width: 8, height: 8)
                Text(session.project ?? "Codex")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(session.doing?.text ?? session.state.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .truncationMode(.tail)
            }
            .lineLimit(1)
            .frame(height: 20)
        }
    }
}

// MARK: - 邮件

/// 小：未读数和「打开邮件」。中：未读数，右边最新 2 封。大：最新 4 封，点一下在「邮件」里打开，
/// 悬停时「标已读」。邮件没开、没权限时说清楚并给一个按钮。
private struct DCMailCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @State private var hovered: String?

    private var mail: MailService { MailService.shared }
    private var config: WidgetConfig { widget.config }
    private var unlocked: Bool { ProAccess.isUnlocked }
    private var storedFilter: String? {
        let raw = config.string(MailInbox.filterKey)
        return raw.isEmpty ? nil : raw
    }
    private var snapshot: MailSnapshot { mail.snapshot ?? MailSnapshot() }
    private var messages: [MailMessage] {
        MailInbox.visible(snapshot, hidden: MailInbox.hidden(config), filter: storedFilter,
                          unlocked: unlocked, limit: max(MailInbox.limit(config), DesktopCardsDataPlan.rows(.mail, size: .large)))
    }

    private var count: Int? {
        if case .unread(let n) = mail.state { return n }
        return nil
    }

    private var stateLine: String {
        switch mail.state {
        case .unread(let n): MailBadge.caption(n)
        case .notRunning: tr("「邮件」没开")
        case .denied: tr("需要允许码头读取「邮件」")
        case .failed: tr("暂时无法读取")
        }
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { mail.start() }
        .task(id: size) {
            guard size != .small else { return }
            // 卡片在桌面上时每分钟读一次列表；「邮件」没开时 15 秒一次，开了很快接上。
            while !Task.isCancelled {
                await mail.loadList(summary: MailInbox.showsSummary(config))
                try? await Task.sleep(for: .seconds(mail.listState == .loaded ? 60 : 15))
            }
        }
    }

    private var bigCount: some View {
        Text(count.map { MailBadge.figure($0) } ?? "-")
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .rollingValue(count ?? 0)
    }

    /// 状态不对时的那个按钮；正常时打开「邮件」。
    private var action: some View {
        Group {
            switch mail.state {
            case .denied: DCButton(title: tr("去允许"), symbol: "lock.open") { mail.openAutomationSettings() }
            default: DCButton(title: tr("打开邮件"), symbol: "envelope") { mail.openMail() }
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            DCTitle(symbol: "envelope.fill", text: tr("邮件"))
            Spacer(minLength: 0)
            bigCount
            Text(stateLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            action
        }
    }

    private func row(_ message: MailMessage, tall: Bool) -> some View {
        let name = message.senderName
        let hover = hovered == message.id
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: MailInbox.avatarHex(name)))
                Text(verbatim: MailInbox.initial(name))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Spacer(minLength: 4)
                    if hover {
                        Button { markRead(message) } label: {
                            Text(tr("标已读"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelPrimary)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Capsule().fill(Color.panelRaised).panelLift())
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(MailInbox.timeLabel(message.received, now: now))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                            .fixedSize()
                    }
                }
                Text(verbatim: message.subject.isEmpty ? tr("（无主题）") : message.subject)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelPrimary)
                if tall, MailInbox.showsSummary(config), !message.summary.isEmpty {
                    Text(verbatim: message.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover ? Color.panelSelected : Color.panelFill)
        }
        .contentShape(.rect(cornerRadius: 10))
        .onHover { inside in
            if inside { hovered = message.id } else if hovered == message.id { hovered = nil }
        }
        .onTapGesture { open(message) }
        .help(tr("在「邮件」中打开"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func list(_ capacity: Int, rowHeight: CGFloat, tall: Bool) -> some View {
        let shown = Array(messages.prefix(capacity))
        if mail.listState == .loaded, shown.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: "#34BE6E"))
                Text(tr("全部读完了"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shown.isEmpty {
            VStack(spacing: 8) {
                Text(stateLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                action
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                ForEach(shown) { message in row(message, tall: tall).frame(height: rowHeight) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DCTitle(symbol: "envelope.fill", text: tr("邮件"))
                Spacer(minLength: 0)
                bigCount
                Text(stateLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 96, alignment: .leading)
            list(DesktopCardsDataPlan.rows(.mail, size: .medium), rowHeight: 63, tall: false)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            DCTitle(symbol: "envelope.fill", text: tr("邮件")) {
                DCButton(title: tr("打开邮件"), symbol: nil) { mail.openMail() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                bigCount
                Text(stateLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
            list(DesktopCardsDataPlan.rows(.mail, size: .large), rowHeight: 50, tall: true)
        }
    }

    private func open(_ message: MailMessage) {
        mail.open(message)
        if MailInbox.marksReadOnOpen(config) { markRead(message) }
    }

    private func markRead(_ message: MailMessage) {
        withAnimation(.snappy(duration: 0.25)) { hovered = nil }
        Task {
            _ = await mail.markRead(message)
            await mail.loadList(summary: MailInbox.showsSummary(config))
        }
    }
}

// MARK: - 「算」中号、大号

/// 中：大输入框，下面大号结果（点一下拷贝）和汇率单价。大：再加最近记录，点一下拿回来再算。
/// 算式存进卡片配置（和扩展栏、面板同一份），回车记进最近记录。
private struct DCCalcCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @State private var draft: String
    @State private var copied = false
    @FocusState private var focused: Bool

    init(widget: WidgetInstance, size: DesktopPinSize) {
        self.widget = widget
        self.size = size
        _draft = State(initialValue: widget.config.string(SmartCalc.expressionKey))
    }

    private var stored: String { widget.config.string(SmartCalc.expressionKey) }
    private var history: [String] { widget.config.strings(SmartCalc.historyKey) }

    private var reading: Result<SmartCalc.Outcome, SmartCalc.Failure>? {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return SmartCalc.evaluate(draft, rates: CurrencyService.shared.rates,
                                  preferences: SmartCalc.Preferences(widget.config))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DCTitle(symbol: "equal.circle", text: WidgetCatalog.entry(.calculator)?.name ?? tr("算")) {
                if copied {
                    Text(tr("已拷贝"))
                        .font(.system(size: 13, weight: .medium))
                        .transition(.opacity)
                }
            }
            field
            result
            if size == .large { recent }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { CurrencyService.shared.refresh(force: false) }
        .onChange(of: stored) { _, value in if !focused { draft = value } }
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save(remember: false)
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = false }
        }
    }

    private var field: some View {
        TextField("", text: $draft, prompt: Text(verbatim: "1299*3+50 usd").foregroundStyle(Color.panelTertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.panelPrimary)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .dcPane(10)
            .onSubmit { save(remember: true) }
    }

    @ViewBuilder private var result: some View {
        switch reading {
        case .success(let out)?:
            Button { copy(out) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(out.text)
                            .font(.system(size: size == .large ? 40 : 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                        if !out.unit.isEmpty {
                            Text(out.unit)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.panelSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if let line = out.rateLine {
                        Text(line)
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点一下拷贝结果"))
        case .failure(let failure)?:
            Text(failure.message)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(2)
        case nil:
            Text(tr("算式、单位、汇率都能直接写"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(2)
        }
    }

    private var recent: some View {
        let rows = Array(history.prefix(DesktopCardsDataPlan.rows(.calculator, size: .large)))
        return VStack(alignment: .leading, spacing: 4) {
            Text(tr("最近记录"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            ForEach(rows, id: \.self) { entry in
                Button {
                    draft = entry
                    save(remember: false)
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: entry)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelPrimary)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(outcomeText(entry))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .dcPane(8)
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text(tr("回车记下一条"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func outcomeText(_ entry: String) -> String {
        guard case .success(let out) = SmartCalc.evaluate(entry, rates: CurrencyService.shared.rates,
                                                          preferences: SmartCalc.Preferences(widget.config)) else { return "" }
        return out.unit.isEmpty ? out.text : "\(out.text) \(out.unit)"
    }

    private func copy(_ out: SmartCalc.Outcome) {
        ColorSampling.copy(out.copyText)
        withAnimation(.easeIn(duration: 0.15)) { copied = true }
    }

    private func save(remember: Bool) {
        let entry = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry != stored || remember else { return }
        let latest = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(latest) { config in
            config.set(SmartCalc.expressionKey, .string(entry))
            guard remember, !entry.isEmpty else { return }
            config.set(SmartCalc.historyKey,
                       .list(SmartCalc.remembering(entry, in: config.strings(SmartCalc.historyKey)).map { .string($0) }))
        }
    }
}

// MARK: - 翻译

/// 小：语言方向、上一条译文，「粘贴翻译」。中：左边输入、右边译文（点一下拷贝）。
/// 大：输入、译文、粘贴 / 拷贝，下面最近两条记录（点一下拿回来）。翻译用系统的 Translation，
/// 和面板一样停手 0.6 秒就翻，结果记进同一份历史。
private struct DCTranslateCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @State private var draft = ""
    @State private var result: TranslateRecord?
    @State private var working = false
    @State private var note: String?
    @State private var copied = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var pending: TranslateJob?
    @FocusState private var editing: Bool

    private var config: WidgetConfig { widget.config }
    private var history: [TranslateRecord] { Translate.history(config) }
    private var last: TranslateRecord? { result ?? history.first }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .translationTask(configuration) { session in
            guard let job = pending else { return }
            let outcome = await TranslationRunner.run(session, job: job) {
                if pending == job { note = tr("首次翻译这对语言需要下载语言包，请在系统弹出的窗口中下载。") }
            }
            guard pending == job, outcome != .cancelled else { return }
            pending = nil
            working = false
            switch outcome {
            case .done(let record):
                result = record
                note = nil
                let latest = WidgetWriter.current(widget.id) ?? widget
                WidgetWriter.write(latest) { config in
                    Translate.store(Translate.recording(record, in: Translate.history(config)), in: &config)
                }
            case .note(let text):
                note = text
            case .cancelled:
                break
            }
        }
        .task(id: draft) {
            guard size != .small else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            translate(draft)
        }
        .onChange(of: draft) { _, text in
            if text.count > Translate.maxCharacters { draft = Translate.clamped(text) }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = false }
        }
    }

    private var pair: some View {
        Text(Translate.tilePair(config))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.panelRaised).panelLift())
    }

    private var title: some View {
        DCTitle(symbol: "translate", text: tr("翻译")) {
            if copied {
                Text(tr("已拷贝")).font(.system(size: 13, weight: .medium))
            } else if working {
                Text(tr("正在翻译…")).font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            pair
            Text(working ? tr("正在翻译…") : (last.map { Translate.snippet($0.resultText) } ?? tr("复制一段文字，点下面翻译")))
                .font(.system(size: last == nil ? 13 : 15, weight: .semibold))
                .foregroundStyle(last == nil ? Color.panelSecondary : Color.panelPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onTapGesture { if let last { copy(last.resultText) } }
            DCButton(title: tr("粘贴翻译"), symbol: "doc.on.clipboard", prominent: true) { pasteAndTranslate() }
        }
    }

    private func input(minHeight: CGFloat) -> some View {
        TextField("", text: $draft, prompt: Text(tr("输入或粘贴要翻译的文字")).foregroundStyle(Color.panelTertiary),
                  axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(3...4)
            .focused($editing)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .dcPane(10)
    }

    private func output(minHeight: CGFloat) -> some View {
        let text = result?.resultText ?? (draft.isEmpty ? last?.resultText : nil)
        return Button { if let text { copy(text) } } label: {
            Text(note ?? text ?? tr("译文在这里，点一下拷贝"))
                .font(.system(size: note == nil && text != nil ? 15 : 13, weight: .semibold))
                .foregroundStyle(note == nil && text != nil ? Color.panelPrimary : Color.panelSecondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
                .dcPane(10)
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(tr("点一下拷贝译文"))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                title
                pair
            }
            HStack(spacing: 8) {
                input(minHeight: 80)
                output(minHeight: 80)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                title
                pair
            }
            input(minHeight: 72)
            output(minHeight: 72)
            HStack(spacing: 8) {
                DCButton(title: tr("粘贴剪贴板"), symbol: "doc.on.clipboard") { pasteAndTranslate() }
                Spacer(minLength: 0)
                if let text = result?.resultText ?? last?.resultText {
                    DCButton(title: tr("拷贝"), symbol: "doc.on.doc", prominent: true) { copy(text) }
                }
            }
            ForEach(Array(history.prefix(DesktopCardsDataPlan.rows(.translate, size: .large)).enumerated()),
                    id: \.offset) { _, record in
                Button {
                    draft = record.sourceText
                    result = record
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: record.sourceText)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: record.resultText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .dcPane(8)
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copy(_ text: String) {
        ColorSampling.copy(text)
        withAnimation(.easeIn(duration: 0.15)) { copied = true }
    }

    private func pasteAndTranslate() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSSound.beep()
            return
        }
        draft = Translate.clamped(text)
        translate(draft)
    }

    /// 和面板一样：选定或识别出的原文语言，智能方向没关时自动定译到哪种。
    private func translate(_ raw: String) {
        let text = Translate.clamped(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else {
            pending = nil
            working = false
            return
        }
        if let result, result.sourceText == text { return }
        let chosen = Translate.source(config)
        let source = chosen == Translate.auto ? Translate.detect(text) : chosen
        let target = Translate.target(source: source, text: text, chosen: Translate.chosenTarget(config),
                                      smart: Translate.smartDirection(config))
        if let source, Translate.same(source, target) {
            note = tr("原文已经是\(TranslationRunner.name(target))，换一个目标语言试试。")
            return
        }
        let job = TranslateJob(text: text, source: source, target: target)
        guard pending != job else { return }
        pending = job
        working = true
        note = nil
        let next = TranslationRunner.configuration(for: job)
        if TranslationRunner.samePair(configuration, next) {
            configuration?.invalidate()
        } else {
            configuration = next
        }
    }
}

// MARK: - 取色器

/// 小：最新颜色一大块（点一下拷贝）和吸管。中：左边大色块和 HEX、rgb，右边 8 个最近色块和吸管。
/// 大：大色块，HEX / rgb / hsl 三行各点一下拷贝，下面 12 个最近色块。
private struct DCColorCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @AppStorage(ColorHistory.defaultsKey) private var stored = ""
    @AppStorage(ColorPalette.defaultsKey) private var palette = ""
    @AppStorage(ColorHistory.legacyRetiredKey) private var retired = false
    @State private var copied: String?

    private var colors: [ColorCode] {
        if widget.config.bool(ColorPalette.showKey) {
            let saved = ColorPalette.colors(palette)
            if !saved.isEmpty { return saved }
        }
        return ColorPicking.recent(widget, stored: stored, retired: retired)
    }

    private var style: ColorCopyStyle { ColorPicking.style(widget) }
    private var latest: ColorCode? { colors.first }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = nil }
        }
    }

    private func copy(_ text: String) {
        ColorSampling.copy(text)
        withAnimation(.easeIn(duration: 0.15)) { copied = text }
    }

    private var dropper: some View {
        DCIconButton(symbol: "eyedropper", help: tr("从屏幕取色")) { ColorPicking.pick(into: widget) }
    }

    /// 大色块：上面压着 HEX，字色按颜色深浅选黑白。
    private func hero(_ color: ColorCode?, corner: CGFloat, font: CGFloat) -> some View {
        Button {
            if let color { copy(style.text(color)) }
        } label: {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.map(\.swiftUIColor) ?? Color.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.panelStroke, lineWidth: 0.5)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(color.map { style.hexStyle.apply($0.hex) } ?? tr("还没有取色"))
                        .font(.system(size: font, weight: .bold).monospacedDigit())
                        .foregroundStyle(color.map { $0.isLight ? Color.black.opacity(0.78) : Color.white } ?? Color.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(10)
                }
                .contentShape(.rect(cornerRadius: corner))
        }
        .buttonStyle(.plain)
        .disabled(color == nil)
        .help(tr("点一下拷贝"))
    }

    private var status: some View {
        Text(copied.map { tr("已拷贝 \($0)") } ?? tr("点色块拷贝"))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            hero(latest, corner: 14, font: 15)
            HStack(spacing: 6) {
                status
                Spacer(minLength: 0)
                dropper
            }
        }
    }

    private func grid(_ size: DesktopPinSize, cell: CGFloat) -> some View {
        let layout = DesktopCardsDataPlan.colorGrid(size)
        let list = Array(colors.dropFirst().prefix(layout.columns * layout.rows))
        return VStack(spacing: 6) {
            ForEach(0..<layout.rows, id: \.self) { line in
                HStack(spacing: 6) {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = line * layout.columns + column
                        let color = index < list.count ? list[index] : nil
                        Button {
                            if let color { copy(style.text(color)) }
                        } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(color.map(\.swiftUIColor) ?? Color.panelFill)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.panelStroke, lineWidth: 0.5)
                                }
                                .frame(height: cell)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(color == nil)
                        .help(color.map { style.hexStyle.apply($0.hex) } ?? "")
                        .accessibilityLabel(color.map { tr("拷贝 \($0.hex)") } ?? tr("空"))
                    }
                }
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            hero(latest, corner: 14, font: 17)
                .frame(width: 132)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    status
                    Spacer(minLength: 0)
                    dropper
                }
                grid(.medium, cell: 36)
                Spacer(minLength: 0)
            }
        }
    }

    private func formatRow(_ title: String, _ text: String) -> some View {
        Button { copy(text) } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(width: 44, alignment: .leading)
                Text(verbatim: text)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: copied == text ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .dcPane(8)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            DCTitle(symbol: "eyedropper.halffull", text: tr("取色器")) { dropper }
            hero(latest, corner: 16, font: 20).frame(height: 78)
            if let latest {
                formatRow("HEX", style.hexStyle.apply(latest.hex))
                formatRow("RGB", latest.rgb)
                formatRow("HSL", latest.hsl)
            }
            Spacer(minLength: 0)
            grid(.large, cell: 34)
        }
    }
}

// MARK: - 表情符号

/// 小：收藏的前 9 个，3×3 大格子，点一下拷贝。中：14 个，两排。大：收藏 18 个，下面一排最近用过，
/// 和「更多…」（打开面板搜索、整理）。拷贝后记进最近用过，和扩展栏同一份。
private struct DCEmojiCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @State private var copied: String?
    @State private var copyCount = 0

    private var prefs: EmojiPrefs { EmojiPrefs(widget.config) }

    private var favorites: [String] {
        let p = prefs
        return !p.favorites.isEmpty ? p.favorites : !p.recent.isEmpty ? p.recent : EmojiPrefs.defaultFavorites
    }

    var body: some View {
        Group {
            switch size {
            case .small: grid(favorites, layout: DesktopCardsDataPlan.emojiGrid(.small), font: 30, cell: 40)
            case .medium: grid(favorites, layout: DesktopCardsDataPlan.emojiGrid(.medium), font: 28, cell: 40)
            case .large: large
            }
        }
        .padding(dcPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: copyCount) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = nil }
        }
    }

    private func cell(_ item: String, font: CGFloat, cell: CGFloat) -> some View {
        let shown = prefs.display(item)
        return Button { copy(item, shown: shown) } label: {
            Text(verbatim: shown)
                .font(.system(size: font))
                .frame(maxWidth: .infinity)
                .frame(height: cell)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(copied == item ? Color.panelSelected : Color.panelFill.opacity(0.6))
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(tr("拷贝 \(shown)"))
    }

    private func grid(_ items: [String], layout: (columns: Int, rows: Int), font: CGFloat, cell size: CGFloat) -> some View {
        let list = Array(items.prefix(layout.columns * layout.rows))
        return VStack(spacing: 6) {
            ForEach(0..<layout.rows, id: \.self) { line in
                HStack(spacing: 6) {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = line * layout.columns + column
                        if index < list.count {
                            cell(list[index], font: font, cell: size)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: size)
                        }
                    }
                }
            }
        }
    }

    private var large: some View {
        let recent = Array(prefs.recent.prefix(DesktopCardsDataPlan.emojiRecent))
        return VStack(alignment: .leading, spacing: 8) {
            DCTitle(symbol: "face.smiling", text: tr("收藏")) {
                if let copied {
                    Text(tr("已拷贝 \(prefs.display(copied))")).font(.system(size: 13, weight: .medium))
                }
            }
            grid(favorites, layout: DesktopCardsDataPlan.emojiGrid(.large), font: 28, cell: 44)
            HStack {
                Text(tr("最近用过"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Spacer(minLength: 0)
                Button { WidgetPanelOpener.shared.open(widget.id) } label: {
                    Text(tr("更多…"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.panelRaised).panelLift())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(tr("搜索、整理收藏、更多表情"))
            }
            if recent.isEmpty {
                Text(tr("拷贝过的表情会出现在这里"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                    .frame(height: 40)
            } else {
                grid(recent, layout: (DesktopCardsDataPlan.emojiRecent, 1), font: 24, cell: 40)
            }
        }
    }

    private func copy(_ item: String, shown: String) {
        ColorSampling.copy(shown)
        copied = item
        copyCount &+= 1
        let latest = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(latest) { config in
            EmojiPrefs(config).recording(item).store(in: &config)
        }
    }
}
