import Foundation

/// When a widget is on the shelf.
///
/// Stored in the widget's own config under `visibility` rather than as a new
/// field on `WidgetInstance`: config already tolerates keys it does not know,
/// so a build that predates this simply ignores it, and nothing about the
/// saved state has to migrate.
public enum WidgetVisibilityMode: String, Sendable, CaseIterable {
    case always
    /// Only while the widget's own condition holds; see `WidgetVisibility`.
    case conditional
    case hidden

    public var title: String {
        switch self {
        case .always: tr("始终显示")
        case .conditional: tr("满足条件时显示")
        case .hidden: tr("隐藏")
        }
    }
}

/// What the shelf currently knows about the things conditions depend on.
///
/// Every field is optional on purpose. `nil` means "could not be read", and a
/// widget whose condition cannot be read stays visible: a reading that failed
/// must never be the reason something the user placed disappears without a
/// trace.
public struct WidgetConditions: Equatable, Sendable {
    public var musicPlaying: Bool?
    /// Whether the Mac is running on its battery. `nil` on a desktop Mac.
    public var onBattery: Bool?
    /// 0...1, the Mac's own battery.
    public var batteryLevel: Double?
    public var micInUse: Bool?
    public var mailUnread: Int?
    /// Codex is working on a turn or waiting for an answer.
    public var codexActive: Bool?
    /// The ambient widget is playing.
    public var ambientPlaying: Bool?
    /// The radio is tuned in and playing.
    public var radioPlaying: Bool?
    /// New feedback per followed GitHub repository, keyed by
    /// `GitHubWatch.key`. A repository missing from it has not been read yet.
    public var githubFeedback: [String: Int]?

    public init(musicPlaying: Bool? = nil, onBattery: Bool? = nil, batteryLevel: Double? = nil,
                micInUse: Bool? = nil, mailUnread: Int? = nil, codexActive: Bool? = nil,
                ambientPlaying: Bool? = nil, radioPlaying: Bool? = nil,
                githubFeedback: [String: Int]? = nil) {
        self.githubFeedback = githubFeedback
        self.ambientPlaying = ambientPlaying
        self.radioPlaying = radioPlaying
        self.codexActive = codexActive
        self.musicPlaying = musicPlaying
        self.onBattery = onBattery
        self.batteryLevel = batteryLevel
        self.micInUse = micInUse
        self.mailUnread = mailUnread
    }

    /// Nothing known: every conditional widget shows.
    public static let unknown = WidgetConditions()
}

public enum WidgetVisibility {
    public static let modeKey = "visibility"
    /// Battery only: show at or below this percentage. 100 means any level.
    public static let thresholdKey = "showBelow"

    public static let thresholdChoices: [Int] = [100, 50, 30, 20, 10]

    public static func mode(_ config: WidgetConfig) -> WidgetVisibilityMode {
        WidgetVisibilityMode(rawValue: config.string(modeKey, default: "always")) ?? .always
    }

    /// Kinds with a condition of their own to show on.
    public static func supportsCondition(_ kind: WidgetKind) -> Bool {
        switch kind {
        case .music, .battery, .microphone, .mail, .aiUsage, .todo, .ambient, .radio, .anniversary, .water,
             .github, .pet: true
        default: false
        }
    }

    public static func batteryThreshold(_ config: WidgetConfig) -> Int {
        let raw = config.int(thresholdKey, default: 100)
        return min(100, max(5, raw))
    }

    /// The condition in words, for menus and settings.
    public static func conditionTitle(_ kind: WidgetKind, config: WidgetConfig) -> String? {
        switch kind {
        case .music: return tr("正在播放时显示")
        case .microphone: return tr("麦克风使用中时显示")
        case .mail: return tr("有未读邮件时显示")
        case .aiUsage: return tr("Codex 工作中或等你确认时显示")
        case .todo: return tr("有未完成的待办时显示")
        case .ambient: return tr("正在播放时显示")
        case .radio: return tr("正在收听时显示")
        case .anniversary: return tr("\(Anniversary.soonDays) 天内有纪念日时显示")
        case .water: return tr("今天未达标时显示")
        case .pet: return tr("需要照顾时显示")
        case .github: return tr("有新反馈时显示")
        case .battery:
            let threshold = batteryThreshold(config)
            return threshold >= 100 ? tr("使用电池时显示") : tr("使用电池且电量不高于 \(threshold)% 时显示")
        default: return nil
        }
    }

    /// Whether the condition holds, or nil when it cannot be told.
    public static func conditionHolds(_ instance: WidgetInstance,
                                      _ conditions: WidgetConditions,
                                      now: Date = Date()) -> Bool? {
        switch instance.kind {
        case .music:
            return conditions.musicPlaying
        case .microphone:
            return conditions.micInUse
        case .mail:
            return conditions.mailUnread.map { $0 > 0 }
        case .aiUsage:
            return conditions.codexActive
        // Read from the widget's own list, so it needs no monitor. 勾掉最后一项
        // 后的庆祝还没播完时仍算满足，播完再收起（见 `QuickTodo.cheerKey`）。
        case .todo:
            return QuickTodo.openCount(instance.config) > 0 || QuickTodo.isCheering(instance.config, now: now)
        case .anniversary:
            return Anniversary.hasSoon(instance.config)
        case .water:
            return WaterIntake.belowGoal(instance.config)
        case .pet:
            return VirtualPet.needsCare(instance.config)
        case .ambient:
            return conditions.ambientPlaying
        case .radio:
            return conditions.radioPlaying
        // Any followed repository with something new. Unknown until at
        // least one of them has been read, and unknown stays visible.
        case .github:
            guard let counts = conditions.githubFeedback else { return nil }
            let known = GitHubWatch.repos(instance.config).compactMap { counts[GitHubWatch.key($0)] }
            guard !known.isEmpty else { return nil }
            return known.contains { $0 > 0 }
        case .battery:
            guard let onBattery = conditions.onBattery else { return nil }
            guard onBattery else { return false }
            let threshold = batteryThreshold(instance.config)
            guard threshold < 100 else { return true }
            guard let level = conditions.batteryLevel else { return nil }
            return Int((min(max(level, 0), 1) * 100).rounded()) <= threshold
        default:
            return nil
        }
    }

    /// Whether a widget is on the shelf right now.
    ///
    /// `ignoringConditions` is for sample renders (the library, screenshots):
    /// nothing there is live, so only an explicit "hidden" applies.
    public static func isVisible(_ instance: WidgetInstance, _ conditions: WidgetConditions,
                                 ignoringConditions: Bool = false) -> Bool {
        switch mode(instance.config) {
        case .always:
            return true
        case .hidden:
            return false
        case .conditional:
            if ignoringConditions || !supportsCondition(instance.kind) { return true }
            return conditionHolds(instance, conditions) ?? true
        }
    }

    /// The shelf's items with every widget that should not show taken out.
    /// Groups and everything that is not a widget pass through untouched.
    public static func visibleItems(_ items: [DockItem], _ conditions: WidgetConditions,
                                    ignoringConditions: Bool = false) -> [DockItem] {
        items.filter { item in
            guard let widget = item.widget else { return true }
            return isVisible(widget, conditions, ignoringConditions: ignoringConditions)
        }
    }

    /// The widgets currently off the shelf, in shelf order, for the
    /// "已隐藏的小组件" menu.
    public static func hiddenWidgets(_ items: [DockItem], _ conditions: WidgetConditions,
                                     ignoringConditions: Bool = false) -> [WidgetInstance] {
        items.compactMap(\.widget).filter {
            !isVisible($0, conditions, ignoringConditions: ignoringConditions)
        }
    }

    /// Why a hidden widget is hidden, as a short line after its name.
    public static func hiddenReason(_ instance: WidgetInstance) -> String {
        mode(instance.config) == .hidden ? tr("已隐藏") : tr("条件未满足")
    }

    /// The widget put back on the shelf for good.
    public static func restored(_ instance: WidgetInstance) -> WidgetInstance {
        var copy = instance
        copy.config.set(modeKey, .string(WidgetVisibilityMode.always.rawValue))
        return copy
    }

    /// Which modes a kind can be set to. A kind without a condition is not
    /// offered one: a "show when" with nothing after it is a switch that
    /// does nothing.
    public static func modes(for kind: WidgetKind) -> [WidgetVisibilityMode] {
        supportsCondition(kind) ? WidgetVisibilityMode.allCases : [.always, .hidden]
    }
}
