import Foundation

/// A drink the user named in the 喝水 panel: 椰子水 at 90%, 豆浆 at 80%.
///
/// Logged as a `.custom` entry carrying the drink's id (see WaterEntry), so
/// the log keeps its one letter codes and the name is looked up when shown.
/// The share is written into the entry as well, which is why changing a
/// drink's share later never rewrites what was already drunk.
public struct CustomDrink: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 0.1...1.5, in steps of 0.1.
    public var factor: Double
    /// One of `CustomDrinks.symbols`.
    public var symbol: String
    /// Taken off the chips while today's log still names it, so the row
    /// keeps its name until the day is folded away (see `CustomDrinks.pruned`).
    public var removed: Bool

    public init(id: String, name: String, factor: Double, symbol: String, removed: Bool = false) {
        self.id = id
        self.name = name
        self.factor = CustomDrinks.clampFactor(factor)
        self.symbol = CustomDrinks.symbols.contains(symbol) ? symbol : CustomDrinks.defaultSymbol
        self.removed = removed
    }

    private enum CodingKeys: String, CodingKey { case id, name, factor, symbol, removed }

    /// Lenient: a missing share, symbol or `removed` takes the default rather
    /// than losing the drink.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  factor: (try? c.decodeIfPresent(Double.self, forKey: .factor)) ?? 1,
                  symbol: (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? CustomDrinks.defaultSymbol,
                  removed: (try? c.decodeIfPresent(Bool.self, forKey: .removed)) ?? false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(factor, forKey: .factor)
        try c.encode(symbol, forKey: .symbol)
        if removed { try c.encode(true, forKey: .removed) }
    }

    public var percent: Int { Int((factor * 100).rounded()) }
}

public enum CustomDrinks {
    /// A JSON list in the widget's config, like AIServices' own sites.
    public static let key = "customDrinks"
    /// About as long as 汽水 and 果汁 are wide on a chip, twice over.
    public static let maxNameLength = 8
    /// Chips beyond this would wrap into a wall.
    public static let maxCount = 12
    public static let factorRange: ClosedRange<Double> = 0.1...1.5
    public static let factorStep = 0.1
    public static let symbols = [
        "waterbottle.fill", "cup.and.saucer.fill", "mug.fill", "wineglass.fill",
        "takeoutbag.and.cup.and.straw.fill", "leaf.fill", "carrot.fill", "drop.fill",
    ]
    public static let defaultSymbol = "waterbottle.fill"

    public enum EditError: Error, Equatable, Sendable {
        case emptyName
        case duplicateName
        case tooMany
        case notFound
    }

    // MARK: Reading and writing

    /// Every drink stored, the removed ones too. Anything unreadable reads as
    /// none rather than trapping.
    public static func all(_ config: WidgetConfig) -> [CustomDrink] {
        let raw = config.string(key)
        guard !raw.isEmpty, let list = try? JSONDecoder().decode([CustomDrink].self, from: Data(raw.utf8)) else {
            return []
        }
        var seen = Set<String>()
        return list.filter { validID($0.id) != nil && seen.insert($0.id).inserted }
    }

    /// The chips.
    public static func visible(_ config: WidgetConfig) -> [CustomDrink] {
        all(config).filter { !$0.removed }
    }

    public static func store(_ drinks: [CustomDrink], in config: inout WidgetConfig) {
        guard !drinks.isEmpty, let data = try? JSONEncoder().encode(drinks),
              let text = String(data: data, encoding: .utf8) else {
            config.set(key, nil)
            return
        }
        config.set(key, .string(text))
    }

    // MARK: Rules

    /// Lowercase letters and digits, at most 12: it sits inside a log token
    /// after `#`, so nothing that could be read as a separator.
    public static func validID(_ raw: String) -> String? {
        guard (1...12).contains(raw.count),
              raw.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || (48...57).contains($0.value) })
        else { return nil }
        return raw
    }

    /// A fresh id not already in `drinks`, taken from `seed`.
    public static func newID(among drinks: [CustomDrink], seed: UUID = UUID()) -> String {
        let hex = seed.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let taken = Set(drinks.map(\.id))
        for length in 6...12 {
            let candidate = String(hex.prefix(length))
            if !taken.contains(candidate) { return candidate }
        }
        var n = 1
        while taken.contains("d\(n)") { n += 1 }
        return "d\(n)"
    }

    /// The name as typed, trimmed, on one line and cut to `maxNameLength`
    /// characters; nil when nothing is left.
    public static func cleanName(_ raw: String) -> String? {
        let oneLine = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// 10% to 150% in steps of 10%.
    public static func clampFactor(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        let stepped = (value * 10).rounded() / 10
        return min(factorRange.upperBound, max(factorRange.lowerBound, stepped))
    }

    private static func isTaken(_ name: String, among drinks: [CustomDrink], except id: String? = nil) -> Bool {
        let folded = name.lowercased()
        return drinks.contains { !$0.removed && $0.id != id && $0.name.lowercased() == folded }
    }

    // MARK: Editing

    public static func adding(name: String, factor: Double, symbol: String, id: String,
                              to drinks: [CustomDrink]) -> Result<[CustomDrink], EditError> {
        guard let clean = cleanName(name) else { return .failure(.emptyName) }
        guard drinks.filter({ !$0.removed }).count < maxCount else { return .failure(.tooMany) }
        guard !isTaken(clean, among: drinks) else { return .failure(.duplicateName) }
        guard let id = validID(id), !drinks.contains(where: { $0.id == id }) else { return .failure(.notFound) }
        return .success(drinks + [CustomDrink(id: id, name: clean, factor: factor, symbol: symbol)])
    }

    public static func updating(id: String, name: String, factor: Double, symbol: String,
                                in drinks: [CustomDrink]) -> Result<[CustomDrink], EditError> {
        guard let index = drinks.firstIndex(where: { $0.id == id && !$0.removed }) else { return .failure(.notFound) }
        guard let clean = cleanName(name) else { return .failure(.emptyName) }
        guard !isTaken(clean, among: drinks, except: id) else { return .failure(.duplicateName) }
        var result = drinks
        result[index] = CustomDrink(id: id, name: clean, factor: factor, symbol: symbol)
        return .success(result)
    }

    /// Takes a drink off the chips. One the log still names is kept, marked
    /// removed, so those rows keep their name; one nothing names is gone.
    public static func removing(id: String, in drinks: [CustomDrink], days: [WaterDay]) -> [CustomDrink] {
        let named = referencedIDs(days)
        return drinks.compactMap { drink in
            guard drink.id == id else { return drink }
            guard named.contains(id) else { return nil }
            var kept = drink
            kept.removed = true
            return kept
        }
    }

    /// Drops removed drinks that no row names any more (their days were
    /// folded into a total or deleted).
    public static func pruned(_ drinks: [CustomDrink], days: [WaterDay]) -> [CustomDrink] {
        let named = referencedIDs(days)
        return drinks.filter { !$0.removed || named.contains($0.id) }
    }

    public static func referencedIDs(_ days: [WaterDay]) -> Set<String> {
        Set(days.flatMap(\.entries).compactMap(\.drinkID))
    }

    // MARK: Showing a row

    /// The name a row shows: the drink's own for one the user named, and the
    /// built-in title otherwise, 自定义 for the old generic one or a drink
    /// that is gone.
    public static func title(of entry: WaterEntry, in drinks: [CustomDrink]) -> String {
        guard entry.type == .custom, let id = entry.drinkID,
              let drink = drinks.first(where: { $0.id == id }) else { return entry.type.title }
        return drink.name
    }

    public static func symbol(of entry: WaterEntry, in drinks: [CustomDrink]) -> String {
        guard entry.type == .custom, let id = entry.drinkID,
              let drink = drinks.first(where: { $0.id == id }) else { return entry.type.symbol }
        return drink.symbol
    }
}
