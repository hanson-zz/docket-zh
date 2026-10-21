import AppKit
import SwiftUI

/// 股票和自选股的面板。
///
/// 股票：正在看的一只看细节：大号价格和涨跌、当日分时（昨收虚线、成交量、提醒价
/// 橙线）、昨收和成交量，在这里设到价提醒（高于或低于，可多条）；设了多只时顶部可以
/// 点着换。自选股：一组看对比：分组切换和新建分组、涨跌统计和比例条、今日盈亏（填了
/// 持仓才有）、排序方式，下面是这一组的每一只。黄金白银可以在这里切元/克和美元/盎司。
///
/// 改动立刻写回小组件设置，面板自己也留一份，因为写回的设置不会回到已经打开的面板。
struct StocksDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    @Environment(\.colorScheme) private var scheme
    var instance: WidgetInstance
    var context: WidgetContext

    /// 面板里改过的设置。nil 时就是小组件自己的。
    @State private var edited: WidgetConfig?
    @State private var alertText = ""
    @State private var editingGroup = false
    @State private var groupName = ""
    @State private var groupCodes = ""
    /// 面板里的「编辑」：搜索添加、删除、排序、填持仓（见 `StockSymbolEditor`）。
    @State private var editingList = false

    private var config: WidgetConfig { edited ?? instance.config }
    private var colors: ChangeColors { StockBoard.colors(config) }
    private var unit: PreciousMetal.DisplayUnit { .from(config) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: backdropColour, fixed: true)
        } content: {
            if instance.kind == .watchlist {
                watchlist
            } else {
                single
            }
        }
        .onAppear { track() }
    }

    /// 底色跟着今天的涨跌走，颜色和卡片同一个设置：红涨绿跌时涨是红底。
    private var backdropColour: Color {
        let move: Double?
        if instance.kind == .watchlist {
            let moves = StockBoard.currentGroup(config).symbols.compactMap { quote($0)?.changePercent }
            move = moves.isEmpty ? nil : moves.reduce(0, +)
        } else {
            move = quote(symbol)?.changePercent
        }
        switch StockBoard.tone(move, colors: colors) {
        case .red: return Color(red: 0.7, green: 0.18, blue: 0.2)
        case .green: return Color(red: 0.1, green: 0.55, blue: 0.35)
        case .neutral: return Color(red: 0.3, green: 0.32, blue: 0.36)
        }
    }

    // MARK: 数据

    private var rotation: [String] { StockBoard.rotation(config) }

    private var symbol: String {
        let saved = StockBoard.normalised(config.string("symbol", default: ""))
        return rotation.contains(saved) ? saved : rotation[0]
    }

    private func quote(_ symbol: String) -> StockQuote? {
        StockDisplay.quote(symbol, preview: context.isPreview, unit: unit)
    }

    private func ink(_ percent: Double?) -> Color {
        StockInk.color(percent, colors: colors, scheme: scheme)
    }

    private func update(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        var next = config
        change(&next)
        edited = next
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance, change)
    }

    /// 卡片已经在取这些代码了；面板里新加的提醒或分组可能还没有，补一次。
    private func track() {
        guard !context.isPreview else { return }
        let symbols: [String]
        if instance.kind == .watchlist {
            symbols = StockBoard.groups(config).flatMap(\.symbols)
        } else {
            symbols = rotation + StockBoard.alerts(config).map(\.symbol)
        }
        StockService.shared.track(StockDisplay.tracked(StockBoard.unique(symbols), unit: unit))
    }

    private var hasMetal: Bool {
        let symbols = instance.kind == .watchlist
            ? StockBoard.groups(config).flatMap(\.symbols) : rotation
        return symbols.contains { PreciousMetal(symbol: $0) != nil }
    }

    // MARK: 股票

    private var single: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if rotation.count > 1 { symbolPicker } else { Spacer(minLength: 0) }
                editButton
            }
            if editingList {
                symbolEditor
            } else {
                singleBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var singleBody: some View {
        if let quote = quote(symbol) {
            if quote.stale { staleNote(quote.fetchedAt) }
            identity(quote)
            price(quote)
            change(quote)
            chart(quote)
            stats(quote)
        } else {
            unavailable(symbol)
        }
        if hasMetal { unitPicker }
        alertSection
    }

    // MARK: 编辑代码

    private var isWatchlist: Bool { instance.kind == .watchlist }

    /// 「编辑」和「完成」：编辑时是实心的深色字按钮。
    private var editButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { editingList.toggle() }
            if !editingList { track() }
        } label: {
            Text(editingList ? tr("完成") : tr("编辑"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editingList ? Color.panelOnPrimary : Color.panelPrimary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if editingList {
                        Capsule().fill(Color.panelPrimary.opacity(0.92))
                    } else {
                        Capsule().strokeBorder(Color.panelQuaternary, lineWidth: 0.8)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(isWatchlist ? tr("添加、删除、排序这一组的股票，填持仓") : tr("添加、删除、排序轮播的股票"))
    }

    private var symbolEditor: some View {
        let watchlist = isWatchlist
        return StockSymbolEditor(
            symbols: StockBoard.editingSymbols(config, watchlist: watchlist),
            holdings: watchlist ? StockBoard.holdingEntries(config) : nil,
            accent: panelTint.accent(or: Color(hex: WidgetCatalog.accentHex(instance.kind) ?? PaletteColor.green.hex)),
            isPreview: context.isPreview,
            subtitle: { symbol in
                StockDisplay.subtitle(symbol, quote: quote(symbol), preview: context.isPreview, unit: unit)
            },
            onAdd: { symbol in
                update { config in
                    if let next = StockBoard.addingSymbol(symbol, to: config, watchlist: watchlist) { config = next }
                }
                track()
            },
            onRemove: { symbol in
                update { config in
                    let list = StockBoard.editingSymbols(config, watchlist: watchlist)
                    guard StockBoard.canRemove(count: list.count) else { return }
                    let key = StockBoard.normalised(symbol)
                    config = StockBoard.settingSymbols(list.filter { $0 != key }, in: config, watchlist: watchlist)
                }
            },
            onMove: { from, to in
                update { config in
                    let list = StockBoard.editingSymbols(config, watchlist: watchlist)
                    config = StockBoard.settingSymbols(StockBoard.moved(list, from: from, to: to),
                                                       in: config, watchlist: watchlist)
                    // 按涨跌幅排时拖了也看不出来：拖过就改成按填写顺序。
                    if watchlist, StockBoard.Order.from(config) == .change {
                        config.set("sort", .string(StockBoard.Order.custom.rawValue))
                    }
                }
            },
            onHolding: { symbol, holding in
                update { config in
                    let list = StockBoard.settingHolding(symbol, holding, in: config)
                    config.set("holdings", .list(list.map { .string($0) }))
                }
            })
    }

    /// 设了多只时顶部一排代码，点哪只看哪只，卡片也跟着换。
    private var symbolPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(rotation, id: \.self) { item in
                    Button {
                        update { $0.set("symbol", .string(item)) }
                    } label: {
                        Text(StockBoard.displaySymbol(item))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(item == symbol ? Color.panelOnPrimary : Color.panelPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(item == symbol ? Color.panelPrimary : Color.panelSelected))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func identity(_ quote: StockQuote) -> some View {
        let subtitle = StockDisplay.subtitle(symbol, quote: quote, preview: context.isPreview, unit: unit)
        let session = StockBoard.session(now: .now, start: quote.sessionStart, end: quote.sessionEnd)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(StockBoard.displaySymbol(symbol))
                .font(WidgetStyle.label(15))
                .foregroundStyle(.panelPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
            }
            Spacer(minLength: 0)
            if session != .unknown {
                Text(session.title)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
            }
        }
        .lineLimit(1)
    }

    private func price(_ quote: StockQuote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(StockBoard.priceText(quote.price))
                .font(WidgetStyle.value(44))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .rollingValue(quote.price)
            // 卡片上没地方写币种，海外上市的会被当成美元；面板写出来。
            Text(StockDisplay.unitLabel(symbol, preview: context.isPreview, unit: unit) ?? quote.currency)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func change(_ quote: StockQuote) -> some View {
        HStack(spacing: 5) {
            Text(StockBoard.changeText(quote.change))
                .monospacedDigit()
                .rollingValue(quote.change)
            Text(StockBoard.percentText(quote.changePercent))
                .monospacedDigit()
                .rollingValue(quote.changePercent)
        }
        .font(WidgetStyle.label(13))
        .foregroundStyle(.panelPrimary)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(ink(quote.changePercent).opacity(0.55), in: .capsule)
    }

    @ViewBuilder
    private func chart(_ quote: StockQuote) -> some View {
        if quote.history.filter(\.isFinite).count >= 2 {
            let alert = StockBoard.nearestAlert(for: symbol, price: quote.price, in: checkableAlerts)
            IntradayChart(quote: quote,
                          tint: ink(quote.changePercent),
                          alert: alert?.price,
                          showsVolume: true,
                          upInk: StockInk.color(rising: true, colors: colors, scheme: scheme),
                          downInk: StockInk.color(rising: false, colors: colors, scheme: scheme),
                          lineWidth: 1.8,
                          guide: .panelPrimary)
                .frame(height: 120)
                .padding(.top, 4)
        }
    }

    private func stats(_ quote: StockQuote) -> some View {
        HStack(spacing: 14) {
            stat(tr("昨收"), StockBoard.priceText(quote.previousClose))
            stat(tr("成交量"), StockBoard.volumeText(quote.volume))
            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
            Text(value)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
        }
    }

    // MARK: 到价提醒

    /// 1 美元换多少人民币，还没取到时是 nil。
    private var usdToCny: Double? { StockDisplay.usdToCny(preview: context.isPreview) }

    /// 能拿显示的价去比的提醒（黄金白银切了单位、提醒价还没换过去的先不算）。
    private var checkableAlerts: [StockBoard.Alert] {
        let rate = usdToCny
        return StockBoard.alerts(config).filter { PreciousMetal.canCheck($0, config: config, usdToCny: rate) }
    }

    private var alertSection: some View {
        let mine = StockBoard.alerts(config).filter { $0.symbol == symbol }
        let checkable = Set(checkableAlerts)
        let current = quote(symbol)?.price
        return VStack(alignment: .leading, spacing: 6) {
            Text("到价提醒")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.panelSecondary)
            NotificationsOffNote(active: NotificationAccess.stockUsesNotifications(
                alertCount: StockBoard.alerts(config).count), preview: context.isPreview)
            ForEach(mine, id: \.self) { alert in
                HStack(spacing: 8) {
                    Circle().fill(StockInk.alert).frame(width: 6, height: 6)
                    Text(alert.above
                         ? tr("涨到 \(StockBoard.priceText(alert.price))")
                         : tr("跌到 \(StockBoard.priceText(alert.price))"))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                    Text(StockBoard.distanceText(alert, price: checkable.contains(alert) ? current : nil))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(StockInk.alert)
                    Spacer(minLength: 0)
                    Button {
                        removeAlert(alert)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.panelSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(tr("删除这条提醒"))
                    .disabled(context.isPreview)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassPane(cornerRadius: 9)
            }
            HStack(spacing: 8) {
                TextField("", text: $alertText, prompt: Text("提醒价，比如 237"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit { addAlert() }
                Button("添加") { addAlert() }
                    .disabled(context.isPreview || Double(alertText.replacingOccurrences(of: ",", with: "")) == nil)
                Spacer(minLength: 0)
            }
            Text("高于现价是涨到提醒，低于现价是跌到提醒；到价时发一次系统通知，卡片闪一下橙边。黄金白银按面板上显示的单位。")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func addAlert() {
        let raw = alertText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        // 黄金白银的提醒价按记账的单位存：输入的是现在显示的单位，换过去；换不过去
        // （切了单位、汇率还没到）时先不加。
        let rate = usdToCny
        guard let entered = Double(raw),
              let target = PreciousMetal.storedAlertPrice(entered, symbol: symbol, config: config, usdToCny: rate)
        else {
            NSSound.beep()
            return
        }
        let current = (quote(symbol)?.price).flatMap {
            PreciousMetal.storedAlertPrice($0, symbol: symbol, config: config, usdToCny: rate)
        }
        guard let alert = StockBoard.makeAlert(symbol: symbol, target: target, current: current) else { return }
        update { config in
            var list = config.strings("alerts", default: [])
            if !StockBoard.alerts(config).contains(alert) { list.append(alert.text) }
            config.set("alerts", .list(list.map { .string($0) }))
        }
        alertText = ""
        track()
    }

    private func removeAlert(_ alert: StockBoard.Alert) {
        update { config in
            let list = config.strings("alerts", default: []).filter { StockBoard.Alert.parse($0) != alert }
            config.set("alerts", .list(list.map { .string($0) }))
            let fired = StockBoard.prunedFired(config.strings("alertsFired", default: []),
                                               alerts: list.compactMap(StockBoard.Alert.parse))
            config.set("alertsFired", .list(fired.map { .string($0) }))
        }
    }

    // MARK: 黄金白银单位

    private var unitPicker: some View {
        HStack {
            Text("黄金白银")
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
            Picker("", selection: Binding(
                get: { unit },
                // 提醒价跟着换算过去，见 `PreciousMetal.switching`。
                set: { value in
                    let rate = usdToCny
                    update { $0 = PreciousMetal.switching($0, to: value, usdToCny: rate) }
                })) {
                ForEach(PreciousMetal.DisplayUnit.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(panelTint.control)
            .labelsHidden()
            .fixedSize()
            .disabled(context.isPreview)
            Spacer(minLength: 0)
        }
    }

    // MARK: 自选股

    private var watchlist: some View {
        let group = StockBoard.currentGroup(config)
        var percents: [String: Double] = [:]
        for symbol in group.symbols {
            if let quote = quote(symbol) { percents[symbol] = quote.changePercent }
        }
        let symbols = StockBoard.sorted(group.symbols, percents: percents, order: .from(config))
        let quotes = symbols.map { quote($0) }
        let staleTimes = quotes.compactMap { $0 }.filter(\.stale).map(\.fetchedAt)
        return VStack(alignment: .leading, spacing: 8) {
            if !staleTimes.isEmpty { staleNote(OfflineQuote.oldest(staleTimes)) }
            HStack(spacing: 8) {
                groupBar(current: group)
                editButton
            }
            if editingGroup { groupEditor }
            if editingList {
                symbolEditor
            } else {
                watchlistBody(symbols, quotes: quotes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func watchlistBody(_ symbols: [String], quotes: [StockQuote?]) -> some View {
        summary(symbols, quotes: quotes)
        HStack {
            Picker("", selection: Binding(
                get: { StockBoard.Order.from(config) },
                set: { value in update { $0.set("sort", .string(value.rawValue)) } })) {
                ForEach(StockBoard.Order.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(panelTint.control)
            .labelsHidden()
            .fixedSize()
            .disabled(context.isPreview)
            Spacer(minLength: 0)
        }
        VStack(spacing: 6) {
            ForEach(symbols.indices, id: \.self) { index in
                row(symbols[index], quote: quotes[index])
            }
        }
        if hasMetal { unitPicker }
    }

    /// 分组：点名字换过去，卡片也跟着换；最后是“＋ 分组”。
    private func groupBar(current: StockBoard.Group) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(StockBoard.groups(config), id: \.name) { item in
                    Button {
                        update { $0.set("group", .string(item.name)) }
                    } label: {
                        Text(item.name)
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(item.name == current.name ? Color.panelOnPrimary : Color.panelPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(item.name == current.name ? Color.panelPrimary : Color.panelSelected))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑这个分组") { startEditing(item) }
                        if StockBoard.groups(config).count > 1 {
                            Button("删除这个分组", role: .destructive) {
                                update { config in
                                    let left = StockBoard.removing(item.name, in: config)
                                    config.set("groups", .list(left.map { .string($0) }))
                                }
                            }
                        }
                    }
                }
                Button {
                    startEditing(nil)
                } label: {
                    Label("分组", systemImage: "plus")
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.panelQuaternary, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .help(tr("新建分组，比如 科技、A股"))
            }
        }
        .scrollIndicators(.never)
    }

    private func startEditing(_ group: StockBoard.Group?) {
        groupName = group?.name ?? ""
        groupCodes = group?.symbols.joined(separator: " ") ?? ""
        editingGroup = true
    }

    /// 新建或修改分组：名字，一串代码（空格隔开），黄金白银一点就加。
    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("", text: $groupName, prompt: Text("分组名，比如 科技"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                TextField("", text: $groupCodes, prompt: Text("代码，空格隔开：NVDA TSLA 600519.SS"))
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 6) {
                ForEach(PreciousMetal.allCases, id: \.self) { metal in
                    Button(tr("＋ \(metal.title)")) {
                        let codes = groupCodes.split(separator: " ").map(String.init)
                        if !codes.map(StockBoard.normalised).contains(metal.symbol) {
                            groupCodes = (codes + [metal.symbol]).joined(separator: " ")
                        }
                    }
                }
                Spacer(minLength: 0)
                Button("取消") { editingGroup = false }
                Button("保存") { saveGroup() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(StockBoard.Group.parse("\(groupName)=\(groupCodes)") == nil)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func saveGroup() {
        guard let group = StockBoard.Group.parse("\(groupName)=\(groupCodes)") else { return }
        update { config in
            config.set("groups", .list(StockBoard.saving(group, in: config).map { .string($0) }))
            config.set("group", .string(group.name))
        }
        editingGroup = false
        track()
    }

    /// 涨跌统计、比例条和今日盈亏。
    private func summary(_ symbols: [String], quotes: [StockQuote?]) -> some View {
        let breadth = StockBoard.breadth(quotes.map { $0?.changePercent })
        let holdings = StockBoard.holdings(config)
        let positions: [StockBoard.Position] = zip(symbols, quotes).compactMap { symbol, quote in
            guard let quote, !quote.stale else { return nil }
            let unitLabel = StockDisplay.unitLabel(symbol, preview: context.isPreview, unit: unit)
            let currency = unitLabel == PreciousMetal.DisplayUnit.cnyPerGram.title ? "CNY" : quote.currency
            return StockBoard.Position(symbol: symbol, price: quote.price, change: quote.change, currency: currency)
        }
        let profits = holdings.isEmpty ? [] : StockBoard.todayProfit(positions, holdings: holdings)
        let held = StockBoard.holdingProfit(positions, holdings: StockBoard.holdingEntries(config))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(tr("涨 \(breadth.up)"))
                        .foregroundStyle(StockInk.color(rising: true, colors: colors, scheme: scheme))
                    Text(tr("跌 \(breadth.down)"))
                        .foregroundStyle(StockInk.color(rising: false, colors: colors, scheme: scheme))
                    if breadth.flat > 0 {
                        Text(tr("平 \(breadth.flat)"))
                            .foregroundStyle(.panelSecondary)
                    }
                }
                .font(WidgetStyle.label(13))
                .monospacedDigit()
                BreadthBar(breadth: breadth, colors: colors, height: 4)
            }
            ForEach(profits, id: \.currency) { profit in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("今日盈亏")
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                    Text(StockBoard.profitText(profit))
                        .font(WidgetStyle.value(22))
                        .foregroundStyle(ink(profit.amount))
                        .monospacedDigit()
                        .rollingValue(profit.amount)
                    if let percent = profit.percent {
                        Text(StockBoard.percentText(percent))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(ink(percent))
                            .monospacedDigit()
                    }
                }
            }
            ForEach(held, id: \.currency) { profit in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tr("持仓盈亏"))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                    Text(StockBoard.profitText(profit))
                        .font(WidgetStyle.label(15))
                        .foregroundStyle(ink(profit.amount))
                        .monospacedDigit()
                    if let percent = profit.percent {
                        Text(StockBoard.percentText(percent))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(ink(percent))
                            .monospacedDigit()
                    }
                }
            }
            if holdings.isEmpty {
                Text(tr("点右上角「编辑」给每只填上持仓，这里会算这一组的今日盈亏。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ symbol: String, quote: StockQuote?) -> some View {
        let subtitle = StockDisplay.subtitle(symbol, quote: quote, preview: context.isPreview, unit: unit)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(StockBoard.displaySymbol(symbol))
                    .font(WidgetStyle.label(14))
                    .foregroundStyle(.panelPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 92, alignment: .leading)

            MiniTrend(samples: quote?.history ?? [], tint: ink(quote?.changePercent),
                      baseline: quote?.previousClose, lineWidth: 1.4, guide: .panelPrimary)
                .frame(height: 26)
                .frame(maxWidth: .infinity)

            Text(StockBoard.priceText(quote?.price))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .rollingValue(quote?.price ?? 0)
            ChangeChip(percent: quote?.changePercent, colors: colors, size: 13, minWidth: 64)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPane(cornerRadius: 10)
        // 和卡片一样：拿不到新数据时变淡。
        .opacity(quote?.stale == true ? 0.55 : 1)
    }

    // MARK: 空状态

    /// 还没取到，或者取失败又没有缓存：服务分不清这两种，这里也不分。
    private func unavailable(_ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(StockBoard.displaySymbol(symbol))
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            Text("暂无报价。")
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
        }
    }

    /// 断网：顶上一条插头横幅，写「离线 · 10:32 的价」，点右边重新取一次。
    /// 和天气、GitHub 面板同一个 `ReconnectStateView`。
    private func staleNote(_ fetched: Date?) -> some View {
        let title: String = OfflineQuote.label(fetched: fetched, now: .now)
        let detail: String = tr("上次刷新失败，显示的是之前获取的有效数据")
        let preview = context.isPreview
        return ReconnectStateView(title: title, detail: detail, style: .compact) {
            guard !preview else { return }
            Task { await StockService.shared.refresh() }
        }
    }
}
