import Foundation

/// 「算」：单位换算、汇率换算和计算器合成的一张卡片，一个输入框自动认。
///
/// 规则很简单，按顺序：
/// 1. 带币种（`100 USD`、`100美元`、`¥500 to EUR`、`$20`）走汇率；
/// 2. 带单位（`5 km`、`3 斤`、`72°F`、`10 in to cm`）走单位换算；
/// 3. 其余当算式（`3*4+2`、括号、`200+10%`），交给 `Calculator`。
///
/// 纯逻辑放在 Core，汇率表由调用方传进来（`CurrencyService` 的那份），
/// 这样识别、换算和迁移都能在测试里跑，不碰网络。
public enum SmartCalc {

    // MARK: 字牌

    // 字牌不再分中英：两种界面都是 `CalcBadge` 的小熊猫脸框计算器，见 CalcBadge.swift。

    // MARK: 结果

    public enum Kind: String, Sendable, CaseIterable {
        case currency, unit, math

        /// 卡片右上角的小标签。
        public var tag: String {
            switch self {
            case .currency: tr("汇率")
            case .unit: tr("单位")
            case .math: tr("计算")
            }
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var kind: Kind
        public var value: Double
        /// 显示用的数字，带千分位（汇率）或按各自的规则省掉多余的零。
        public var text: String
        /// 数字后面的单位或币种代码，算式为空。
        public var unit: String
        /// 换算的两头，面板和卡片的小字用：`100 USD`、`5 km`。算式为空。
        public var source: String
        /// 源单位或币种代码（`USD`、`km`），算式为空。
        public var sourceUnit: String
        /// 汇率：一个源币种值多少目标币种，其他为 nil。
        public var rate: Double?
        /// 单位换算的类别（长度、重量、温度）。
        public var category: UnitCategory?

        /// 点击复制时放进剪贴板的：小数位和显示的一样（卡片设了 2 位就拷 2 位），
        /// 但不带千分位，粘到表格或别处再算不会被逗号断开。
        public var copyText: String { text.replacingOccurrences(of: ",", with: "") }

        /// 汇率的单价：`1 USD = 7.12429 CNY`，最多六位有效数字。不是汇率时为 nil。
        public var rateLine: String? {
            guard kind == .currency, let rate else { return nil }
            return "1 \(sourceUnit) = \(UnitConverter.format(rate)) \(unit)"
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case empty
        case math(Calculator.Failure)
        /// 看起来写了单位或币种，但认不出来。
        case unknownUnit(String)
        /// 两头不是同一类：长度换重量、币种换单位。
        case mismatch
        /// 汇率还没取到（第一次打开又没联网），或者表里没有这个币种。
        case noRate(String)

        public var message: String {
            switch self {
            case .empty: tr("输入算式、单位或币种")
            case .math(let failure): failure.message
            case .unknownUnit(let token): tr("认不出“\(token)”")
            case .mismatch: tr("两边不是同一类，没法换算")
            case .noRate(let code): tr("暂时没有 \(code) 的汇率")
            }
        }

        /// 是不是汇率这一路的失败：卡片照样标「汇率」。
        public var kind: Kind {
            switch self {
            case .noRate: .currency
            case .mismatch, .unknownUnit: .unit
            case .empty, .math: .math
            }
        }
    }

    /// 只写了一头时换成什么，由卡片的设置决定。
    public struct Preferences: Equatable, Sendable {
        /// 常用币种：输入的就是「默认换成」那种时，换成它。
        public var currencyFrom: String
        /// 默认换成：输入别的币种时都换成它。
        public var currencyTo: String
        /// 旧的单位换算卡片留下的一对单位：输入其中一个时换成另一个。
        public var unitFrom: ConversionUnit?
        public var unitTo: ConversionUnit?
        /// 结果的小数位和千分位。
        public var number: CalcNumberStyle

        public init(currencyFrom: String = SmartCalc.defaultCurrencyFrom,
                    currencyTo: String = SmartCalc.defaultCurrencyTo,
                    unitFrom: ConversionUnit? = nil, unitTo: ConversionUnit? = nil,
                    number: CalcNumberStyle = CalcNumberStyle()) {
            self.currencyFrom = currencyFrom.uppercased()
            self.currencyTo = currencyTo.uppercased()
            self.unitFrom = unitFrom
            self.unitTo = unitTo
            self.number = number
        }

        public init(_ config: WidgetConfig) {
            let from = config.string(SmartCalc.currencyFromKey, default: SmartCalc.defaultCurrencyFrom)
            let to = config.string(SmartCalc.currencyToKey, default: SmartCalc.defaultCurrencyTo)
            self.init(currencyFrom: from.isEmpty ? SmartCalc.defaultCurrencyFrom : from,
                      currencyTo: to.isEmpty ? SmartCalc.defaultCurrencyTo : to,
                      unitFrom: ConversionUnit(rawValue: config.string(SmartCalc.unitFromKey)),
                      unitTo: ConversionUnit(rawValue: config.string(SmartCalc.unitToKey)),
                      number: CalcNumberStyle(config))
        }

        /// 只写了源币种时的目标。
        public func currencyTarget(for code: String) -> String {
            let code = code.uppercased()
            if code != currencyTo { return currencyTo }
            if code != currencyFrom { return currencyFrom }
            return code == "CNY" ? "USD" : "CNY"
        }

        /// 只写了源单位时的目标：先看旧卡片留下的那一对，再用常见的对应。
        public func unitTarget(for unit: ConversionUnit) -> ConversionUnit {
            if let a = unitFrom, let b = unitTo, a.category == b.category, a != b {
                if unit == a { return b }
                if unit == b { return a }
            }
            return SmartCalc.counterpart(unit)
        }
    }

    // MARK: 配置键

    /// 最后一次输入。和旧计算器同一个键，旧卡片的算式直接接着用。
    public static let expressionKey = "expression"
    /// 最近记录，新的在前。
    public static let historyKey = "history"
    /// 固定到卡片的一条；有它时卡片显示它而不是最后一次。
    public static let pinnedKey = "pinned"
    public static let currencyFromKey = "currencyFrom"
    public static let currencyToKey = "currencyTo"
    public static let unitFromKey = "unitFrom"
    public static let unitToKey = "unitTo"

    public static let defaultCurrencyFrom = "USD"
    public static let defaultCurrencyTo = "CNY"
    public static let historyLimit = 12

    // MARK: 识别

    /// 认出来的输入，还没算。
    public enum Parsed: Equatable, Sendable {
        case currency(amount: Double, from: String, to: String?)
        case unit(value: Double, from: ConversionUnit, to: ConversionUnit?)
        case math(String)
        case failure(Failure)

        public var kind: Kind {
            switch self {
            case .currency: .currency
            case .unit: .unit
            case .math: .math
            case .failure(let failure): failure.kind
            }
        }
    }

    /// 输入属于哪一类。`codes` 是汇率表里有的币种代码（没有表时用常用的那些），
    /// 三个字母的代码只认这里面的，免得把随便三个字母当成币种。
    public static func parse(_ text: String, codes: Set<String> = commonCodes) -> Parsed {
        var input = clean(text)
        // 结尾的「=」「=?」「是多少」只是在问结果。
        for tail in ["=?", "＝?", "=？", "＝？", "=", "＝", "?", "？", "是多少", "等于多少", "等于几"] where input.hasSuffix(tail) {
            input = String(input.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !input.isEmpty else { return .failure(.empty) }

        // 先试「A to B」：每个分隔符都试，两边都认得才算数。
        var splitFailure: Failure?
        for separator in separators {
            var searchStart = input.startIndex
            while let range = input.range(of: separator, options: .caseInsensitive,
                                          range: searchStart..<input.endIndex) {
                searchStart = input.index(after: range.lowerBound)
                let left = String(input[input.startIndex..<range.lowerBound])
                let right = String(input[range.upperBound..<input.endIndex])
                guard !left.trimmingCharacters(in: .whitespaces).isEmpty,
                      !right.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                guard let target = token(right, codes: codes) else { continue }
                switch (quantity(left, codes: codes), target) {
                case (.currency(let amount, let from)?, .currency(let to)):
                    return .currency(amount: amount, from: from, to: to)
                case (.unit(let value, let from)?, .unit(let to)):
                    guard from.category == to.category else { splitFailure = .mismatch; continue }
                    return .unit(value: value, from: from, to: to)
                case (.unknown(let word)?, _):
                    splitFailure = .unknownUnit(word)
                case (.some, _):
                    splitFailure = .mismatch
                case (nil, _):
                    continue
                }
            }
        }

        switch quantity(input, codes: codes) {
        case .currency(let amount, let from)?: return .currency(amount: amount, from: from, to: nil)
        case .unit(let value, let from)?: return .unit(value: value, from: from, to: nil)
        case .bare(let expression)?:
            if let splitFailure { return .failure(splitFailure) }
            return .math(expression)
        case .unknown(let word)?:
            return .failure(splitFailure ?? .unknownUnit(word))
        case nil:
            return .failure(splitFailure ?? .math(.empty))
        }
    }

    /// 认出来并算好。`rates` 为 nil 时汇率这一路返回 `.noRate`。
    public static func evaluate(_ text: String, rates: CurrencyRates?,
                                preferences: Preferences = Preferences()) -> Result<Outcome, Failure> {
        var codes = commonCodes
        if let rates { codes.formUnion(rates.rates.keys.map { $0.uppercased() }) }
        switch parse(text, codes: codes) {
        case .failure(let failure):
            return .failure(failure)
        case .math(let expression):
            switch Calculator.evaluate(expression) {
            case .success(let value):
                return .success(Outcome(kind: .math, value: value,
                                        text: preferences.number.text(value, auto: Calculator.format(value)),
                                        unit: "", source: "", sourceUnit: "", rate: nil, category: nil))
            case .failure(let failure):
                return .failure(.math(failure))
            }
        case .unit(let value, let from, let to):
            let target = to ?? preferences.unitTarget(for: from)
            guard let result = UnitConverter.convert(value, from: from, to: target) else {
                return .failure(.mismatch)
            }
            return .success(Outcome(kind: .unit, value: result,
                                    text: preferences.number.text(result, auto: UnitConverter.format(result)),
                                    unit: target.symbol,
                                    source: "\(UnitConverter.format(value)) \(from.symbol)",
                                    sourceUnit: from.symbol, rate: nil, category: from.category))
        case .currency(let amount, let from, let to):
            let target = to ?? preferences.currencyTarget(for: from)
            guard let rates else { return .failure(.noRate(from == target ? from : target)) }
            guard let result = rates.convert(amount, from: from, to: target) else {
                let missing = rates.rate(from: from, to: from) == nil ? from : target
                return .failure(.noRate(missing))
            }
            return .success(Outcome(kind: .currency, value: result,
                                    text: preferences.number.text(result, auto: CurrencyNames.format(result, code: target)),
                                    unit: target,
                                    source: "\(CurrencyNames.format(amount, code: from)) \(from)",
                                    sourceUnit: from, rate: rates.rate(from: from, to: target), category: nil))
        }
    }

    // MARK: 最近记录

    /// 把一次输入放到最前，去掉重复和空白，最多留 `historyLimit` 条。
    public static func remembering(_ entry: String, in history: [String], limit: Int = historyLimit) -> [String] {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return Array(history.prefix(limit)) }
        return Array(([entry] + history.filter { $0 != entry }).prefix(limit))
    }

    /// 卡片上显示哪一条：固定的优先，否则最后一次。
    public static func shown(_ config: WidgetConfig) -> String {
        let pinned = config.string(pinnedKey).trimmingCharacters(in: .whitespaces)
        if !pinned.isEmpty { return pinned }
        return config.string(expressionKey).trimmingCharacters(in: .whitespaces)
    }

    // MARK: 迁移

    /// 旧的「单位换算」「汇率换算」存档里的 kind 原始值。
    public static let legacyConverterKind = "converter"
    public static let legacyCurrencyKind = "currency"

    /// 旧计算器：算式照旧在 `expression`，补一条最近记录。
    public static func migratingCalculator(_ config: WidgetConfig) -> WidgetConfig {
        var out = config
        let expression = config.string(expressionKey).trimmingCharacters(in: .whitespaces)
        if out[historyKey] == nil, !expression.isEmpty {
            out.set(historyKey, .list([.string(expression)]))
        }
        return out
    }

    /// 旧单位换算（`category`、`from`、`to`、`value`）读成「算」：
    /// 最后一次输入写成 `1 mi to km`，那一对单位留作只写一头时的默认。
    public static func migratingConverter(_ config: WidgetConfig) -> WidgetConfig {
        let category = UnitCategory(rawValue: config.string("category")) ?? .length
        let pair = category.defaultPair
        var from = ConversionUnit(rawValue: config.string("from")) ?? pair.from
        var to = ConversionUnit(rawValue: config.string("to")) ?? pair.to
        if from.category != category { from = pair.from }
        if to.category != category { to = pair.to }
        var value = config.double("value", default: 1)
        if !value.isFinite { value = 1 }

        var out = config
        for key in ["category", "from", "to", "value"] { out.set(key, nil) }
        let expression = "\(UnitConverter.format(value)) \(from.symbol) to \(to.symbol)"
        out.set(expressionKey, .string(expression))
        out.set(historyKey, .list([.string(expression)]))
        out.set(unitFromKey, .string(from.rawValue))
        out.set(unitToKey, .string(to.rawValue))
        return out
    }

    /// 旧汇率换算（`from`、`to`、`amount`）读成「算」：币种对变成默认币种对，
    /// 最后一次输入写成 `100 USD to CNY`。
    public static func migratingCurrency(_ config: WidgetConfig) -> WidgetConfig {
        let from = cleanCode(config.string("from", default: defaultCurrencyFrom), fallback: defaultCurrencyFrom)
        let to = cleanCode(config.string("to", default: defaultCurrencyTo), fallback: defaultCurrencyTo)
        var amount = config.double("amount", default: 100)
        if !amount.isFinite { amount = 100 }

        var out = config
        for key in ["from", "to", "amount"] { out.set(key, nil) }
        let expression = "\(Calculator.format(amount)) \(from) to \(to)"
        out.set(expressionKey, .string(expression))
        out.set(historyKey, .list([.string(expression)]))
        out.set(currencyFromKey, .string(from))
        out.set(currencyToKey, .string(to))
        return out
    }

    private static func cleanCode(_ raw: String, fallback: String) -> String {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return code.count == 3 && code.allSatisfy({ $0.isASCII && $0.isLetter }) ? code : fallback
    }

    // MARK: 词表

    /// 常用币种的代码，汇率表还没到时也认。
    public static let commonCodes: Set<String> = Set(CurrencyNames.common.map(\.code))

    /// 「A 换成 B」的分隔符，先试明确的，`in` 和 `=` 最后试（`5 in to cm` 里的 in 是英寸）。
    static let separators: [String] = [
        " to ", " into ", "->", "→", "=>", "⇒",
        "换算成", "兑换成", "转换成", "换成", "转成", "折合", "合多少", "等于多少", "是多少", "等于", "兑",
        " in ", " as ", "=", "＝",
    ]

    /// 只能写在数字前面的币种符号，长的在前。
    static let prefixSymbols: [(String, String)] = [
        ("us$", "USD"), ("hk$", "HKD"), ("nt$", "TWD"), ("nz$", "NZD"), ("a$", "AUD"), ("c$", "CAD"),
        ("s$", "SGD"), ("jp¥", "JPY"), ("$", "USD"), ("¥", "CNY"), ("￥", "CNY"), ("€", "EUR"),
        ("£", "GBP"), ("₩", "KRW"), ("฿", "THB"), ("₽", "RUB"), ("₹", "INR"), ("₫", "VND"),
    ]

    /// 币种的中英文叫法（小写），代码本身另外认。
    static let currencyAliases: [String: String] = {
        var table: [String: String] = [:]
        let names: [(String, [String])] = [
            ("CNY", ["rmb", "yuan", "人民币", "元", "块", "块钱", "圆", "¥", "￥", "cn¥"]),
            ("USD", ["$", "us$", "dollar", "dollars", "buck", "bucks", "美元", "美金", "刀"]),
            ("EUR", ["€", "euro", "euros", "欧元"]),
            ("JPY", ["jp¥", "円", "yen", "日元", "日币", "日圆"]),
            ("HKD", ["hk$", "港币", "港元", "港纸"]),
            ("GBP", ["£", "英镑"]),
            ("KRW", ["₩", "won", "韩元", "韩币"]),
            ("TWD", ["nt$", "新台币", "台币"]),
            ("MOP", ["澳门元", "澳门币", "葡币"]),
            ("SGD", ["s$", "新加坡元", "新币"]),
            ("AUD", ["a$", "澳元", "澳币"]),
            ("CAD", ["c$", "加元", "加币"]),
            ("CHF", ["瑞士法郎", "法郎"]),
            ("THB", ["฿", "baht", "泰铢"]),
            ("RUB", ["₽", "ruble", "rubles", "rouble", "卢布"]),
            ("NZD", ["nz$", "新西兰元", "纽币"]),
            ("MYR", ["ringgit", "林吉特", "马币", "马来西亚林吉特"]),
            ("VND", ["₫", "dong", "越南盾"]),
            ("INR", ["₹", "rupee", "rupees", "印度卢比", "卢比"]),
            ("AED", ["dirham", "dirhams", "迪拉姆", "阿联酋迪拉姆"]),
        ]
        for (code, words) in names { for word in words { table[word] = code } }
        return table
    }()

    /// 单位的中英文叫法（小写）。
    static let unitAliases: [String: ConversionUnit] = {
        var table: [String: ConversionUnit] = [:]
        let names: [(ConversionUnit, [String])] = [
            (.millimetre, ["mm", "毫米", "millimeter", "millimeters", "millimetre", "millimetres"]),
            (.centimetre, ["cm", "厘米", "公分", "centimeter", "centimeters", "centimetre", "centimetres"]),
            (.metre, ["m", "米", "公尺", "meter", "meters", "metre", "metres"]),
            (.kilometre, ["km", "公里", "千米", "kilometer", "kilometers", "kilometre", "kilometres"]),
            (.inch, ["in", "inch", "inches", "英寸", "吋"]),
            (.foot, ["ft", "foot", "feet", "英尺", "呎"]),
            (.yard, ["yd", "yds", "yard", "yards", "码"]),
            (.mile, ["mi", "mile", "miles", "英里"]),
            (.milligram, ["mg", "毫克", "milligram", "milligrams"]),
            (.gram, ["g", "克", "gram", "grams", "gramme"]),
            (.kilogram, ["kg", "kgs", "千克", "公斤", "kilo", "kilos", "kilogram", "kilograms"]),
            (.tonne, ["t", "吨", "公吨", "tonne", "tonnes", "ton", "tons"]),
            (.ounce, ["oz", "ounce", "ounces", "盎司", "安士"]),
            (.pound, ["lb", "lbs", "pound", "pounds", "磅"]),
            (.jin, ["jin", "斤", "市斤"]),
            (.celsius, ["c", "°c", "℃", "°", "celsius", "摄氏度", "摄氏"]),
            (.fahrenheit, ["f", "°f", "℉", "fahrenheit", "华氏度", "华氏"]),
            (.kelvin, ["k", "kelvin", "开尔文", "开氏度"]),
        ]
        for (unit, words) in names { for word in words { table[word] = unit } }
        return table
    }()

    /// 只写了源单位时的常见对应：公制换英制，英制换公制，斤换公斤，温度互换。
    public static func counterpart(_ unit: ConversionUnit) -> ConversionUnit {
        switch unit {
        case .millimetre, .centimetre: .inch
        case .metre: .foot
        case .kilometre: .mile
        case .inch: .centimetre
        case .foot, .yard: .metre
        case .mile: .kilometre
        case .milligram: .gram
        case .gram: .ounce
        case .kilogram: .pound
        case .tonne: .kilogram
        case .ounce: .gram
        case .pound, .jin: .kilogram
        case .celsius: .fahrenheit
        case .fahrenheit, .kelvin: .celsius
        }
    }

    // MARK: 内部

    private enum Target: Equatable {
        case currency(String)
        case unit(ConversionUnit)
    }

    private enum Quantity: Equatable {
        case currency(Double, String)
        case unit(Double, ConversionUnit)
        /// 没有单位：整段是算式。
        case bare(String)
        /// 结尾有字但认不出来。
        case unknown(String)
    }

    /// 全角字母和空白先收拾一下，中文输入法常打出来。
    private static func clean(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF21...0xFF3A, 0xFF41...0xFF5A:
                out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0x3000: out.append(" ")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 数字和算式里会出现的字符：数字后面剩下的才是单位。
    private static func isAmountCharacter(_ c: Character) -> Bool {
        if c.isWhitespace { return true }
        if c.isASCII, c.isNumber { return true }
        if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1,
           (0xFF10...0xFF19).contains(scalar.value) { return true }
        return ".。,，+-*/^()%×÷−–－＋（）％＊／".contains(c)
    }

    /// 目标那一头：只有单位或币种，可以带「多少」「的」。
    private static func token(_ text: String, codes: Set<String>) -> Target? {
        var word = text.trimmingCharacters(in: .whitespaces).lowercased()
        for filler in ["多少", "几"] where word.hasPrefix(filler) {
            word = String(word.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !word.isEmpty else { return nil }
        if let unit = unitAliases[word] { return .unit(unit) }
        if let code = currencyCode(word, codes: codes) { return .currency(code) }
        return nil
    }

    private static func currencyCode(_ word: String, codes: Set<String>) -> String? {
        if let code = currencyAliases[word] { return code }
        let upper = word.uppercased()
        if upper.count == 3, codes.contains(upper) { return upper }
        return nil
    }

    /// 「数字（或算式）加单位」。没有单位就是 `.bare`；只有单位时数量是 1。
    private static func quantity(_ text: String, codes: Set<String>) -> Quantity? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        // 写在前面的币种符号：$100、¥500、HK$20。
        for (symbol, code) in prefixSymbols where lowered.hasPrefix(symbol) {
            let rest = String(trimmed.dropFirst(symbol.count))
            guard let amount = amount(rest, allowEmpty: true) else { return .unknown(trimmed) }
            return .currency(amount, code)
        }

        // 数字后面那段：先当整段单位认，再看是不是「万」「亿」「千」加单位。
        var split = trimmed.endIndex
        while split > trimmed.startIndex {
            let before = trimmed.index(before: split)
            if isAmountCharacter(trimmed[before]) { break }
            split = before
        }
        let number = String(trimmed[trimmed.startIndex..<split])
        let word = String(trimmed[split...]).trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return .bare(trimmed) }

        let lowerWord = word.lowercased()
        var multiplier: Double = 1
        var unitWord = lowerWord
        if unitAliases[lowerWord] == nil, currencyCode(lowerWord, codes: codes) == nil {
            for (mark, factor) in [("万", 1e4), ("亿", 1e8), ("千", 1e3)] where lowerWord.hasPrefix(mark) {
                multiplier = factor
                unitWord = String(lowerWord.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        let numberIsBlank = number.trimmingCharacters(in: .whitespaces).isEmpty
        if unitWord.isEmpty {
            // 「3万」：只有倍数，还是算式。
            guard !numberIsBlank, let value = amount(number, allowEmpty: false) else { return .unknown(word) }
            return .bare(Calculator.format(value * multiplier))
        }
        if let unit = unitAliases[unitWord] {
            // 光一个「c」「m」不带数字太像打错字，不当成单位。
            if numberIsBlank && unitWord.count == 1 { return .unknown(word) }
            guard let value = amount(number, allowEmpty: true) else { return .unknown(trimmed) }
            return .unit(value * multiplier, unit)
        }
        if let code = currencyCode(unitWord, codes: codes) {
            guard let value = amount(number, allowEmpty: true) else { return .unknown(trimmed) }
            return .currency(value * multiplier, code)
        }
        return .unknown(word)
    }

    /// 数量那段：可以是算式（`(100+20) USD`），空着的话按 1 算。
    private static func amount(_ text: String, allowEmpty: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return allowEmpty ? 1 : nil }
        guard case .success(let value) = Calculator.evaluate(trimmed) else { return nil }
        return value
    }
}
