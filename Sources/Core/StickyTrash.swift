import Foundation

/// 便签的垃圾桶：撕掉的纸先放这里，可以恢复、彻底删除或清空。
///
/// 存在这张便签自己的配置 `trash` 里，每张是 `[颜色, 文字, 撕掉的时间（秒）, 编号]`，
/// 最近撕的在前。旧便签没有这一项，读出来就是空的；写坏的项跳过。
///
/// 留多久：7 天之内、最多最近 30 张，两条都要满足，超出的读的时候就丢掉，下次写回时
/// 一起清掉。空白的纸撕掉不进来。
public enum StickyTrash {
    public static let key = "trash"
    public static let maxCount = 30
    public static let maxAge: TimeInterval = 7 * 24 * 3600

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        public var sheet: StickySheet
        public var tornAt: Date

        public init(id: String, sheet: StickySheet, tornAt: Date) {
            self.id = id
            self.sheet = sheet
            self.tornAt = tornAt
        }

        /// 列表里的标题：第一行有字的那行，框子去掉。
        public var title: String {
            for line in StickyChecklist.lines(sheet.text) {
                let words: String
                switch line {
                case .text(let t): words = t
                case .item(_, let t): words = t
                }
                let trimmed = words.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
            return ""
        }

        /// 列表里的小字：有清单项时「清单 2/5」，否则「86 字」（不算空白）。
        public var summary: String {
            let progress = StickyChecklist.progress(sheet.text)
            if progress.total > 0 { return tr("清单 \(progress.done)/\(progress.total)") }
            let count = sheet.text.filter { !$0.isWhitespace }.count
            return tr("\(count) 字")
        }
    }

    /// 撕掉的那一下，撤销时用：撕下来的纸、原来第几张、进垃圾桶时的编号（空白纸没有）。
    public struct Torn: Equatable, Sendable {
        public var sheet: StickySheet
        public var index: Int
        public var entryID: String?
    }

    /// 读出来：最近的在前，过期和超出 30 张的去掉。
    public static func entries(_ config: WidgetConfig, now: Date) -> [Entry] {
        guard case .list(let items) = config[key] else { return [] }
        var list: [Entry] = []
        for item in items {
            guard case .list(let fields) = item, fields.count >= 3,
                  case .string(let color) = fields[0],
                  case .string(let text) = fields[1],
                  case .number(let seconds) = fields[2], seconds.isFinite else { continue }
            var id = "\(seconds)-\(list.count)"
            if fields.count > 3, case .string(let stored) = fields[3], !stored.isEmpty { id = stored }
            list.append(Entry(id: id, sheet: StickySheet(text: text, color: color),
                              tornAt: Date(timeIntervalSince1970: seconds)))
        }
        return pruned(list, now: now)
    }

    /// 按撕掉的时间从新到旧排，只留 7 天之内的、最多 30 张。时间在将来的（改过系统
    /// 时钟）照样留着，排在最前。
    public static func pruned(_ list: [Entry], now: Date) -> [Entry] {
        let fresh = list.filter { now.timeIntervalSince($0.tornAt) <= maxAge }
        let sorted = fresh.enumerated().sorted { a, b in
            a.element.tornAt != b.element.tornAt ? a.element.tornAt > b.element.tornAt : a.offset < b.offset
        }.map(\.element)
        return Array(sorted.prefix(maxCount))
    }

    /// 写回去。空了就把这一项去掉，和旧便签一样。
    public static func store(_ list: [Entry], in config: inout WidgetConfig) {
        if list.isEmpty {
            config.values.removeValue(forKey: key)
            return
        }
        config.set(key, .list(list.map { entry in
            .list([.string(entry.sheet.color), .string(entry.sheet.text),
                   .number(entry.tornAt.timeIntervalSince1970), .string(entry.id)])
        }))
    }

    /// 撕掉最上面那张：写字的纸放进垃圾桶（编号 `id`），露出下一张。撕不了时是 nil。
    public static func tear(_ config: inout WidgetConfig, now: Date, id: String) -> Torn? {
        let pile = StickyStack.pile(config)
        guard let result = pile.tearingFront() else { return nil }
        StickyStack.store(result.pile, in: &config)
        var entryID: String?
        if pile.frontHasWords {
            var list = entries(config, now: now)
            list.insert(Entry(id: id, sheet: result.sheet, tornAt: now), at: 0)
            store(pruned(list, now: now), in: &config)
            entryID = id
        }
        return Torn(sheet: result.sheet, index: result.index, entryID: entryID)
    }

    /// 撤销刚才那一下：从垃圾桶拿出来，放回原来的位置。叠满了放不下时不动，返回 false。
    @discardableResult
    public static func undo(_ torn: Torn, in config: inout WidgetConfig, now: Date) -> Bool {
        guard let back = StickyStack.pile(config).inserting(torn.sheet, at: torn.index) else { return false }
        StickyStack.store(back, in: &config)
        if let id = torn.entryID {
            store(entries(config, now: now).filter { $0.id != id }, in: &config)
        }
        return true
    }

    /// 能不能恢复：叠满 10 张又不是只剩一张空白纸时放不下。
    public static func canRestore(_ config: WidgetConfig) -> Bool {
        let pile = StickyStack.pile(config)
        return pile.canAdd || (pile.count == 1 && !pile.frontHasWords)
    }

    /// 恢复一张：放回最上面（现在这张的位置，原来那张往后挪一张），从垃圾桶拿掉。
    @discardableResult
    public static func restore(_ id: String, in config: inout WidgetConfig, now: Date) -> Bool {
        var list = entries(config, now: now)
        guard let at = list.firstIndex(where: { $0.id == id }) else { return false }
        let pile = StickyStack.pile(config)
        guard let back = pile.inserting(list[at].sheet, at: pile.page) else { return false }
        StickyStack.store(back, in: &config)
        list.remove(at: at)
        store(list, in: &config)
        return true
    }

    /// 彻底删除一张。
    public static func delete(_ id: String, in config: inout WidgetConfig, now: Date) {
        store(entries(config, now: now).filter { $0.id != id }, in: &config)
    }

    /// 清空垃圾桶。
    public static func empty(_ config: inout WidgetConfig) {
        config.values.removeValue(forKey: key)
    }

    /// 过期的已经读不出来了，写回去把它们真的清掉。没变时不写。
    public static func purge(_ config: inout WidgetConfig, now: Date) -> Bool {
        guard case .list(let items) = config[key] else { return false }
        let kept = entries(config, now: now)
        guard kept.count != items.count else { return false }
        store(kept, in: &config)
        return true
    }

    /// 列表里的「刚刚」「3 小时前」「昨天」「5 天前」。
    public static func age(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return tr("刚刚") }
        if seconds < 3600 { return tr("\(Int(seconds / 60)) 分钟前") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return tr("\(Int(seconds / 3600)) 小时前") }
        if days == 1 { return tr("昨天") }
        return tr("\(days) 天前")
    }
}
