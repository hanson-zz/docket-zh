import SwiftUI

/// A few coins side by side, 96pt each: the coin's round badge, ticker and a
/// solid 24-hour chip over the price, with the seven-day line under them.
///
/// Built like the Watchlist tile (a column per symbol on the shelf, a row per
/// symbol in the side column) and fed by `CryptoService`, which keeps the
/// last good prices and fades them when a refresh fails. Rises and falls are
/// red and green the Chinese way round unless the widget's 涨跌颜色 says
/// otherwise. The card has no controls; its click opens the panel.
///
/// 到价提醒（Pro）也在这里判断：每次取到新价，开着的提醒到了就发通知、
/// 自动关掉，并把这个币在卡片上染成金色，直到打开面板（见 `CryptoWatch`）。
struct CryptoTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    private var ids: [String] { CryptoMarket.coinIDs(instance.config) }
    private var currency: String { CryptoMarket.currency(instance.config) }
    private var colors: ChangeColors { ChangeColors.from(instance.config) }
    private var showsChart: Bool { instance.config.bool("chart", default: true) }

    private func quote(_ id: String) -> CryptoQuote? {
        context.isPreview ? .preview(id, currency: currency) : CryptoService.shared.quote(id, currency: currency)
    }

    private var stale: Bool { !context.isPreview && CryptoService.shared.isStale(currency) }

    private var alertsOn: Bool {
        !context.isPreview && ProLicenseGate.canUseCryptoAlerts(unlocked: ProAccess.isUnlocked)
    }

    /// 开着的提醒（没解锁时是空的：不判断、不取价、不变色）。
    private var liveAlerts: [CryptoAlert] {
        guard alertsOn else { return [] }
        return CryptoWatch.alerts(instance.config, coins: ids).filter(\.on)
    }

    /// 到过价、还没打开面板看的币，卡片上染成金色。
    private var hits: Set<String> {
        alertsOn ? Set(CryptoWatch.hits(instance.config)) : []
    }

    /// 提醒要用的价每更新一次就变：用到的每种计价的取价时间，加上提醒本身。
    private var alertKey: String {
        let alerts = liveAlerts
        guard !alerts.isEmpty else { return "" }
        let stamps = CryptoWatch.currencies(alerts).sorted().map { cur in
            "\(cur)=\(CryptoService.shared.updated(cur)?.timeIntervalSince1970 ?? 0)"
        }
        return (alerts.map(\.text) + stamps).joined(separator: ",")
    }

    private var offlineLine: some View {
        OfflineQuoteText(fetched: CryptoService.shared.updated(currency), now: context.now)
    }

    var body: some View {
        let shown = Array(ids.prefix(CryptoMarket.tileCoins))
        return WidgetSurface {
            Group {
                if context.position.isVertical { column(shown) } else { wide(shown) }
            }
            .opacity(stale ? OfflineQuote.staleOpacity : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(currency):\(ids.joined(separator: ",")):\(liveAlerts.map(\.text).joined(separator: ","))") {
            guard !context.isPreview else { return }
            CryptoService.shared.track(ids, currency: currency)
            // 提醒设在另一种计价下的，那种计价也去取价。
            let alerts = liveAlerts
            for cur in CryptoWatch.currencies(alerts) where cur != currency {
                CryptoService.shared.track(alerts.filter { $0.currency == cur }.map(\.coin), currency: cur)
            }
        }
        .task(id: alertKey) { checkAlerts() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("加密货币行情")
    }

    // MARK: Layouts

    /// 每币一列 96pt：币种圆标和代码、24 小时涨跌色块；价格；7 天迷你线，
    /// 虚线是 7 天前的价格，右下写 7 天涨跌。
    private func wide(_ shown: [String]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            coins(shown)
            // 断网时 7 天线让位给底行的说明。
            if stale { offlineLine }
        }
        .padding(.vertical, 4)
    }

    private func coins(_ shown: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(shown, id: \.self) { id in
                let quote = quote(id)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        badge(quote, id: id, size: 11)
                        Text(CryptoMarket.label(id: id, quote: quote))
                            .font(WidgetStyle.label(10))
                            .foregroundStyle(WidgetStyle.primary)
                        Spacer(minLength: 0)
                        ChangeChip(percent: quote?.change24h, colors: colors, size: 8)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                            .rollingValue(quote?.price)
                        Spacer(minLength: 0)
                        Text("24h")
                            .font(WidgetStyle.caption(7.5))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    if showsChart, !stale {
                        HStack(alignment: .bottom, spacing: 3) {
                            week(quote)
                                .frame(height: 12)
                            VStack(alignment: .trailing, spacing: -1) {
                                Text("7天")
                                    .font(WidgetStyle.caption(7))
                                    .foregroundStyle(WidgetStyle.secondary)
                                Text(CryptoMarket.changeText(quote?.change7d))
                                    .font(WidgetStyle.label(8.5))
                                    .foregroundStyle(weekInk(quote))
                                    .monospacedDigit()
                            }
                            .fixedSize()
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { hitGlow(id) }
            }
        }
    }

    /// 到价的币：一圈淡金色，打开面板就消失。
    @ViewBuilder
    private func hitGlow(_ id: String) -> some View {
        if hits.contains(id) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: "#F5C451").opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(hex: "#F5C451").opacity(0.7), lineWidth: 1)
                }
                .padding(.horizontal, -3)
                .padding(.vertical, -2)
                .accessibilityLabel(tr("已到提醒价"))
        }
    }

    /// 开着的提醒到价了：发通知、关掉这条、卡片上标出这个币。断网时的旧价不算。
    private func checkAlerts() {
        let alerts = liveAlerts
        guard !alerts.isEmpty else { return }
        let due = CryptoWatch.due(alerts) { coin, cur in
            guard !CryptoService.shared.isStale(cur) else { return nil }
            return CryptoService.shared.quote(coin, currency: cur)?.price
        }
        guard !due.isEmpty else { return }
        for alert in due {
            let quote = CryptoService.shared.quote(alert.coin, currency: alert.currency)
            let name = CryptoWatch.displayName(id: alert.coin, fallback: quote?.name)
            CryptoAlertNotifier.shared.post(alert, name: name, price: quote?.price ?? alert.price, widget: instance.id)
        }
        let saved = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(saved) { config in
            let all = CryptoWatch.alerts(config)
            CryptoWatch.writeAlerts(CryptoWatch.firing(due, in: all), into: &config)
            CryptoWatch.addingHits(due.map(\.coin), to: &config)
        }
    }

    /// 币种圆标：币自己的颜色，中间是首字母（比特币是 B，以太坊是 Ξ）。
    private func badge(_ quote: CryptoQuote?, id: String, size: CGFloat) -> some View {
        let symbol = CryptoMarket.label(id: id, quote: quote)
        return Text(CryptoMarket.badgeLetter(symbol))
            .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: CryptoMarket.badgeHex(symbol))))
            .accessibilityHidden(true)
    }

    private func week(_ quote: CryptoQuote?) -> some View {
        MiniTrend(samples: quote?.sparkline ?? [], tint: weekInk(quote),
                  baseline: quote?.sparkline.first, lineWidth: 1.1)
    }

    private func weekInk(_ quote: CryptoQuote?) -> Color {
        CryptoInk.color(CryptoMarket.tone(quote?.change7d, colors: colors), scheme: scheme)
    }

    private func column(_ shown: [String]) -> some View {
        VStack(spacing: 4) {
            ForEach(shown, id: \.self) { id in
                let quote = quote(id)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Text(CryptoMarket.label(id: id, quote: quote))
                            .font(WidgetStyle.label(9))
                            .foregroundStyle(WidgetStyle.secondary)
                        Spacer(minLength: 0)
                        Text(CryptoMarket.changeText(quote?.change24h))
                            .font(WidgetStyle.label(8))
                            .foregroundStyle(ink(quote))
                            .monospacedDigit()
                            .rollingValue(quote?.change24h)
                    }
                    Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                        .font(WidgetStyle.value(12))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(quote?.price)
                    if showsChart {
                        week(quote).frame(height: 10).padding(.top, 1)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { hitGlow(id) }
            }
            if stale { offlineLine }
        }
        .padding(.vertical, 4)
    }

    private func ink(_ quote: CryptoQuote?) -> Color {
        CryptoInk.color(CryptoMarket.tone(quote?.change24h, colors: colors), scheme: scheme)
    }
}

/// The two colours of a change, the Stock widgets' own so a rise in a coin
/// and a rise in a share are the same red (or green) on one shelf.
enum CryptoInk {
    static func color(_ tone: ChangeTone, scheme: ColorScheme) -> Color {
        StockInk.color(tone, scheme: scheme)
    }
}
