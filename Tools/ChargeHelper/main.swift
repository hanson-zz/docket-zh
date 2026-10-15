import Foundation
import IOKit.ps

// 码头的充电上限助手：以 root 身份由 launchd 启动，每 20 秒读一次电量和
// /Users/Shared/Dockling/charge-limit.json，到上限暂停充电，低于缓冲恢复，
// 并把状态写到 charge-status.json 给码头看。收到 SIGTERM（卸载、关机）或
// 用 --reset 运行时恢复充电后退出，绝不把电池留在不充电的状态。

/// 恢复充电。信号处理里也调用，所以自己开一个新连接。
func allowCharging() {
    if let smc = SMC(), let charge = ChargeSwitch(smc: smc) { charge.set(inhibited: false) }
}

/// 内置电池的电量（0 到 100）和是否插着电源。
func batteryState() -> (percent: Int?, pluggedIn: Bool) {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
        return (nil, false)
    }
    for source in list {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
        let current = desc[kIOPSCurrentCapacityKey] as? Int
        let max = desc[kIOPSMaxCapacityKey] as? Int
        let percent = current.flatMap { c in max.map { m in m > 0 ? Int((Double(c) / Double(m) * 100).rounded()) : c } }
        let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return (percent, plugged)
    }
    return (nil, false)
}

func readConfig() -> ChargeLimitConfig {
    guard let data = FileManager.default.contents(atPath: ChargeHelperFiles.configPath),
          let config = try? ChargeHelperFiles.decoder().decode(ChargeLimitConfig.self, from: data) else {
        return .default
    }
    return config.clamped
}

func writeStatus(_ status: ChargeHelperStatus) {
    guard let data = try? ChargeHelperFiles.encoder().encode(status) else { return }
    let url = URL(fileURLWithPath: ChargeHelperFiles.statusPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
    // 让普通用户的码头读得到。
    chmod(ChargeHelperFiles.statusPath, 0o644)
}

if CommandLine.arguments.contains("--reset") {
    allowCharging()
    exit(0)
}

for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig) { _ in
        allowCharging()
        exit(0)
    }
}

guard let smc = SMC() else {
    writeStatus(ChargeHelperStatus(version: ChargeHelperFiles.helperVersion, supported: false, key: nil,
                                   inhibited: false, percent: batteryState().percent,
                                   pluggedIn: batteryState().pluggedIn, updated: Date()))
    // 打不开 SMC 时别让 launchd 每秒重启，睡一会儿再退出。
    sleep(300)
    exit(1)
}

let charge = ChargeSwitch(smc: smc)
var inhibited = charge?.isInhibited ?? false

while true {
    let config = readConfig()
    let state = batteryState()
    if let charge {
        let want = ChargeLimitPolicy.shouldInhibit(percent: state.percent, config: config,
                                                   currentlyInhibited: inhibited)
        if want != inhibited || (charge.isInhibited ?? want) != want {
            if charge.set(inhibited: want) { inhibited = want }
        }
    }
    writeStatus(ChargeHelperStatus(version: ChargeHelperFiles.helperVersion, supported: charge != nil,
                                   key: charge?.key, inhibited: inhibited, percent: state.percent,
                                   pluggedIn: state.pluggedIn, updated: Date()))
    Thread.sleep(forTimeInterval: ChargeHelperFiles.interval)
}
