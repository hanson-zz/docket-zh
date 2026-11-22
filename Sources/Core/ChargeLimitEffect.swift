import Foundation

/// 充电助手这一刻的状况，只看助手，不看用户开没开。
///
/// 原来写在 `ChargeLimitService.state` 里，搬到 Core 好测。助手（Tools/ChargeHelper）
/// 只编 ChargeLimit.swift，所以这里单独一个文件，可以用 `tr`。
public enum ChargeHelperState: Equatable, Sendable {
    case notInstalled
    case starting
    case unsupported
    case needsUpdate
    case running

    /// `installed`：系统位置有没有助手和 launchd 配置；`status`：助手写的状态文件。
    public static func resolve(installed: Bool, status: ChargeHelperStatus?, now: Date) -> ChargeHelperState {
        // 助手在按时写状态就说明它在跑，哪怕码头这边看不到安装的文件。
        let fresh = status.map { $0.isFresh(now: now) } ?? false
        guard installed || fresh else { return .notInstalled }
        guard let status, fresh else { return .starting }
        if !status.supported { return .unsupported }
        if status.version != ChargeHelperFiles.helperVersion { return .needsUpdate }
        return .running
    }
}

/// 充电上限实际怎么样。开关只是用户的意图，这里说的是上限有没有真的在起作用，
/// 面板标题行的状态胶囊和下面那一行说明都看它，不再只看开关。
public enum ChargeLimitEffect: Equatable, Sendable {
    /// 用户没打开（或上限是 100%，等于不限制）。
    case off
    /// 已启用且生效：助手在跑、这台 Mac 能控制充电、Pro 已解锁。
    case effective
    /// 已开启但未生效：助手还在启动，或码头 Pro 没解锁。
    case pending(PendingReason)
    /// 设备不支持：助手找不到能控制充电的芯片接口。`enabled` 是用户有没有打开上限。
    case unsupported(enabled: Bool)
    /// 需要安装（`update` 为 false）或更新助手，之前上限不生效。
    case needsHelper(update: Bool)

    public enum PendingReason: Equatable, Sendable {
        case starting
        case locked
    }

    /// 胶囊的颜色：生效是绿，其余要提醒的是橙。
    public enum Tone: Equatable, Sendable {
        case good
        case warning
    }

    /// `config` 是用户自己的选择，`unlocked` 是 Pro 能不能用，`helper` 是助手的状况。
    public static func resolve(config: ChargeLimitConfig, unlocked: Bool, helper: ChargeHelperState) -> ChargeLimitEffect {
        let wanted = config.isActive
        // 设备不支持放最前：开没开都要让用户知道这台 Mac 用不了。
        if helper == .unsupported { return .unsupported(enabled: wanted) }
        guard wanted else { return .off }
        guard unlocked else { return .pending(.locked) }
        switch helper {
        case .notInstalled: return .needsHelper(update: false)
        case .needsUpdate: return .needsHelper(update: true)
        case .starting: return .pending(.starting)
        case .unsupported: return .unsupported(enabled: true)
        case .running: return .effective
        }
    }

    /// 上限真的在限制充电。
    public var isEffective: Bool { self == .effective }

    /// 要不要醒目提醒（橙色胶囊加说明）。
    public var needsAttention: Bool {
        switch self {
        case .off, .effective: false
        case .pending, .unsupported, .needsHelper: true
        }
    }

    /// 标题行右边的小胶囊；关着时没有胶囊。
    public var badge: (text: String, tone: Tone)? {
        switch self {
        case .off: nil
        case .effective: (tr("生效中"), .good)
        case .pending: (tr("未生效"), .warning)
        case .unsupported(let enabled): (enabled ? tr("未生效") : tr("不支持"), .warning)
        case .needsHelper(let update): (update ? tr("需更新助手") : tr("需安装助手"), .warning)
        }
    }

    /// 胶囊下面那一行说明；生效和关着时不加这一行（原来的说明照常写）。
    public var notice: String? {
        switch self {
        case .off, .effective: nil
        case .pending(.starting): tr("助手正在启动，设置的上限尚未生效。")
        case .pending(.locked): tr("码头 Pro 未解锁，设置的上限尚未生效，电池照常充满。")
        case .unsupported(let enabled):
            enabled ? tr("当前设备无法控制充电，设置的上限尚未生效。") : tr("当前设备无法控制充电，充电上限在这台 Mac 上用不了。")
        case .needsHelper(let update):
            update ? tr("充电助手需要更新，更新前设置的上限不生效。") : tr("还没有安装充电助手，设置的上限尚未生效。")
        }
    }

    /// 购买或打开充电上限前的兼容性提示（Pro 说明和面板里都用这一句）。
    public static var compatibilityNote: String { tr("充电上限需要 Apple 芯片 Mac 并安装充电助手，部分机型或系统版本无法控制充电，以面板里显示的状态为准。") }
}
