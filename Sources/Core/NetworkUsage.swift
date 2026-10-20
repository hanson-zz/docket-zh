import Foundation

// MARK: - 网速单位

/// 网络活动卡片和面板的单位：MB/s（按字节）或 Mbps（按比特，宽带都这么说）。
/// 存在卡片配置 `unit` 里，面板顶上的切换和设置页改的是同一个键，卡片跟着变。
public enum NetworkRateUnit: String, CaseIterable, Sendable {
    case bytes
    case bits

    public static let key = "unit"

    public static func from(_ config: WidgetConfig) -> NetworkRateUnit {
        NetworkRateUnit(rawValue: config.string(key, default: NetworkRateUnit.bytes.rawValue)) ?? .bytes
    }

    /// 切换按钮上的字。
    public var label: String {
        switch self {
        case .bytes: "MB/s"
        case .bits: "Mbps"
        }
    }
}

public enum NetworkRateFormat {
    /// 每秒字节数换成一个数字和单位。
    ///
    /// MB/s：不到 1 MB/s 用 KB/s 整数，以上一位小数（和原来卡片一样）。
    /// Mbps：不到 1 Mbps 用 Kbps 整数，100 以下一位小数，100 起整数，
    /// 千兆宽带跑满也只有四位数，卡片放得下。
    public static func format(_ bytesPerSecond: Double, unit: NetworkRateUnit) -> (value: String, unit: String) {
        let bytes = bytesPerSecond.isFinite ? max(bytesPerSecond, 0) : 0
        switch unit {
        case .bytes:
            let kb = bytes / 1024
            if kb < 1024 { return ("\(Int(kb.rounded()))", "KB/s") }
            return (String(format: "%.1f", kb / 1024), "MB/s")
        case .bits:
            // 网络上的 M 是十进制的一百万比特。
            let kbps = bytes * 8 / 1000
            if kbps < 1000 { return ("\(Int(kbps.rounded()))", "Kbps") }
            let mbps = kbps / 1000
            if mbps < 99.95 { return (String(format: "%.1f", mbps), "Mbps") }
            return ("\(Int(mbps.rounded()))", "Mbps")
        }
    }

    public static func text(_ bytesPerSecond: Double, unit: NetworkRateUnit) -> String {
        let value = format(bytesPerSecond, unit: unit)
        return "\(value.value) \(value.unit)"
    }
}

/// 今天累计用了多少：字节数说成 KB / MB / GB（1024 进位，和访达一致）。
public enum NetworkByteFormat {
    public static func text(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value < 1024 * 1024 { return "\(Int((value / 1024).rounded())) KB" }
        if value < 1024 * 1024 * 1024 { return "\(Int((value / 1024 / 1024).rounded())) MB" }
        return String(format: "%.1f GB", value / 1024 / 1024 / 1024)
    }
}

// MARK: - 今天累计

/// 今天下载、上传了多少字节。码头开着、网络活动在采样时累计，零点清零，
/// 存在 UserDefaults（`network.today`），重启后接着加。
public struct NetworkDayTotals: Codable, Equatable, Sendable {
    public static let defaultsKey = "network.today"

    /// `yyyy-MM-dd`，按本机时区。
    public var day: String
    public var download: UInt64
    public var upload: UInt64

    public init(day: String = "", download: UInt64 = 0, upload: UInt64 = 0) {
        self.day = day
        self.download = download
        self.upload = upload
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        download = try c.decodeIfPresent(UInt64.self, forKey: .download) ?? 0
        upload = try c.decodeIfPresent(UInt64.self, forKey: .upload) ?? 0
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 加上一次采样的字节数；日子换了先清零再加。
    public func adding(download down: UInt64, upload up: UInt64, at date: Date,
                       calendar: Calendar = .current) -> NetworkDayTotals {
        let today = Self.dayKey(date, calendar: calendar)
        var next = day == today ? self : NetworkDayTotals(day: today)
        next.download = next.download.addingReportingOverflow(down).overflow ? .max : next.download + down
        next.upload = next.upload.addingReportingOverflow(up).overflow ? .max : next.upload + up
        return next
    }

    /// 面板上显示的数：存的是昨天的就是 0（过了零点还没采样时也对）。
    public func shown(at date: Date, calendar: Calendar = .current) -> (download: UInt64, upload: UInt64) {
        day == Self.dayKey(date, calendar: calendar) ? (download, upload) : (0, 0)
    }

    public static func decode(_ data: Data?) -> NetworkDayTotals {
        guard let data, let value = try? JSONDecoder().decode(NetworkDayTotals.self, from: data) else {
            return NetworkDayTotals()
        }
        return value
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

// MARK: - 谁在用网（nettop）

/// `nettop -P -L 2 -x` 的一行：一个进程到这一刻为止收发的字节数。
public struct NettopSample: Equatable, Sendable {
    public var name: String
    public var pid: Int32
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(name: String, pid: Int32, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.pid = pid
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var key: String { "\(name).\(pid)" }
}

/// 一个进程这一秒的速度（字节/秒）。
public struct ProcessNetRate: Equatable, Sendable {
    public var name: String
    public var pid: Int32
    public var download: Double
    public var upload: Double

    public init(name: String, pid: Int32, download: Double, upload: Double) {
        self.name = name
        self.pid = pid
        self.download = download
        self.upload = upload
    }
}

/// 面板「谁在用网」的一行：一个 App（它的辅助进程合在一起）或一个系统进程。
public struct NetAppUsage: Equatable, Sendable, Identifiable {
    /// App 用 bundle id，别的用进程名。
    public var id: String
    public var name: String
    public var bundleID: String?
    public var download: Double
    public var upload: Double

    public init(id: String, name: String, bundleID: String?, download: Double, upload: Double) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.download = download
        self.upload = upload
    }

    public var total: Double { download + upload }
}

public enum NettopParser {
    /// 读码头调用的 nettop 参数。`-t external` 不算本机回环（本地代理不会被算两遍），
    /// 老系统不认这个类型时去掉它再试一次。
    public static let arguments = ["-P", "-L", "2", "-s", "1", "-x", "-n", "-J", "bytes_in,bytes_out",
                                   "-t", "external"]
    public static let fallbackArguments = ["-P", "-L", "2", "-s", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]

    /// 把 CSV 输出拆成每次采样一组。
    ///
    /// 每次采样前面有一行表头（含 bytes_in、bytes_out）；只有一行表头的输出
    /// 按第一列的时间分组。读不出表头返回空数组，面板就把这一块藏起来。
    public static func parse(_ output: String) -> [[NettopSample]] {
        var blocks: [[NettopSample]] = []
        var current: [NettopSample]?
        var columns: (name: Int, bytesIn: Int, bytesOut: Int)?
        var times: [String] = []
        var headerCount = 0

        for raw in output.split(whereSeparator: \.isNewline) {
            let fields = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let inIndex = fields.firstIndex(of: "bytes_in"), let outIndex = fields.firstIndex(of: "bytes_out") {
                headerCount += 1
                if let block = current { blocks.append(block) }
                current = []
                // 进程名那一列表头是空的，在时间之后；找不到就当第二列。
                let nameIndex = fields.indices.first { $0 > 0 && fields[$0].isEmpty && $0 != inIndex && $0 != outIndex } ?? 1
                columns = (nameIndex, inIndex, outIndex)
                continue
            }
            guard let columns, current != nil else { continue }
            let needed = max(columns.name, columns.bytesIn, columns.bytesOut)
            guard fields.count > needed,
                  let process = splitProcess(fields[columns.name]),
                  let bytesIn = UInt64(fields[columns.bytesIn]),
                  let bytesOut = UInt64(fields[columns.bytesOut]) else { continue }
            current?.append(NettopSample(name: process.name, pid: process.pid, bytesIn: bytesIn, bytesOut: bytesOut))
            times.append(fields.first ?? "")
        }
        if let block = current { blocks.append(block) }

        // 只有一行表头：同一时间戳的是一次采样。
        if headerCount == 1, let only = blocks.first, !only.isEmpty {
            var grouped: [[NettopSample]] = []
            var lastTime: String?
            for (sample, time) in zip(only, times) {
                if time != lastTime {
                    grouped.append([])
                    lastTime = time
                }
                grouped[grouped.count - 1].append(sample)
            }
            return grouped
        }
        return blocks
    }

    /// `Google Chrome H.1234` 拆成名字和 pid（名字里也可能有点）。
    public static func splitProcess(_ field: String) -> (name: String, pid: Int32)? {
        guard let dot = field.lastIndex(of: ".") else { return nil }
        let name = String(field[..<dot])
        guard !name.isEmpty, let pid = Int32(field[field.index(after: dot)...]), pid > 0 else { return nil }
        return (name, pid)
    }

    /// 两次采样相减除以间隔，得每个进程的速度。第一次没有的进程不算（不知道
    /// 它之前收了多少），计数变小的当 0。
    public static func rates(from first: [NettopSample], to second: [NettopSample],
                             interval: Double) -> [ProcessNetRate] {
        guard interval > 0 else { return [] }
        var before: [String: NettopSample] = [:]
        for sample in first { before[sample.key] = sample }
        return second.compactMap { sample in
            guard let old = before[sample.key] else { return nil }
            let down = sample.bytesIn >= old.bytesIn ? sample.bytesIn - old.bytesIn : 0
            let up = sample.bytesOut >= old.bytesOut ? sample.bytesOut - old.bytesOut : 0
            return ProcessNetRate(name: sample.name, pid: sample.pid,
                                  download: Double(down) / interval, upload: Double(up) / interval)
        }
    }

    /// 整段输出直接得速度：最后两次采样相减。读不出来是 nil。
    public static func rates(output: String, interval: Double = 1) -> [ProcessNetRate]? {
        let blocks = parse(output)
        guard blocks.count >= 2 else { return nil }
        return rates(from: blocks[blocks.count - 2], to: blocks[blocks.count - 1], interval: interval)
    }
}

public enum NetAppRanking {
    public static let limit = 5

    /// 按 App 合并（`owner` 告诉一个进程属于哪个 App），按上下行合计排，
    /// 去掉这一秒没有流量的，取前 `limit` 个。名字相同时按 id 排，免得两次一样的读数换位置。
    public static func top(_ rates: [ProcessNetRate], limit: Int = limit,
                           owner: (ProcessNetRate) -> (id: String, name: String, bundleID: String?)) -> [NetAppUsage] {
        var merged: [String: NetAppUsage] = [:]
        var order: [String] = []
        for rate in rates where rate.download + rate.upload > 0 {
            let who = owner(rate)
            if var row = merged[who.id] {
                row.download += rate.download
                row.upload += rate.upload
                merged[who.id] = row
            } else {
                merged[who.id] = NetAppUsage(id: who.id, name: who.name, bundleID: who.bundleID,
                                             download: rate.download, upload: rate.upload)
                order.append(who.id)
            }
        }
        return order.compactMap { merged[$0] }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.id < $1.id }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

// MARK: - 本机 IP 和网络名

public enum LocalAddress {
    /// 从各网卡的 IPv4 地址里挑一个当「本机 IP」：跳过回环、自分配（169.254）
    /// 和 VPN 隧道（utun、ipsec、ppp），en0 优先，其次别的 en*，再其次第一个。
    public static func pick(_ candidates: [(interface: String, address: String)]) -> String? {
        let usable = candidates.filter { item in
            !item.address.isEmpty
                && !item.address.hasPrefix("127.")
                && !item.address.hasPrefix("169.254.")
                && !["lo", "utun", "ipsec", "ppp", "gif", "stf", "awdl", "llw", "bridge"]
                    .contains { item.interface.hasPrefix($0) }
        }
        if let primary = usable.first(where: { $0.interface == "en0" }) { return primary.address }
        if let ethernet = usable.first(where: { $0.interface.hasPrefix("en") }) { return ethernet.address }
        return usable.first?.address
    }
}

public enum NetworkPlaceText {
    /// 面板第二行左边的名字：连着 Wi-Fi 时是网络名，系统不给名字（没有定位权限）
    /// 时就写「Wi-Fi」；没连 Wi-Fi 但有 IP 是有线；都没有是没联网。
    public static func name(onWifi: Bool, ssid: String?, hasAddress: Bool) -> String {
        if onWifi {
            if let ssid = ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty { return ssid }
            return "Wi-Fi"
        }
        return hasAddress ? tr("有线网络") : tr("没有联网")
    }
}
