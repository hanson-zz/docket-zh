import Foundation

/// 分组窗口里 App 名字的短名：去掉厂商前缀和结尾的年份、版本号，
/// 「Adobe Illustrator 2026」显示成「Illustrator」。
///
/// 只是显示，不改 App 本身，也不改用户自己起的名字（见 `DockGroup.itemNames`）。
/// 去完太短（少于两个字）或什么都不剩就退回原名；同组里两个 App 短名撞了，
/// 一步步把去掉的部分加回来（先加回年份，再加回厂商），直到能分清。
public enum AppShortNames {

    /// 常见的厂商前缀，按整词比较、不分大小写。要加新的厂商往这里加。
    public static let vendorPrefixes: [String] = [
        "Adobe", "Microsoft", "Google", "Apple", "Autodesk", "JetBrains",
        "Mozilla", "Tencent", "腾讯", "Alibaba", "阿里", "Corel", "Wondershare",
    ]

    /// 结尾可以去掉的固定词（不分大小写）。年份和版本号另外按形状判断。
    public static let trailingWords: [String] = ["CC"]

    /// 去完以后至少要有几个字，不然退回原名（「Adobe XD」去完是「XD」，两个字，留着）。
    public static let minimumLength = 2

    /// 一个名字的短名。不用看同组的其他名字时用它；同组一起显示用 `displayNames`。
    public static func shortName(_ name: String) -> String {
        candidate(name, stripVendor: true, stripSuffix: true)
    }

    /// 只去掉一部分时的名字，撞名时一级级退回用。不够长就是原名（去掉首尾空白）。
    public static func candidate(_ name: String, stripVendor: Bool, stripSuffix: Bool) -> String {
        let original = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = original.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return original }
        if stripVendor, let first = words.first,
           vendorPrefixes.contains(where: { $0.caseInsensitiveCompare(first) == .orderedSame }) {
            words.removeFirst()
        }
        if stripSuffix {
            while let last = words.last, words.count > 1, isStrippableSuffix(last) {
                words.removeLast()
            }
            // 「Photoshop 2026」只剩一个词时也要看最后这个：剩下的唯一一个词是
            // 年份（App 就叫「Adobe 2026」）时去掉会空，下面退回原名。
            if words.count == 1, isStrippableSuffix(words[0]) { words.removeAll() }
        }
        let trimmed = trimSeparators(words.joined(separator: " "))
        return trimmed.count >= minimumLength ? trimmed : original
    }

    /// 结尾的这个词能不能去掉：年份（1990 到 2099）、版本号（「8」「v2」「2.1」）、
    /// 固定词（「CC」）。
    public static func isStrippableSuffix(_ word: String) -> Bool {
        let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]"))
        guard !w.isEmpty else { return false }
        if trailingWords.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { return true }
        if w.count == 4, let year = Int(w), (1990...2099).contains(year) { return true }
        // 不带点的纯数字只认三位以内（「8」「16」「365」），四位以上又不是年份的
        // 多半是名字的一部分（「1984」）。
        if w.allSatisfy({ $0.isASCII && $0.isNumber }) { return w.count <= 3 }
        var body = Substring(w)
        if body.first == "v" || body.first == "V" { body = body.dropFirst() }
        guard let first = body.first, first.isASCII, first.isNumber else { return false }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    private static func trimSeparators(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " -–:：·|").union(.whitespaces))
    }

    /// 同组一起显示的名字：按 id 给出。
    ///
    /// - Parameters:
    ///   - names: 组里每一项的原名，按组里的顺序。
    ///   - custom: 用户自己起的名字（按 id），有就用它，不再缩短，也不参与撞名判断。
    public static func displayNames(_ names: [(id: UUID, name: String)],
                                    custom: [UUID: String] = [:]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        // 每一项的几级候选：全去掉、只去厂商（留年份）、只去年份（留厂商）、原名。
        var levels: [UUID: [String]] = [:]
        var auto: [UUID] = []
        for entry in names {
            if let own = custom[entry.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
                result[entry.id] = own
                continue
            }
            levels[entry.id] = [
                candidate(entry.name, stripVendor: true, stripSuffix: true),
                candidate(entry.name, stripVendor: true, stripSuffix: false),
                candidate(entry.name, stripVendor: false, stripSuffix: true),
                entry.name.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            auto.append(entry.id)
        }
        func key(_ s: String) -> String { s.lowercased() }
        // 按全去掉的短名分堆，只有一个的直接用。
        var clusters: [String: [UUID]] = [:]
        var order: [String] = []
        for id in auto {
            let k = key(levels[id]![0])
            if clusters[k] == nil { order.append(k) }
            clusters[k, default: []].append(id)
        }
        for k in order where clusters[k]!.count == 1 {
            let id = clusters[k]![0]
            result[id] = levels[id]![0]
        }
        // 撞名的一堆：找第一级让这一堆互不相同、也不和别的项撞的候选。
        for k in order where clusters[k]!.count > 1 {
            let ids = clusters[k]!
            let others = Set(result.values.map(key))
            var chosen: Int?
            for level in 1..<4 {
                let picked = ids.map { key(levels[$0]![level]) }
                if Set(picked).count == picked.count, others.isDisjoint(with: picked) {
                    chosen = level
                    break
                }
            }
            for id in ids { result[id] = levels[id]![chosen ?? 3] }
        }
        return result
    }
}
