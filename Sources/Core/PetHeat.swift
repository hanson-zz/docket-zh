import Foundation

/// 电子宠物什么时候热得化成一滩：Mac 过热（系统的热状态到了“严重”），
/// CPU 持续很忙，或者外面很热。凉下来就恢复，不改它的四项需求。
///
/// 三个来源都是已经有的读数，宠物自己不去开任何采样：
/// - 热状态是 `ProcessInfo.thermalState` 的 rawValue（0 正常、1 稍热、2 严重、3 危急）；
/// - CPU 是系统活动小组件在跑时留下的每秒读数，没在跑就是空的，不算；
/// - 气温是天气小组件取到的当前温度，没有就不算。
public enum PetHeat {
    /// 热状态到这一级（严重）就化。
    public static let thermalLine = 2
    /// 最近这么多秒的 CPU 平均到这个占用就化；读数不够这么多秒不算，
    /// 免得打开一个应用的一下子就化了。
    public static let cpuLine = 0.9
    public static let cpuSeconds = 30
    /// 室外气温到这么多摄氏度就化。
    public static let outdoorCelsius = 35.0

    public static func isMelting(thermal: Int, cpuHistory: [Double], outdoorCelsius: Double?) -> Bool {
        if thermal >= thermalLine { return true }
        if cpuBusy(cpuHistory) { return true }
        if let celsius = outdoorCelsius, celsius.isFinite, celsius >= Self.outdoorCelsius { return true }
        return false
    }

    /// 最近 `cpuSeconds` 个读数的平均到了 `cpuLine`。
    public static func cpuBusy(_ history: [Double]) -> Bool {
        let recent = history.suffix(cpuSeconds).filter(\.isFinite)
        guard recent.count >= cpuSeconds else { return false }
        return recent.reduce(0, +) / Double(recent.count) >= cpuLine
    }
}
