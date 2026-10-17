import SwiftUI

/// Every configured coin with its name, price, 24-hour change and a larger
/// 24-hour line, a switch between 人民币 and 美元, and the credit CoinGecko's
/// terms ask for wherever its prices are shown.
struct CryptoDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// The currency as the panel has it: a config write does not come back
    /// into an open panel, so without this the switch would not move.
    @State private var picked: String?

    private var ids: [String] { CryptoMarket.coinIDs(instance.config) }
    private var currency: String { picked ?? CryptoMarket.currency(instance.config) }
    private var colors: ChangeColors { ChangeColors.from(instance.config) }

    private func quote(_ id: String) -> CryptoQuote? {
        context.isPreview ? .preview(id, currency: currency) : CryptoService.shared.quote(id, currency: currency)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                VStack(spacing: 6) {
                    ForEach(ids, id: \.self) { id in row(id) }
                }
                footer
            }
        }
        .onAppear { track() }
        .onChange(of: currency) { _, _ in track() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("加密货币行情")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(currency == "usd" ? tr("美元计价") : tr("人民币计价"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Picker("", selection: Binding(get: { currency }, set: { choose($0) })) {
                Text("CNY").tag("cny")
                Text("USD").tag("usd")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(context.isPreview)
        }
    }

    private func row(_ id: String) -> some View {
        let quote = quote(id)
        let tone = CryptoMarket.tone(quote?.change24h, colors: colors)
        let ink = CryptoInk.color(tone, scheme: .dark)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CryptoMarket.label(id: id, quote: quote))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.white)
                Text(quote?.name ?? tr("暂无数据"))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 72, alignment: .leading)
            DitherChart(samples: quote?.sparkline ?? [], tint: ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            VStack(alignment: .trailing, spacing: 2) {
                Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .rollingValue(quote?.price)
                Text(CryptoMarket.changeText(quote?.change24h))
                    .font(WidgetStyle.label(11))
                    .foregroundStyle(tone == .neutral ? Color.white.opacity(0.7) : .white)
                    .monospacedDigit()
                    .rollingValue(quote?.change24h)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(tone == .neutral ? Color.white.opacity(0.12) : ink.opacity(0.8)))
            }
            .frame(width: 96, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassPane(cornerRadius: 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !context.isPreview, CryptoService.shared.isStale(currency) {
                Text("刷新失败，显示的是上次成功获取的价格。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 6) {
                Link(CryptoMarket.attribution, destination: CryptoMarket.attributionURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(updatedLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }
            Text("涨跌幅为 24 小时，走势线为最近 24 小时；每 5 分钟最多刷新一次。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updatedLine: String {
        if context.isPreview { return tr("示例数据") }
        guard let date = CryptoService.shared.updated(currency) else { return tr("尚未获取") }
        return tr("更新于 ") + date.formatted(date: .omitted, time: .shortened)
    }

    private func choose(_ value: String) {
        guard !context.isPreview else { return }
        picked = value
        WidgetWriter.write(instance) { config in config.set("currency", .string(value)) }
    }

    private func track() {
        guard !context.isPreview else { return }
        CryptoService.shared.track(ids, currency: currency)
    }

    private var accent: Color {
        Color(hex: WidgetCatalog.accentHex(.crypto) ?? PaletteColor.yellow.hex)
    }
}
