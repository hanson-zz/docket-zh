import Foundation

/// Exchange rates against one base currency, as fetched and as cached.
///
/// Pure: parsing the provider's JSON, crossing two rates, and deciding when a
/// copy is too old are all here so they are tested without the network.
public struct CurrencyRates: Codable, Equatable, Sendable {
    public var base: String
    /// Units of each currency per one unit of `base`.
    public var rates: [String: Double]
    /// When the provider last updated them, not when they were fetched.
    public var updated: Date

    public init(base: String, rates: [String: Double], updated: Date) {
        self.base = base
        self.rates = rates
        self.updated = updated
    }

    /// open.er-api.com's free endpoint:
    /// `{"result":"success","base_code":"CNY","time_last_update_unix":…,"rates":{…}}`.
    /// Nil for an error response or anything malformed.
    public static func parse(_ data: Data) -> CurrencyRates? {
        struct Wire: Decodable {
            var result: String
            var base_code: String?
            var time_last_update_unix: Double?
            var rates: [String: Double]?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.result == "success", let base = wire.base_code,
              let rates = wire.rates, !rates.isEmpty
        else { return nil }
        let clean = rates.filter { $0.value.isFinite && $0.value > 0 }
        guard !clean.isEmpty else { return nil }
        var all = clean
        all[base] = 1
        let updated = wire.time_last_update_unix.map { Date(timeIntervalSince1970: $0) } ?? .now
        return CurrencyRates(base: base, rates: all, updated: updated)
    }

    /// `amount` of `from` in `to`, through the base. Nil when either is
    /// missing from the table.
    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard amount.isFinite, let a = rate(from), let b = rate(to) else { return nil }
        return amount / a * b
    }

    /// One `from` in `to`.
    public func rate(from: String, to: String) -> Double? { convert(1, from: from, to: to) }

    private func rate(_ code: String) -> Double? {
        let code = code.uppercased()
        if code == base.uppercased() { return 1 }
        return rates[code]
    }

    public var codes: [String] { rates.keys.sorted() }

    /// The provider publishes once a day; anything older than that is due a
    /// fetch, though it stays usable until one succeeds.
    public func isStale(now: Date, maxAge: TimeInterval = 12 * 3600) -> Bool {
        now.timeIntervalSince(updated) > maxAge
    }
}

/// The currencies offered in menus, with their Chinese names, in the order a
/// reader in China is most likely to want them.
public enum CurrencyNames {
    public static let common: [(code: String, name: String)] = [
        ("CNY", tr("人民币")), ("USD", tr("美元")), ("EUR", tr("欧元")), ("JPY", tr("日元")),
        ("HKD", tr("港币")), ("GBP", tr("英镑")), ("KRW", tr("韩元")), ("TWD", tr("新台币")),
        ("MOP", tr("澳门元")), ("SGD", tr("新加坡元")), ("AUD", tr("澳元")), ("CAD", tr("加元")),
        ("CHF", tr("瑞士法郎")), ("THB", tr("泰铢")), ("RUB", tr("卢布")), ("NZD", tr("新西兰元")),
        ("MYR", tr("马来西亚林吉特")), ("VND", tr("越南盾")), ("INR", tr("印度卢比")), ("AED", tr("阿联酋迪拉姆")),
    ]

    public static func name(_ code: String) -> String {
        common.first { $0.code == code.uppercased() }?.name ?? code.uppercased()
    }

    /// A converted amount at the currency's own minor units: two decimals for
    /// most, none for yen, won and dong, three for the Gulf dinars. See
    /// `CurrencyCatalog.format`.
    public static func format(_ value: Double, code: String) -> String {
        CurrencyCatalog.format(value, code: code)
    }
}
