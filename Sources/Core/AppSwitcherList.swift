import Foundation

/// 应用切换器的排法：固定的 App、隐藏的 App 和排序，卡片和面板共用。
///
/// 规则：
/// - 固定的 App 没开也在（卡片和面板的「固定」一行），点了启动；最多 12 个，按固定的先后排。
/// - 隐藏的 App 不在「正在运行」列表和卡片上；固定和隐藏互斥，固定一个会把它从隐藏里拿出来，反过来也一样。
/// - 「正在运行」三种排序：最近使用（当前的在最前，其余按最近切到的先后，没切过的按打开先后）、
///   名称、固定在前（固定的按固定先后排在前面，其余按最近使用）。
/// - 卡片：固定的在前，后面是没固定、没隐藏的运行中 App，按所选排序。
///
/// 全部是纯函数，配置只存 bundle id。
public enum AppSwitcherList {

    // MARK: Keys

    public static let pinnedKey = "pinned"
    public static let hiddenKey = "hidden"
    public static let sortKey = "sort"

    public static let maxPinned = 12
    public static let maxHidden = 60
    /// 最近使用记多少个。
    public static let maxRecent = 64

    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case recent, name, pinnedFirst

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .recent: tr("最近使用")
            case .name: tr("名称")
            case .pinnedFirst: tr("固定在前")
            }
        }
    }

    // MARK: Reading

    public static func sort(_ config: WidgetConfig) -> Sort {
        Sort(rawValue: config.string(sortKey, default: Sort.recent.rawValue)) ?? .recent
    }

    /// 存着的固定列表：去空、去重，最多 12 个。
    public static func pinned(_ config: WidgetConfig) -> [String] {
        Array(clean(config.strings(pinnedKey)).prefix(maxPinned))
    }

    /// 存着的隐藏列表：去空、去重，去掉已经固定的。
    public static func hidden(_ config: WidgetConfig) -> [String] {
        let pins = Set(pinned(config))
        return Array(clean(config.strings(hiddenKey)).filter { !pins.contains($0) }.prefix(maxHidden))
    }

    static func clean(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out
    }

    // MARK: Editing

    /// 固定或取消固定；固定时从隐藏里拿出来。已满 12 个时固定不了，原样返回。
    public static func togglePin(_ id: String, pinned: [String], hidden: [String])
        -> (pinned: [String], hidden: [String]) {
        if pinned.contains(id) {
            return (pinned.filter { $0 != id }, hidden)
        }
        guard pinned.count < maxPinned, !id.isEmpty else { return (pinned, hidden) }
        return (pinned + [id], hidden.filter { $0 != id })
    }

    /// 隐藏或取消隐藏；隐藏时顺带取消固定。
    public static func toggleHide(_ id: String, pinned: [String], hidden: [String])
        -> (pinned: [String], hidden: [String]) {
        if hidden.contains(id) {
            return (pinned, hidden.filter { $0 != id })
        }
        guard !id.isEmpty else { return (pinned, hidden) }
        return (pinned.filter { $0 != id }, Array((hidden + [id]).suffix(maxHidden)))
    }

    /// 固定的往前（-1）或往后（+1）挪一格，到头不动。
    public static func move(_ id: String, by step: Int, in pinned: [String]) -> [String] {
        guard let index = pinned.firstIndex(of: id) else { return pinned }
        let target = index + step
        guard pinned.indices.contains(target) else { return pinned }
        var list = pinned
        list.swapAt(index, target)
        return list
    }

    /// 切到一个 App 时记一笔：挪到最前面。
    public static func noteActive(_ id: String?, recent: [String]) -> [String] {
        guard let id, !id.isEmpty else { return recent }
        return Array(([id] + recent.filter { $0 != id }).prefix(maxRecent))
    }

    // MARK: Arranging

    /// 一个正在运行的 App；`id` 是 bundle id，传进来的先后是打开的先后。
    public struct App: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var isActive: Bool

        public init(id: String, name: String, isActive: Bool) {
            self.id = id
            self.name = name
            self.isActive = isActive
        }
    }

    /// 最近使用：当前的在最前，其余按 `recent` 的先后，`recent` 里没有的按打开先后排在后面。
    public static func byRecency(_ apps: [App], recent: [String]) -> [App] {
        var rank: [String: Int] = [:]
        for (i, id) in recent.enumerated() where rank[id] == nil { rank[id] = i }
        let indexed = Array(apps.enumerated())
        return indexed.sorted { a, b in
            if a.element.isActive != b.element.isActive { return a.element.isActive }
            let ra = rank[a.element.id], rb = rank[b.element.id]
            switch (ra, rb) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// 按名称，不分大小写，数字按大小，中文按本机的排序规则。
    public static func byName(_ apps: [App], locale: Locale = .current) -> [App] {
        apps.sorted { a, b in
            let order = a.name.compare(b.name, options: [.caseInsensitive, .numeric], range: nil, locale: locale)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// 面板「正在运行」列表：去掉隐藏的，按排序排好。
    public static func running(_ apps: [App], recent: [String], pinned: [String], hidden: [String],
                               sort: Sort, locale: Locale = .current) -> [App] {
        let hide = Set(hidden).subtracting(pinned)
        let shown = apps.filter { !hide.contains($0.id) }
        switch sort {
        case .recent:
            return byRecency(shown, recent: recent)
        case .name:
            return byName(shown, locale: locale)
        case .pinnedFirst:
            let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let front = pinned.compactMap { byID[$0] }
            let pins = Set(pinned)
            return front + byRecency(shown.filter { !pins.contains($0.id) }, recent: recent)
        }
    }

    /// 卡片上的一格：固定的（可能没开）或运行中的。
    public struct Slot: Equatable, Sendable, Identifiable {
        public var id: String
        public var isPinned: Bool
        public var isRunning: Bool
        public var isActive: Bool

        public init(id: String, isPinned: Bool, isRunning: Bool, isActive: Bool) {
            self.id = id
            self.isPinned = isPinned
            self.isRunning = isRunning
            self.isActive = isActive
        }
    }

    /// 卡片：固定的在前（没开也在），后面是其余没隐藏的运行中 App。
    public static func tile(_ apps: [App], recent: [String], pinned: [String], hidden: [String],
                            sort: Sort, locale: Locale = .current) -> [Slot] {
        let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let front = pinned.map { id in
            Slot(id: id, isPinned: true, isRunning: byID[id] != nil, isActive: byID[id]?.isActive ?? false)
        }
        let pins = Set(pinned)
        let rest = running(apps.filter { !pins.contains($0.id) }, recent: recent, pinned: [], hidden: hidden,
                           sort: sort == .pinnedFirst ? .recent : sort, locale: locale)
            .map { Slot(id: $0.id, isPinned: false, isRunning: true, isActive: $0.isActive) }
        return front + rest
    }

    /// 面板标题下的一行：「固定 4 个 · 运行中 6 个」，没固定时「6 个应用正在运行」。
    public static func subtitle(pinned: Int, running: Int) -> String {
        pinned > 0 ? tr("固定 \(pinned) 个 · 运行中 \(running) 个") : tr("\(running) 个应用正在运行")
    }

    /// 窗口列表里没有标题的窗口。
    public static func windowTitle(_ raw: String?, minimized: Bool) -> String {
        let title = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title.isEmpty ? tr("无标题窗口") : title
        return minimized ? tr("\(base)（已最小化）") : base
    }
}
