import SwiftUI

/// A few coins side by side: ticker and 24-hour change over the price, with
/// a small 24-hour line under them.
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

    var body: some View {
        let shown = Array(ids.prefix(CryptoMarket.tileCoins))
        return WidgetSurface {
            Group {
                if context.position.isVertical { column(shown) } else { wide(shown) }
            }
            .opacity(stale ? 0.55 : 1)
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

    private func wide(_ shown: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(shown, id: \.self) { id in
                let quote = quote(id)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(CryptoMarket.label(id: id, quote: quote))
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(WidgetStyle.primary)
                        Spacer(minLength: 0)
                        Text(CryptoMarket.changeText(quote?.change24h))
                            .font(WidgetStyle.label(9))
                            .foregroundStyle(ink(quote))
                            .monospacedDigit()
                            .rollingValue(quote?.change24h)
                    }
                    Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(quote?.price)
                    if showsChart {
                        spark(quote).frame(height: 12)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                        spark(quote).frame(height: 10).padding(.top, 1)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func spark(_ quote: CryptoQuote?) -> some View {
        DitherChart(samples: quote?.sparkline ?? [], tint: ink(quote), filled: false, lineWidth: 1.1)
    }

    private func ink(_ quote: CryptoQuote?) -> Color {
        CryptoInk.color(CryptoMarket.tone(quote?.change24h, colors: colors), scheme: scheme)
    }
}

/// The two colours of a change, borrowed from the Stock widgets so a rise in
/// a coin and a rise in a share are the same red (or green) on one shelf.
enum CryptoInk {
    static func color(_ tone: ChangeTone, scheme: ColorScheme) -> Color {
        switch tone {
        case .green: StockInk.accent(rising: true, scheme: scheme)
        case .red: StockInk.accent(rising: false, scheme: scheme)
        case .neutral: WidgetStyle.secondary
        }
    }
}
