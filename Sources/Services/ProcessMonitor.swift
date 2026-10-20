import AppKit
import Darwin
import Observation

/// 系统活动面板的“占用最高”：每 2 秒读一遍进程（libproc 的 proc_pid_rusage），
/// 同一个 App 的辅助进程并进 App 自己，排名在 Core 的 `ProcessRanking`。
///
/// 只在面板开着时读：面板出现时 `begin()`，消失时 `end()`，没人看就停掉定时器，
/// 不在后台耗电。别的用户（root、系统账户）的进程读不到 CPU 和内存，不列。
///
/// 退出只给普通 App（程序坞里会出现的那种）：调 `NSRunningApplication.terminate()`，
/// 和在 App 里按 ⌘Q 一样，App 可以先问要不要存档，不强制结束。
@MainActor @Observable
final class ProcessMonitor {
    static let shared = ProcessMonitor()

    private(set) var rows: [ProcessUsageRow] = []
    var sort: ProcessSort = .cpu {
        didSet { if oldValue != sort { rank() } }
    }

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var baseline: [Int32: UInt64] = [:]
    @ObservationIgnored private var baselineAt: UInt64 = 0
    /// 上一次排名用的两次读数，换排序时重排不用再读。
    @ObservationIgnored private var lastPrevious: [Int32: UInt64] = [:]
    @ObservationIgnored private var lastReadings: [ProcessReading] = []
    @ObservationIgnored private var lastElapsed: UInt64 = 1
    @ObservationIgnored private var apps: [String: NSRunningApplication] = [:]

    private init() {}

    func begin() {
        users += 1
        guard timer == nil else { return }
        sample()
        // 第一次只是基线，一秒后才有 CPU 差值，之后每 2 秒一次。
        let timer = Timer(fire: Date(timeIntervalSinceNow: 1), interval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func end() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
        baseline = [:]
        baselineAt = 0
    }

    // MARK: 退出

    /// 这一行对应的普通 App，码头自己除外。
    func app(for row: ProcessUsageRow) -> NSRunningApplication? {
        guard let app = apps[row.group], app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    func canQuit(_ row: ProcessUsageRow) -> Bool { app(for: row) != nil }

    /// 名字：App 用它自己的显示名，其余用进程名。
    func name(for row: ProcessUsageRow) -> String {
        apps[row.group]?.localizedName ?? row.name
    }

    func icon(for row: ProcessUsageRow) -> NSImage? {
        apps[row.group]?.icon
    }

    /// 礼貌地退出（不强制）。返回有没有发出去。
    @discardableResult
    func quit(_ row: ProcessUsageRow) -> Bool {
        guard let app = app(for: row) else { return false }
        let sent = app.terminate()
        if sent { rows.removeAll { $0.group == row.group } }
        return sent
    }

    // MARK: 读数

    private func sample() {
        var byPID: [pid_t: NSRunningApplication] = [:]
        var byGroup: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            byPID[app.processIdentifier] = app
            if let path = app.bundleURL?.path { byGroup[path] = app }
        }
        let now = DispatchTime.now().uptimeNanoseconds
        var readings: [ProcessReading] = []
        for pid in Self.allPIDs() where pid > 0 {
            guard let usage = Self.usage(pid) else { continue }
            let group: String
            let name: String
            if let app = byPID[pid], let path = app.bundleURL?.path {
                group = path
                name = app.localizedName ?? ProcessRanking.bundleName(path)
            } else {
                let path = Self.path(pid)
                if let bundle = ProcessRanking.appBundle(fromPath: path) {
                    group = bundle
                    name = byGroup[bundle]?.localizedName ?? ProcessRanking.bundleName(bundle)
                } else {
                    group = "pid:\(pid)"
                    name = path.isEmpty ? Self.processName(pid) : (path as NSString).lastPathComponent
                }
            }
            readings.append(ProcessReading(pid: pid, group: group, name: name,
                                           cpuNanos: usage.cpuNanos, memory: usage.memory))
        }
        apps = byGroup
        if baselineAt > 0 {
            lastPrevious = baseline
            lastReadings = readings
            lastElapsed = max(now &- baselineAt, 1)
            rank()
        } else if rows.isEmpty {
            // 只有基线时先按内存排出来，CPU 记 0，不让面板空一秒。
            lastPrevious = [:]
            lastReadings = readings
            lastElapsed = 1
            rank()
        }
        baseline = Dictionary(readings.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: { a, _ in a })
        baselineAt = now
    }

    private func rank() {
        let next = ProcessRanking.top(previous: lastPrevious, current: lastReadings,
                                      elapsedNanos: lastElapsed, sort: sort)
        if next != rows { rows = next }
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    /// CPU 时间（纳秒）和物理占用。读不到（别的用户的进程）是 nil。
    private static func usage(_ pid: pid_t) -> (cpuNanos: UInt64, memory: UInt64)? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        // Apple 芯片上这两个是 mach 时间单位，要换成纳秒。
        let ticks = info.ri_user_time &+ info.ri_system_time
        let nanos = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
        let cpu = nanos.overflow ? ticks : nanos.partialValue / UInt64(max(timebase.denom, 1))
        return (cpu, info.ri_phys_footprint)
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 { info = mach_timebase_info_data_t(numer: 1, denom: 1) }
        return info
    }()

    private static func path(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "\(pid)" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
