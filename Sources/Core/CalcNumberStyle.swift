import Foundation

/// 「算」的结果怎么写：小数位（自动 / 2 位 / 4 位）和千分位。
///
/// 卡片和面板用同一份（读卡片配置 `decimals`、`grouping`），点结果拷贝时
/// 也按显示的样子拷贝。「自动」就是原来各自的规则：算式最多 12 位有效数字、
/// 单位换算 6 位、汇率 2 位；固定位数时四舍五入到那一位，尾巴的零留着，
/// 一列数对得齐。大到要写成科学计数（1e15 以上）的照旧，不硬凑小数位。
public struct CalcNumberStyle: Equatable, Sendable {
    public enum Decimals: String, CaseIterable, Sendable {
        case auto
        case two = "2"
        case four = "4"

        public var title: String {
            switch self {
            case .auto: tr("自动")
            case .two: tr("2 位")
            case .four: tr("4 位")
            }
        }

        var places: Int? {
            switch self {
            case .auto: nil
            case .two: 2
            case .four: 4
            }
        }
    }

    public static let decimalsKey = "decimals"
    public static let groupingKey = "grouping"
    public static let defaultDecimals = Decimals.auto
    /// 配置里没存过 `grouping` 的老卡片不带千分位，和升级前一样。
    public static let defaultGrouping = false
    /// 新放的卡片默认带千分位（效果图的「改后」），在 WidgetCatalog.make 里写进配置。
    public static let newWidgetGrouping = true

    /// 新放一张「算」时写进配置的值。
    public static func applyNewWidget(to config: inout WidgetConfig) {
        config.set(groupingKey, .bool(newWidgetGrouping))
    }

    public var decimals: Decimals
    /// nil = 不动各自规则给的写法（只给测试和旧调用用，卡片配置总有值）。
    public var grouping: Bool?

    public init(decimals: Decimals = .auto, grouping: Bool? = nil) {
        self.decimals = decimals
        self.grouping = grouping
    }

    public init(_ config: WidgetConfig) {
        self.init(decimals: Decimals(rawValue: config.string(Self.decimalsKey,
                                                             default: Self.defaultDecimals.rawValue)) ?? .auto,
                  grouping: config.bool(Self.groupingKey, default: Self.defaultGrouping))
    }

    /// 写出一个结果。`auto` 是这个结果按原来规则写出的字。
    public func text(_ value: Double, auto: String) -> String {
        var out = auto
        if let places = decimals.places, value.isFinite, abs(value) < 1e15 {
            out = String(format: "%.\(places)f", value)
            if out.hasPrefix("-"), Double(out) == 0 { out.removeFirst() }
        }
        switch grouping {
        case true?: return Self.grouped(out)
        case false?: return out.replacingOccurrences(of: ",", with: "")
        case nil: return out
        }
    }

    /// 整数部分每三位加一个逗号。科学计数和认不出的原样返回。
    public static func grouped(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: ",", with: "")
        guard !plain.contains("e"), !plain.contains("E") else { return text }
        var sign = ""
        var body = Substring(plain)
        if body.hasPrefix("-") { sign = "-"; body = body.dropFirst() }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = parts.first, !whole.isEmpty, whole.allSatisfy(\.isNumber) else { return text }
        var digits = Array(whole)
        var index = digits.count - 3
        while index > 0 {
            digits.insert(",", at: index)
            index -= 3
        }
        let fraction = parts.count > 1 ? "." + parts[1] : ""
        return sign + String(digits) + fraction
    }
}
