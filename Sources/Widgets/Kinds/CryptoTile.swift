import SwiftUI

/// A few coins side by side, 96pt each: the coin's round badge, ticker and a
/// solid 24-hour chip over the price, with the seven-day line under them.
///
/// Built like the Watchlist tile (a column per symbol on the shelf, a row per
/// symbol in the side column) and fed by `CryptoService`, which keeps the
/// last good prices and fades them when a refresh fails. Rises and falls are
/// red and green the Chinese way round unless the widget's 涨跌颜色 says
/// otherwise. The card has no controls; its click opens the panel.
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

    /// 断网时底行那句「离线 · 10:32 的价」。
    private var offlineText: String {
        OfflineQuote.label(fetched: CryptoService.shared.updated(currency), now: .now)
    }

    private var offlineLine: some View {
        Text(offlineText)
            .font(WidgetStyle.label(9))
            .foregroundStyle(WidgetStyle.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
        .task(id: "\(currency):\(ids.joined(separator: ","))") {
            guard !context.isPreview else { return }
            CryptoService.shared.track(ids, currency: currency)
        }
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
            }
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
