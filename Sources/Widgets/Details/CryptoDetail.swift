import SwiftUI

/// 加密货币面板，320pt，两个状态：
/// - 浏览：人民币/美元一键切换；每个币一行（圆标、名字和代码、最近 7 天走势线、
///   价格、24 小时涨跌色块），设了到价提醒的名字旁有金色铃铛；下面一行“到价
///   提醒”（Pro），写最近要提醒的那条；底下写清色块和线各是什么，以及 CoinGecko
///   的署名（它的条款要求）。
/// - 编辑：右上“编辑”进入。搜索添加币种（常见币中英文名、代码在本地马上出，
///   两个字母起再去 CoinGecko 搜），“我的币种”拖左边的把手排序、红钮删除（至少
///   留一个，最多 12 个）；点铃铛展开到价提醒：高于、低于各一个价和开关，
///   提醒一次后自动关掉；最下面换涨跌颜色。
///
/// 到价提醒是 Pro（`ProLicenseGate.canUseCryptoAlerts`）：没解锁时照样列出，带
/// Pro 标，点开关、改价弹付费墙；不判断、不标铃铛，存着的提醒不改写。
/// 到没到价由卡片判断（见 `CryptoTile`），这里打开时清掉卡片上的变色。
struct CryptoDetail: View {
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false
    /// 面板里切的计价，写回设置后面板拿到新 instance 之前也不跳回去。
    @State private var picked: String?
    @State private var query = ""
    @FocusState private var focus: Field?
    @State private var remote: [CryptoSearchHit] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var fullNote = false
    /// 展开到价提醒的那个币。
    @State private var expanded: String?
    /// 提醒价输入框里正在写的字，键是 `Field.price` 的 slot。
    @State private var drafts: [String: String] = [:]
    @State private var drag: (from: Int, offset: CGFloat)?

    private enum Field: Hashable {
        case search
        case price(String)
    }

    private static let purple = Color(hex: "#C8A2FF")
    private static let purpleInk = Color(hex: "#22093A")
    private static let gold = Color(hex: "#F5C451")
    private static let red = Color(hex: "#FF6B5A")
    private static let upRed = Color(hex: "#FF5E57")
    private static let downGreen = Color(hex: "#3FCB7E")
    /// 编辑态“我的币种”一行 48，行距 6：拖动按这个换算落点。
    private static let rowHeight: CGFloat = 48
    private static let rowGap: CGFloat = 6

    private var accent: Color { panelTint.accent(or: Self.purple) }
    private var accentInk: Color { panelTint.ink(or: Self.purpleInk) }

    /// 写过之后面板拿到的可能还是打开时那份，写之前读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { context.isPreview ? instance.config : current.config }

    private var ids: [String] { CryptoMarket.coinIDs(config) }
    private var currency: String { picked ?? CryptoMarket.currency(config) }
    private var colors: ChangeColors { ChangeColors.from(config) }
    private var unlocked: Bool { context.isPreview || ProAccess.isUnlocked }
    private var alertsOn: Bool { ProLicenseGate.canUseCryptoAlerts(unlocked: unlocked) }

    private var alerts: [CryptoAlert] {
        if context.isPreview {
            return [CryptoAlert(coin: "bitcoin", above: true, price: currency == "usd" ? 112_000 : 800_000,
                                currency: currency)]
        }
        return CryptoWatch.alerts(config, coins: ids)
    }

    private func quote(_ id: String) -> CryptoQuote? {
        context.isPreview ? .preview(id, currency: currency) : CryptoService.shared.quote(id, currency: currency)
    }

    private func name(_ id: String) -> String {
        CryptoWatch.displayName(id: id, fallback: quote(id)?.name ?? CryptoService.shared.seen[id]?.name)
    }

    private func symbol(_ id: String) -> String {
        if let quote = quote(id) { return quote.symbol }
        if let hit = CryptoService.shared.seen[id] { return hit.symbol }
        return CryptoMarket.label(id: id, quote: nil)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 14)
                if editing { edit } else { browse }
            }
        }
        .onAppear {
            track()
            clearHits()
        }
        .onDisappear {
            // 写着提醒价就关了面板：照样存下。
            if case .price(let slot) = focus { commit(slot) }
        }
        .onChange(of: currency) { _, _ in track() }
        .onChange(of: focus) { old, _ in
            if case .price(let slot) = old { commit(slot) }
        }
        .task(id: fullNote) {
            guard fullNote else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            fullNote = false
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editing ? tr("编辑币种") : tr("加密货币"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(editing ? tr("搜索添加 · 拖动排序") : subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !context.isPreview {
                if editing {
                    Button { switchEditing(false) } label: {
                        Text(tr("完成"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentInk)
                            .padding(.horizontal, 15)
                            .frame(height: 28)
                            .background(Capsule().fill(accent))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { switchEditing(true) } label: {
                        Text(tr("编辑"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 13)
                            .frame(height: 28)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(tr("搜索添加币种、调整顺序、设到价提醒"))
                }
            }
        }
    }

    /// `人民币计价 · 10:21 更新`。
    private var subtitle: String {
        let base = currency == "usd" ? tr("美元计价") : tr("人民币计价")
        if context.isPreview { return base + " · " + tr("示例数据") }
        guard let date = CryptoService.shared.updated(currency) else { return base + " · " + tr("尚未获取") }
        return base + " · " + tr("\(date.formatted(date: .omitted, time: .shortened)) 更新")
    }

    private func switchEditing(_ on: Bool, focusSearch: Bool = true) {
        if !on, case .price(let slot) = focus { commit(slot) }
        if on, focusSearch { WidgetDetailWindow.shared.focusField { focus = .search } } else { focus = nil }
        withAnimation(.snappy(duration: 0.25)) {
            editing = on
            query = ""
            remote = []
            expanded = nil
            drafts = [:]
            drag = nil
            fullNote = false
        }
    }

    // MARK: 浏览

    private var browse: some View {
        VStack(alignment: .leading, spacing: 0) {
            segment([(tr("人民币 ¥"), "cny"), (tr("美元 $"), "usd")], selection: currency) { choose($0) }
                .padding(.bottom, 14)
            if !context.isPreview, CryptoService.shared.isStale(currency) {
                // 断网：和天气、GitHub 面板同一条插头横幅，点右边马上重取。
                ReconnectStateView(title: OfflineQuote.label(fetched: CryptoService.shared.updated(currency),
                                                             now: .now),
                                   detail: tr("刷新失败，显示的是上次成功获取的价格"),
                                   style: .compact,
                                   retry: { CryptoService.shared.retryNow() })
                    .padding(.bottom, 10)
            }
            VStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in browseRow(id) }
            }
            .padding(.bottom, 10)
            alertCard
                .padding(.bottom, 12)
            footer
        }
    }

    private func browseRow(_ id: String) -> some View {
        let quote = quote(id)
        let tone = CryptoMarket.tone(quote?.change24h, colors: colors)
        let watched = alertsOn && CryptoWatch.watchedCoins(alerts).contains(id)
        return HStack(spacing: 10) {
            badge(id, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name(id))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(13.0 / 15.0)
                    if watched {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Self.gold)
                            .accessibilityLabel(tr("已设到价提醒"))
                    }
                }
                Text(symbol(id))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            MiniTrend(samples: quote?.sparkline ?? [], tint: weekInk(quote), baseline: nil, lineWidth: 1.6,
                      guide: .white)
                .frame(width: 56, height: 28)
                .help(tr("最近 7 天 \(CryptoMarket.changeText(quote?.change7d))"))
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.map { CryptoMarket.priceText($0.price, currency: currency) } ?? "-")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(13.0 / 15.0)
                    .rollingValue(quote?.price)
                Text(CryptoWatch.chipText(quote?.change24h))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(tone == .neutral ? Color.white.opacity(0.7) : ink(tone))
                    .lineLimit(1)
                    .frame(minWidth: 54, minHeight: 20)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tone == .neutral ? Color.white.opacity(0.10) : ink(tone).opacity(0.2)))
                    .rollingValue(quote?.change24h)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.leading, 13)
        .padding(.trailing, 14)
        .frame(height: 64)
        .glassPane(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    /// 到价提醒一行：Pro 写最近要提醒的那条，点一下去编辑；没解锁点一下弹付费墙。
    private var alertCard: some View {
        let featured = CryptoWatch.featured(alerts, order: ids)
        let more = alerts.filter(\.on).count - 1
        let title: String
        let detail: String
        if let featured {
            title = CryptoWatch.title(featured, name: name(featured.coin))
            detail = more > 0 ? tr("另有 \(more) 条 · 到了发通知，卡片变色") : tr("到了发通知，卡片变色")
        } else {
            title = tr("到价提醒")
            detail = alertsOn ? tr("点「编辑」里币种旁的铃铛设高于、低于") : tr("高于或低于你设的价时发通知")
        }
        return Button {
            guard !context.isPreview else { return }
            if !alertsOn {
                PaywallWindow.shared.show()
            } else {
                switchEditing(true, focusSearch: false)
                expanded = featured?.coin ?? ids.first
                loadDrafts()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Self.gold.opacity(alertsOn && featured != nil ? 1 : 0.7))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                ProCrown()
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .contentShape(.rect)
            .glassPane(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .help(alertsOn ? tr("设到价提醒") : tr("到价提醒是码头 Pro 专属。点一下购买、输入激活码或开始试用。"))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("24 小时涨跌 · 线是最近 7 天 · \(colors.title)"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Link(CryptoMarket.attribution, destination: CryptoMarket.attributionURL)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .help(tr("每 5 分钟最多刷新一次"))
        }
    }

    // MARK: 编辑

    private var edit: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.bottom, 8)
            if !trimmedQuery.isEmpty {
                results
                    .padding(.bottom, 10)
            }
            HStack {
                Text(tr("我的币种 \(ids.count)"))
                Spacer()
                Text(fullNote ? tr("最多 \(CryptoMarket.maxCoins) 个") : tr("卡片放前 \(CryptoMarket.tileCoins) 个"))
                    .foregroundStyle(fullNote ? Self.red : Color.white.opacity(0.62))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.top, 8)
            .padding(.bottom, 8)
            myCoins
                .padding(.bottom, 14)
            // 英文 "Up/down colors" 加 "Red up, green down" 两格一行放不下，
            // 原来两格被压成 "Red up, gr…"；放不下时分段放到标题下面。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    colorsTitle
                    colorsSegment
                }
                VStack(alignment: .leading, spacing: 6) {
                    colorsTitle
                    colorsSegment
                }
            }
        }
    }

    private var colorsTitle: some View {
        Text(tr("涨跌颜色"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize()
    }

    private var colorsSegment: some View {
        segment(ChangeColors.allCases.map { ($0.title, $0.rawValue) }, selection: colors.rawValue) { raw in
            write { $0.set("colors", .string(raw)) }
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        let active = focus == .search || !query.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            TextField("", text: $query, prompt: Text(tr("搜索：比特币、BTC、sol")).foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .focused($focus, equals: .search)
                .onSubmit { if let first = shownResults.first { add(first) } }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("清除搜索"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(active ? accent.opacity(0.9) : Color.white.opacity(0.14), lineWidth: active ? 1.2 : 0.6)
        }
        .contentShape(.rect)
        .onTapGesture { WidgetDetailWindow.shared.focusField { focus = .search } }
        .task(id: trimmedQuery) { await runSearch(trimmedQuery) }
    }

    private var shownResults: [CryptoSearchHit] {
        CryptoWatch.mergedResults(local: CryptoWatch.localSearch(trimmedQuery), remote: remote)
    }

    private var results: some View {
        let hits = shownResults
        return VStack(spacing: 0) {
            if hits.isEmpty {
                Text(searching ? tr("正在搜索…") : searchFailed ? tr("搜索失败，稍后再试") : tr("没找到「\(trimmedQuery)」"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            } else {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    resultRow(hit)
                    if index < hits.count - 1 {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.leading, 46)
                    }
                }
                if searchFailed {
                    Text(tr("联网搜索失败，只列出常见币种"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
    }

    private func resultRow(_ hit: CryptoSearchHit) -> some View {
        let added = ids.contains(hit.id)
        return HStack(spacing: 8) {
            letterBadge(hit.symbol, size: 26)
            Text(CryptoWatch.displayName(id: hit.id, fallback: hit.name))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
            Text(hit.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 6)
            if added {
                Text(tr("已添加"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize()
            } else {
                Button { add(hit) } label: {
                    Text(tr("添加"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CryptoWatch.canAdd(count: ids.count) ? accentInk : Color.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(CryptoWatch.canAdd(count: ids.count) ? accent : Color.white.opacity(0.12)))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(CryptoWatch.canAdd(count: ids.count) ? tr("加到我的币种") : tr("最多 \(CryptoMarket.maxCoins) 个，先删掉一个"))
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .frame(height: 46)
    }

    // MARK: 我的币种

    private var myCoins: some View {
        let list = ids
        let target = drag.map { CryptoWatch.dropIndex(from: $0.from, offset: Double($0.offset),
                                                      step: Double(Self.rowHeight + Self.rowGap), count: list.count) }
        return VStack(spacing: Self.rowGap) {
            ForEach(Array(list.enumerated()), id: \.element) { index, id in
                VStack(spacing: Self.rowGap) {
                    coinRow(id, index: index, count: list.count)
                        .offset(y: rowOffset(index, target: target))
                        .zIndex(drag?.from == index ? 1 : 0)
                    if expanded == id, drag == nil {
                        alertEditor(id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .zIndex(drag?.from == index ? 1 : 0)
            }
        }
    }

    private func rowOffset(_ index: Int, target: Int?) -> CGFloat {
        guard let drag, let target else { return 0 }
        if index == drag.from { return drag.offset }
        let step = Self.rowHeight + Self.rowGap
        if drag.from < target, index > drag.from, index <= target { return -step }
        if drag.from > target, index < drag.from, index >= target { return step }
        return 0
    }

    private func coinRow(_ id: String, index: Int, count: Int) -> some View {
        let watched = CryptoWatch.watchedCoins(alerts).contains(id)
        let lifted = drag?.from == index
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(count > 1 ? 0.55 : 0.2))
                .frame(width: 24, height: Self.rowHeight)
                .contentShape(.rect)
                .gesture(reorder(index: index, count: count))
                .help(tr("拖动排序"))
                .accessibilityLabel(tr("拖动排序"))
            badge(id, size: 26)
            Text(name(id))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
            Text(symbol(id))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { toggleExpanded(id) } label: {
                Image(systemName: watched && alertsOn ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(watched && alertsOn ? Self.gold : Color.white.opacity(expanded == id ? 0.9 : 0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("到价提醒"))
            .accessibilityLabel(tr("到价提醒"))
            Button { remove(id) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Self.red.opacity(CryptoWatch.canRemove(count: count) ? 1 : 0.35))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Self.red.opacity(CryptoWatch.canRemove(count: count) ? 0.22 : 0.08)))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!CryptoWatch.canRemove(count: count))
            .help(CryptoWatch.canRemove(count: count) ? tr("删除") : tr("至少留一个币种"))
            .accessibilityLabel(tr("删除"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Self.rowHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(lifted ? 0.16 : 0.06)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
        .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 8, y: 3)
    }

    private func reorder(index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard count > 1 else { return }
                if drag == nil {
                    if case .price(let slot) = focus { commit(slot) }
                    expanded = nil
                }
                drag = (index, value.translation.height)
            }
            .onEnded { value in
                guard let from = drag?.from else { return }
                let to = CryptoWatch.dropIndex(from: from, offset: Double(value.translation.height),
                                               step: Double(Self.rowHeight + Self.rowGap), count: count)
                drag = nil
                guard to != from else { return }
                let next = CryptoWatch.moving(ids, from: from, to: to)
                write { CryptoWatch.writeCoins(next, into: &$0) }
            }
    }

    // MARK: 到价提醒

    private func slot(_ id: String, above: Bool) -> String { id + (above ? ">" : "<") }

    private func alertEditor(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("到价提醒"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                ProCrown()
                Spacer(minLength: 0)
            }
            alertLine(id, above: true)
            alertLine(id, above: false)
            Text(note(id))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.10)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
    }

    /// 提醒下面那行小字：现价已经过了线的说一声，免得打开就响；没解锁的说清楚。
    private func note(_ id: String) -> String {
        guard alertsOn else { return tr("到价提醒是码头 Pro 专属，没解锁时只显示不提醒") }
        let price = quote(id)?.price
        for above in [true, false] {
            if let alert = CryptoWatch.alert(alerts, coin: id, above: above), alert.on,
               alert.currency == currency, alert.isReached(by: price) {
                return above ? tr("现价已经高于这个价，下次刷新就会提醒") : tr("现价已经低于这个价，下次刷新就会提醒")
            }
        }
        return tr("提醒一次后自动关掉")
    }

    private func alertLine(_ id: String, above: Bool) -> some View {
        let key = slot(id, above: above)
        let alert = CryptoWatch.alert(alerts, coin: id, above: above)
        let shownCurrency = alert?.currency ?? currency
        let isOn = (alert?.on ?? false)
        let focused = focus == .price(key)
        let suggestion = CryptoWatch.suggested(current: quote(id)?.price, above: above)
            .map { CryptoWatch.inputText($0, currency: shownCurrency) } ?? ""
        return HStack(spacing: 10) {
            Text(above ? tr("高于") : tr("低于"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize()
            HStack(spacing: 2) {
                Text(shownCurrency == "usd" ? "$" : "¥")
                    .foregroundStyle(.white.opacity(isOn || focused ? 1 : 0.6))
                TextField("", text: Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 }),
                          prompt: Text(suggestion).foregroundStyle(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(isOn || focused ? 1 : 0.6))
                    .focused($focus, equals: .price(key))
                    .onSubmit { focus = nil }
                    .disabled(!alertsOn)
            }
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.10)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused || isOn ? accent.opacity(0.9) : Color.white.opacity(0.2), lineWidth: focused || isOn ? 1.2 : 0.6)
            }
            .contentShape(.rect)
            .onTapGesture {
                if alertsOn {
                    WidgetDetailWindow.shared.focusField { focus = .price(key) }
                } else {
                    PaywallWindow.shared.show()
                }
            }
            PillToggle(isOn: isOn && alertsOn, accent: accent) { flip(id, above: above) }
                .accessibilityLabel(above ? tr("高于时提醒") : tr("低于时提醒"))
        }
    }

    private func toggleExpanded(_ id: String) {
        if case .price(let slot) = focus { commit(slot) }
        focus = nil
        withAnimation(.snappy(duration: 0.22)) {
            expanded = expanded == id ? nil : id
        }
        loadDrafts()
    }

    /// 输入框里先放存着的价。
    private func loadDrafts() {
        var next: [String: String] = [:]
        for alert in alerts {
            next[slot(alert.coin, above: alert.above)] = CryptoWatch.inputText(alert.price, currency: alert.currency)
        }
        drafts = next
    }

    /// 输入框写完（回车或点到别处）：空了删掉这条，写错了退回原来的，写对了存下，
    /// 新写的一条默认打开。
    private func commit(_ key: String) {
        guard alertsOn, !context.isPreview, key.count > 1 else { return }
        let id = String(key.dropLast())
        let above = key.hasSuffix(">")
        let existing = CryptoWatch.alert(alerts, coin: id, above: above)
        let text = (drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            guard existing != nil else { return }
            saveAlerts(CryptoWatch.removing(coin: id, above: above, from: alerts))
            return
        }
        guard let price = CryptoWatch.parsePrice(text) else {
            drafts[key] = existing.map { CryptoWatch.inputText($0.price, currency: $0.currency) } ?? ""
            return
        }
        let cur = existing?.currency ?? currency
        drafts[key] = CryptoWatch.inputText(price, currency: cur)
        if let existing, existing.price == price { return }
        let alert = CryptoAlert(coin: id, above: above, price: price, currency: cur, on: true)
        saveAlerts(CryptoWatch.setting(alert, in: alerts))
    }

    /// 开关：没解锁弹付费墙；有这条就开关它；没有就用输入框里的价，空着用建议价。
    private func flip(_ id: String, above: Bool) {
        guard !context.isPreview else { return }
        guard alertsOn else {
            PaywallWindow.shared.show()
            return
        }
        let key = slot(id, above: above)
        if focus == .price(key) { focus = nil }
        if var alert = CryptoWatch.alert(alerts, coin: id, above: above) {
            alert.on.toggle()
            saveAlerts(CryptoWatch.setting(alert, in: alerts))
            return
        }
        let typed = drafts[key].flatMap(CryptoWatch.parsePrice)
        guard let price = typed ?? CryptoWatch.suggested(current: quote(id)?.price, above: above) else { return }
        drafts[key] = CryptoWatch.inputText(price, currency: currency)
        saveAlerts(CryptoWatch.setting(CryptoAlert(coin: id, above: above, price: price, currency: currency), in: alerts))
    }

    private func saveAlerts(_ next: [CryptoAlert]) {
        write { CryptoWatch.writeAlerts(next, into: &$0) }
        track()
    }

    // MARK: 动作

    private func add(_ hit: CryptoSearchHit) {
        guard !context.isPreview else { return }
        CryptoService.shared.remember([hit])
        guard !ids.contains(hit.id) else { return }
        guard let next = CryptoWatch.adding(hit.id, to: ids) else {
            fullNote = true
            return
        }
        write { CryptoWatch.writeCoins(next, into: &$0) }
        CryptoService.shared.track(next, currency: currency)
    }

    private func remove(_ id: String) {
        guard !context.isPreview, CryptoWatch.canRemove(count: ids.count) else { return }
        let next = CryptoWatch.removing(id, from: ids)
        let kept = CryptoWatch.removing(coin: id, from: CryptoWatch.alerts(config))
        if expanded == id { expanded = nil }
        withAnimation(.snappy(duration: 0.2)) {
            write { config in
                CryptoWatch.writeCoins(next, into: &config)
                CryptoWatch.writeAlerts(kept, into: &config)
            }
        }
        fullNote = false
    }

    private func runSearch(_ q: String) async {
        remote = []
        searchFailed = false
        guard CryptoWatch.wantsRemoteSearch(q) else {
            searching = false
            return
        }
        searching = true
        // 停手 0.4 秒再搜，打字时不连着发请求。
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let hits = await CryptoService.shared.search(q)
        guard !Task.isCancelled else { return }
        searching = false
        if let hits { remote = hits } else { searchFailed = true }
    }

    private func choose(_ value: String) {
        guard !context.isPreview else { return }
        picked = value
        write { $0.set("currency", .string(value)) }
    }

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(current, change)
    }

    /// 卡片因为到价变了色：打开面板就算看过了。
    private func clearHits() {
        guard !context.isPreview, !CryptoWatch.hits(current.config).isEmpty else { return }
        write { $0.set(CryptoWatch.hitsKey, .list([])) }
    }

    private func track() {
        guard !context.isPreview else { return }
        CryptoService.shared.track(ids, currency: currency)
        guard alertsOn else { return }
        let live = alerts.filter(\.on)
        for cur in CryptoWatch.currencies(live) where cur != currency {
            CryptoService.shared.track(live.filter { $0.currency == cur }.map(\.coin), currency: cur)
        }
    }

    // MARK: 小零件

    private func ink(_ tone: ChangeTone) -> Color {
        switch tone {
        case .red: Self.upRed
        case .green: Self.downGreen
        case .neutral: .white.opacity(0.7)
        }
    }

    private func weekInk(_ quote: CryptoQuote?) -> Color {
        let tone = CryptoMarket.tone(quote?.change7d, colors: colors)
        return tone == .neutral ? .white.opacity(0.6) : ink(tone)
    }

    private func badge(_ id: String, size: CGFloat) -> some View {
        letterBadge(symbol(id), size: size)
    }

    private func letterBadge(_ symbol: String, size: CGFloat) -> some View {
        Text(CryptoMarket.badgeLetter(symbol))
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: CryptoMarket.badgeHex(symbol))))
            .accessibilityHidden(true)
    }

    /// 两段的切换：选中的是实心强调色、深色字。
    private func segment(_ options: [(String, String)], selection: String,
                         choose: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let (title, value) = options[index]
                let on = value == selection
                Button { choose(value) } label: {
                    Text(title)
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? accentInk : Color.white.opacity(0.82))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Capsule().fill(on ? accent : Color.clear))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6) }
    }
}

/// 效果图上的 Pro 标：金色小皇冠加“Pro”，13pt。
private struct ProCrown: View {
    var body: some View {
        let gold = Color(hex: "#F5C451")
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: ProFeatures.badgeTitle)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(gold)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(gold.opacity(0.16)))
        .overlay(Capsule().strokeBorder(gold.opacity(0.55), lineWidth: 0.6))
        .fixedSize()
        .help(ProFeatures.help)
        .accessibilityLabel(ProFeatures.label)
    }
}

/// 效果图上的开关：46 × 26 的胶囊，开着是强调色。
private struct PillToggle: View {
    var isOn: Bool
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? accent : Color.white.opacity(0.18))
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
            .frame(width: 46, height: 26)
            .animation(.snappy(duration: 0.18), value: isOn)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? tr("开") : tr("关"))
    }
}
