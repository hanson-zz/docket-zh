import AppKit
import Foundation
import Observation

/// 网络活动面板的「谁在用网」和第二行的网络名、本机 IP。
///
/// 每个 App 的流量用系统自带的 `/usr/bin/nettop` 读（公开命令，不要权限）：
/// 采样两次、相隔一秒，相减得到每个进程这一秒收发了多少，再按 App 合并。
/// 只在面板打开时读：面板出现时 `panelAppeared()`，消失时 `panelDisappeared()`，
/// 关掉面板不留任何定时器或子进程。nettop 不在、跑不起来或输出读不懂时
/// `available` 变成 false，面板把这一块藏起来，不报错。
@MainActor @Observable
final class NetworkTopApps {
    static let shared = NetworkTopApps()

    /// 前 5 个，速度从高到低。还没读到第一次时是空的。
    private(set) var apps: [NetAppUsage] = []
    /// nettop 能用。读失败一次就藏起来，下次打开面板再试。
    private(set) var available = true
    /// 第一次读完之前，面板显示「正在读取…」而不是「没有 App 在用网」。
    private(set) var loaded = false
    /// 网络名（拿不到就是 nil）、是否连着 Wi-Fi、本机 IPv4。
    private(set) var ssid: String?
    private(set) var onWifi = false
    private(set) var address: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var viewers = 0
    /// `-t external` 不认时记住，后面直接用不带它的参数。
    @ObservationIgnored private var useFallback = false

    private init() {}

    func panelAppeared() {
        viewers += 1
        guard task == nil else { return }
        available = true
        refreshPlace()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.readOnce()
                self.refreshPlace()
                // nettop 自己就要一秒多，读完歇一秒：大约两秒一更新。
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func panelDisappeared() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        task?.cancel()
        task = nil
    }

    // MARK: 网络名和 IP

    private func refreshPlace() {
        let wifi = WifiMetrics.shared
        wifi.sampleNow()
        let nextWifi = wifi.rssi != nil
        if nextWifi != onWifi { onWifi = nextWifi }
        let nextSSID = nextWifi ? wifi.ssid : nil
        if nextSSID != ssid { ssid = nextSSID }
        let nextAddress = LocalAddress.pick(Self.ipv4Addresses())
        if nextAddress != address { address = nextAddress }
    }

    /// 每块网卡的 IPv4 地址（只是读 getifaddrs，不联网）。
    nonisolated static func ipv4Addresses() -> [(interface: String, address: String)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [(interface: String, address: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            found.append((name, text))
        }
        return found
    }

    // MARK: nettop

    private func readOnce() async {
        let fallback = useFallback
        let result = await Task.detached(priority: .utility) {
            Self.runNettop(fallback ? NettopParser.fallbackArguments : NettopParser.arguments)
        }.value
        guard !Task.isCancelled else { return }

        var rates = result.flatMap { NettopParser.rates(output: $0) }
        if rates == nil, !fallback {
            // 老系统不认 `-t external`：换不带它的参数再试一次，以后都用它。
            let retry = await Task.detached(priority: .utility) {
                Self.runNettop(NettopParser.fallbackArguments)
            }.value
            guard !Task.isCancelled else { return }
            rates = retry.flatMap { NettopParser.rates(output: $0) }
            if rates != nil { useFallback = true }
        }
        guard let rates else {
            if available { available = false }
            if !apps.isEmpty { apps = [] }
            task?.cancel()
            task = nil
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let next = NetAppRanking.top(rates.filter { $0.pid != ownPID }) { rate in
            Self.owner(of: rate)
        }
        if !available { available = true }
        if !loaded { loaded = true }
        if next != apps { apps = next }
    }

    /// 一个进程算在哪个 App 头上：自己是 App 就是自己，辅助进程问系统它替谁干活，
    /// 都不是（系统服务）就用进程名。
    private static func owner(of rate: ProcessNetRate) -> (id: String, name: String, bundleID: String?) {
        if let app = NSRunningApplication(processIdentifier: rate.pid),
           app.activationPolicy == .regular, let bundleID = app.bundleIdentifier {
            return (bundleID, app.localizedName ?? AppIdentity.name(for: bundleID), bundleID)
        }
        if let bundleID = Responsibility.ownerBundleID(of: rate.pid) {
            return (bundleID, AppIdentity.name(for: bundleID), bundleID)
        }
        return (rate.name, rate.name, nil)
    }

    /// 跑一次 nettop，最多等 6 秒；跑不起来、超时或退出码不是 0 都是 nil。
    nonisolated private static func runNettop(_ arguments: [String]) -> String? {
        let url = URL(fileURLWithPath: "/usr/bin/nettop")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        // 先把输出读完（读到 EOF），免得管道写满卡住 nettop。
        let reader = DispatchQueue(label: "network-top.read")
        let box = OutputBox()
        let readDone = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        reader.async {
            box.data = handle.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + 6) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
            _ = readDone.wait(timeout: .now() + 1)
            return nil
        }
        _ = readDone.wait(timeout: .now() + 2)
        guard process.terminationStatus == 0 else { return nil }
        return String(data: box.data, encoding: .utf8)
    }
}

/// 读输出的线程写、等它的线程读，中间隔着信号量。
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
