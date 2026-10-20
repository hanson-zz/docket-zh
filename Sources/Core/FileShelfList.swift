import Foundation

/// 文件暂存的清单：放进来的文件位置和放进来的时间，以及「放进来多久后自动移出」。
///
/// 只记位置，不复制、不移动、不删除文件。自动移出和「清掉找不到的」都只是把
/// 条目从清单里拿掉，文件本身一概不碰。
///
/// 存在小组件自己的配置里：`files` 是路径（新的在前，旧版本就是这个键），
/// `added` 是同样顺序的放进来时间（1970 年起的秒数，0 表示旧版本留下的、
/// 不知道什么时候放的）。两个都不是设置项，不放进目录的默认值；`expire`
/// 是设置项，设置页和面板都能改。
public enum FileShelfList {
    public static let pathsKey = "files"
    public static let datesKey = "added"
    public static let expireKey = "expire"
    /// 最多记 50 个，再放就挤掉最早的。
    public static let limit = 50

    public struct Item: Equatable, Sendable {
        public var path: String
        /// nil：旧版本放进来的，不知道时间。开了自动移出以后从那一刻开始算。
        public var added: Date?

        public init(path: String, added: Date?) {
            self.path = path
            self.added = added
        }
    }

    // MARK: 自动移出

    /// 放进来多久后移出清单。顺序就是面板上分段的顺序。
    public enum Expiry: String, CaseIterable, Sendable {
        case one = "1", three = "3", seven = "7", never = "0"

        public var days: Int? {
            switch self {
            case .one: 1
            case .three: 3
            case .seven: 7
            case .never: nil
            }
        }

        public var title: String {
            switch self {
            case .one: tr("1 天")
            case .three: tr("3 天")
            case .seven: tr("7 天")
            case .never: tr("不移出")
            }
        }
    }

    /// 默认不移出：和以前一样，放好的东西不会自己不见。
    public static let defaultExpiry = Expiry.never

    public static func expiry(_ config: WidgetConfig) -> Expiry {
        Expiry(rawValue: config.string(expireKey, default: defaultExpiry.rawValue)) ?? defaultExpiry
    }

    // MARK: 读写

    public static func paths(_ config: WidgetConfig) -> [String] {
        config.strings(pathsKey)
    }

    public static func read(_ config: WidgetConfig) -> [Item] {
        let held = paths(config)
        var stamps: [Double] = []
        if case .list(let list)? = config.values[datesKey] {
            stamps = list.map { value -> Double in
                if case .number(let n) = value { return n }
                return 0
            }
        }
        return held.enumerated().map { index, path in
            let stamp = index < stamps.count ? stamps[index] : 0
            return Item(path: path, added: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil)
        }
    }

    public static func write(_ items: [Item], into config: inout WidgetConfig) {
        config.set(pathsKey, .list(items.map { .string($0.path) }))
        config.set(datesKey, .list(items.map { .number($0.added?.timeIntervalSince1970 ?? 0) }))
    }

    // MARK: 增删

    /// 新放进来的排在最前，按拖进来的顺序；已经在清单里的挪到最前并重新计时。
    public static func adding(_ paths: [String], to items: [Item], now: Date,
                              limit: Int = FileShelfList.limit) -> [Item] {
        var seen = Set<String>()
        let incoming = paths.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !incoming.isEmpty else { return items }
        let fresh = incoming.map { Item(path: $0, added: now) }
        let rest = items.filter { !seen.contains($0.path) }
        return Array((fresh + rest).prefix(max(0, limit)))
    }

    public static func removing(_ paths: Set<String>, from items: [Item]) -> [Item] {
        items.filter { !paths.contains($0.path) }
    }

    // MARK: 到期

    /// 到了这个时间就移出；不移出或不知道放进来时间时为 nil。
    public static func expiresAt(_ item: Item, expiry: Expiry) -> Date? {
        guard let days = expiry.days, let added = item.added else { return nil }
        return added.addingTimeInterval(Double(days) * 86_400)
    }

    public struct Sweep: Equatable, Sendable {
        public var kept: [Item]
        /// 这次移出的路径。
        public var removed: [String]
        /// 清单要不要写回（有移出的，或者给旧条目补上了时间）。
        public var changed: Bool
    }

    /// 把到期的移出清单。开着自动移出时，旧版本留下的不知道时间的条目
    /// 从现在开始算，免得一打开就把它们全清掉。
    public static func sweep(_ items: [Item], expiry: Expiry, now: Date) -> Sweep {
        guard expiry.days != nil else { return Sweep(kept: items, removed: [], changed: false) }
        var kept: [Item] = []
        var removed: [String] = []
        var changed = false
        for var item in items {
            if item.added == nil {
                item.added = now
                changed = true
            }
            if let end = expiresAt(item, expiry: expiry), now >= end {
                removed.append(item.path)
                changed = true
            } else {
                kept.append(item)
            }
        }
        return Sweep(kept: kept, removed: removed, changed: changed)
    }

    /// 下一个条目到期的时间，卡片按它安排下一次检查。
    public static func nextExpiry(_ items: [Item], expiry: Expiry) -> Date? {
        items.compactMap { expiresAt($0, expiry: expiry) }.min()
    }

    // MARK: 文字

    /// 「清掉找不到的 2 个」。
    public static func clearMissingTitle(_ count: Int) -> String {
        tr("清掉找不到的 \(count) 个")
    }

    /// 标题下面那一行。
    public static func subtitle(count: Int, missing: Int, selecting: Bool) -> String {
        if selecting { return tr("点行勾选 · 按住「全部拖出」拖走") }
        if count == 0 { return tr("把文件拖到这里") }
        if missing > 0 { return tr("\(count) 个文件 · \(missing) 个找不到了") }
        return tr("\(count) 个文件 · 拖出即可使用")
    }
}
