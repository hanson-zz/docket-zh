import Foundation
import Observation

/// 试连电台地址：发一个普通 GET，读到头几百字节就交给 `RadioProbe.alive`
/// 下结论，然后断开。超时、出错都算连不上。
enum RadioProbeClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    nonisolated static func check(_ address: String, timeout: Double) async -> Bool {
        guard let url = RadioDial.streamURL(address) else { return false }
        let work = Task { await probe(url, timeout: timeout) }
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        let alive = await work.value
        timer.cancel()
        return alive
    }

    private nonisolated static func probe(_ url: URL, timeout: Double) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(RadioBrowser.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            let http = response as? HTTPURLResponse
            var head = Data()
            for try await byte in bytes {
                head.append(byte)
                if head.count >= RadioProbe.headBytes { break }
            }
            return RadioProbe.alive(status: http?.statusCode ?? 200,
                                    contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                                    head: head)
        } catch {
            return false
        }
    }

    /// 取回一份 .m3u / .pls 播放列表的文字，取不到是 nil。
    nonisolated static func fetchPlaylist(_ url: URL, timeout: Double) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(RadioBrowser.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 1_000_000 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// 收藏失效检查：打开面板时每天最多自动一次，或者手动点“检查”。逐条试连
/// 收藏里每个电台的每条地址（同时最多 4 条，每条约 8 秒），把结果交给
/// `RadioHealth.applying`：只标“可能失效”、把连得上的地址提前，不删任何东西。
@MainActor @Observable
final class RadioStationCheck {
    static let shared = RadioStationCheck()

    /// 正在检查的收音机小组件。
    private(set) var running: Set<UUID> = []
    /// 上次检查完有几个电台连不上（这次打开 App 以来），面板据此说“都连得上”。
    private(set) var reports: [UUID: Int] = [:]
    /// 上次检查一个也连不上（多半没联网）的小组件，面板据此说“可能没联网”。
    private(set) var offline: Set<UUID> = []

    private init() {}

    func isRunning(_ id: UUID) -> Bool { running.contains(id) }

    private static func lastKey(_ id: UUID) -> String { "radio.healthCheckedOn.\(id.uuidString)" }
    private static func dismissedKey(_ id: UUID) -> String { "radio.healthDismissed.\(id.uuidString)" }

    /// 关掉“N 个电台连不上”提示时记下的那一批。
    static func dismissed(_ id: UUID) -> String? {
        UserDefaults.standard.string(forKey: dismissedKey(id))
    }

    static func dismiss(_ id: UUID, dead: [RadioStation]) {
        UserDefaults.standard.set(RadioHealth.dismissToken(dead), forKey: dismissedKey(id))
    }

    /// 手动点“检查”时清掉，结果照样提示。
    static func clearDismissed(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: dismissedKey(id))
    }

    /// 打开面板时调：今天没自动检查过才检查。
    func checkIfDue(_ instance: WidgetInstance) {
        let last = UserDefaults.standard.string(forKey: Self.lastKey(instance.id))
        guard RadioHealth.shouldAutoCheck(lastStamp: last, now: .now) else { return }
        check(instance)
    }

    /// 手动点“检查”，或到了每天那一次。
    func check(_ instance: WidgetInstance) {
        guard !running.contains(instance.id) else { return }
        let addresses = RadioHealth.addresses(RadioDial.stations(instance.config))
        UserDefaults.standard.set(RadioHealth.dayStamp(.now), forKey: Self.lastKey(instance.id))
        guard !addresses.isEmpty else { return }
        let id = instance.id
        running.insert(id)
        reports[id] = nil
        offline.remove(id)
        Task {
            let results = await Self.probeAll(addresses)
            running.remove(id)
            // 一条都连不上多半是没联网：不标失效，也不算今天检查过，下次打开面板再查。
            let tested = RadioDial.stations(WidgetWriter.current(id)?.config ?? instance.config)
            if RadioHealth.looksOffline(results, stations: tested) {
                offline.insert(id)
                UserDefaults.standard.removeObject(forKey: Self.lastKey(id))
                return
            }
            // 检查期间收藏可能改过，按最新的收藏套结果，没测到的电台原样保留。
            guard let current = WidgetWriter.current(id), current.kind == .radio else { return }
            let before = RadioDial.stations(current.config)
            let after = RadioHealth.applying(results, to: before)
            reports[id] = RadioHealth.dead(after).count
            guard after != before else { return }
            RadioRemote.edit(current) { list, _ in list = RadioHealth.applying(results, to: list) }
        }
    }

    /// 同时最多 `RadioProbe.maxConcurrent` 条。
    private nonisolated static func probeAll(_ addresses: [String]) async -> [String: Bool] {
        await withTaskGroup(of: (String, Bool).self) { group in
            var results: [String: Bool] = [:]
            var next = 0
            while next < min(RadioProbe.maxConcurrent, addresses.count) {
                let address = addresses[next]
                group.addTask { (address, await RadioProbeClient.check(address, timeout: RadioProbe.checkTimeout)) }
                next += 1
            }
            while let (address, alive) = await group.next() {
                results[address] = alive
                if next < addresses.count {
                    let queued = addresses[next]
                    group.addTask { (queued, await RadioProbeClient.check(queued, timeout: RadioProbe.checkTimeout)) }
                    next += 1
                }
            }
            return results
        }
    }
}
