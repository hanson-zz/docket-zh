import Foundation

/// 股票和自选股的纯逻辑：涨跌颜色、到价提醒、分时图的坐标、自选股分组、排序、
/// 涨跌统计、色块深浅、持仓盈亏和“还有 N 只”。放在 Core，测试不用联网也不用界面。
///
/// 股票盯一只：看清它今天怎么走，离提醒价还有多远。自选股管一组：谁领涨、谁拖后腿，
/// 这一组今天赚没赚。两种卡片和加密货币行情共用一个“涨跌颜色”设置，默认红涨绿跌。
public enum StockBoard {

    // MARK: 涨跌颜色

    /// 股票和自选股的涨跌颜色，和加密货币行情同一个键 `colors`，默认红涨绿跌。
    public static func colors(_ config: WidgetConfig) -> ChangeColors {
        ChangeColors.from(config)
    }

    /// 一个涨跌幅读成红、绿还是不变（灰）。和加密货币行情同一套规则：
    /// 绝对值不到 0.005% 算不变。
    public static func tone(_ percent: Double?, colors: ChangeColors) -> ChangeTone {
        CryptoMarket.tone(percent, colors: colors)
    }

    /// 涨跌幅色块的深浅，0.35 到 1：幅度越大颜色越深，5% 封顶。
    /// 没有数据或不变时最浅。
    public static func chipStrength(_ percent: Double?) -> Double {
        guard let percent, percent.isFinite else { return 0.35 }
        let share = min(abs(percent), 5) / 5
        return 0.35 + 0.65 * share
    }

    /// `+2.41%`、`-0.62%`、`0.00%`，没有数据是 `-`。
    public static func percentText(_ percent: Double?) -> String {
        CryptoMarket.changeText(percent)
    }

    /// `+5.46`、`-22.80`。
    public static func changeText(_ change: Double?) -> String {
        guard let change, change.isFinite else { return "-" }
        let rounded = (change * 100).rounded() / 100
        let sign = rounded > 0 ? "+" : ""
        return sign + grouped(rounded == 0 ? 0 : rounded, digits: 2)
    }

    /// `1,486.20`：千分位、两位小数，不跟系统地区走，卡片上宽度稳定。
    public static func priceText(_ price: Double?) -> String {
        guard let price, price.isFinite else { return "-" }
        return grouped(price, digits: abs(price) < 1 ? 4 : 2)
    }

    /// `4,812万`、`2.3亿`、`8,600`：成交量按中文习惯的万、亿。
    public static func volumeText(_ volume: Double?) -> String {
        guard let volume, volume.isFinite, volume > 0 else { return "-" }
        // 英文界面按千、百万、十亿：48.1M。
        if L10n.isEnglish {
            if volume >= 1_000_000_000 { return grouped(volume / 1_000_000_000, digits: 1) + "B" }
            if volume >= 1_000_000 { return grouped(volume / 1_000_000, digits: 1) + "M" }
            if volume >= 10_000 { return grouped(volume / 1_000, digits: 0) + "K" }
            return grouped(volume, digits: 0)
        }
        if volume >= 100_000_000 {
            return tr("\(grouped(volume / 100_000_000, digits: 1))亿")
        }
        if volume >= 10_000 {
            return tr("\(grouped((volume / 10_000).rounded(), digits: 0))万")
        }
        return grouped(volume, digits: 0)
    }

    static func grouped(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    // MARK: 代码

    /// 去空白、转大写。`600519.ss` 和 `600519.SS` 是同一只。
    public static func normalised(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 去重、去空，保持填写顺序。
    public static func unique(_ symbols: [String]) -> [String] {
        var seen: [String] = []
        for symbol in symbols.map(normalised) where !symbol.isEmpty && !seen.contains(symbol) {
            seen.append(symbol)
        }
        return seen
    }

    /// 股票卡片轮播的代码：`symbols` 去重；空的时候退回 `symbol`，再退回 AAPL。
    public static func rotation(_ config: WidgetConfig) -> [String] {
        let list = unique(config.strings("symbols", default: []))
        if !list.isEmpty { return list }
        let single = normalised(config.string("symbol", default: "AAPL"))
        return [single.isEmpty ? "AAPL" : single]
    }

    /// 轮播的下一只（或上一只）。不在列表里的从第一只开始。
    public static func step(from symbol: String, in rotation: [String], by offset: Int = 1) -> String? {
        guard !rotation.isEmpty else { return nil }
        guard let index = rotation.firstIndex(of: normalised(symbol)) else { return rotation.first }
        let count = rotation.count
        return rotation[((index + offset) % count + count) % count]
    }

    /// 自动轮播的间隔，秒。
    public static let rotationInterval: TimeInterval = 10

    // MARK: 中文名称

    /// 常见代码的中文名。卡片上代码旁边的小字；英文界面查表换成英文名。
    /// 表里没有的用行情接口给的名称。
    public static let knownNames: [String: String] = [
        "AAPL": "苹果", "MSFT": "微软", "NVDA": "英伟达", "TSLA": "特斯拉",
        "GOOGL": "谷歌", "GOOG": "谷歌", "AMZN": "亚马逊", "META": "Meta",
        "NFLX": "奈飞", "AMD": "超威半导体", "INTC": "英特尔", "BABA": "阿里巴巴",
        "PDD": "拼多多", "JD": "京东", "BIDU": "百度", "NIO": "蔚来",
        "TSM": "台积电", "AVGO": "博通", "COIN": "Coinbase",
        "600519.SS": "贵州茅台", "000001.SS": "上证指数", "399001.SZ": "深证成指",
        "0700.HK": "腾讯控股", "9988.HK": "阿里巴巴", "3690.HK": "美团",
        "^GSPC": "标普 500", "^IXIC": "纳斯达克", "^DJI": "道琼斯", "^HSI": "恒生指数",
        PreciousMetal.gold.symbol: "黄金", PreciousMetal.silver.symbol: "白银",
    ]

    /// 显示用的名称：先查中文表（按界面语言翻译），再用接口给的名称，
    /// 都没有就是空的，卡片上只写代码。
    public static func displayName(_ symbol: String, fallback: String?) -> String {
        let key = normalised(symbol)
        if let known = knownNames[key] { return trKey(known) }
        guard let fallback, !fallback.isEmpty, normalised(fallback) != key else { return "" }
        return fallback
    }

    /// 贵金属的代码在卡片上不写 `GC=F`，直接写“黄金”。
    public static func displaySymbol(_ symbol: String) -> String {
        if let metal = PreciousMetal(symbol: symbol) { return metal.title }
        return normalised(symbol)
    }

    // MARK: 到价提醒

    /// 一条到价提醒：`AAPL>237` 是涨到 237 以上提醒，`AAPL<220` 是跌到 220 以下。
    public struct Alert: Equatable, Hashable, Sendable {
        public var symbol: String
        public var price: Double
        public var above: Bool

        public init(symbol: String, price: Double, above: Bool) {
            self.symbol = StockBoard.normalised(symbol)
            self.price = price
            self.above = above
        }

        /// 存进设置的写法，`AAPL>237`、`GC=F<2300.5`。
        public var text: String {
            symbol + (above ? ">" : "<") + StockBoard.trimmed(price)
        }

        /// 读一条。`AAPL > 237`、`aapl>237`、`AAPL ≥ 237` 都认；读不出来是 nil。
        public static func parse(_ raw: String) -> Alert? {
            let text = raw.replacingOccurrences(of: "≥", with: ">")
                .replacingOccurrences(of: "≤", with: "<")
                .replacingOccurrences(of: "＞", with: ">")
                .replacingOccurrences(of: "＜", with: "<")
            let above: Bool
            let parts: [Substring]
            if text.contains(">") {
                above = true
                parts = text.split(separator: ">", omittingEmptySubsequences: false)
            } else if text.contains("<") {
                above = false
                parts = text.split(separator: "<", omittingEmptySubsequences: false)
            } else {
                return nil
            }
            guard parts.count == 2 else { return nil }
            let symbol = StockBoard.normalised(String(parts[0]))
            let number = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            guard !symbol.isEmpty, let price = Double(number), price.isFinite, price > 0 else { return nil }
            return Alert(symbol: symbol, price: price, above: above)
        }

        /// 现价到了没有：高于的涨到或超过，低于的跌到或低于。
        public func isReached(by price: Double?) -> Bool {
            guard let price, price.isFinite else { return false }
            return above ? price >= self.price : price <= self.price
        }

        /// 现价离提醒价还差百分之几，按现价算，始终是正数：`2.1` 是还差 2.1%。
        /// 已经到了是 0。
        public func distance(from price: Double?) -> Double? {
            guard let price, price.isFinite, price > 0 else { return nil }
            if isReached(by: price) { return 0 }
            return abs(self.price - price) / price * 100
        }
    }

    /// 设置里的提醒列表，读不出来的条目丢掉，重复的只留一条。
    public static func alerts(_ config: WidgetConfig) -> [Alert] {
        var result: [Alert] = []
        for raw in config.strings("alerts", default: []) {
            guard let alert = Alert.parse(raw), !result.contains(alert) else { continue }
            result.append(alert)
        }
        return result
    }

    /// 卡片上画的那一条：这一只还没到的提醒里离现价最近的。都到了就是 nil。
    public static func nearestAlert(for symbol: String, price: Double?, in alerts: [Alert]) -> Alert? {
        let key = normalised(symbol)
        return alerts
            .filter { $0.symbol == key && !$0.isReached(by: price) }
            .min { ($0.distance(from: price) ?? .infinity) < ($1.distance(from: price) ?? .infinity) }
    }

    /// `距提醒价 2.1%`，到了是“已到提醒价”。
    public static func distanceText(_ alert: Alert, price: Double?) -> String {
        guard let distance = alert.distance(from: price) else { return tr("提醒价 \(trimmed(alert.price))") }
        if distance == 0 { return tr("已到提醒价") }
        return tr("距提醒价 \(String(format: "%.1f", distance))%")
    }

    /// 这次要发通知的提醒：到价了、而且以前没发过的。`fired` 是发过的 `text`。
    /// 每条提醒只通知一次；改了提醒价就是一条新的提醒。
    public static func newlyReached(_ alerts: [Alert], prices: [String: Double],
                                    fired: Set<String>) -> [Alert] {
        alerts.filter { alert in
            !fired.contains(alert.text) && alert.isReached(by: prices[alert.symbol])
        }
    }

    /// 发过的记录只留还在列表里的，删掉的提醒不一直占着。
    public static func prunedFired(_ fired: [String], alerts: [Alert]) -> [String] {
        let live = Set(alerts.map(\.text))
        return fired.filter { live.contains($0) }
    }

    /// 在面板里加一条：方向按现价自动定，提醒价高于现价就是“涨到”，否则是“跌到”。
    public static func makeAlert(symbol: String, target: Double, current: Double?) -> Alert? {
        guard target.isFinite, target > 0 else { return nil }
        let above = current.map { target >= $0 } ?? true
        return Alert(symbol: symbol, price: target, above: above)
    }

    /// `237`、`237.5`、`0.1234`：去掉多余的零。
    static func trimmed(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: 分时图

    /// 交易时段的状态。
    public enum Session: Equatable, Sendable {
        case open, closed, unknown

        public var title: String {
            switch self {
            case .open: tr("盘中")
            case .closed: tr("已收盘")
            case .unknown: ""
            }
        }
    }

    /// 现在在不在正常交易时段里。时段来自行情接口的 `currentTradingPeriod.regular`。
    public static func session(now: Date, start: Date?, end: Date?) -> Session {
        guard let start, let end, end > start else { return .unknown }
        return (start...end).contains(now) ? .open : .closed
    }

    /// 每个点的横坐标（0 到 1）。有交易时段时按时间铺满整个时段，盘中只画到现在；
    /// 没有时段或时间对不上时按序号平均铺开。
    public static func xPositions(timestamps: [Double], count: Int,
                                  start: Date?, end: Date?) -> [Double] {
        guard count > 0 else { return [] }
        if let start, let end, end > start, timestamps.count == count {
            let from = start.timeIntervalSince1970
            let span = end.timeIntervalSince1970 - from
            return timestamps.map { min(max(($0 - from) / span, 0), 1) }
        }
        guard count > 1 else { return [0] }
        return (0..<count).map { Double($0) / Double(count - 1) }
    }

    /// 纵轴范围：走势本身加昨收，好让昨收虚线总在图里；提醒价离现价不到 5% 时也放进来，
    /// 远了就不画线，只在标签上写差多少。上下各留一点空。
    public static func yRange(values: [Double], previousClose: Double?,
                              alert: Double?) -> ClosedRange<Double>? {
        var points = values.filter(\.isFinite)
        guard !points.isEmpty else { return nil }
        if let previousClose, previousClose.isFinite, previousClose > 0 { points.append(previousClose) }
        if let alert, alert.isFinite, let last = values.last(where: \.isFinite), last > 0,
           abs(alert - last) / last <= 0.05 {
            points.append(alert)
        }
        guard let low = points.min(), let high = points.max() else { return nil }
        let pad = max((high - low) * 0.08, abs(high) * 0.0005, .ulpOfOne)
        return (low - pad)...(high + pad)
    }

    /// 一个值在纵轴上的位置，0 是底、1 是顶；超出范围的是 nil。
    public static func yFraction(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0, range.contains(value) else { return nil }
        return (value - range.lowerBound) / span
    }

    /// 成交量小柱：按时间分成 `buckets` 段合计，再按最大的一段归一到 0 到 1。
    /// `rising` 是这一段收在上一段之上（或开盘价之上），定柱子的颜色。
    public struct VolumeBar: Equatable, Sendable {
        public var position: Double
        public var height: Double
        public var rising: Bool
    }

    public static func volumeBars(volumes: [Double], closes: [Double], positions: [Double],
                                  buckets: Int) -> [VolumeBar] {
        let count = min(volumes.count, closes.count, positions.count)
        guard count > 0, buckets > 0 else { return [] }
        var totals = [Double](repeating: 0, count: buckets)
        var lastClose = [Double?](repeating: nil, count: buckets)
        var firstClose = [Double?](repeating: nil, count: buckets)
        for index in 0..<count {
            let volume = volumes[index]
            guard volume.isFinite, volume > 0 else { continue }
            let slot = min(Int(positions[index] * Double(buckets)), buckets - 1)
            totals[slot] += volume
            if firstClose[slot] == nil { firstClose[slot] = closes[index] }
            lastClose[slot] = closes[index]
        }
        guard let peak = totals.max(), peak > 0 else { return [] }
        var previous: Double?
        var bars: [VolumeBar] = []
        for slot in 0..<buckets where totals[slot] > 0 {
            let close = lastClose[slot] ?? 0
            let reference = previous ?? firstClose[slot] ?? close
            bars.append(VolumeBar(position: (Double(slot) + 0.5) / Double(buckets),
                                  height: totals[slot] / peak,
                                  rising: close >= reference))
            previous = close
        }
        return bars
    }

    // MARK: 自选股分组

    /// 一个分组：名字和一串代码。设置里写成 `科技=NVDA TSLA AAPL`。
    public struct Group: Equatable, Sendable {
        public var name: String
        public var symbols: [String]

        public init(name: String, symbols: [String]) {
            self.name = name
            self.symbols = StockBoard.unique(symbols)
        }

        public var text: String { name + "=" + symbols.joined(separator: " ") }

        /// `科技=NVDA TSLA`、`A股: 600519.SS 000001.SS`、`港股＝0700.HK`。
        /// 代码之间用空格、顿号或分号隔开。没有名字或没有代码是 nil。
        public static func parse(_ raw: String) -> Group? {
            let separators: [Character] = ["=", "＝", ":", "："]
            guard let cut = raw.firstIndex(where: { separators.contains($0) }) else { return nil }
            let name = raw[..<cut].trimmingCharacters(in: .whitespaces)
            let rest = raw[raw.index(after: cut)...]
            let symbols = rest.split(whereSeparator: { " 、;；\t".contains($0) }).map(String.init)
            let group = Group(name: name, symbols: symbols)
            guard !name.isEmpty, !group.symbols.isEmpty else { return nil }
            return group
        }
    }

    /// 自选股的全部分组。设置了 `groups` 就用它（同名的只留第一个）；
    /// 一个都没有时整串 `symbols` 就是一个叫“自选”的分组。
    public static func groups(_ config: WidgetConfig) -> [Group] {
        var result: [Group] = []
        for raw in config.strings("groups", default: []) {
            guard let group = Group.parse(raw), !result.contains(where: { $0.name == group.name }) else { continue }
            result.append(group)
        }
        if !result.isEmpty { return result }
        var symbols = unique(config.strings("symbols", default: defaultWatchlist))
        if symbols.isEmpty { symbols = defaultWatchlist }
        return [Group(name: tr("自选"), symbols: symbols)]
    }

    public static let defaultWatchlist = ["AAPL", "MSFT", "NVDA"]

    /// 卡片上正在看的分组：`group` 记名字，找不到就是第一个。
    public static func currentGroup(_ config: WidgetConfig) -> Group {
        let all = groups(config)
        let name = config.string("group", default: "")
        return all.first { $0.name == name } ?? all[0]
    }

    /// 点分组名换到下一个分组的名字。
    public static func nextGroupName(_ config: WidgetConfig) -> String {
        let all = groups(config)
        let current = currentGroup(config)
        let index = all.firstIndex(of: current) ?? 0
        return all[(index + 1) % all.count].name
    }

    /// 新建或改一个分组之后的 `groups` 列表：同名的替换，没有的加在最后。
    /// 原来还没有分组时，先把“自选”那串代码收成第一个分组，免得它凭空消失。
    public static func saving(_ group: Group, in config: WidgetConfig) -> [String] {
        var current = config.strings("groups", default: []).compactMap(Group.parse)
        if current.isEmpty {
            current = groups(config)
        }
        if let index = current.firstIndex(where: { $0.name == group.name }) {
            current[index] = group
        } else {
            current.append(group)
        }
        return current.map(\.text)
    }

    /// 删掉一个分组之后的 `groups` 列表。最后一个不删。
    public static func removing(_ name: String, in config: WidgetConfig) -> [String] {
        let current = groups(config)
        guard current.count > 1 else { return current.map(\.text) }
        return current.filter { $0.name != name }.map(\.text)
    }

    /// 设置里点“＋ 黄金”“＋ 白银”这类快捷项：自选股有分组时加进正在看的分组，
    /// 否则加在代码列表最后；已经有了就不重复。股票卡片顺带把正在显示的换成它，
    /// 加完马上看得到。
    public static func adding(_ symbol: String, to config: WidgetConfig, watchlist: Bool) -> WidgetConfig {
        let key = normalised(symbol)
        guard !key.isEmpty else { return config }
        var result = config
        if watchlist, !config.strings("groups", default: []).compactMap(Group.parse).isEmpty {
            var group = currentGroup(config)
            guard !group.symbols.contains(key) else { return config }
            group.symbols.append(key)
            result.set("groups", .list(saving(group, in: config).map { .string($0) }))
            return result
        }
        let fallback = watchlist ? defaultWatchlist : rotation(config)
        var list = unique(config.strings("symbols", default: fallback))
        if !list.contains(key) { list.append(key) }
        result.set("symbols", .list(list.map { .string($0) }))
        if !watchlist { result.set("symbol", .string(key)) }
        return result
    }

    // MARK: 排序和统计

    /// 自选股的排序：按涨跌幅从高到低，或者按填写的顺序。
    public enum Order: String, CaseIterable, Sendable {
        case change, custom

        public var title: String {
            switch self {
            case .change: tr("按涨跌幅")
            case .custom: tr("按填写顺序")
            }
        }

        public static func from(_ config: WidgetConfig) -> Order {
            Order(rawValue: config.string("sort", default: Order.change.rawValue)) ?? .change
        }
    }

    /// 排好的代码。按涨跌幅时还没有报价的排在最后，涨跌幅一样的保持原来的先后。
    public static func sorted(_ symbols: [String], percents: [String: Double], order: Order) -> [String] {
        guard order == .change else { return symbols }
        return symbols.enumerated().sorted { lhs, rhs in
            let left = percents[lhs.element].flatMap { $0.isFinite ? $0 : nil }
            let right = percents[rhs.element].flatMap { $0.isFinite ? $0 : nil }
            switch (left, right) {
            case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l > r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// 一组里涨几只、跌几只、平几只，和红绿比例条里“涨”占的比例。
    public struct Breadth: Equatable, Sendable {
        public var up: Int
        public var down: Int
        public var flat: Int

        /// 涨占涨跌合计的比例，0 到 1；都没涨没跌时是 0.5。
        public var upShare: Double {
            up + down == 0 ? 0.5 : Double(up) / Double(up + down)
        }
    }

    public static func breadth(_ percents: [Double?]) -> Breadth {
        var result = Breadth(up: 0, down: 0, flat: 0)
        for percent in percents {
            guard let percent, percent.isFinite else { continue }
            if abs(percent) < 0.005 { result.flat += 1 } else if percent > 0 { result.up += 1 } else { result.down += 1 }
        }
        return result
    }

    /// 卡片放得下几行：`capacity` 行里放不下时最后一格让给“还有 N 只”。
    public static func fit(count: Int, capacity: Int) -> (shown: Int, hidden: Int) {
        guard capacity > 0 else { return (0, count) }
        guard count > capacity else { return (count, 0) }
        let shown = capacity - 1
        return (shown, count - shown)
    }

    public static func moreText(_ hidden: Int) -> String {
        tr("还有 \(hidden) 只")
    }

    /// `涨 5 跌 3`。
    public static func breadthText(_ breadth: Breadth) -> String {
        tr("涨 \(breadth.up) 跌 \(breadth.down)")
    }

    /// 宽卡片一列放 3 行，共两列。
    public static let watchlistRowsPerColumn = 3
    public static let watchlistCapacity = 6

    /// 竖排扩展栏的自选股：顶部涨跌统计，下面一行一只，最多 6 行。
    public static func watchlistColumnHeight(count: Int) -> Double {
        let rows = min(max(count, 1), watchlistCapacity)
        return Double(24 + rows * 18 + 6)
    }

    // MARK: 持仓和今日盈亏

    /// 持仓：`NVDA 100`、`AAPL:50`、`600519.SS=200`。填了才算今日盈亏。
    public static func holdings(_ config: WidgetConfig) -> [String: Double] {
        var result: [String: Double] = [:]
        for raw in config.strings("holdings", default: []) {
            let parts = raw.split(whereSeparator: { " :=：＝\t".contains($0) })
            guard parts.count == 2 else { continue }
            let symbol = normalised(String(parts[0]))
            guard !symbol.isEmpty, let shares = Double(parts[1]), shares.isFinite, shares != 0 else { continue }
            result[symbol] = shares
        }
        return result
    }

    /// 一只的报价里算盈亏要用的部分。
    public struct Position: Equatable, Sendable {
        public var symbol: String
        public var price: Double
        public var change: Double
        public var currency: String

        public init(symbol: String, price: Double, change: Double, currency: String) {
            self.symbol = StockBoard.normalised(symbol)
            self.price = price
            self.change = change
            self.currency = currency
        }
    }

    /// 今日盈亏：一种货币一笔，金额是 涨跌额 × 股数，百分比按昨天收盘的市值算。
    /// 没填持仓的不算；按金额绝对值从大到小排。
    public struct Profit: Equatable, Sendable {
        public var currency: String
        public var amount: Double
        public var percent: Double?
    }

    public static func todayProfit(_ positions: [Position], holdings: [String: Double]) -> [Profit] {
        var amount: [String: Double] = [:]
        var base: [String: Double] = [:]
        for position in positions {
            guard let shares = holdings[position.symbol], position.price.isFinite, position.change.isFinite
            else { continue }
            amount[position.currency, default: 0] += position.change * shares
            base[position.currency, default: 0] += (position.price - position.change) * shares
        }
        return amount.map { currency, value in
            let start = base[currency] ?? 0
            return Profit(currency: currency, amount: value, percent: start > 0 ? value / start * 100 : nil)
        }
        .sorted { abs($0.amount) == abs($1.amount) ? $0.currency < $1.currency : abs($0.amount) > abs($1.amount) }
    }

    /// `+¥1,286.40`、`-$12.30`、`+1,286.40 HKD`。
    public static func profitText(_ profit: Profit) -> String {
        let sign = profit.amount > 0.004 ? "+" : (profit.amount < -0.004 ? "-" : "")
        let number = grouped(abs(profit.amount), digits: 2)
        switch profit.currency.uppercased() {
        case "CNY": return sign + "¥" + number
        case "USD": return sign + "$" + number
        case "HKD": return sign + "HK$" + number
        default: return sign + number + " " + profit.currency.uppercased()
        }
    }

    // MARK: 尺寸

    /// 股票卡片：有图时右半边画分时，没图只留读数。
    public static func stockTileWidth(chart: Bool) -> Double { chart ? 228 : 124 }

    /// 自选股卡片：两列，每列三行。
    public static let watchlistTileWidth: Double = 320
}
