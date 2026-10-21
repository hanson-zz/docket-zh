import Foundation

/// 黄金、白银：股票和自选股添加代码处的两个快捷项。
///
/// 行情来自 Yahoo 的 COMEX 期货 `GC=F`、`SI=F`，报价是美元/盎司。国内看金价习惯
/// 元/克，所以默认用 `USDCNY=X` 的汇率换算：1 金衡盎司 = 31.1035 克。设置和面板里
/// 可以切回美元/盎司。这里只有纯换算，取数在 StockService。
public enum PreciousMetal: String, CaseIterable, Sendable {
    case gold, silver

    /// Yahoo 的代码。
    public var symbol: String {
        switch self {
        case .gold: "GC=F"
        case .silver: "SI=F"
        }
    }

    /// 卡片上代替代码显示的中文名，英文界面查表成 Gold、Silver。
    public var title: String {
        switch self {
        case .gold: tr("黄金")
        case .silver: tr("白银")
        }
    }

    /// `GC=F`、`gc=f` 都是黄金；`XAUUSD=X` 这类现货代码也认成同一种金属。
    public init?(symbol: String) {
        switch symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "GC=F", "XAUUSD=X", "XAU=X": self = .gold
        case "SI=F", "XAGUSD=X", "XAG=X": self = .silver
        default: return nil
        }
    }

    /// 汇率的代码：1 美元换多少人民币。
    public static let exchangeSymbol = "USDCNY=X"

    /// 1 金衡盎司是多少克。
    public static let gramsPerOunce = 31.1035

    /// 显示单位。
    public enum DisplayUnit: String, CaseIterable, Sendable {
        case cnyPerGram, usdPerOunce

        public var title: String {
            switch self {
            case .cnyPerGram: tr("元/克")
            case .usdPerOunce: tr("美元/盎司")
            }
        }

        /// 设置键 `metalUnit`。没存或存坏了时用地区默认（中文是元/克），和 WidgetCatalog 一致。
        public static func from(_ config: WidgetConfig) -> DisplayUnit {
            DisplayUnit(rawValue: config.string("metalUnit")) ?? RegionalDefaults.current.metalUnit
        }
    }

    /// 美元/盎司换成要显示的单位要乘的系数。元/克要有汇率，没有汇率（还没取到、
    /// 取失败）时是 nil，界面照旧显示美元/盎司，不拿一个假的汇率去算。
    public static func factor(_ unit: DisplayUnit, usdToCny: Double?) -> Double? {
        switch unit {
        case .usdPerOunce:
            return 1
        case .cnyPerGram:
            guard let usdToCny, usdToCny.isFinite, usdToCny > 0 else { return nil }
            return usdToCny / gramsPerOunce
        }
    }

    /// 一个美元/盎司的价格换成元/克。
    public static func cnyPerGram(usdPerOunce price: Double, usdToCny rate: Double) -> Double? {
        guard price.isFinite, let factor = factor(.cnyPerGram, usdToCny: rate) else { return nil }
        return price * factor
    }

    /// 真正显示出来的单位：要元/克但没有汇率时退回美元/盎司。
    public static func shownUnit(_ unit: DisplayUnit, usdToCny: Double?) -> DisplayUnit {
        factor(unit, usdToCny: usdToCny) == nil ? .usdPerOunce : unit
    }

    /// 这一只有没有单位切换（元/克、美元/盎司）：只有黄金白银有。持仓的成本价
    /// 切换单位时不换算，填成本价的地方给这些品种加一行提示。
    public static func hasUnitSwitch(_ symbol: String) -> Bool {
        PreciousMetal(symbol: symbol) != nil
    }

    /// 这一串代码里有没有贵金属，有的话要顺带取汇率。
    public static func needsExchangeRate(_ symbols: [String], unit: DisplayUnit) -> Bool {
        unit == .cnyPerGram && symbols.contains { PreciousMetal(symbol: $0) != nil }
    }
}

// MARK: - 提醒价跟着单位走

extension PreciousMetal {
    /// 设置键：黄金白银的到价提醒价是按哪个单位记的。
    ///
    /// 提醒价存成一个数（`GC=F>780`），和卡片上显示的价格比。切换单位（元/克和
    /// 美元/盎司）以后数不能原样留着，要按汇率和克/盎司换算过去，所以记下这些数
    /// 是哪个单位的。没写这个键的老设置当作和当前的 `metalUnit` 一致。
    public static let alertUnitKey = "metalAlertUnit"

    /// 提醒价记的单位。
    public static func alertUnit(_ config: WidgetConfig) -> DisplayUnit {
        let current = DisplayUnit.from(config)
        return DisplayUnit(rawValue: config.string(alertUnitKey, default: current.rawValue)) ?? current
    }

    /// 一个价格从一个单位换到另一个单位。同单位原样返回；要用汇率但没有时是 nil。
    public static func converted(_ price: Double, from: DisplayUnit, to: DisplayUnit,
                                 usdToCny: Double?) -> Double? {
        guard price.isFinite else { return nil }
        if from == to { return price }
        guard let source = factor(from, usdToCny: usdToCny),
              let target = factor(to, usdToCny: usdToCny) else { return nil }
        return price / source * target
    }

    /// 换算后的提醒价取到几位：10 以上留两位小数（金价 780.52 元/克、3400.15
    /// 美元/盎司），10 以下留三位（银价 9.876 元/克）。
    public static func roundedAlertPrice(_ price: Double) -> Double {
        let scale = abs(price) >= 10 ? 100.0 : 1000.0
        return (price * scale).rounded() / scale
    }

    /// 设置里有没有黄金白银的提醒。
    public static func hasMetalAlerts(_ config: WidgetConfig) -> Bool {
        StockBoard.alerts(config).contains { PreciousMetal(symbol: $0.symbol) != nil }
    }

    /// 提醒价的单位和设置的单位对不上，等汇率到了换算（这时要顺带取汇率）。
    public static func alertsPending(_ config: WidgetConfig) -> Bool {
        hasMetalAlerts(config) && alertUnit(config) != DisplayUnit.from(config)
    }

    /// 把提醒价对齐到当前的 `metalUnit`，要写回时返回改好的设置，不用改时是 nil。
    ///
    /// - 有黄金白银提醒、还没记单位：记成当前单位（老数据就是按当前单位设的）。
    /// - 单位变了：黄金白银的提醒价按汇率和克/盎司换算，方向（涨到/跌到）不变，
    ///   “已经通知过”的记录跟着换成新的写法，换算以后不会再响一遍。别的代码不动。
    /// - 要汇率但还没有：先不动，返回 nil，等汇率到了再来。在那之前这些提醒不参加
    ///   到价判断（见 `canCheck`），不会拿元/克的数去和美元/盎司的价比。
    public static func reconciled(_ config: WidgetConfig, usdToCny: Double?) -> WidgetConfig? {
        let unit = DisplayUnit.from(config)
        let stored = config.string(alertUnitKey)
        guard hasMetalAlerts(config) else {
            // 没有黄金白银的提醒：记着的旧单位没用了，跟上当前单位，下次新加的就按它算。
            guard !stored.isEmpty, stored != unit.rawValue else { return nil }
            var next = config
            next.set(alertUnitKey, .string(unit.rawValue))
            return next
        }
        guard !stored.isEmpty else {
            var next = config
            next.set(alertUnitKey, .string(unit.rawValue))
            return next
        }
        let from = alertUnit(config)
        guard from != unit else { return nil }
        var renamed: [String: String] = [:]
        var list: [String] = []
        for raw in config.strings("alerts", default: []) {
            guard let alert = StockBoard.Alert.parse(raw), PreciousMetal(symbol: alert.symbol) != nil else {
                list.append(raw)
                continue
            }
            guard let price = converted(alert.price, from: from, to: unit, usdToCny: usdToCny) else { return nil }
            var moved = alert
            moved.price = roundedAlertPrice(price)
            guard moved.price > 0 else { continue }
            renamed[alert.text] = moved.text
            list.append(moved.text)
        }
        var next = config
        next.set("alerts", .list(list.map { .string($0) }))
        let fired = config.strings("alertsFired", default: []).map { renamed[$0] ?? $0 }
        next.set("alertsFired", .list(fired.map { .string($0) }))
        next.set(alertUnitKey, .string(unit.rawValue))
        return next
    }

    /// 切换单位：顺手把提醒价换过去（有汇率时当场换，没有时记下旧单位，等汇率到了
    /// 由 `reconciled` 再换）。
    public static func switching(_ config: WidgetConfig, to unit: DisplayUnit,
                                 usdToCny: Double?) -> WidgetConfig {
        var next = config
        // 先把提醒价原来的单位记死，再改显示单位。
        next.set(alertUnitKey, .string(alertUnit(config).rawValue))
        next.set("metalUnit", .string(unit.rawValue))
        return reconciled(next, usdToCny: usdToCny) ?? next
    }

    /// 这条提醒现在能不能拿卡片上的价去比：股票总能；黄金白银要提醒价的单位和
    /// 实际显示的单位一致（要元/克但汇率还没到、显示的是美元/盎司时不能）。
    public static func canCheck(_ alert: StockBoard.Alert, config: WidgetConfig, usdToCny: Double?) -> Bool {
        guard PreciousMetal(symbol: alert.symbol) != nil else { return true }
        return alertUnit(config) == shownUnit(DisplayUnit.from(config), usdToCny: usdToCny)
    }

    /// 面板里输入的提醒价（按现在显示的单位）换成要存的数（按提醒价的单位）。
    /// 股票原样返回；换不过去（缺汇率）时是 nil，这时不让加。
    public static func storedAlertPrice(_ entered: Double, symbol: String, config: WidgetConfig,
                                        usdToCny: Double?) -> Double? {
        guard PreciousMetal(symbol: symbol) != nil else { return entered }
        let shown = shownUnit(DisplayUnit.from(config), usdToCny: usdToCny)
        let target = alertUnit(config)
        guard shown != target else { return entered }
        return converted(entered, from: shown, to: target, usdToCny: usdToCny).map(roundedAlertPrice)
    }
}
