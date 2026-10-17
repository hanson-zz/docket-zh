import Foundation

/// 新手引导里可以多选的“用途”。
///
/// 每个用途按偏好顺序列出候选小组件（`WidgetKind.rawValue`）。候选里可以有
/// 目录中暂时没有的种类，挑选时会按目录过滤掉，所以这里
/// 写上它不会让布局里多出一个读不出来的小组件。
public enum OnboardingUse: String, CaseIterable, Sendable, Hashable {
    case productivity, health, system, fun, developer

    public var title: String {
        switch self {
        case .productivity: "效率"
        case .health: "健康"
        case .system: "系统"
        case .fun: "娱乐"
        case .developer: "开发"
        }
    }

    /// 卡片上的一行说明。
    public var caption: String {
        switch self {
        case .productivity: "待办、日历、专注计时、习惯"
        case .health: "喝水、久坐提醒、小熊猫的竹篮"
        case .system: "电池、网络、系统活动"
        case .fun: "音乐、收音机、播客、电子宠物"
        case .developer: "GitHub、Codex 用量"
        }
    }

    public var symbol: String {
        switch self {
        case .productivity: "checklist"
        case .health: "heart.fill"
        case .system: "cpu"
        case .fun: "music.note"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }

    public var colorHex: String {
        switch self {
        case .productivity: PaletteColor.orange.hex
        case .health: PaletteColor.green.hex
        case .system: PaletteColor.blue.hex
        case .fun: PaletteColor.pink.hex
        case .developer: PaletteColor.indigo.hex
        }
    }

    /// 候选小组件，靠前的优先。
    public var candidates: [String] {
        switch self {
        case .productivity: ["todo", "calendar", "timer", "habit", "reminders"]
        case .health: ["water", "posture", "perfect-day"]
        case .system: ["battery", "network", "system", "gauges"]
        case .fun: ["music", "radio", "podcast", "pet"]
        case .developer: ["github", "ai-usage"]
        }
    }
}

/// 新手引导的步骤，顺序即进度条的顺序。
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, position, uses, permissions, building, done

    /// 分段进度条点亮到第几段（从 1 开始）。
    public var filledSegments: Int { rawValue + 1 }

    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    /// 布置中和完成两步不能返回：布局已经生成，返回只会让人以为能撤销。
    public var canGoBack: Bool { previous != nil && self != .building && self != .done }
}

/// 新手引导的纯逻辑：什么时候弹、选了什么就放什么、需要哪些权限。
public enum Onboarding {
    /// UserDefaults 里记录“已经看过新手引导”的键。
    public static let seenKey = "onboarding.seen"

    /// 每个用途最多放几个小组件。
    public static let maxPerUse = 3

    /// “布置中”一步的总时长（秒）。
    public static let buildDuration: Double = 2.5

    /// “布置中”下方清单的三条文字。
    public static let checklist = ["正在读取你的选择", "正在挑选小组件", "正在布置你的码头"]

    /// 是否在启动时弹出新手引导。
    ///
    /// 只看两件事：看过就不再弹；老用户升级上来，已经有保存的布局（或配置）
    /// 的也不弹，免得把一个用了很久的人当成新人。
    public static func shouldShow(seen: Bool, hasSavedSetup: Bool) -> Bool {
        !seen && !hasSavedSetup
    }

    /// 引导关掉以后再等多久才问“要检查码头的新版本吗？”（秒），免得窗口一关
    /// 提示框就迎面弹出来。
    public static let updatePromptSettle: Double = 2

    /// 首次启动时“检查更新”的提示框现在能不能弹。
    ///
    /// 新手引导还开着（或已经排好、马上要弹）时不弹，免得模态提示框盖住引导；
    /// 引导关掉后再等 `updatePromptSettle` 秒。从来没开过引导的（老用户）
    /// `closedAt` 为 nil，照常弹。
    public static func mayPromptForUpdates(onboardingActive: Bool, closedAt: Date?, now: Date) -> Bool {
        guard !onboardingActive else { return false }
        guard let closedAt else { return true }
        return now.timeIntervalSince(closedAt) >= updatePromptSettle
    }

    /// 选中的用途对应要追加的小组件，按用途的固定顺序排列。
    ///
    /// - Parameters:
    ///   - uses: 选中的用途，顺序和重复都不影响结果。
    ///   - available: 目录里存在、可以添加的种类。不在其中的候选直接跳过。
    ///   - existing: 当前布局里已经有的种类。已有的不重复添加，空出的名额由
    ///     后面的候选补上。
    /// - Returns: 不重复的种类列表，每个用途至多 `maxPerUse` 个。
    public static func kinds(for uses: some Sequence<OnboardingUse>,
                             available: Set<String>,
                             existing: Set<String> = []) -> [String] {
        let chosen = Set(uses)
        var picked: [String] = []
        var taken = existing
        for use in OnboardingUse.allCases where chosen.contains(use) {
            var count = 0
            for kind in use.candidates where count < maxPerUse {
                guard available.contains(kind), !taken.contains(kind) else { continue }
                picked.append(kind)
                taken.insert(kind)
                count += 1
            }
        }
        return picked
    }

    /// 这些小组件真正需要的权限，按出现顺序去重。
    public static func permissions(for kinds: [String],
                                   table: [String: String] = WidgetSearch.permissions) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for kind in kinds {
            guard let permission = table[kind], seen.insert(permission).inserted else { continue }
            result.append(permission)
        }
        return result
    }

    /// 布置进度（0...1）时，清单里已经打勾的条数。
    ///
    /// 三条平均分配：过三分之一勾第一条，过三分之二勾第二条，满了勾第三条。
    public static func checkedItems(progress: Double, total: Int = checklist.count) -> Int {
        guard total > 0 else { return 0 }
        let clamped = min(max(progress, 0), 1)
        if clamped >= 1 { return total }
        return min(total - 1, Int(clamped * Double(total)))
    }

    /// 靠岸动画里第 `index` 个小组件（共 `count` 个）此刻走了多远，0 是还在画面外，1 是已经停进扩展栏。
    ///
    /// 小组件一个接一个出发：每个占用 `span` 这么长的一段进度，后一个比前一个晚
    /// 出发，前后有重叠，读起来像排队进港。最后一个正好在进度走满时靠岸。
    public static func dockingFraction(index: Int, count: Int, progress: Double, span: Double = 0.45) -> Double {
        guard count > 0, index >= 0, index < count else { return 0 }
        let clamped = min(max(progress, 0), 1)
        if clamped >= 1 { return 1 }
        let span = min(max(span, 0.05), 1)
        let step = count > 1 ? (1 - span) / Double(count - 1) : 0
        let start = Double(index) * step
        return min(max((clamped - start) / span, 0), 1)
    }

    /// 进度为 `progress` 时已经靠岸的小组件个数。
    public static func dockedCount(count: Int, progress: Double, span: Double = 0.45) -> Int {
        (0..<max(0, count)).filter { dockingFraction(index: $0, count: count, progress: progress, span: span) >= 1 }.count
    }

    /// 靠岸动画里每个小组件小船上的 SF Symbol。
    public static func symbol(for kind: String) -> String {
        symbols[kind] ?? "square.grid.2x2.fill"
    }

    /// 靠岸动画里每个小组件小船的颜色。
    public static func colorHex(for kind: String) -> String {
        colors[kind] ?? PaletteColor.graphite.hex
    }

    private static let symbols: [String: String] = [
        "todo": "checklist",
        "calendar": "calendar",
        "timer": "timer",
        "habit": "checkmark.seal.fill",
        "reminders": "list.bullet",
        "water": "drop.fill",
        "posture": "figure.stand",
        "perfect-day": "leaf.fill",
        "battery": "battery.75percent",
        "network": "wifi",
        "system": "cpu",
        "gauges": "gauge.with.dots.needle.50percent",
        "music": "music.note",
        "radio": "radio.fill",
        "podcast": "headphones",
        "pet": "pawprint.fill",
        "github": "chevron.left.forwardslash.chevron.right",
        "ai-usage": "sparkles",
    ]

    private static let colors: [String: String] = [
        "todo": PaletteColor.orange.hex,
        "calendar": PaletteColor.red.hex,
        "timer": PaletteColor.indigo.hex,
        "habit": PaletteColor.green.hex,
        "reminders": PaletteColor.orange.hex,
        "water": PaletteColor.blue.hex,
        "posture": PaletteColor.green.hex,
        "perfect-day": PaletteColor.green.hex,
        "battery": MetricColor.batteryPresent,
        "network": MetricColor.netUpload,
        "system": MetricColor.cpu,
        "gauges": MetricColor.storage,
        "music": PaletteColor.pink.hex,
        "radio": PaletteColor.orange.hex,
        "podcast": "#25B4E1",
        "pet": PaletteColor.red.hex,
        "github": PaletteColor.graphite.hex,
        "ai-usage": PaletteColor.indigo.hex,
    ]
}
