import Foundation

/// 便签上的一张纸：写了什么、什么颜色。颜色存原始值，认不出的照样留着，
/// 画的时候才按柠檬黄读。
public struct StickySheet: Equatable, Sendable {
    public var text: String
    public var color: String
    /// 这张纸自己的标识，单独钉到桌面时才分配（见 `DesktopPinSheet`），平时是空的。
    /// 翻页、撕掉别的、加新一张都跟着这张纸走。
    public var id: String

    public init(text: String = "", color: String = PaperColor.yellow.rawValue, id: String = "") {
        self.text = text
        self.color = color
        self.id = id
    }

    /// 画出来的纸色：认不出的按柠檬黄；没解锁码头 Pro 时 Pro 纸色也退回柠檬黄。
    public func paper(unlocked: Bool) -> PaperColor {
        ProLicenseGate.noteColor(config: WidgetConfig([ProFeatures.noteColorKey: .string(color)]),
                                 unlocked: unlocked)
    }
}

/// 便签 = 一张长期贴着的纸，可以叠几张，每张一种颜色。
///
/// 不会自动清空，一直贴着直到自己撕掉。行首写 `[ ]` 的行是可勾的清单项
/// （见 `StickyChecklist`），别的行照旧是字。
///
/// 存法和旧版兼容：`text` 和 `color` 仍是最上面那张（设置里的“便签内容”
/// 和“颜色”改的就是它，换颜色只改这一张），其余几张按翻页顺序放在 `stack`
/// 里，每张是 `[颜色, 文字]`，`page` 记最上面那张是第几张（从 1 起）。
/// 旧便签没有 `stack`，读出来就是一张，样子不变；原来添加面板里按颜色分的
/// 样式卡本来就是把 `color` 写进配置，放好的那张直接变成这张纸的颜色设置。
public enum StickyStack {
    public static let textKey = "text"
    public static let colorKey = ProFeatures.noteColorKey
    public static let stackKey = "stack"
    public static let pageKey = "page"
    /// 最上面那张的标识（`StickySheet.id`），没有时不写。其余几张的标识是 `stack` 里
    /// 每项的第三个元素。
    public static let sheetIDKey = "sheetID"
    /// 最多叠几张。原来 3 张，2026-10-20 提到 10 张（叠放翻页不变）。
    public static let limit = 10

    /// 按顺序的几张纸，和最上面那张的下标（从 0 起）。
    public struct Pile: Equatable, Sendable {
        public var sheets: [StickySheet]
        public var page: Int

        public init(sheets: [StickySheet], page: Int = 0) {
            self.sheets = sheets.isEmpty ? [StickySheet()] : Array(sheets.prefix(StickyStack.limit))
            self.page = min(max(0, page), self.sheets.count - 1)
        }

        public var count: Int { sheets.count }
        public var front: StickySheet { sheets[page] }

        /// 最上面那张后面露出来的几张，挨着的在前。
        public var behind: [StickySheet] {
            (1..<count).map { sheets[(page + $0) % count] }
        }

        /// 卡片角上的“1/3”。只有一张时不显示。
        public var marker: String? {
            count > 1 ? "\(page + 1)/\(count)" : nil
        }

        public var canAdd: Bool { count < StickyStack.limit }
        public var canRemove: Bool { count > 1 }

        /// 翻到下一张，最后一张之后回到第一张。
        public func flipped() -> Pile {
            flipped(by: 1)
        }

        /// 往后（正数）或往前（负数）翻几张，首尾相接：第一张往前是最后一张。
        /// 滚轮和触控板往下滚是下一张，往上滚是上一张。
        public func flipped(by step: Int) -> Pile {
            var next = self
            next.page = ((page + step) % count + count) % count
            return next
        }

        /// 改最上面那张的字。
        public func writing(_ text: String) -> Pile {
            var next = self
            next.sheets[page].text = text
            return next
        }

        /// 拖到便签上的文字：在最上面那张末尾另起一行接上。空白的纸直接写上；
        /// 拖来的是空白时不动。多行的文字照原样保留换行，只去掉首尾空白。
        public func appendingLine(_ line: String) -> Pile {
            let words = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return self }
            let current = front.text
            let trimmed = String(current.reversed().drop(while: { $0 == "\n" || $0 == " " }).reversed())
            return writing(trimmed.isEmpty ? words : trimmed + "\n" + words)
        }

        /// 只给最上面那张换颜色，其余几张不动。
        public func coloring(_ color: String) -> Pile {
            var next = self
            next.sheets[page].color = color
            return next
        }

        /// 加一张空白的放到最后，并翻到它。满了不动。
        public func adding(color: String) -> Pile {
            guard canAdd else { return self }
            var next = self
            next.sheets.append(StickySheet(color: color))
            next.page = next.sheets.count - 1
            return next
        }

        /// 这张纸上写了字（不算空白）。空白的纸撕掉不进垃圾桶。
        public var frontHasWords: Bool {
            !front.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 能撕：叠着不止一张，或者只剩一张但上面有字（撕掉后换一张同色的空白纸）。
        public var canTear: Bool { count > 1 || frontHasWords }

        /// 撕掉最上面那张：返回撕完的一叠、撕下来的那张和它原来是第几张（从 0 起）。
        /// 只剩一张时留一张同色的空白纸。撕不了时是 nil。
        public func tearingFront() -> (pile: Pile, sheet: StickySheet, index: Int)? {
            guard canTear else { return nil }
            let sheet = front
            if count == 1 {
                return (Pile(sheets: [StickySheet(color: sheet.color)]), sheet, 0)
            }
            return (removingFront(), sheet, page)
        }

        /// 把一张纸放回第 `index` 张并翻到它（撤销、从垃圾桶恢复）。只剩一张空白纸时
        /// 直接换掉它；满了放不下是 nil。
        public func inserting(_ sheet: StickySheet, at index: Int) -> Pile? {
            if count == 1 && !frontHasWords { return Pile(sheets: [sheet]) }
            guard canAdd else { return nil }
            var list = sheets
            let at = min(max(0, index), list.count)
            list.insert(sheet, at: at)
            return Pile(sheets: list, page: at)
        }

        /// 标识是 `id` 的那一张在第几张（从 0 起），撕掉了是 nil。
        public func index(ofSheet id: String) -> Int? {
            guard !id.isEmpty else { return nil }
            return sheets.firstIndex { $0.id == id }
        }

        /// 给第 `index` 张一个标识（已经有就用原来的），单独钉到桌面前调用。
        public func identifying(at index: Int, newID: String) -> (pile: Pile, id: String)? {
            guard sheets.indices.contains(index) else { return nil }
            if !sheets[index].id.isEmpty { return (self, sheets[index].id) }
            var next = self
            next.sheets[index].id = newID
            return (next, newID)
        }

        /// 改第 `index` 张的字（桌面上摊开的那张），不翻页。
        public func writing(_ text: String, at index: Int) -> Pile {
            guard sheets.indices.contains(index) else { return self }
            var next = self
            next.sheets[index].text = text
            return next
        }

        /// 撕掉最上面那张，露出下一张。只剩一张时不动（清空字就好）。
        public func removingFront() -> Pile {
            guard canRemove else { return self }
            var list = sheets
            list.remove(at: page)
            return Pile(sheets: list, page: page % list.count)
        }
    }

    /// 读出来。旧便签只有 `text`、`color`，就是一张。
    public static func pile(_ config: WidgetConfig) -> Pile {
        let front = StickySheet(text: config.string(textKey),
                                color: config.string(colorKey, default: PaperColor.yellow.rawValue),
                                id: config.string(sheetIDKey))
        var rest: [StickySheet] = []
        if case .list(let items) = config[stackKey] {
            for item in items {
                guard case .list(let pair) = item else { continue }
                var color = PaperColor.yellow.rawValue
                var text = ""
                var id = ""
                if pair.count > 0, case .string(let c) = pair[0] { color = c }
                if pair.count > 1, case .string(let t) = pair[1] { text = t }
                if pair.count > 2, case .string(let i) = pair[2] { id = i }
                rest.append(StickySheet(text: text, color: color, id: id))
            }
        }
        let cyclic = Array(([front] + rest).prefix(limit))
        let n = cyclic.count
        var page = 0
        // 先夹到范围里再转整数：配置里写坏成很大的数时 Int() 会直接崩。
        if case .number(let stored) = config[pageKey], stored.isFinite {
            page = Int(min(max(stored, 0), Double(limit))) - 1
        }
        page = min(max(0, page), n - 1)
        // `cyclic` 从最上面那张起；排回原来的顺序。
        let ordered = (0..<n).map { cyclic[($0 - page + n) % n] }
        return Pile(sheets: ordered, page: page)
    }

    /// 写回去。只有一张时不留 `stack` 和 `page`，和旧便签一模一样。
    public static func store(_ pile: Pile, in config: inout WidgetConfig) {
        config.set(textKey, .string(pile.front.text))
        config.set(colorKey, .string(pile.front.color))
        if pile.front.id.isEmpty {
            config.values.removeValue(forKey: sheetIDKey)
        } else {
            config.set(sheetIDKey, .string(pile.front.id))
        }
        if pile.count > 1 {
            config.set(stackKey, .list(pile.behind.map { sheet in
                sheet.id.isEmpty
                    ? .list([.string(sheet.color), .string(sheet.text)])
                    : .list([.string(sheet.color), .string(sheet.text), .string(sheet.id)])
            }))
            config.set(pageKey, .number(Double(pile.page + 1)))
        } else {
            config.values.removeValue(forKey: stackKey)
            config.values.removeValue(forKey: pageKey)
        }
    }

    /// 新加一张时用的颜色：免费的五种里挑一个还没用上的，挑不出就柠檬黄。
    public static func nextColor(after pile: Pile) -> String {
        let used = Set(pile.sheets.map(\.color))
        let order: [PaperColor] = [.yellow, .mint, .peach, .lavender, .cream]
        return (order.first { !used.contains($0.rawValue) } ?? .yellow).rawValue
    }
}
