import Foundation

/// 一个表情和它的中英文关键词。
public struct EmojiEntry: Hashable, Sendable {
    public let emoji: String
    /// 能不能加肤色（👍 能，😂 不能）。
    public let modifiable: Bool
    public let zh: [String]
    public let en: [String]
}

/// 内置表情表：搜索、肤色用。数据在 `EmojiCatalogData`（Unicode 和 CLDR 生成）。
public enum EmojiCatalog {
    public static let all: [EmojiEntry] = EmojiCatalogData.table
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { line -> EmojiEntry? in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 4, !parts[0].isEmpty else { return nil }
            func words(_ s: Substring) -> [String] {
                s.split(separator: "|").map { String($0).lowercased() }
            }
            return EmojiEntry(emoji: String(parts[0]), modifiable: parts[1] == "1",
                              zh: words(parts[2]), en: words(parts[3]))
        }

    static let index: [String: Int] = {
        var map: [String: Int] = [:]
        for (i, entry) in all.enumerated() where map[entry.emoji] == nil {
            map[entry.emoji] = i
            // 用户手打的可能少了 FE0F（❤ 和 ❤️），两种都认。
            let bare = entry.emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
            if map[bare] == nil { map[bare] = i }
        }
        return map
    }()

    public static func entry(_ emoji: String) -> EmojiEntry? {
        let base = EmojiTone.base(of: emoji)
        if let i = index[base] ?? index[base.replacingOccurrences(of: "\u{FE0F}", with: "")] { return all[i] }
        return nil
    }

    /// 能不能换肤色。表外的（用户在设置里手写的旗子、符号）当作不能。
    public static func isModifiable(_ emoji: String) -> Bool {
        entry(emoji)?.modifiable ?? false
    }

    /// 搜索结果最多这么多个，再多也翻不完。
    public static let searchLimit = 160

    /// 中英文关键词搜索。中文按包含算（笑、心、猫）；英文按词首算（cat 找到
    /// cat face，不会找到 education）。完全相同的关键词排最前，其次是开头相同，
    /// 再次是包含；同分按 Unicode 官方顺序。也能直接粘一个表情进来搜它自己。
    public static func search(_ query: String, limit: Int = searchLimit) -> [EmojiEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, limit > 0 else { return [] }
        // 直接粘了一个表情进来：就是它自己。
        if let hit = entry(q) { return [hit] }
        var scored: [(score: Int, order: Int)] = []
        for (i, entry) in all.enumerated() {
            let s = score(q, entry)
            if s > 0 { scored.append((s, i)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(limit).map { all[$0.order] }
    }

    static func score(_ q: String, _ entry: EmojiEntry) -> Int {
        var best = 0
        for word in entry.zh {
            if word == q { best = max(best, 30) }
            else if word.hasPrefix(q) { best = max(best, 20) }
            else if word.contains(q) { best = max(best, 10) }
        }
        for (n, phrase) in entry.en.enumerated() {
            // 第一个是表情的英文名，名字完全一样最优先。
            if phrase == q { best = max(best, n == 0 ? 31 : 30) }
            let tokens = phrase.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" })
            if tokens.contains(where: { $0 == q }) { best = max(best, 25) }
            else if phrase.hasPrefix(q) { best = max(best, 20) }
            else if tokens.contains(where: { $0.hasPrefix(q) }) { best = max(best, 12) }
        }
        return best
    }

    /// 搜索框右边那句“也能搜 cat”：只在用中文搜时给，取前 8 个结果英文名和
    /// 单词关键词里出现最多的那个词（同样多取先出现的），face、hand 这类太泛的
    /// 不算。没结果就不说。
    public static func alsoTry(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.unicodeScalars.contains(where: isHan) else { return nil }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for entry in search(q, limit: 8) {
            guard let name = entry.en.first else { continue }
            let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).map(String.init)
                + entry.en.dropFirst().filter { !$0.contains(" ") }
            var seen = Set<String>()
            for word in words where !vague.contains(word) && word.allSatisfy(\.isLetter) && seen.insert(word).inserted {
                if counts[word] == nil { order.append(word) }
                counts[word, default: 0] += 1
            }
        }
        guard let top = counts.values.max() else { return nil }
        return order.first { counts[$0] == top }
    }

    static let vague: Set<String> = ["face", "hand", "person", "symbol", "sign", "body",
                                     "with", "of", "the", "and", "a", "in", "on"]

    static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x3400...0x4DBF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || (0xF900...0xFAFF).contains(s.value)
    }
}

/// 肤色：0 是默认的黄色，1 到 5 从浅到深（Fitzpatrick 1-2 到 6）。
public enum EmojiTone {
    public static let count = 6
    static let modifiers: [Unicode.Scalar] = ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]

    public static func clamp(_ tone: Int) -> Int { min(max(tone, 0), count - 1) }

    public static func hasTone(_ emoji: String) -> Bool {
        emoji.unicodeScalars.contains(where: { modifiers.contains($0) })
    }

    /// 去掉肤色，回到表里的写法（✌🏽 回到 ✌️，带 FE0F）。
    public static func base(of emoji: String) -> String {
        guard hasTone(emoji) else { return emoji }
        let stripped = String(String.UnicodeScalarView(emoji.unicodeScalars.filter { !modifiers.contains($0) }))
        // 肤色原本占着第一个字后面的位置；表里那一位是 FE0F 的要补回来。
        guard let first = stripped.unicodeScalars.first,
              stripped.unicodeScalars.dropFirst().first != "\u{FE0F}" else { return stripped }
        var withVS = String.UnicodeScalarView([first, "\u{FE0F}"])
        withVS.append(contentsOf: stripped.unicodeScalars.dropFirst())
        let candidate = String(withVS)
        return EmojiCatalog.index[candidate] != nil ? candidate : stripped
    }

    /// 给一个表情加上肤色：肤色放在第一个字后面，紧跟的 FE0F 去掉（👍 → 👍🏽，
    /// ✌️ → ✌🏽，🙋‍♀️ → 🙋🏽‍♀️）。不能换肤色的、tone 是 0 的原样返回。
    public static func apply(_ tone: Int, to emoji: String) -> String {
        let base = base(of: emoji)
        let t = clamp(tone)
        guard t > 0, EmojiCatalog.isModifiable(base), let first = base.unicodeScalars.first else { return base }
        var out = String.UnicodeScalarView([first, modifiers[t - 1]])
        var rest = base.unicodeScalars.dropFirst()
        if rest.first == "\u{FE0F}" { rest = rest.dropFirst() }
        out.append(contentsOf: rest)
        return String(out)
    }

    /// 表情现在带的是哪一种肤色（没有就是 0）。
    public static func tone(of emoji: String) -> Int {
        guard let s = emoji.unicodeScalars.first(where: { modifiers.contains($0) }),
              let i = modifiers.firstIndex(of: s) else { return 0 }
        return i + 1
    }

    /// 选肤色条上的 6 个：黄色加 5 种肤色。
    public static func variants(of emoji: String) -> [String] {
        (0..<count).map { apply($0, to: emoji) }
    }
}

/// 表情面板存的东西，都在小组件自己的设置里，重启后还在：
/// - `emoji`：收藏（卡片和面板共用，设置页也能写逗号列表），最多 24 个；
/// - `recent`：最近用过，最多 16 个，新的在前；
/// - `skinTone`：默认肤色 0 到 5；
/// - `tones`：单个表情另选的肤色，“👍=3”这样一条一个。
/// 后三个是内容不是设置，不放进目录默认值，设置页里也就没有它们。
/// 收藏、最近都存不带肤色的写法，显示时按单个另选或默认肤色加上去。
public struct EmojiPrefs: Equatable, Sendable {
    public static let favoritesKey = "emoji"
    public static let recentKey = "recent"
    public static let toneKey = "skinTone"
    public static let overridesKey = "tones"
    public static let maxFavorites = 24
    public static let maxRecent = 16
    public static let defaultFavorites = ["😂", "✨", "✅", "🔥", "🥹", "🙏", "💡", "🚀", "❤️"]

    public var favorites: [String]
    public var recent: [String]
    public var tone: Int
    public var overrides: [String: Int]

    public init(favorites: [String] = EmojiPrefs.defaultFavorites, recent: [String] = [],
                tone: Int = 0, overrides: [String: Int] = [:]) {
        self.favorites = favorites
        self.recent = recent
        self.tone = tone
        self.overrides = overrides
    }

    public init(_ config: WidgetConfig) {
        // 没存过收藏的老卡片用默认；用户自己清空的就是空，不再塞回默认。
        let rawFavorites = config.values[Self.favoritesKey] == nil
            ? Self.defaultFavorites : config.strings(Self.favoritesKey)
        var overrides: [String: Int] = [:]
        for item in config.strings(Self.overridesKey) {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let t = Int(parts[1]), (0..<EmojiTone.count).contains(t) else { continue }
            overrides[EmojiTone.base(of: String(parts[0]))] = t
        }
        // 设置页里手写的“👍🏽”：存成不带肤色的，再记一条单个另选。
        var favorites: [String] = []
        for raw in rawFavorites {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let base = EmojiTone.base(of: text)
            if EmojiTone.hasTone(text), overrides[base] == nil { overrides[base] = EmojiTone.tone(of: text) }
            if !favorites.contains(base) { favorites.append(base) }
        }
        self.favorites = Array(favorites.prefix(Self.maxFavorites))
        self.recent = Self.unique(config.strings(Self.recentKey).map(EmojiTone.base(of:)), cap: Self.maxRecent)
        self.tone = EmojiTone.clamp(config.int(Self.toneKey, default: 0))
        self.overrides = overrides
    }

    public func store(in config: inout WidgetConfig) {
        config.set(Self.favoritesKey, .list(favorites.prefix(Self.maxFavorites).map { .string($0) }))
        config.set(Self.recentKey, .list(recent.prefix(Self.maxRecent).map { .string($0) }))
        config.set(Self.toneKey, .number(Double(tone)))
        let lines = overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        config.set(Self.overridesKey, lines.isEmpty ? nil : .list(lines.map { .string($0) }))
    }

    static func unique(_ items: [String], cap: Int) -> [String] {
        var seen = Set<String>()
        return Array(items.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(cap))
    }

    // MARK: 显示

    /// 这个表情现在用哪种肤色：单个另选的优先，否则默认肤色。
    public func toneFor(_ emoji: String) -> Int {
        overrides[EmojiTone.base(of: emoji)] ?? tone
    }

    /// 屏幕上显示、拷贝出去的写法。
    public func display(_ emoji: String) -> String {
        guard EmojiCatalog.isModifiable(emoji) else { return emoji }
        return EmojiTone.apply(toneFor(emoji), to: emoji)
    }

    public func isFavorite(_ emoji: String) -> Bool {
        favorites.contains(EmojiTone.base(of: emoji))
    }

    public var favoritesFull: Bool { favorites.count >= Self.maxFavorites }

    // MARK: 改动（都返回新值，调用的地方写回去）

    /// 用了一次：挪到最近用过的最前面。
    public func recording(_ emoji: String) -> EmojiPrefs {
        var next = self
        let base = EmojiTone.base(of: emoji)
        next.recent = Self.unique([base] + recent.filter { $0 != base }, cap: Self.maxRecent)
        return next
    }

    public func clearingRecent() -> EmojiPrefs {
        var next = self
        next.recent = []
        return next
    }

    /// 星标：没收藏就加到最后，收藏了就移除。满了加不进去，返回 nil。
    public func togglingFavorite(_ emoji: String) -> EmojiPrefs? {
        var next = self
        let base = EmojiTone.base(of: emoji)
        if let i = favorites.firstIndex(of: base) {
            next.favorites.remove(at: i)
        } else {
            guard !favoritesFull else { return nil }
            next.favorites.append(base)
        }
        return next
    }

    public func removingFavorite(at index: Int) -> EmojiPrefs {
        var next = self
        if favorites.indices.contains(index) { next.favorites.remove(at: index) }
        return next
    }

    public func movingFavorite(from: Int, to: Int) -> EmojiPrefs {
        var next = self
        next.favorites = Self.moving(favorites, from: from, to: to)
        return next
    }

    /// 单个表情另选肤色；选回和默认一样的就去掉这一条。
    public func choosingTone(_ tone: Int, for emoji: String) -> EmojiPrefs {
        var next = self
        let base = EmojiTone.base(of: emoji)
        let t = EmojiTone.clamp(tone)
        next.overrides[base] = t == self.tone ? nil : t
        return next
    }

    /// 改默认肤色。之前单个另选成和新默认一样的，那条就多余了，去掉。
    public func settingDefaultTone(_ tone: Int) -> EmojiPrefs {
        var next = self
        next.tone = EmojiTone.clamp(tone)
        next.overrides = overrides.filter { $0.value != next.tone }
        return next
    }

    /// 恢复默认：默认收藏、黄色、没有单个另选。最近用过另有按钮清，这里不动。
    public func restoringDefaults() -> EmojiPrefs {
        EmojiPrefs(favorites: Self.defaultFavorites, recent: recent, tone: 0, overrides: [:])
    }

    // MARK: 网格拖动

    public static func moving<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from) else { return items }
        var out = items
        let item = out.remove(at: from)
        out.insert(item, at: min(max(0, to), out.count))
        return out
    }

    /// 网格里拖了 (dx, dy) 之后落在第几格：按格子大小四舍五入成行列，再夹在
    /// 0 到 count - 1 之间。
    public static func dropIndex(from: Int, dx: Double, dy: Double, cell: Double, rowStep: Double,
                                 columns: Int, count: Int) -> Int {
        guard count > 0, columns > 0, cell > 0, rowStep > 0, from >= 0, from < count else { return max(0, from) }
        let row = from / columns + Int((dy / rowStep).rounded())
        let column = min(max(0, from % columns + Int((dx / cell).rounded())), columns - 1)
        return min(max(0, row * columns + column), count - 1)
    }

    /// 网格要几行。
    public static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }
}
