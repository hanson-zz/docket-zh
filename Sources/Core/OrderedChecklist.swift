import Foundation

/// 设置页和面板里「可拖动勾选列表」背后的规则，纯函数，方便测试。
///
/// 存的仍是原来那个列表键（比如系统活动的 `metrics`、快速开关的 `actions`）：
/// 里面只放勾上的，先后就是卡片上的顺序。画列表时勾上的按存的先后排在前面，
/// 没勾的按目录顺序跟在后面。
///
/// - 拖动只排勾上的那几行：拖到哪一行的位置就插到哪，没勾的行不能拖（拖柄画淡），
///   因为它们的先后不存，拖了松手也会回到原处。
/// - 勾上一项接在勾上的最后面；取消勾选从列表里拿掉。
/// - 至少留一项：取消最后一项不写（返回 nil），卡片不会变成空的。
/// - 有上限的列表（`limit`）勾满了再勾不写。
public enum OrderedChecklist {
    /// 用这个控件的设置键：系统活动指标、圆环仪表、快速开关、环境音的声音、摸鱼时钟显示项。
    /// 电池的设备和摸鱼时钟的工作日不在里面：前者卡片按固定位置画，后者是星期几，排序没有意义。
    public static let keys: Set<String> = ["metrics", "rings", "actions", "sounds", "more"]

    public struct Row: Equatable, Sendable {
        public var value: String
        public var on: Bool

        public init(value: String, on: Bool) {
            self.value = value
            self.on = on
        }
    }

    /// 存着的列表里认得的、去掉重复的，按存的先后。卡片读顺序都走这里。
    public static func ordered(_ saved: [String], all: [String]) -> [String] {
        let known = Set(all)
        var seen = Set<String>()
        return saved.filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// 列表上的每一行：勾上的在前（存的先后），没勾的在后（目录顺序）。
    public static func rows(saved: [String], all: [String]) -> [Row] {
        let on = ordered(saved, all: all)
        let onSet = Set(on)
        return on.map { Row(value: $0, on: true) } + all.filter { !onSet.contains($0) }.map { Row(value: $0, on: false) }
    }

    /// 把勾上的 `value` 挪到 `target` 那一行的位置，返回新的存法。
    /// 拖的不是勾上的、目标不在列表里、或位置没变，返回 nil（不用写）。
    /// 目标是没勾的行时放到勾上的最后面。
    public static func move(saved: [String], all: [String], value: String, onto target: String) -> [String]? {
        var on = ordered(saved, all: all)
        guard let from = on.firstIndex(of: value), value != target, all.contains(target) else { return nil }
        let to = on.firstIndex(of: target) ?? on.count - 1
        guard from != to else { return nil }
        on.remove(at: from)
        on.insert(value, at: min(to, on.count))
        return on
    }

    /// 上移（-1）或下移（+1）一格，给右键菜单和辅助功能用。到头了返回 nil。
    public static func step(saved: [String], all: [String], value: String, by offset: Int) -> [String]? {
        var on = ordered(saved, all: all)
        guard let from = on.firstIndex(of: value) else { return nil }
        let to = from + offset
        guard on.indices.contains(to), to != from else { return nil }
        on.swapAt(from, to)
        return on
    }

    /// 勾上或取消一项。会变空、超上限、或什么都没变时返回 nil（不写）。
    public static func toggle(saved: [String], all: [String], value: String, on: Bool,
                              limit: Int? = nil) -> [String]? {
        var list = ordered(saved, all: all)
        guard all.contains(value) else { return nil }
        if on {
            guard !list.contains(value) else { return nil }
            if let limit, list.count >= limit { return nil }
            list.append(value)
        } else {
            guard list.contains(value) else { return nil }
            list.removeAll { $0 == value }
            guard !list.isEmpty else { return nil }
        }
        return list
    }

    /// 勾上的能不能再取消：只剩一项时不能。
    public static func canUncheck(saved: [String], all: [String]) -> Bool {
        ordered(saved, all: all).count > 1
    }
}
