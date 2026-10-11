import SwiftUI

/// The panel behind Stripe, Paddle and Shopify.
///
/// One view rather than three near-copies: the three are the same widget with
/// different plumbing - an account, a metric, a period, an amount, a chart -
/// and the provider only decides which metrics and periods are on offer and
/// what the figure is called. Stripe's `revenue` is titled "Net revenue" on
/// Paddle; at this layer that is nearly the whole difference.
///
/// **No figure is drawn anywhere in here.** All three are network-backed (a
/// restricted Stripe key, Paddle's `metrics.read`, a Shopify custom app) and
/// this build ships no client for any of them: there is no series, no total
/// and no last refresh to report. A plausible amount under a real account name
/// is indistinguishable from a working widget, which is the one failure a
/// money readout cannot afford - so the panel states the connection instead,
/// and keeps only the labels that are genuinely knowable from the config.
struct RevenueDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // The provider's own colour, so a Stripe panel is recognisably
        // Stripe's before a word is read.
        DetailCard {
            MeshBackdrop(color: brand)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    accountRow
                    metricRow
                    Text(caption)
                        .font(WidgetStyle.caption(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                unconnected
                about
                    .padding(12)
                    .glassPane()
            }
        }
    }

    /// Stripe's blurple, Paddle's navy, Shopify's green.
    private var brand: Color {
        switch instance.kind {
        case .paddle: Color(hex: "#2B3A67")
        case .shopify: Color(hex: "#008060")
        default: Color(hex: "#635BFF")
        }
    }

    // MARK: Rows

    private var accountRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
            Text(account.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var metricRow: some View {
        HStack(spacing: 8) {
            Text(metricTitle)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(periodShort)
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
                .fixedSize()
        }
    }

    /// Where the amount and the chart belong. Dashed rather than filled: the
    /// box has to read as a slot nothing has arrived in, not as a card whose
    /// contents happen to be words.
    private var unconnected: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("未连接")
                .font(WidgetStyle.value(20))
                .foregroundStyle(WidgetStyle.primary)
            Text("Docket 没有保存任何 \(provider) 凭据，因此没有可显示的金额，也没有可绘制的历史数据。")
                .font(WidgetStyle.caption(12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            // Points at the panel's own settings button rather than repeating
            // it: the header already carries the only control that can reach
            // the widget's settings from here.
            Label("使用此面板顶部的设置按钮连接账户",
                  systemImage: "slider.horizontal.3")
                .font(WidgetStyle.label(11.5))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// What the figure would mean, which is worth saying whether or not the
    /// figure is there - and the one part of this panel that is fully known
    /// without an account.
    private var about: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("关于此指标")
                .font(WidgetStyle.label(12))
                .foregroundStyle(WidgetStyle.primary)
            Text(explanation)
                .font(WidgetStyle.caption(11.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Provider

    /// Spelled here rather than read from the catalog: these three kinds have
    /// no catalog entry yet, so `WidgetCatalog.entry` is nil for all of them.
    private var provider: String {
        switch instance.kind {
        case .paddle: "Paddle"
        case .shopify: "Shopify"
        default: "Stripe"
        }
    }

    private var account: String {
        let name = instance.config.string("account").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? provider : name
    }

    /// The widget's own swatch when it has one, otherwise the colour the panel
    /// is already tinted with, so the dot and the glass agree.
    private var accent: Color {
        if let picked = PaletteColor(rawValue: instance.config.string("color")) {
            return Color(hex: picked.hex)
        }
        return WidgetCatalog.accentHex(instance.kind).map { Color(hex: $0) } ?? WidgetStyle.primary
    }

    // MARK: Metric

    private var metric: String {
        instance.config.string("metric", default: instance.kind == .shopify ? "sales" : "revenue")
    }

    private var metricTitle: String {
        // Paddle calls its `revenue` "Net revenue"; every other raw value
        // means the same on whichever provider offers it.
        if metric == "revenue", instance.kind == .paddle { return "净收入" }
        return switch metric {
        case "revenue": "收入"
        case "net": "净收入"
        case "mrr": "MRR"
        case "arr": "ARR"
        case "subscribers": "订阅者"
        case "arpu": "ARPU"
        case "sales": "销售额"
        case "netSales": "净销售额"
        case "orders": "订单"
        case "averageOrderValue": "平均订单金额"
        case "returns": "退货"
        case "visitors": "访客"
        case "sessions": "会话"
        case "pageviews": "页面浏览量"
        case "conversionRate": "转化率"
        case "addedToCart": "加入购物车"
        case "reachedCheckout": "进入结账"
        case "completedCheckout": "完成结账"
        // A metric this build predates still deserves a readable name.
        default: WidgetCatalog.optionLabel(metric)
        }
    }

    /// Metrics that report a level rather than a total. They have no period to
    /// sum over, so they say "now" where the others name a window.
    private var isLevel: Bool {
        ["mrr", "arr", "subscribers", "arpu", "averageOrderValue", "conversionRate"]
            .contains(metric)
    }

    /// Stripe is the only provider that pins a currency in the widget; Paddle
    /// and Shopify report in the account's own, which is unknowable until one
    /// is connected. Head counts are not money on any of them.
    private var currency: String? {
        guard instance.kind == .stripe, metric != "subscribers" else { return nil }
        return instance.config.string("currency", default: "USD")
    }

    // MARK: Period

    private var period: String {
        instance.config.string("period", default: "month")
    }

    private var periodShort: String {
        if isLevel { return instance.kind == .paddle ? "最新" : "当前" }
        return switch period {
        case "today": "今天"
        case "week": "近7天"
        case "month": "本月"
        case "thirtyDays": "近30天"
        case "fourWeeks": "近4周"
        case "sixtyDays": "近60天"
        case "ninetyDays": "近90天"
        case "sixMonths": "近6月"
        case "twelveMonths": "近12月"
        case "quarter": "本季"
        case "year": "本年"
        case "lastYear": "近365天"
        case "allTime": "全部"
        default: "-"
        }
    }

    private var periodName: String {
        if isLevel { return instance.kind == .paddle ? "最新报告" : "当前" }
        return switch period {
        case "today": "今天"
        case "week": "最近 7 天"
        case "month": "本月至今"
        case "thirtyDays": "最近 30 天"
        case "fourWeeks": "最近 4 周"
        case "sixtyDays": "最近 60 天"
        case "ninetyDays": "最近 90 天"
        case "sixMonths": "最近 6 个月"
        case "twelveMonths": "最近 12 个月"
        case "quarter": "本季度至今"
        case "year": "本年至今"
        case "lastYear": "最近 365 天"
        case "allTime": "全部时间"
        default: "自定义时段"
        }
    }

    /// The dates the period actually spans, off `context.now`. The window is
    /// real even when the figures inside it are missing, and it is the only
    /// way to tell "Last 30 days" from "Month to date" on the second of a
    /// month. A level metric has no window, and "all time" has no start.
    private var range: (start: Date, end: Date)? {
        guard !isLevel else { return nil }
        let calendar = Calendar.current
        let now = context.now
        // Inclusive of today, so a 7-point week starts six days back.
        func back(_ points: Int) -> Date? {
            calendar.date(byAdding: .day, value: -(points - 1), to: now)
        }
        let start: Date? = switch period {
        case "today": calendar.dateInterval(of: .day, for: now)?.start
        case "week": back(7)
        case "month": calendar.dateInterval(of: .month, for: now)?.start
        case "thirtyDays": back(30)
        case "fourWeeks": back(28)
        case "sixtyDays": back(60)
        case "ninetyDays": back(90)
        case "sixMonths": back(180)
        case "twelveMonths", "lastYear": back(365)
        case "quarter": calendar.dateInterval(of: .quarter, for: now)?.start
        case "year": calendar.dateInterval(of: .year, for: now)?.start
        default: nil
        }
        return start.map { (start: $0, end: now) }
    }

    // MARK: Copy

    private var caption: String {
        var parts = [periodName]
        if let range {
            let start = range.start.formatted(.dateTime.month(.abbreviated).day())
            let end = range.end.formatted(.dateTime.month(.abbreviated).day())
            // A period that begins today is one date, not a range of one.
            parts.append(start == end ? start : "\(start) – \(end)")
        }
        if let currency { parts.append(currency) }
        return parts.joined(separator: " · ")
    }

    private var explanation: String {
        // Stripe and Paddle break today down by the hour; everything else,
        // Shopify included, is a point per day.
        let grain = period == "today" && instance.kind != .shopify ? "按小时统计的" : "按天统计的"
        let headline = isLevel
            ? "“\(metricTitle)”是序列中的最新数据点而非合计，即上次刷新时的水平。"
            : "“\(metricTitle)”是\(periodName)内所有\(grain)数据点的合计。"
        return headline + "扩展栏显示在屏幕上时，已连接的账户每五分钟刷新一次。"
    }
}
