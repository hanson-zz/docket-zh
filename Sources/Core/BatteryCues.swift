import Foundation

// MARK: - 电池卡片和面板上的小熊猫
//
// 电池界面平时是纯数据，小熊猫只在两种时候出来：Mac 电量低于 20% 又没接电源时举爪提醒
// （一直在，直到接上电源或电量回来）；充满（100%，或到达生效中的充电上限）时挥爪一次，
// 停 `PandaMotion.doneHold` 秒后消失。判定都在这里，界面只照着画。

public enum BatteryPandaCue {
    /// 低于这个百分比、没接电源时小熊猫出来提醒。
    public static let lowLevel = 20

    /// 小熊猫这一刻的常态：低电量又没接电源是 `.alert`，其余 nil（不画小熊猫）。
    /// `percent` 为 nil（读不到 Mac 电池，台式机）时也是 nil，绝不编一个提醒出来。
    public static func base(percent: Int?, onPower: Bool, charging: Bool) -> PandaState? {
        guard let percent, !onPower, !charging else { return nil }
        return percent < lowLevel ? .alert : nil
    }

    /// 「充满」的那条线：充电上限生效中且低于 100 时是上限，否则 100。
    /// `effectiveLimit` 只在上限真的在起作用时给（见 `ChargeLimitEffect.isEffective`）。
    public static func fullTarget(effectiveLimit: Int?) -> Int {
        guard let limit = effectiveLimit, (1..<100).contains(limit) else { return 100 }
        return limit
    }

    /// 充满时那一次挥爪的表态，从 `now` 起停 `PandaMotion.doneHold` 秒。
    public static func fullPulse(at now: Date) -> PandaPulse {
        PandaPulse(state: .done, started: now, until: now.addingTimeInterval(PandaMotion.doneHold))
    }
}

/// 记住这一次接电源有没有庆祝过充满，免得在上限附近来回跳时反复挥爪。
///
/// - 接上电源（或启动时已接着电源）时电量低于那条线，才算「这次在充」，到线时挥爪一次；
///   插上时已经满了不挥。
/// - 挥过以后，电量要掉到挥爪时那一格以下 `rearmMargin` 个百分点才会再挥（充电上限的缓冲区里
///   来回不算）。那条线临时变高（比如助手状态一时读不到，上限按 100 算）不算掉下去，
///   线变回上限时也不会再挥一次。
/// - 拔掉电源全部重来。
public struct BatteryFullWatch: Equatable, Sendable {
    public static let rearmMargin = 5

    private var armed = false
    private var lastOnPower: Bool?
    /// 上一次挥爪（或插上时已经满了）那一格；重新可以挥要从这里往下掉 `rearmMargin`。
    private var settledAt: Int?

    public init() {}

    /// 喂一次读数，该挥爪时返回 true。
    public mutating func update(percent: Int, onPower: Bool, target: Int) -> Bool {
        defer { lastOnPower = onPower }
        guard onPower else {
            armed = false
            settledAt = nil
            return false
        }
        if lastOnPower != true {
            // 刚接上电源，或启动后的第一次读数：没满才算在充。
            armed = percent < target
            settledAt = armed ? nil : percent
            return false
        }
        if percent >= target {
            guard armed else { return false }
            armed = false
            settledAt = percent
            return true
        }
        let line = min(target, settledAt ?? target)
        if percent <= line - Self.rearmMargin {
            armed = true
            settledAt = nil
        }
        return false
    }
}

// MARK: - 蓝牙配件状态变化

/// 多设备卡片上某一格的一次轻提示：连上、断开、电量低。
public enum AccessoryChange: String, Equatable, Sendable {
    case connected
    case disconnected
    case low

    /// 圆环下面小胶囊里的字，要短：一格只有六七十点宽。
    public var label: String {
        switch self {
        case .connected: tr("已连上")
        case .disconnected: tr("已断开")
        case .low: tr("电量低")
        }
    }
}

/// 一个配件这一刻的样子。`group` 是它在多设备卡片上占哪一格：耳机 `buds`、充电盒 `case`、
/// 鼠标等外设 `peripheral`；断开以后卡片那一格只剩「未连接」，靠 `group` 找回这次提示。
public struct AccessoryPresence: Equatable, Sendable {
    public var id: String
    public var group: String
    /// 0...100；读不到电量时 nil（连着但不报电量，不算低电量）。
    public var percent: Int?
    /// 连上、断开要不要提示。AirPods 充电盒只在开盖时报电量，一合盖就像「断开」了，
    /// 所以充电盒只提示电量低。
    public var announcesPresence: Bool

    public init(id: String, group: String, percent: Int?, announcesPresence: Bool = true) {
        self.id = id
        self.group = group
        self.percent = percent
        self.announcesPresence = announcesPresence
    }

    public static let budsGroup = "buds"
    public static let caseGroup = "case"
    public static let peripheralGroup = "peripheral"

    /// 采样器那份配件清单拆成多设备卡片的几格：耳机（AirPods 或带左右耳的）一格，
    /// 它的充电盒另一格（id 后面加 `#case`），其余是外设。
    public static func from(_ accessories: [BluetoothBattery]) -> [AccessoryPresence] {
        var result: [AccessoryPresence] = []
        for item in accessories {
            let buds = item.kind.isAirPods || item.hasBuds
            result.append(AccessoryPresence(id: item.id, group: buds ? budsGroup : peripheralGroup,
                                            percent: item.level))
            if let caseLevel = item.caseLevel {
                result.append(AccessoryPresence(id: caseID(item.id), group: caseGroup, percent: caseLevel,
                                                announcesPresence: false))
            }
        }
        return result
    }

    /// 充电盒那一格的 id。
    public static func caseID(_ id: String) -> String { "\(id)#case" }
}

/// 一次正在显示的提示，到 `until` 为止。
public struct AccessoryFlash: Equatable, Sendable {
    public var change: AccessoryChange
    public var until: Date

    public init(change: AccessoryChange, until: Date) {
        self.change = change
        self.until = until
    }

    public func isActive(at now: Date) -> Bool { now < until }
}

/// 比较前后两次读数，得出哪个配件连上、断开、电量跌破 20%，每次提示停 `duration` 秒。
///
/// - 第一次读数和启动后 `warmup` 秒里的变化只当底数：系统信息那边的配件要一两秒后才报上来，
///   不能一启动就满屏「已连接」。
/// - 电量低只在从 20% 及以上跌到 20% 以下时提示一次，回到 25% 以上才会再提示。
/// - 连上时电量就低，提示「电量低」（比「已连接」更要紧）。
/// - 不发系统通知，只给卡片画轻提示。
public struct AccessoryChangeTracker: Equatable, Sendable {
    public static let duration: TimeInterval = 2.5
    public static let warmup: TimeInterval = 15
    public static let lowLevel = 20
    public static let lowRearm = 25

    private var known: [String: AccessoryPresence]?
    private var startedAt: Date?
    private var lowSaid: Set<String> = []
    /// 按配件 id 记的提示。
    public private(set) var byID: [String: AccessoryFlash] = [:]
    /// 断开的提示也按格记一份（那一格已经找不到配件 id 了）。
    public private(set) var byGroup: [String: AccessoryFlash] = [:]

    public init() {}

    /// 喂一次读数，返回这次新出现的变化（测试用；界面读 `flash`）。
    @discardableResult
    public mutating func update(_ readings: [AccessoryPresence], now: Date) -> [String: AccessoryChange] {
        prune(now: now)
        let current = Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let start = startedAt ?? now
        startedAt = start
        let baseline = known == nil || now.timeIntervalSince(start) < Self.warmup
        let previous = known ?? [:]
        known = current

        var changes: [String: AccessoryChange] = [:]
        for (id, item) in current {
            let isLow = item.percent.map { $0 < Self.lowLevel } ?? false
            let wasLow = previous[id]?.percent.map { $0 < Self.lowLevel } ?? false
            if let percent = item.percent, percent > Self.lowRearm { lowSaid.remove(id) }
            if baseline {
                if isLow { lowSaid.insert(id) }
                continue
            }
            if previous[id] == nil {
                if !item.announcesPresence {
                    if isLow, !lowSaid.contains(id) {
                        changes[id] = .low
                        lowSaid.insert(id)
                    }
                } else if isLow {
                    changes[id] = .low
                    lowSaid.insert(id)
                } else {
                    changes[id] = .connected
                }
            } else if isLow, !wasLow, !lowSaid.contains(id) {
                changes[id] = .low
                lowSaid.insert(id)
            }
        }
        for (id, item) in previous where current[id] == nil {
            // 充电盒合上不算断开，说过的电量低也记着，下次开盖不再说。
            guard item.announcesPresence else { continue }
            lowSaid.remove(id)
            guard !baseline else { continue }
            changes[id] = .disconnected
            let flash = AccessoryFlash(change: .disconnected, until: now.addingTimeInterval(Self.duration))
            byGroup[item.group] = flash
        }
        for (id, change) in changes {
            let flash = AccessoryFlash(change: change, until: now.addingTimeInterval(Self.duration))
            byID[id] = flash
            // 同一格又连上了：先前那条「已断开」不再显示。
            if change != .disconnected, let group = current[id]?.group { byGroup[group] = nil }
        }
        return changes
    }

    /// 从现在起再当 `warmup` 秒底数：睡眠醒来、或系统信息那份配件清单过期后重新报上来时，
    /// 配件会成批消失又出现，不能满屏「已断开」「已连上」。已经在显示的提示照常到期。
    public mutating func rebaseline(now: Date) {
        guard known != nil else { return }
        startedAt = now
    }

    /// 去掉到期的提示；有东西被去掉时返回 true（界面据此刷新一次）。
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        let before = byID.count + byGroup.count
        byID = byID.filter { $0.value.isActive(at: now) }
        byGroup = byGroup.filter { $0.value.isActive(at: now) }
        return byID.count + byGroup.count != before
    }

    /// 这一格现在该显示的提示：先按配件 id 找，配件不在了再按格找「已断开」。
    public func flash(id: String?, group: String, now: Date) -> AccessoryChange? {
        if let id, let flash = byID[id], flash.isActive(at: now) { return flash.change }
        if id == nil, let flash = byGroup[group], flash.isActive(at: now) { return flash.change }
        return nil
    }
}
