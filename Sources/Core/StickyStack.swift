import Foundation

/// 便签上的一张纸：写了什么、什么颜色。颜色存原始值，认不出的照样留着，
/// 画的时候才按柠檬黄读。
public struct StickySheet: Equatable, Sendable {
    public var text: String
    public var color: String

    public init(text: String = "", color: String = PaperColor.yellow.rawValue) {
        self.text = text
        self.color = color
    }

    /// 画出来的纸色：认不出的按柠檬黄；没解锁码头 Pro 时 Pro 纸色也退回柠檬黄。
    public func paper(unlocked: Bool) -> PaperColor {
        ProLicenseGate.noteColor(config: WidgetConfig([ProFeatures.noteColorKey: .string(color)]),
                                 unlocked: unlocked)
    }
}

/// 便签 = 一张长期贴着的纸，可以叠几张，每张一种颜色。
///
/// 不能勾选，也不会自动清空，一直贴着直到自己撕掉。
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
    /// 最多叠几张。
    public static let limit = 3

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
            var next = self
            next.page = (page + 1) % count
            return next
        }

        /// 改最上面那张的字。
        public func writing(_ text: String) -> Pile {
            var next = self
            next.sheets[page].text = text
            return next
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
                                color: config.string(colorKey, default: PaperColor.yellow.rawValue))
        var rest: [StickySheet] = []
        if case .list(let items) = config[stackKey] {
            for item in items {
                guard case .list(let pair) = item else { continue }
                var color = PaperColor.yellow.rawValue
                var text = ""
                if pair.count > 0, case .string(let c) = pair[0] { color = c }
                if pair.count > 1, case .string(let t) = pair[1] { text = t }
                rest.append(StickySheet(text: text, color: color))
            }
        }
        let cyclic = Array(([front] + rest).prefix(limit))
        let n = cyclic.count
        var page = 0
        if case .number(let stored) = config[pageKey] { page = Int(stored) - 1 }
        page = min(max(0, page), n - 1)
        // `cyclic` 从最上面那张起；排回原来的顺序。
        let ordered = (0..<n).map { cyclic[($0 - page + n) % n] }
        return Pile(sheets: ordered, page: page)
    }

    /// 写回去。只有一张时不留 `stack` 和 `page`，和旧便签一模一样。
    public static func store(_ pile: Pile, in config: inout WidgetConfig) {
        config.set(textKey, .string(pile.front.text))
        config.set(colorKey, .string(pile.front.color))
        if pile.count > 1 {
            config.set(stackKey, .list(pile.behind.map { .list([.string($0.color), .string($0.text)]) }))
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
