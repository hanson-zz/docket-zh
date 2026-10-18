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

        /// 设置键 `metalUnit`，默认元/克。
        public static func from(_ config: WidgetConfig) -> DisplayUnit {
            DisplayUnit(rawValue: config.string("metalUnit", default: DisplayUnit.cnyPerGram.rawValue)) ?? .cnyPerGram
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

    /// 这一串代码里有没有贵金属，有的话要顺带取汇率。
    public static func needsExchangeRate(_ symbols: [String], unit: DisplayUnit) -> Bool {
        unit == .cnyPerGram && symbols.contains { PreciousMetal(symbol: $0) != nil }
    }
}
