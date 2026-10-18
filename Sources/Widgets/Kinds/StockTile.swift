import SwiftUI

/// 股票：只盯一只。看清它今天怎么走，离提醒价还有多远。
///
/// 宽卡片左边是代码和中文名、大号价格、涨跌幅和涨跌额；右边是当日分时（按交易时段
/// 铺满，盘中只画到现在）、昨收虚线、底部的成交量小柱，设了到价提醒时一条橙色细线
/// 和“距提醒价 2.1%”。没设提醒时右上角写盘中或已收盘。竖排扩展栏只有 76pt 宽，
/// 叠成代码、价格、涨跌和一小段分时。
///
/// 设了多只时每 10 秒自动轮播一只（可在设置里关掉），底部圆点指示，点圆点直接换。
/// 到了提醒价发一次系统通知，卡片闪一下橙边。涨跌颜色跟设置走，默认红涨绿跌。
/// 黄金白银按设置的单位显示，默认元/克。
struct StockTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    /// 轮播到第几只。nil 时用设置里记的 `symbol`。
    @State private var index: Int?
    /// 手动点了圆点就从头计时，不会刚点完就被自动轮播换走。
    @State private var manualTick = 0
    /// 发了到价通知就加一，卡片闪橙边。
    @State private var flash = 0

    private var rotation: [String] { StockBoard.rotation(instance.config) }

    private var symbol: String {
        let list = rotation
        if let index, list.indices.contains(index) { return list[index] }
        let saved = StockBoard.normalised(instance.config.string("symbol", default: ""))
        return list.contains(saved) ? saved : list[0]
    }

    private var currentIndex: Int { rotation.firstIndex(of: symbol) ?? 0 }
    private var unit: PreciousMetal.DisplayUnit { .from(instance.config) }
    private var colors: ChangeColors { StockBoard.colors(instance.config) }
    /// 能拿卡片上的价去比的提醒：黄金白银的提醒价单位和显示单位对不上（切了单位、
    /// 汇率还没到）时先不算，见 `PreciousMetal.canCheck`。
    private var alerts: [StockBoard.Alert] {
        let rate = StockDisplay.usdToCny(preview: context.isPreview)
        return StockBoard.alerts(instance.config).filter {
            PreciousMetal.canCheck($0, config: instance.config, usdToCny: rate)
        }
    }
    private var rotates: Bool { instance.config.bool("rotate", default: true) && rotation.count > 1 }
    private var showsChart: Bool { instance.config.bool("chart", default: true) }

    private func quote(_ symbol: String) -> StockQuote? {
        StockDisplay.quote(symbol, preview: context.isPreview, unit: unit)
    }

    /// 要取的代码：轮播的每一只、提醒里的每一只，贵金属要元/克时加上汇率。
    /// 提醒价还没换到当前单位时也要汇率，换完就不用了。
    private var tracked: [String] {
        let symbols = StockBoard.unique(rotation + StockBoard.alerts(instance.config).map(\.symbol))
        let list = StockDisplay.tracked(symbols, unit: unit)
        guard PreciousMetal.alertsPending(instance.config), !list.contains(PreciousMetal.exchangeSymbol) else {
            return list
        }
        return list + [PreciousMetal.exchangeSymbol]
    }

    /// 提醒价要不要换单位：设置或汇率有没有变。
    private var unitSignature: String {
        let rate = StockDisplay.usdToCny(preview: context.isPreview)
        return [instance.config.string("metalUnit"), instance.config.string(PreciousMetal.alertUnitKey),
                instance.config.strings("alerts", default: []).joined(separator: ","),
                rate == nil ? "-" : "rate"].joined(separator: "|")
    }

    var body: some View {
        let quote = quote(symbol)
        let alert = StockBoard.nearestAlert(for: symbol, price: quote?.price, in: alerts)
        WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(quote, alert: alert)
                } else {
                    wide(quote, alert: alert)
                }
            }
            // 刷新失败时留着上次的数，变淡表示不是最新的，不清空也不写零。
            .opacity(quote?.stale == true ? 0.55 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .phaseAnimator([0.0, 1.0, 0.0, 1.0, 0.0], trigger: flash) { content, glow in
            content.overlay {
                RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous)
                    .strokeBorder(StockInk.alert, lineWidth: 1.5)
                    .opacity(glow)
                    .allowsHitTesting(false)
            }
        } animation: { _ in .easeInOut(duration: 0.25) }
        .task(id: tracked) {
            guard !context.isPreview else { return }
            StockService.shared.track(tracked)
        }
        .task(id: "\(rotates)|\(rotation.joined(separator: ","))|\(manualTick)") {
            await autoRotate()
        }
        .onChange(of: unitSignature, initial: true) { _, _ in reconcileAlertUnit() }
        .onChange(of: alertSignature, initial: true) { _, _ in checkAlerts() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText(quote))
    }

    // MARK: 布局

    private func wide(_ quote: StockQuote?, alert: StockBoard.Alert?) -> some View {
        HStack(spacing: 8) {
            readout(quote, symbolSize: 10.5, priceSize: 19, percentSize: 10)
                .frame(width: showsChart ? 88 : nil, alignment: .leading)
                .frame(maxWidth: showsChart ? nil : .infinity, alignment: .leading)
            if showsChart {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        dots(size: 3.5)
                        Spacer(minLength: 0)
                        corner(quote, alert: alert)
                    }
                    .frame(height: 11)
                    chart(quote, alert: alert, volume: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showsChart { dots(size: 3.5) }
        }
        .padding(.vertical, 6)
    }

    private func column(_ quote: StockQuote?, alert: StockBoard.Alert?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            readout(quote, symbolSize: 9, priceSize: 14, percentSize: 9, compact: true)
            if showsChart {
                chart(quote, alert: alert, volume: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 2)
            } else {
                Spacer(minLength: 0)
            }
            if let alert {
                Text(StockBoard.distanceText(alert, price: quote?.price))
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(StockInk.alert)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack { Spacer(minLength: 0); dots(size: 3); Spacer(minLength: 0) }
        }
        .padding(.vertical, 6)
    }

    private func readout(_ quote: StockQuote?, symbolSize: CGFloat, priceSize: CGFloat,
                         percentSize: CGFloat, compact: Bool = false) -> some View {
        let ink = StockInk.color(quote?.changePercent, colors: colors, scheme: scheme)
        let subtitle = StockDisplay.subtitle(symbol, quote: quote, preview: context.isPreview, unit: unit)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(StockBoard.displaySymbol(symbol))
                    .font(WidgetStyle.label(symbolSize))
                    .foregroundStyle(WidgetStyle.primary)
                    .layoutPriority(1)
                if !compact, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WidgetStyle.caption(symbolSize - 2))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
            Text(StockBoard.priceText(quote?.price))
                .font(.system(size: priceSize, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(StockBoard.priceText(quote?.price))
            HStack(spacing: 4) {
                Text(StockBoard.percentText(quote?.changePercent))
                    .font(WidgetStyle.label(percentSize))
                    .monospacedDigit()
                    .rollingValue(StockBoard.percentText(quote?.changePercent))
                if !compact {
                    Text(StockBoard.changeText(quote?.change))
                        .font(WidgetStyle.caption(percentSize - 1.5))
                        .monospacedDigit()
                        .opacity(0.85)
                }
            }
            .foregroundStyle(ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func chart(_ quote: StockQuote?, alert: StockBoard.Alert?, volume: Bool) -> some View {
        IntradayChart(quote: quote,
                      tint: StockInk.color(quote?.changePercent, colors: colors, scheme: scheme),
                      alert: alert?.price,
                      showsVolume: volume,
                      upInk: StockInk.color(rising: true, colors: colors, scheme: scheme),
                      downInk: StockInk.color(rising: false, colors: colors, scheme: scheme),
                      lineWidth: context.position.isVertical ? 1.1 : 1.3)
    }

    /// 右上角：有提醒时写离提醒价多远，没有时写盘中或已收盘。
    @ViewBuilder
    private func corner(_ quote: StockQuote?, alert: StockBoard.Alert?) -> some View {
        if let alert {
            Text(StockBoard.distanceText(alert, price: quote?.price))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(StockInk.alert)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .overlay(Capsule().strokeBorder(StockInk.alert.opacity(0.8), lineWidth: 0.7))
        } else {
            Text(StockBoard.session(now: .now, start: quote?.sessionStart, end: quote?.sessionEnd).title)
                .font(WidgetStyle.caption(8))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func dots(size: CGFloat) -> some View {
        if rotation.count > 1 {
            RotationDots(count: rotation.count, index: currentIndex, size: size) { pick($0) }
                .disabled(context.isPreview)
        }
    }

    // MARK: 轮播

    private func pick(_ item: Int) {
        guard rotation.indices.contains(item) else { return }
        withAnimation(.snappy(duration: 0.3)) { index = item }
        manualTick += 1
        let next = rotation[item]
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { config in
            config.set("symbol", .string(next))
        }
    }

    private func autoRotate() async {
        guard rotates, !context.isPreview else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(StockBoard.rotationInterval))
            guard !Task.isCancelled else { return }
            let count = rotation.count
            guard count > 1 else { return }
            withAnimation(.snappy(duration: 0.35)) { index = (currentIndex + 1) % count }
        }
    }

    // MARK: 到价提醒

    /// 提醒和它们对应的现价，任何一个变了就检查一遍。
    private var alertSignature: String {
        alerts.map { alert in
            let price = quote(alert.symbol).flatMap { $0.stale ? nil : $0.price }
            return "\(alert.text)=\(price.map { String($0) } ?? "-")"
        }
        .joined(separator: ",")
    }

    /// 切过黄金白银的单位（在面板或设置里）：提醒价按汇率和克/盎司换算过去，
    /// 汇率还没到就等它到了再换。见 `PreciousMetal.reconciled`。
    private func reconcileAlertUnit() {
        guard !context.isPreview else { return }
        let rate = StockDisplay.usdToCny(preview: false)
        let saved = WidgetWriter.current(instance.id) ?? instance
        guard let next = PreciousMetal.reconciled(saved.config, usdToCny: rate) else { return }
        WidgetWriter.write(saved) { $0 = next }
    }

    private func checkAlerts() {
        guard !context.isPreview, !alerts.isEmpty else { return }
        var prices: [String: Double] = [:]
        for alert in alerts {
            if let quote = quote(alert.symbol), !quote.stale { prices[alert.symbol] = quote.price }
        }
        let fired = Set(instance.config.strings("alertsFired", default: []))
        let hits = StockBoard.newlyReached(alerts, prices: prices, fired: fired)
        guard !hits.isEmpty else { return }
        for hit in hits {
            let name = StockBoard.displaySymbol(hit.symbol)
            StockAlertNotifier.shared.post(hit, name: name, price: prices[hit.symbol] ?? hit.price,
                                           widget: instance.id)
        }
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { config in
            let kept = StockBoard.prunedFired(config.strings("alertsFired", default: []),
                                              alerts: StockBoard.alerts(config))
            config.set("alertsFired", .list((kept + hits.map(\.text)).map { .string($0) }))
        }
        flash += 1
    }

    private func accessibilityText(_ quote: StockQuote?) -> String {
        guard let quote else { return StockBoard.displaySymbol(symbol) }
        return "\(StockBoard.displaySymbol(symbol)) \(StockBoard.priceText(quote.price)) "
            + StockBoard.percentText(quote.changePercent)
    }
}
