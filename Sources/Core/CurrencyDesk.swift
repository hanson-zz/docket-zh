import Foundation

/// 币种的名字、符号、旗帜、标准小数位和搜索：「算」面板的币种选择器、
/// 多币种列表和换算结果都从这里读。
///
/// 常用的 20 种用 `CurrencyNames.common` 里的中文叫法（有英文翻译），其余按
/// 界面语言向系统要名字。旗帜是国家或地区代码拼出来的旗帜表情（EUR 用欧盟旗），
/// 拼不出的（X 开头的特别提款权、贵金属这类）返回 nil，界面画符号。
public enum CurrencyCatalog {

    public struct Item: Equatable, Hashable, Sendable, Identifiable {
        public var code: String
        public var name: String
        public var symbol: String
        public var flag: String?
        public var id: String { code }
    }

    /// 常用币种写在数字前面的符号；没有的显示代码本身。
    static let symbols: [String: String] = [
        "CNY": "¥", "USD": "$", "EUR": "€", "JPY": "¥", "HKD": "HK$", "GBP": "£", "KRW": "₩",
        "TWD": "NT$", "MOP": "MOP$", "SGD": "S$", "AUD": "A$", "CAD": "C$", "CHF": "Fr",
        "THB": "฿", "RUB": "₽", "NZD": "NZ$", "MYR": "RM", "VND": "₫", "INR": "₹", "AED": "د.إ",
        "PHP": "₱", "IDR": "Rp", "TRY": "₺", "BRL": "R$", "MXN": "Mex$", "ZAR": "R", "ILS": "₪",
        "PLN": "zł", "SEK": "kr", "NOK": "kr", "DKK": "kr", "SAR": "﷼", "UAH": "₴", "KZT": "₸",
        "EGP": "E£", "NGN": "₦", "PKR": "₨", "LKR": "Rs", "BDT": "৳", "MNT": "₮", "CZK": "Kč",
        "HUF": "Ft",
    ]

    /// 没有分的币种（日元、韩元、越南盾这些）和三位小数的（科威特第纳尔这些），
    /// 其余按两位。新台币实际流通不用角分，原来就按整数写，保持。
    static let zeroDecimals: Set<String> = [
        "JPY", "KRW", "VND", "IDR", "TWD", "CLP", "ISK", "PYG", "UGX", "XAF", "XOF", "XPF",
        "KMF", "GNF", "RWF", "DJF", "VUV", "BIF", "LAK", "MMK", "IQD",
    ]
    static let threeDecimals: Set<String> = ["BHD", "KWD", "OMR", "JOD", "TND", "LYD"]

    /// 拼不出旗帜的代码：X 开头的超国家单位和贵金属，以及已经不存在的地区。
    static func hasNoFlag(_ code: String) -> Bool {
        code.hasPrefix("X") || ["ANG"].contains(code)
    }

    public static func fractionDigits(_ code: String) -> Int {
        let code = code.uppercased()
        if zeroDecimals.contains(code) { return 0 }
        if threeDecimals.contains(code) { return 3 }
        return 2
    }

    public static func flag(_ code: String) -> String? {
        let code = code.uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        if code == "EUR" { return "🇪🇺" }
        guard !hasNoFlag(code) else { return nil }
        var out = ""
        for scalar in code.prefix(2).unicodeScalars {
            guard let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return nil }
            out.unicodeScalars.append(flagScalar)
        }
        return out
    }

    public static func symbol(_ code: String) -> String {
        symbols[code.uppercased()] ?? code.uppercased()
    }

    /// 常用的有自己的叫法，其余向系统要（按界面语言），都没有就是代码。
    public static func name(_ code: String) -> String {
        let code = code.uppercased()
        if let known = CurrencyNames.common.first(where: { $0.code == code }) { return known.name }
        if let named = CityFacts.currencies[code] { return L10n.isEnglish ? named.en : named.zh }
        if let system = L10n.interfaceLocale.localizedString(forCurrencyCode: code), !system.isEmpty,
           system.uppercased() != code {
            return system
        }
        return code
    }

    public static func item(_ code: String) -> Item {
        let code = code.uppercased()
        return Item(code: code, name: name(code), symbol: symbol(code), flag: flag(code))
    }

    /// 选择器里列的币种：汇率表里有的全部，没有表时用常用的那些。
    public static func codes(_ rates: CurrencyRates?) -> [String] {
        let table = rates?.codes ?? []
        let common = CurrencyNames.common.map(\.code)
        return table.isEmpty ? common : Array(Set(table).union(common)).sorted()
    }

    /// 搜索：代码开头最先，其次中英文名字、别名（美金、港纸、bucks）、符号。
    /// 空着时 `pinned`（常用）在前，其余按代码排。结果去重。
    public static func search(_ query: String, codes: [String], pinned: [String]) -> [Item] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = Set(codes.map { $0.uppercased() })
        let pins = pinned.map { $0.uppercased() }.filter { all.contains($0) }
        let rank: (String) -> Int = { pins.firstIndex(of: $0) ?? (pins.count + 1) }
        guard !wanted.isEmpty else {
            let rest = all.subtracting(pins).sorted()
            return (dedupe(pins) + rest).map(item)
        }
        var scored: [(code: String, score: Int)] = []
        for code in all {
            if let score = matchScore(code, wanted) { scored.append((code, score)) }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score < $1.score }
            if rank($0.code) != rank($1.code) { return rank($0.code) < rank($1.code) }
            return $0.code < $1.code
        }
        return scored.map { item($0.code) }
    }

    /// 越小越靠前，nil 不匹配。
    static func matchScore(_ code: String, _ query: String) -> Int? {
        let lowerCode = code.lowercased()
        if lowerCode == query { return 0 }
        if lowerCode.hasPrefix(query) { return 1 }
        let name = name(code).lowercased()
        if name.hasPrefix(query) { return 2 }
        if name.contains(query) { return 3 }
        if let named = CityFacts.currencies[code],
           named.zh.lowercased().contains(query) || named.en.lowercased().contains(query) { return 3 }
        if SmartCalc.currencyAliases.contains(where: { $0.value == code && $0.key.hasPrefix(query) }) { return 3 }
        if symbol(code).lowercased() == query { return 4 }
        if query.count >= 2, lowerCode.contains(query) { return 5 }
        return nil
    }

    private static func dedupe(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    /// 金额按币种的标准小数位写，带千分位：100 美元写 100.00，2105.4 日元写 2,105，
    /// 1.2345 科威特第纳尔写 1.235。不到 1 的整数币种写两位（0.47 日元），不到一分的
    /// 写 6 位小数，不写成 0 或 0.00。
    public static func format(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "-" }
        return grouped(value, digits: displayDigits(value, code: code))
    }

    static func displayDigits(_ value: Double, code: String) -> Int {
        var digits = fractionDigits(code)
        if value != 0, abs(value) < 1, digits == 0 { digits = 2 }
        if value != 0, abs(value) < 0.01 { digits = max(digits, 6) }
        return digits
    }

    /// 结果的字：卡片的小数位设置是「自动」时按币种的标准小数位，固定位数时按设置；
    /// 千分位跟设置。
    public static func format(_ value: Double, code: String, style: CalcNumberStyle) -> String {
        style.text(value, auto: format(value, code: code))
    }

    /// 带回计算、拷贝用：按币种小数位四舍五入，不带千分位，去掉没用的零。
    public static func plain(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "0" }
        var text = String(format: "%.\(displayDigits(value, code: code))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    static func grouped(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        if text.hasPrefix("-"), Double(text) == 0 { text.removeFirst() }
        guard abs(value) < 1e15 else { return text }
        return CalcNumberStyle.grouped(text)
    }

    /// 汇率本身：`7.1198`、`0.1405`、`153.21`、`0.006812`。大于 100 两位小数，
    /// 1 到 100 四位，小于 1 四位有效数字，读起来和银行牌价差不多。
    public static func rateText(_ rate: Double) -> String {
        guard rate.isFinite, rate > 0 else { return "-" }
        if rate >= 100 { return String(format: "%.2f", rate) }
        if rate >= 1 { return String(format: "%.4f", rate) }
        let digits = min(10, 3 - Int(floor(log10(rate))))
        return String(format: "%.\(digits)f", rate)
    }

    /// `1 USD = 7.1198 CNY`。
    public static func rateLine(from: String, to: String, rate: Double) -> String {
        "1 \(from.uppercased()) = \(rateText(rate)) \(to.uppercased())"
    }
}

/// 「算」面板的汇率页：从 / 到两行，一个金额同时换成多币种，收藏常用换算，
/// 记录和计算页共用。
///
/// 配置里存的（都在卡片自己的配置里，删卡片一起删）：
/// - `fxFrom`、`fxTo`、`fxAmount`：两行的币种和金额那一栏的原文（可以是算式）。
///   老卡片没有这几个键：先看卡片显示的那条是不是汇率（迁移来的 `100 USD to CNY`），
///   是就照它摆；不是就用设置里的常用币种和默认换成，金额 100。
/// - `fxList`：多币种列表（Pro），没存过时是日元、欧元、港币、英镑。
/// - `fxFavorites`：收藏的换算，写法和记录一样（`100 USD to CNY`），卡片轮播也读它。
/// - `mode`：面板打开在汇率页还是计算页；没存过时看卡片上那条是不是单位或算式。
/// - `keypad`：小键盘开着没有。
///
/// 这些键都不进设置页（`WidgetCatalog` 的默认值里没有），只在面板里改。
public enum CurrencyDesk {

    public static let fromKey = "fxFrom"
    public static let toKey = "fxTo"
    public static let amountKey = "fxAmount"
    public static let listKey = "fxList"
    public static let favoritesKey = "fxFavorites"
    public static let modeKey = "mode"
    public static let keypadKey = "keypad"

    public static let defaultAmount = "100"
    public static let defaultList = ["JPY", "EUR", "HKD", "GBP"]
    public static let listLimit = 8
    public static let favoritesLimit = 12

    public enum Mode: String, CaseIterable, Sendable {
        case fx, calc

        public var title: String {
            switch self {
            case .fx: tr("汇率")
            case .calc: tr("计算")
            }
        }
    }

    /// 面板打开在哪一页：存过就照存的；没存过时卡片上那条是单位或算式就开计算页，
    /// 其余（汇率、空着）开汇率页。
    public static func mode(_ config: WidgetConfig) -> Mode {
        if let stored = Mode(rawValue: config.string(modeKey)) { return stored }
        let shown = SmartCalc.shown(config)
        guard !shown.isEmpty else { return .fx }
        switch SmartCalc.parse(shown).kind {
        case .currency: return .fx
        case .unit, .math: return .calc
        }
    }

    // MARK: 状态

    public struct State: Equatable, Sendable {
        public var from: String
        public var to: String
        /// 金额那一栏的原文：`100`、`1,299*3+50`，也可以带币种 `100 eur to jpy`。
        public var amount: String
        public var list: [String]
        public var favorites: [String]

        public init(from: String = SmartCalc.defaultCurrencyFrom, to: String = SmartCalc.defaultCurrencyTo,
                    amount: String = CurrencyDesk.defaultAmount, list: [String] = CurrencyDesk.defaultList,
                    favorites: [String] = []) {
            self.from = from.uppercased()
            self.to = to.uppercased()
            self.amount = amount
            self.list = CurrencyDesk.cleanList(list)
            self.favorites = favorites
        }

        public init(_ config: WidgetConfig) {
            let list = config[CurrencyDesk.listKey] == nil ? CurrencyDesk.defaultList : config.strings(CurrencyDesk.listKey)
            let favorites = config.strings(CurrencyDesk.favoritesKey)
            let storedFrom = CurrencyDesk.cleanCode(config.string(CurrencyDesk.fromKey))
            let storedTo = CurrencyDesk.cleanCode(config.string(CurrencyDesk.toKey))
            if let storedFrom, let storedTo {
                let amount = config[CurrencyDesk.amountKey] == nil ? CurrencyDesk.defaultAmount
                    : config.string(CurrencyDesk.amountKey)
                self.init(from: storedFrom, to: storedTo, amount: amount, list: list, favorites: favorites)
                return
            }
            // 老卡片：卡片上那条是汇率就照它摆。
            let preferences = SmartCalc.Preferences(config)
            if case .currency(let amount, let from, let to) = SmartCalc.parse(SmartCalc.shown(config)) {
                self.init(from: from, to: to ?? preferences.currencyTarget(for: from),
                          amount: Calculator.format(amount), list: list, favorites: favorites)
                return
            }
            self.init(from: preferences.currencyFrom, to: preferences.currencyTo, amount: CurrencyDesk.defaultAmount,
                      list: list, favorites: favorites)
        }

        public func write(into config: inout WidgetConfig) {
            config.set(CurrencyDesk.fromKey, .string(from))
            config.set(CurrencyDesk.toKey, .string(to))
            config.set(CurrencyDesk.amountKey, .string(amount))
            config.set(CurrencyDesk.listKey, .list(list.map { .string($0) }))
            config.set(CurrencyDesk.favoritesKey, .list(favorites.map { .string($0) }))
        }

        /// 多币种列表里显示的：去掉正在当「从」「到」的两种。
        public var shownList: [String] { list.filter { $0 != from && $0 != to } }
    }

    static func cleanCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return code.count == 3 && code.allSatisfy({ $0.isASCII && $0.isLetter }) ? code : nil
    }

    static func cleanList(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.compactMap(cleanCode).filter { seen.insert($0).inserted }.prefix(listLimit).map { $0 }
    }

    // MARK: 读金额

    public struct Reading: Equatable, Sendable {
        public var from: String
        public var to: String
        /// 算出来的金额；算式写错时为 nil，`failure` 说为什么。
        public var amount: Double?
        public var failure: Calculator.Failure?
        /// 金额栏是算式（不是一个光秃秃的数），界面在下面写「= 3,947.00」。
        public var isExpression: Bool
        /// 金额栏里自己写了币种（`100 eur to jpy`），两行跟着它变。
        public var typedCodes: Bool
    }

    /// 读金额栏：空着按 1（看汇率本身）；带币种的照 SmartCalc 的认法换两行；
    /// 其余当算式。
    public static func read(_ state: State, codes: Set<String> = SmartCalc.commonCodes) -> Reading {
        let text = state.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        var reading = Reading(from: state.from, to: state.to, amount: 1, failure: nil,
                              isExpression: false, typedCodes: false)
        guard !text.isEmpty else { return reading }
        reading.isExpression = plainNumber(text) == nil
        switch SmartCalc.parse(text, codes: codes) {
        case .currency(let amount, let from, let to):
            reading.typedCodes = true
            reading.amount = amount
            reading.from = from
            if let to {
                reading.to = to
            } else if from == state.to {
                // 写了「到」那一种：两行对调。
                reading.to = state.from
            }
            if reading.from == reading.to { reading.to = reading.from == state.to ? state.from : state.to }
            reading.isExpression = true
        default:
            switch Calculator.evaluate(text) {
            case .success(let value):
                reading.amount = value
            case .failure(let failure):
                reading.amount = nil
                reading.failure = failure
            }
        }
        return reading
    }

    /// 只是一个数（可以带千分位、正负号）。
    static func plainNumber(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Double(cleaned)
    }

    // MARK: 换算

    public struct Line: Equatable, Sendable, Identifiable {
        public var code: String
        public var value: Double
        public var text: String
        public var id: String { code }
    }

    public struct Conversion: Equatable, Sendable {
        public var reading: Reading
        /// 「从」那一行算出来的金额，写好的（算式时显示在下面）。
        public var amountText: String
        public var result: Line?
        /// 1 从 = ? 到；没有汇率表或表里缺币种时 nil。
        public var rate: Double?
        public var inverse: Double?
        /// 多币种列表，顺序同 `State.shownList`。缺汇率的币种不列。
        public var list: [Line]

        public var rateLine: String? {
            rate.map { CurrencyCatalog.rateLine(from: reading.from, to: reading.to, rate: $0) }
        }

        public var inverseLine: String? {
            inverse.map { CurrencyCatalog.rateLine(from: reading.to, to: reading.from, rate: $0) }
        }

        /// 拷贝结果：显示的数字，不带千分位，粘到表格里还能算。
        public var copyText: String? { result.map { $0.text.replacingOccurrences(of: ",", with: "") } }

        /// 整句：`3,947.00 USD = 28,101.88 CNY`。
        public var sentence: String? {
            guard let result else { return nil }
            return "\(amountText) \(reading.from) = \(result.text) \(result.code)"
        }

        /// 带去计算页的数：按币种小数位四舍五入，不带千分位。
        public var carryText: String? { result.map { CurrencyCatalog.plain($0.value, code: $0.code) } }
    }

    public static func convert(_ state: State, rates: CurrencyRates?, style: CalcNumberStyle = CalcNumberStyle(),
                               codes: Set<String>? = nil) -> Conversion {
        var known = codes ?? SmartCalc.commonCodes
        if codes == nil, let rates { known.formUnion(rates.rates.keys.map { $0.uppercased() }) }
        let reading = read(state, codes: known)
        let amount = reading.amount
        let amountText = amount.map { CurrencyCatalog.format($0, code: reading.from, style: style) } ?? "-"
        var conversion = Conversion(reading: reading, amountText: amountText, result: nil, rate: nil,
                                    inverse: nil, list: [])
        guard let rates else { return conversion }
        conversion.rate = rates.rate(from: reading.from, to: reading.to)
        conversion.inverse = rates.rate(from: reading.to, to: reading.from)
        guard let amount else { return conversion }
        if let value = rates.convert(amount, from: reading.from, to: reading.to) {
            conversion.result = Line(code: reading.to, value: value,
                                     text: CurrencyCatalog.format(value, code: reading.to, style: style))
        }
        let shown = state.list.filter { $0 != reading.from && $0 != reading.to }
        conversion.list = shown.compactMap { code in
            guard let value = rates.convert(amount, from: reading.from, to: code) else { return nil }
            return Line(code: code, value: value, text: CurrencyCatalog.format(value, code: code, style: style))
        }
        return conversion
    }

    // MARK: 操作

    /// 金额栏里写了币种时，先把它落到两行上，金额栏只留数。
    public static func settled(_ state: State, codes: Set<String> = SmartCalc.commonCodes) -> State {
        let reading = read(state, codes: codes)
        guard reading.typedCodes else { return state }
        var next = state
        next.from = reading.from
        next.to = reading.to
        next.amount = reading.amount.map(Calculator.format) ?? state.amount
        return next
    }

    /// 对调：金额栏不变，100 USD → CNY 变成 100 CNY → USD。
    public static func swapped(_ state: State, codes: Set<String> = SmartCalc.commonCodes) -> State {
        var next = settled(state, codes: codes)
        (next.from, next.to) = (next.to, next.from)
        return next
    }

    /// 选「从」的币种：选了「到」那一种就对调。
    public static func choosingFrom(_ code: String, in state: State, codes: Set<String> = SmartCalc.commonCodes) -> State {
        var next = settled(state, codes: codes)
        let code = code.uppercased()
        if code == next.to { return swapped(next, codes: codes) }
        next.from = code
        return next
    }

    /// 选「到」的币种：选了「从」那一种就对调。原来的「到」顶到列表里它的位置，
    /// 列表里的币种不会因为换一下就少一个。
    public static func choosingTo(_ code: String, in state: State, codes: Set<String> = SmartCalc.commonCodes) -> State {
        var next = settled(state, codes: codes)
        let code = code.uppercased()
        if code == next.from { return swapped(next, codes: codes) }
        if let index = next.list.firstIndex(of: code), !next.list.contains(next.to) {
            next.list[index] = next.to
        }
        next.to = code
        return next
    }

    /// 点多币种列表里的一行：它变成「从」，金额换成它那一行的数，所以其余各行
    /// 的值不变。原来的「从」顶到列表里它的位置。
    public static func promoting(_ code: String, in state: State, rates: CurrencyRates?,
                                 codes: Set<String> = SmartCalc.commonCodes) -> State {
        var next = settled(state, codes: codes)
        let code = code.uppercased()
        guard code != next.from else { return next }
        if code == next.to { return swapped(next, codes: codes) }
        let amount = read(next, codes: codes).amount
        if let amount, let value = rates?.convert(amount, from: next.from, to: code) {
            next.amount = CurrencyCatalog.plain(value, code: code)
        }
        if let index = next.list.firstIndex(of: code), !next.list.contains(next.from) {
            next.list[index] = next.from
        }
        next.from = code
        return next
    }

    /// 方向键换「到」：在「到」和多币种列表里按顺序转。
    public static func cyclingTarget(_ state: State, step: Int, codes: Set<String> = SmartCalc.commonCodes) -> State {
        let settledState = settled(state, codes: codes)
        let order = [settledState.to] + settledState.shownList
        guard order.count > 1 else { return settledState }
        let index = ((step % order.count) + order.count) % order.count
        return choosingTo(order[index], in: settledState, codes: codes)
    }

    // MARK: 多币种列表

    public static func canAdd(_ list: [String]) -> Bool { list.count < listLimit }

    public static func adding(_ code: String, to list: [String]) -> [String] {
        let code = code.uppercased()
        guard !list.contains(code), canAdd(list) else { return list }
        return list + [code]
    }

    public static func removing(_ code: String, from list: [String]) -> [String] {
        list.filter { $0 != code.uppercased() }
    }

    /// 把第 `from` 个挪到第 `to` 个的位置，越界的夹到两头。
    public static func moving(_ list: [String], from: Int, to: Int) -> [String] {
        guard list.indices.contains(from) else { return list }
        var out = list
        let item = out.remove(at: from)
        out.insert(item, at: min(max(to, 0), out.count))
        return out
    }

    /// 拖动排序：拖了多远换算成落到第几个。`step` 是一行的高度加行距。
    public static func dropIndex(from: Int, offset: Double, step: Double, count: Int) -> Int {
        guard count > 0, step > 0, offset.isFinite else { return max(0, min(from, count - 1)) }
        let moved = Int((offset / step).rounded())
        return min(max(from + moved, 0), count - 1)
    }

    /// 拖动的是显示出来的那几行（去掉了「从」「到」），落到存着的列表里对应的位置。
    public static func movingShown(_ state: State, from: Int, to: Int) -> [String] {
        let shown = state.shownList
        guard shown.indices.contains(from), shown.indices.contains(to), from != to else { return state.list }
        let reordered = moving(shown, from: from, to: to)
        var iterator = reordered.makeIterator()
        return state.list.map { shown.contains($0) ? (iterator.next() ?? $0) : $0 }
    }

    // MARK: 记录和收藏

    /// 这一次换算记成一条：`1299*3+50 USD to CNY`，和计算页的记录同一种写法，
    /// 点一下能重算，卡片也能显示。金额栏写了币种的按算出来的数写。
    public static func entry(_ state: State, codes: Set<String> = SmartCalc.commonCodes) -> String? {
        let reading = read(state, codes: codes)
        guard reading.amount != nil else { return nil }
        let text = state.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount: String
        if reading.typedCodes || text.isEmpty {
            amount = Calculator.format(reading.amount ?? 1)
        } else {
            amount = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        }
        return "\(amount) \(reading.from) to \(reading.to)"
    }

    /// 一条记录或收藏读回两行。不是汇率的返回 nil。
    public static func loading(_ entry: String, into state: State, codes: Set<String> = SmartCalc.commonCodes) -> State? {
        guard case .currency(let amount, let from, let to) = SmartCalc.parse(entry, codes: codes) else { return nil }
        var next = state
        next.from = from
        if let to { next.to = to } else if from == state.to { next.to = state.from }
        if next.from == next.to { next.to = next.from == SmartCalc.defaultCurrencyTo ? SmartCalc.defaultCurrencyFrom
            : SmartCalc.defaultCurrencyTo }
        // 记录里的算式原样放回金额栏，好接着改。
        let left = entry.components(separatedBy: " ").first ?? ""
        next.amount = plainNumber(left) != nil || Calculator.evaluate(left) == .success(amount) ? left : Calculator.format(amount)
        return next
    }

    /// 收藏和记录上的短写法：`100 USD → CNY`。认不出的原样。
    public static func label(_ entry: String, codes: Set<String> = SmartCalc.commonCodes) -> String {
        guard case .currency(let amount, let from, let to?) = SmartCalc.parse(entry, codes: codes) else { return entry }
        let left = entry.components(separatedBy: " ").first ?? ""
        let shown = plainNumber(left) == nil && Calculator.evaluate(left) == .success(amount) ? left : Calculator.format(amount)
        return "\(shown) \(from) → \(to)"
    }

    public static func isFavorite(_ entry: String, in favorites: [String]) -> Bool {
        let key = normalized(entry)
        return favorites.contains { normalized($0) == key }
    }

    /// 收藏或取消：新的放最前，最多 `favoritesLimit` 条，满了挤掉最旧的。
    public static func togglingFavorite(_ entry: String, in favorites: [String]) -> [String] {
        let key = normalized(entry)
        if favorites.contains(where: { normalized($0) == key }) {
            return favorites.filter { normalized($0) != key }
        }
        return Array(([entry] + favorites).prefix(favoritesLimit))
    }

    static func normalized(_ entry: String) -> String {
        entry.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
    }

    // MARK: 卡片轮播

    /// 卡片轮播的几条：Pro、收藏至少两条、没有固定别的、最后一次也是汇率（或空着）时，
    /// 卡片轮流显示收藏。刚在计算页算了单位或算式时卡片先显示那一条，下次换算汇率后
    /// 再接着轮播。
    public static func rotation(_ config: WidgetConfig, unlocked: Bool) -> [String] {
        guard unlocked, config.string(SmartCalc.pinnedKey).trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let last = config.string(SmartCalc.expressionKey).trimmingCharacters(in: .whitespaces)
        if !last.isEmpty, SmartCalc.parse(last).kind != .currency { return [] }
        let favorites = config.strings(favoritesKey).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return favorites.count >= 2 ? favorites : []
    }

    /// 轮播每条停几秒。
    public static let rotationPeriod: TimeInterval = 6

    /// 现在轮到第几条：按钟点算，几张卡片、重开面板都对得上，不用自己记。
    public static func rotationIndex(now: Date, count: Int, period: TimeInterval = rotationPeriod) -> Int {
        guard count > 0, period > 0 else { return 0 }
        let tick = Int((now.timeIntervalSince1970 / period).rounded(.down))
        return ((tick % count) + count) % count
    }

    // MARK: 小键盘

    public enum Key: Hashable, Sendable {
        case digit(Int)
        case doubleZero
        case dot
        case add, subtract, multiply, divide
        case open, close
        case back
        case clear

        /// 键帽上的字。
        public var title: String {
            switch self {
            case .digit(let n): String(n)
            case .doubleZero: "00"
            case .dot: "."
            case .add: "+"
            case .subtract: "−"
            case .multiply: "×"
            case .divide: "÷"
            case .open: "("
            case .close: ")"
            case .back: "⌫"
            case .clear: "C"
            }
        }

        var isOperator: Bool { [.add, .subtract, .multiply, .divide].contains(self) }

        /// 写进输入框的字：ASCII，和键盘打的一样，Calculator 照常认。
        var insert: String {
            switch self {
            case .add: "+"
            case .subtract: "-"
            case .multiply: "*"
            case .divide: "/"
            default: title
            }
        }
    }

    /// 小键盘的排法，一行四个。
    public static let keypad: [[Key]] = [
        [.clear, .open, .close, .divide],
        [.digit(7), .digit(8), .digit(9), .multiply],
        [.digit(4), .digit(5), .digit(6), .subtract],
        [.digit(1), .digit(2), .digit(3), .add],
        [.digit(0), .doubleZero, .dot, .back],
    ]

    /// 按一下小键盘后输入框里的字。运算符接运算符时换掉前一个（开头和括号后
    /// 只允许负号）；一个数里只有一个小数点；空着按小数点写「0.」；「0」后按数字换掉它。
    public static func pressing(_ key: Key, in text: String) -> String {
        let operators: Set<Character> = ["+", "-", "*", "/"]
        switch key {
        case .clear:
            return ""
        case .back:
            return String(text.dropLast())
        case .add, .subtract, .multiply, .divide:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasSuffix("(") {
                return key == .subtract ? trimmed + "-" : trimmed
            }
            if let last = trimmed.last, operators.contains(last) {
                let head = String(trimmed.dropLast())
                if head.isEmpty || head.hasSuffix("(") { return key == .subtract ? trimmed : head }
                return head + key.insert
            }
            return trimmed + key.insert
        case .dot:
            let segment = currentNumber(text)
            if segment.contains(".") { return text }
            return segment.isEmpty ? text + "0." : text + "."
        case .digit, .doubleZero:
            let segment = currentNumber(text)
            if segment == "0" {
                if key == .doubleZero || key == .digit(0) { return text }
                return String(text.dropLast()) + key.insert
            }
            if key == .doubleZero, segment.isEmpty { return text + "0" }
            return text + key.insert
        case .open:
            if let last = text.last, last.isNumber || last == ")" { return text + "*(" }
            return text + "("
        case .close:
            let opens = text.filter { $0 == "(" }.count
            let closes = text.filter { $0 == ")" }.count
            guard opens > closes, let last = text.last, last.isNumber || last == ")" else { return text }
            return text + ")"
        }
    }

    /// 输入框结尾正在写的那个数。
    static func currentNumber(_ text: String) -> String {
        var out = ""
        for c in text.reversed() {
            guard c.isNumber || c == "." else { break }
            out.insert(c, at: out.startIndex)
        }
        return out
    }
}
