import SwiftUI

/// 自选股：管一组对比。一眼看出谁领涨、谁拖后腿，这一组今天赚没赚。
///
/// 宽卡片顶部是分组名（有多个分组时点一下换下一个）、“涨 5 跌 3”和红绿比例条，
/// 填了持仓时右边是今日盈亏；下面两列、每列两行（行高 18pt，字不小于 9.5pt），
/// 按涨跌幅从高到低（也可按填写顺序），每行是代码、当日迷你走势、现价和涨跌幅色块，
/// 幅度越大色块越深。放不下时最后一格写“还有 N 只”，点开面板或点分组名翻看其余的。
/// 竖排扩展栏只放涨跌统计和代码加色块。
///
/// 涨跌颜色跟设置走，默认红涨绿跌；黄金白银按设置的单位显示，默认元/克。
struct WatchlistTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    private var group: StockBoard.Group { StockBoard.currentGroup(instance.config) }
    private var groupCount: Int { StockBoard.groups(instance.config).count }
    private var unit: PreciousMetal.DisplayUnit { .from(instance.config) }
    private var colors: ChangeColors { StockBoard.colors(instance.config) }
    private var order: StockBoard.Order { .from(instance.config) }

    private func quote(_ symbol: String) -> StockQuote? {
        StockDisplay.quote(symbol, preview: context.isPreview, unit: unit)
    }

    /// 这一组按设置排好的代码。
    private func ordered(_ symbols: [String]) -> [String] {
        var percents: [String: Double] = [:]
        for symbol in symbols {
            if let quote = quote(symbol) { percents[symbol] = quote.changePercent }
        }
        return StockBoard.sorted(symbols, percents: percents, order: order)
    }

    var body: some View {
        let symbols = ordered(group.symbols)
        let tracked = StockDisplay.tracked(group.symbols, unit: unit)
        WidgetSurface {
            Group {
                if context.position.isVertical { column(symbols) } else { wide(symbols) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: tracked) {
            guard !context.isPreview else { return }
            StockService.shared.track(tracked)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("自选股 \(group.name)"))
    }

    // MARK: 宽卡片

    /// 最小字号，见 `StockBoard.watchlistMinFontSize`。
    private static let font = CGFloat(StockBoard.watchlistMinFontSize)

    private func wide(_ symbols: [String]) -> some View {
        let fit = StockBoard.fit(count: symbols.count, capacity: StockBoard.watchlistCapacity)
        let shown = Array(symbols.prefix(fit.shown))
        let perColumn = StockBoard.watchlistRowsPerColumn
        return VStack(alignment: .leading, spacing: CGFloat(StockBoard.watchlistHeaderSpacing)) {
            header(symbols)
                .frame(height: CGFloat(StockBoard.watchlistHeaderHeight))
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<2, id: \.self) { columnIndex in
                    VStack(spacing: 0) {
                        ForEach(0..<perColumn, id: \.self) { rowIndex in
                            let slot = columnIndex * perColumn + rowIndex
                            Group {
                                if slot < shown.count {
                                    row(shown[slot])
                                } else if slot == shown.count, fit.hidden > 0 {
                                    Text(StockBoard.moreText(fit.hidden))
                                        .font(WidgetStyle.caption(Self.font))
                                        .foregroundStyle(WidgetStyle.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: CGFloat(StockBoard.watchlistRowHeight))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, CGFloat(StockBoard.watchlistVerticalPadding))
    }

    private func header(_ symbols: [String]) -> some View {
        let breadth = StockBoard.breadth(symbols.map { quote($0)?.changePercent })
        return HStack(spacing: 6) {
            groupName
            breadthText(breadth, size: Self.font)
            BreadthBar(breadth: breadth, colors: colors, height: 3)
                .frame(width: 36)
            Spacer(minLength: 0)
            if let offline = offlineText(symbols) {
                // 断网时右上角写「离线 · 10:32 的价」，盈亏用的是旧价，先不显示。
                Text(offline)
                    .font(WidgetStyle.label(Self.font))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            } else {
                profit(symbols)
            }
        }
        .lineLimit(1)
    }

    /// 这一组里有过期的报价时的那句话，时间取最早的那只。
    private func offlineText(_ symbols: [String]) -> String? {
        guard !context.isPreview else { return nil }
        let stale = symbols.compactMap { quote($0) }.filter(\.stale)
        guard !stale.isEmpty else { return nil }
        return OfflineQuote.label(fetched: OfflineQuote.oldest(stale.map(\.fetchedAt)), now: .now)
    }

    /// 分组名。只有一个分组时就是个标题；多个时点一下换下一个分组。
    @ViewBuilder
    private var groupName: some View {
        let label = Text(group.name)
            .font(WidgetStyle.label(9.5))
            .foregroundStyle(WidgetStyle.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 0.5)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
        if groupCount > 1, !context.isPreview {
            Button(action: { nextGroup() }) {
                HStack(spacing: 2) {
                    label
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点一下换下一个分组"))
            .accessibilityLabel(tr("换下一个分组"))
        } else {
            label
        }
    }

    private func breadthText(_ breadth: StockBoard.Breadth, size: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text(tr("涨 \(breadth.up)"))
                .foregroundStyle(StockInk.color(rising: true, colors: colors, scheme: scheme))
            Text(tr("跌 \(breadth.down)"))
                .foregroundStyle(StockInk.color(rising: false, colors: colors, scheme: scheme))
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
    }

    /// 今日盈亏：填了持仓才显示，没填这一块收起。
    @ViewBuilder
    private func profit(_ symbols: [String]) -> some View {
        let holdings = StockBoard.holdings(instance.config)
        if !holdings.isEmpty, let first = StockBoard.todayProfit(positions(symbols), holdings: holdings).first {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("今日")
                    .font(WidgetStyle.caption(Self.font))
                    .foregroundStyle(WidgetStyle.secondary)
                Text(StockBoard.profitText(first))
                    .font(WidgetStyle.label(9.5))
                    .foregroundStyle(StockInk.color(first.amount, colors: colors, scheme: scheme))
                    .monospacedDigit()
                    .rollingValue(StockBoard.profitText(first))
            }
        }
    }

    /// 算盈亏用的报价：黄金白银换成元/克时货币记成人民币。
    private func positions(_ symbols: [String]) -> [StockBoard.Position] {
        symbols.compactMap { symbol in
            guard let quote = quote(symbol), !quote.stale else { return nil }
            let unitLabel = StockDisplay.unitLabel(symbol, preview: context.isPreview, unit: unit)
            let currency = unitLabel == PreciousMetal.DisplayUnit.cnyPerGram.title ? "CNY" : quote.currency
            return StockBoard.Position(symbol: symbol, price: quote.price, change: quote.change, currency: currency)
        }
    }

    private func row(_ symbol: String) -> some View {
        let quote = quote(symbol)
        let ink = StockInk.color(quote?.changePercent, colors: colors, scheme: scheme)
        // 不缩字：放不下时代码截断，现价和涨跌幅保持 9.5pt。
        return HStack(spacing: 3) {
            Text(StockBoard.displaySymbol(symbol))
                .font(WidgetStyle.label(Self.font))
                .foregroundStyle(WidgetStyle.primary)
                .truncationMode(.tail)
                .frame(width: 36, alignment: .leading)
            MiniTrend(samples: quote?.history ?? [], tint: ink, baseline: quote?.previousClose, lineWidth: 1)
                .frame(width: 18, height: 10)
            Spacer(minLength: 0)
            Text(StockBoard.priceText(quote?.price))
                .font(WidgetStyle.caption(Self.font))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .layoutPriority(1)
                .rollingValue(StockBoard.priceText(quote?.price))
            ChangeChip(percent: quote?.changePercent, colors: colors, size: Self.font, minWidth: 40,
                       minimumScale: 1)
                .layoutPriority(1)
        }
        .lineLimit(1)
        .opacity(quote?.stale == true ? OfflineQuote.staleOpacity : 1)
    }

    // MARK: 竖排

    private func column(_ symbols: [String]) -> some View {
        let breadth = StockBoard.breadth(symbols.map { quote($0)?.changePercent })
        let fit = StockBoard.fit(count: symbols.count, capacity: StockBoard.watchlistColumnCapacity)
        return VStack(alignment: .leading, spacing: 2) {
            breadthText(breadth, size: 8.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            BreadthBar(breadth: breadth, colors: colors, height: 2.5)
            ForEach(Array(symbols.prefix(fit.shown)), id: \.self) { symbol in
                let quote = quote(symbol)
                HStack(spacing: 2) {
                    Text(StockBoard.displaySymbol(symbol))
                        .font(WidgetStyle.label(8.5))
                        .foregroundStyle(WidgetStyle.primary)
                    Spacer(minLength: 0)
                    ChangeChip(percent: quote?.changePercent, colors: colors, size: 7.5)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 16)
                .opacity(quote?.stale == true ? OfflineQuote.staleOpacity : 1)
            }
            if fit.hidden > 0 {
                Text(StockBoard.moreText(fit.hidden))
                    .font(WidgetStyle.caption(7.5))
                    .foregroundStyle(WidgetStyle.secondary)
                    .frame(height: 16)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: 分组

    private func nextGroup() {
        let current = WidgetWriter.current(instance.id) ?? instance
        let next = StockBoard.nextGroupName(current.config)
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { config in config.set("group", .string(next)) }
        }
    }
}
