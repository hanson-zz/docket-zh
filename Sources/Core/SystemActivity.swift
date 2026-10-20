import Foundation

// 系统活动面板的纯逻辑：四个读数、24 小时环形缓冲、每分钟汇总、占用最高的进程
// 排名、超阈值提醒的规则和判断、卡片显示哪几项。采样和界面在 Services 和
// Widgets 里，这里不碰系统接口，测试直接编译。

// MARK: - 读数

/// 面板上的四个读数。网络是下行速率，磁盘是启动磁盘的可用空间。
public enum SystemMetricKind: String, CaseIterable, Codable, Sendable {
    case cpu, memory, network, disk

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: tr("内存")
        case .network: tr("网络")
        case .disk: tr("磁盘")
        }
    }
}

/// 面板配色（效果图 panels-batch1 的系统活动列）：绿色只给曲线、选中和主按钮这些
/// 小面积，实心按钮上用深色字；红色是退出和正在提醒；金色是 Pro 标。
public enum SystemActivityStyle {
    public static let accent = "#4CD787"
    public static let accentInk = "#04210F"
    public static let alertRed = "#FF6B5A"
    public static let alertInk = "#330B05"
    public static let gold = "#F5C451"
    public static let base = "#1D1D21"
}

// MARK: - 环形缓冲

/// 定长环形缓冲：写满后新的一条盖掉最旧的一条，不搬动数组。
///
/// 存盘时按从旧到新的顺序写成普通数组，读回来再排好，所以文件里看不出
/// 写到了哪一格，换了容量也读得回来（多的从最旧的丢）。
public struct RingBuffer<Element: Codable & Sendable & Equatable>: Codable, Equatable, Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    /// 下一条写进哪一格；没写满时等于 `storage.count`。
    private var head = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(min(self.capacity, 4096))
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
            head = storage.count % capacity
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// 从旧到新。
    public var elements: [Element] {
        guard storage.count == capacity, head != 0 else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    /// 最新的一条。
    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(head - 1 + storage.count) % storage.count]
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    private enum CodingKeys: String, CodingKey { case capacity, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(capacity: try c.decode(Int.self, forKey: .capacity))
        for item in try c.decode([Element].self, forKey: .items).suffix(capacity) { append(item) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(capacity, forKey: .capacity)
        try c.encode(elements, forKey: .items)
    }

    public static func == (a: RingBuffer, b: RingBuffer) -> Bool {
        a.capacity == b.capacity && a.elements == b.elements
    }
}

// MARK: - 24 小时

/// 一分钟的平均读数。`minute` 是 1970 年起的第几分钟。
public struct SystemMinuteSample: Codable, Equatable, Sendable {
    public var minute: Int
    /// 0...1。
    public var cpu: Double
    /// 0...1。
    public var memory: Double
    /// 下行字节每秒。
    public var network: Double
    /// 可用字节。
    public var diskFree: Double

    public init(minute: Int, cpu: Double, memory: Double, network: Double, diskFree: Double) {
        self.minute = minute
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.diskFree = diskFree
    }

    public func value(_ metric: SystemMetricKind) -> Double {
        switch metric {
        case .cpu: cpu
        case .memory: memory
        case .network: network
        case .disk: diskFree
        }
    }

    private enum CodingKeys: String, CodingKey {
        case minute = "m", cpu = "c", memory = "r", network = "n", diskFree = "d"
    }
}

/// 最近 24 小时，每分钟一条，最多 1440 条。
///
/// 合盖、休眠或码头没开的那几分钟没有记录，曲线在那里断开，不拿直线连过去。
public struct SystemActivityHistory: Codable, Equatable, Sendable {
    public static let minutes = 24 * 60

    public private(set) var samples = RingBuffer<SystemMinuteSample>(capacity: SystemActivityHistory.minutes)

    public init() {}

    public static func minute(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    public static func date(ofMinute minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }

    /// 记一分钟。同一分钟或更早的（时钟往回拨）不记，返回有没有记。
    @discardableResult
    public mutating func record(_ sample: SystemMinuteSample) -> Bool {
        if let last = samples.last, sample.minute <= last.minute { return false }
        samples.append(sample)
        return true
    }

    /// 截至 `now` 的最近 24 小时，从旧到新。
    public func window(now: Date) -> [SystemMinuteSample] {
        let end = Self.minute(of: now)
        let start = end - Self.minutes
        return samples.elements.filter { $0.minute > start && $0.minute <= end }
    }

    /// 曲线上要标的那一点：CPU、内存、网络是最高，磁盘是可用空间最少。
    public func peak(_ metric: SystemMetricKind, now: Date) -> SystemMinuteSample? {
        let list = window(now: now)
        if metric == .disk { return list.min { $0.diskFree < $1.diskFree } }
        return list.max { $0.value(metric) < $1.value(metric) }
    }

    /// 曲线的纵轴范围。CPU、内存固定 0...1，读起来是绝对占用；网络从 0 到
    /// 最高值；磁盘按可用空间的上下限留一点边，免得一条几乎平的线贴在边上。
    public static func range(_ metric: SystemMetricKind, values: [Double]) -> ClosedRange<Double> {
        switch metric {
        case .cpu, .memory:
            return 0...1
        case .network:
            return 0...max(values.max() ?? 0, 64 * 1024)
        case .disk:
            guard let lo = values.min(), let hi = values.max() else { return 0...1 }
            let pad = max((hi - lo) * 0.25, 1_000_000_000)
            return max(0, lo - pad)...(hi + pad)
        }
    }

    /// 24 小时的曲线：每点的横坐标是 0...1（24 小时前到现在），纵坐标是 0...1。
    /// 相邻两条隔了不止两分钟的地方断成两段。
    public func segments(_ metric: SystemMetricKind, now: Date) -> [[(x: Double, y: Double)]] {
        let list = window(now: now)
        guard !list.isEmpty else { return [] }
        let range = Self.range(metric, values: list.map { $0.value(metric) })
        let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
        let end = Double(Self.minute(of: now))
        var result: [[(x: Double, y: Double)]] = []
        var current: [(x: Double, y: Double)] = []
        var previous: Int?
        for sample in list {
            if let previous, sample.minute - previous > 2, !current.isEmpty {
                result.append(current)
                current = []
            }
            let x = 1 - (end - Double(sample.minute)) / Double(Self.minutes)
            let y = (sample.value(metric) - range.lowerBound) / span
            current.append((x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
            previous = sample.minute
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// 把每秒一次的读数攒成每分钟一条：进了新的一分钟时交出上一分钟的平均值。
public struct SystemMinuteAccumulator: Sendable {
    private var minute: Int?
    private var count = 0
    private var cpu = 0.0
    private var memory = 0.0
    private var network = 0.0
    private var diskFree = 0.0

    public init() {}

    public mutating func add(cpu: Double, memory: Double, network: Double, diskFree: Double,
                             at date: Date) -> SystemMinuteSample? {
        let now = SystemActivityHistory.minute(of: date)
        var finished: SystemMinuteSample?
        if let minute, now != minute {
            if count > 0, now > minute {
                let n = Double(count)
                finished = SystemMinuteSample(minute: minute, cpu: self.cpu / n, memory: self.memory / n,
                                              network: self.network / n, diskFree: self.diskFree)
            }
            reset()
        }
        minute = now
        count += 1
        self.cpu += cpu
        self.memory += memory
        self.network += max(network, 0)
        // 磁盘只取最新的一次：它半分钟才读一次，平均反而会被 0 拉低。
        if diskFree > 0 { self.diskFree = diskFree }
        return finished
    }

    private mutating func reset() {
        count = 0
        cpu = 0
        memory = 0
        network = 0
        // 可用空间留着：新的一分钟里还没读到磁盘时沿用上一次。
    }
}

// MARK: - 文字

public enum SystemReadout {
    /// 速率：数字和单位分开，单位小字。1000 进位，和活动监视器一样。
    public static func rate(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let b = max(bytesPerSecond, 0)
        if b >= 1_000_000_000 { return (number(b / 1_000_000_000), "GB/s") }
        if b >= 1_000_000 { return (number(b / 1_000_000), "MB/s") }
        if b >= 1_000 { return (number(b / 1_000), "KB/s") }
        return ("\(Int(b.rounded()))", "B/s")
    }

    /// 卡片上放得下的短写法：“2.4M”“860K”。
    public static func shortRate(_ bytesPerSecond: Double) -> String {
        let b = max(bytesPerSecond, 0)
        if b >= 1_000_000_000 { return number(b / 1_000_000_000) + "G" }
        if b >= 1_000_000 { return number(b / 1_000_000) + "M" }
        if b >= 1_000 { return "\(Int((b / 1_000).rounded()))K" }
        return "0K"
    }

    /// 十以下留一位小数，十以上取整。
    public static func number(_ value: Double) -> String {
        if value < 9.95 { return String(format: "%.1f", value) }
        return "\(Int(value.rounded()))"
    }

    /// GB（1000 进位，和访达一样）：十以下一位小数，十以上取整。
    public static func gigabytes(_ bytes: Double) -> String {
        number(max(bytes, 0) / 1_000_000_000)
    }

    /// 百分比，0...1 进来，取整。
    public static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// 开机多久：“3 天 4 小时”“4 小时 12 分钟”“12 分钟”。
    public static func uptime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0) / 60
        let days = total / (24 * 60)
        let hours = total / 60 % 24
        let minutes = total % 60
        if days > 0 { return tr("已运行 \(days) 天 \(hours) 小时") }
        if hours > 0 { return tr("已运行 \(hours) 小时 \(minutes) 分钟") }
        return tr("已运行 \(minutes) 分钟")
    }

    /// 某一分钟在本地是几点几分。
    public static func clock(minute: Int, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: SystemActivityHistory.date(ofMinute: minute))
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 曲线上峰值那一点的说明。
    public static func peakLabel(_ metric: SystemMetricKind, sample: SystemMinuteSample,
                                 timeZone: TimeZone = .current) -> String {
        let time = clock(minute: sample.minute, timeZone: timeZone)
        switch metric {
        case .cpu, .memory:
            // 百分号放进参数：格式串里单独的 % 会被 String(format:) 吃掉。
            let value = "\(percent(sample.value(metric)))%"
            return tr("峰值 \(value) · \(time)")
        case .network:
            let r = rate(sample.network)
            let value = "\(r.value) \(r.unit)"
            return tr("峰值 \(value) · \(time)")
        case .disk:
            return tr("最少可用 \(gigabytes(sample.diskFree)) GB · \(time)")
        }
    }
}

// MARK: - 占用最高的进程

/// 一个进程的一次读数。`group` 相同的进程算一行：同一个 App 的辅助进程
/// （浏览器的渲染进程之类）并进 App 自己，不是 App 的按进程各算一行。
public struct ProcessReading: Equatable, Sendable {
    public var pid: Int32
    public var group: String
    public var name: String
    /// 开始以来累计用掉的 CPU 时间，纳秒。
    public var cpuNanos: UInt64
    /// 占用的内存（物理占用），字节。
    public var memory: UInt64

    public init(pid: Int32, group: String, name: String, cpuNanos: UInt64, memory: UInt64) {
        self.pid = pid
        self.group = group
        self.name = name
        self.cpuNanos = cpuNanos
        self.memory = memory
    }
}

/// 排好的一行。
public struct ProcessUsageRow: Equatable, Sendable, Identifiable {
    public var group: String
    public var name: String
    public var pids: [Int32]
    /// 占一个核心的百分比，和活动监视器一样，多核满载可以超过 100。
    public var cpuPercent: Double
    public var memory: UInt64

    public var id: String { group }
}

public enum ProcessSort: String, CaseIterable, Sendable {
    case cpu, memory

    public var title: String {
        switch self {
        case .cpu: tr("按 CPU")
        case .memory: tr("按内存")
        }
    }
}

public enum ProcessRanking {
    public static let limit = 5

    /// 路径里最外层的 .app 包，没有就是 nil。
    /// “/Applications/浏览器.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/Helper”
    /// 归到 “/Applications/浏览器.app”。
    public static func appBundle(fromPath path: String) -> String? {
        if let range = path.range(of: ".app/") { return String(path[..<range.lowerBound]) + ".app" }
        return path.hasSuffix(".app") ? path : nil
    }

    /// 包名去掉 .app：“/Applications/视频剪辑.app” 是 “视频剪辑”。
    public static func bundleName(_ bundlePath: String) -> String {
        let last = bundlePath.split(separator: "/").last.map(String.init) ?? bundlePath
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    /// 两次读数之间每一组用了多少 CPU，按 `sort` 排好取前 `limit` 个。
    ///
    /// 上一次没有的进程（刚启动）这一次只算内存、CPU 记 0，下一次才有差值；
    /// 计数比上次小（pid 被复用）的同样记 0。
    public static func top(previous: [Int32: UInt64], current: [ProcessReading], elapsedNanos: UInt64,
                           sort: ProcessSort, limit: Int = ProcessRanking.limit) -> [ProcessUsageRow] {
        var rows: [String: ProcessUsageRow] = [:]
        var order: [String] = []
        let elapsed = Double(max(elapsedNanos, 1))
        for reading in current {
            var used = 0.0
            if let before = previous[reading.pid], reading.cpuNanos >= before {
                used = Double(reading.cpuNanos - before) / elapsed * 100
            }
            if var row = rows[reading.group] {
                row.cpuPercent += used
                row.memory += reading.memory
                row.pids.append(reading.pid)
                rows[reading.group] = row
            } else {
                rows[reading.group] = ProcessUsageRow(group: reading.group, name: reading.name, pids: [reading.pid],
                                                      cpuPercent: used, memory: reading.memory)
                order.append(reading.group)
            }
        }
        let list = order.compactMap { rows[$0] }
        let sorted = list.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            switch sort {
            case .cpu:
                if x.cpuPercent != y.cpuPercent { return x.cpuPercent > y.cpuPercent }
                if x.memory != y.memory { return x.memory > y.memory }
            case .memory:
                if x.memory != y.memory { return x.memory > y.memory }
                if x.cpuPercent != y.cpuPercent { return x.cpuPercent > y.cpuPercent }
            }
            return a.offset < b.offset
        }
        return Array(sorted.prefix(max(limit, 0)).map(\.element))
    }

    /// 行上的读数：CPU “62%”（不到 10 留一位小数），内存 “3.1 GB” 或 “420 MB”。
    public static func cpuText(_ percent: Double) -> String {
        let p = max(percent, 0)
        if p < 9.95 { return String(format: "%.1f%%", p) }
        return "\(Int(p.rounded()))%"
    }

    public static func memoryText(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000_000 { return "\(SystemReadout.number(b / 1_000_000_000)) GB" }
        return "\(Int((b / 1_000_000).rounded())) MB"
    }
}

// MARK: - 超阈值提醒（Pro）

/// 一条提醒规则：某个读数超过（磁盘是可用空间低于）阈值、持续几分钟就发通知。
public struct SystemAlertRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var metric: SystemMetricKind
    /// CPU、内存是百分比（50...100），网络是 MB/s，磁盘是 GB。
    public var threshold: Double
    public var minutes: Int
    public var enabled: Bool

    public init(id: String = UUID().uuidString, metric: SystemMetricKind, threshold: Double,
                minutes: Int, enabled: Bool) {
        self.id = id
        self.metric = metric
        self.threshold = threshold
        self.minutes = minutes
        self.enabled = enabled
    }

    /// 滑杆的范围和步长。
    public static func range(_ metric: SystemMetricKind) -> ClosedRange<Double> {
        switch metric {
        case .cpu, .memory: 50...100
        case .network: 1...200
        case .disk: 5...200
        }
    }

    public static func step(_ metric: SystemMetricKind) -> Double {
        switch metric {
        case .cpu, .memory: 5
        case .network: 1
        case .disk: 5
        }
    }

    public static func defaultThreshold(_ metric: SystemMetricKind) -> Double {
        switch metric {
        case .cpu: 90
        case .memory: 85
        case .network: 50
        case .disk: 20
        }
    }

    public static let minuteRange = 1...60

    /// 磁盘看可用空间，低于阈值算超；其余高于阈值算超。
    public var isBelow: Bool { metric == .disk }

    /// 换指标时阈值换成那个指标的默认值。
    public func switching(to metric: SystemMetricKind) -> SystemAlertRule {
        var next = self
        guard metric != self.metric else { return next }
        next.metric = metric
        next.threshold = Self.defaultThreshold(metric)
        return next
    }

    /// 放进范围、对齐步长。
    public var clamped: SystemAlertRule {
        var next = self
        let range = Self.range(metric)
        let step = Self.step(metric)
        let snapped = (min(max(threshold, range.lowerBound), range.upperBound) / step).rounded() * step
        next.threshold = min(max(snapped, range.lowerBound), range.upperBound)
        next.minutes = min(max(minutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        return next
    }

    /// 阈值的写法：“90%”“50 MB/s”“20 GB”。
    public var thresholdText: String {
        let value = Int(threshold.rounded())
        switch metric {
        case .cpu, .memory: return "\(value)%"
        case .network: return "\(value) MB/s"
        case .disk: return "\(value) GB"
        }
    }

    /// 规则一行的标题：“CPU > 90% 持续 5 分钟”“磁盘可用 < 20 GB 持续 5 分钟”。
    public var summary: String {
        let name = metric == .disk ? tr("磁盘可用") : metric.title
        let sign = isBelow ? "<" : ">"
        return tr("\(name) \(sign) \(thresholdText) 持续 \(minutes) 分钟")
    }

    /// 这次读数算不算超。`reading` 用 `SystemAlertReading` 的单位。
    public func exceeded(by reading: SystemAlertReading) -> Bool? {
        guard let value = reading.value(metric) else { return nil }
        switch metric {
        case .cpu, .memory: return value * 100 > threshold
        case .network: return value / 1_000_000 > threshold
        case .disk: return value / 1_000_000_000 < threshold
        }
    }
}

/// 判断用的一次读数：CPU、内存 0...1，网络下行字节每秒，磁盘可用字节。没读到的是 nil。
public struct SystemAlertReading: Sendable {
    public var cpu: Double?
    public var memory: Double?
    public var network: Double?
    public var diskFree: Double?

    public init(cpu: Double? = nil, memory: Double? = nil, network: Double? = nil, diskFree: Double? = nil) {
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.diskFree = diskFree
    }

    public func value(_ metric: SystemMetricKind) -> Double? {
        switch metric {
        case .cpu: cpu
        case .memory: memory
        case .network: network
        case .disk: diskFree.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// 通知里写的现在的读数。
    public func text(_ metric: SystemMetricKind) -> String {
        guard let value = value(metric) else { return "-" }
        switch metric {
        case .cpu, .memory: return "\(SystemReadout.percent(value))%"
        case .network:
            let r = SystemReadout.rate(value)
            return "\(r.value) \(r.unit)"
        case .disk: return "\(SystemReadout.gigabytes(value)) GB"
        }
    }
}

/// 到点要发的一条通知。
public struct SystemAlert: Equatable, Sendable {
    public var ruleID: String
    public var metric: SystemMetricKind
    public var title: String
    public var body: String
}

/// 规则存在小组件配置的 `alertRules` 键里（一段 JSON 文字），只有面板读写，
/// 不列进设置窗口的选项。没存过的卡片给三条默认规则，都是关着的，用户自己打开。
public enum SystemAlertRules {
    public static let key = "alertRules"
    public static let maxCount = 8

    public static var defaults: [SystemAlertRule] {
        [SystemAlertRule(id: "cpu", metric: .cpu, threshold: 90, minutes: 5, enabled: false),
         SystemAlertRule(id: "memory", metric: .memory, threshold: 85, minutes: 10, enabled: false),
         SystemAlertRule(id: "disk", metric: .disk, threshold: 20, minutes: 5, enabled: false)]
    }

    public static func rules(_ config: WidgetConfig) -> [SystemAlertRule] {
        guard let raw = config.values[key] else { return defaults }
        guard case .string(let text) = raw, let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SystemAlertRule].self, from: data)
        else { return defaults }
        return Array(decoded.prefix(maxCount)).map(\.clamped)
    }

    public static func store(_ rules: [SystemAlertRule], in config: inout WidgetConfig) {
        let list = Array(rules.prefix(maxCount)).map(\.clamped)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(list), let text = String(data: data, encoding: .utf8) else { return }
        config.set(key, .string(text))
    }

    /// 新加一条：挑一个还没有规则的指标，都有了就用 CPU。默认打开。
    public static func newRule(after rules: [SystemAlertRule], id: String = UUID().uuidString) -> SystemAlertRule {
        let used = Set(rules.map(\.metric))
        let metric = SystemMetricKind.allCases.first { !used.contains($0) } ?? .cpu
        return SystemAlertRule(id: id, metric: metric, threshold: SystemAlertRule.defaultThreshold(metric),
                               minutes: 5, enabled: true)
    }
}

/// 记着每条规则从什么时候开始超，持续够了发一次通知；回落到阈值以内才重新
/// 计时，所以一直超着不会每分钟响一次。正在超且已经响过的指标是“正在提醒”，
/// 卡片上那个读数变红。
///
/// 码头 Pro 没解锁时不判断、不提醒、卡片不变红，记的状态清掉；规则照旧存着，
/// 解锁或试用后从头计时。
public struct SystemAlertTracker: Sendable {
    private var since: [String: Date] = [:]
    private var fired: Set<String> = []

    public init() {}

    public struct Result: Equatable, Sendable {
        public var alerts: [SystemAlert]
        /// 正在提醒的指标。
        public var firing: Set<SystemMetricKind>
    }

    public mutating func check(_ reading: SystemAlertReading, rules: [SystemAlertRule], unlocked: Bool,
                               now: Date = .now) -> Result {
        guard ProLicenseGate.systemAlertsActive(unlocked: unlocked) else {
            since = [:]
            fired = []
            return Result(alerts: [], firing: [])
        }
        var alerts: [SystemAlert] = []
        var firing: Set<SystemMetricKind> = []
        let live = Set(rules.filter(\.enabled).map(\.id))
        since = since.filter { live.contains($0.key) }
        fired = fired.filter { live.contains($0) }
        for rule in rules where rule.enabled {
            // 没读到（磁盘还没读过之类）不算超也不算回落，原样等下一次。
            guard let over = rule.exceeded(by: reading) else {
                if fired.contains(rule.id) { firing.insert(rule.metric) }
                continue
            }
            guard over else {
                since[rule.id] = nil
                fired.remove(rule.id)
                continue
            }
            let start = since[rule.id] ?? now
            since[rule.id] = start
            if fired.contains(rule.id) {
                firing.insert(rule.metric)
            } else if now.timeIntervalSince(start) >= Double(rule.minutes) * 60 {
                fired.insert(rule.id)
                firing.insert(rule.metric)
                alerts.append(alert(for: rule, reading: reading))
            }
        }
        return Result(alerts: alerts, firing: firing)
    }

    private func alert(for rule: SystemAlertRule, reading: SystemAlertReading) -> SystemAlert {
        let now = reading.text(rule.metric)
        let title: String
        switch rule.metric {
        case .disk: title = tr("磁盘可用空间不到 \(rule.thresholdText)")
        case .cpu: title = tr("CPU 占用已持续 \(rule.minutes) 分钟超过 \(rule.thresholdText)")
        case .memory: title = tr("内存占用已持续 \(rule.minutes) 分钟超过 \(rule.thresholdText)")
        case .network: title = tr("网络下行已持续 \(rule.minutes) 分钟超过 \(rule.thresholdText)")
        }
        let body: String
        switch rule.metric {
        case .disk: body = tr("现在只剩 \(now)，可以清理一下大文件或废纸篓。")
        default: body = tr("现在是 \(now)，可以打开系统活动看看占用最高的 App。")
        }
        return SystemAlert(ruleID: rule.id, metric: rule.metric, title: title, body: body)
    }
}

// MARK: - 卡片显示哪几项

/// 卡片上显示的读数存在 `metrics` 键里，和设置窗口的多选是同一个键。
public enum SystemCardMetrics {
    public static let key = "metrics"
    /// 面板编辑态能勾的，按这个顺序存。电池是原来就有的选项，留着。
    public static let all = ["cpu", "memory", "network", "disk", "battery"]
    public static let fallback = ["cpu", "memory"]

    public static func shown(_ config: WidgetConfig) -> [String] {
        let list = config.strings(key, default: fallback).filter { all.contains($0) }
        return list.isEmpty ? fallback : list
    }

    /// 勾上或去掉一项，至少留一项，按 `all` 的顺序排。
    public static func toggling(_ metric: String, in current: [String]) -> [String] {
        guard all.contains(metric) else { return current }
        var set = Set(current.filter { all.contains($0) })
        if set.contains(metric) {
            guard set.count > 1 else { return all.filter { set.contains($0) } }
            set.remove(metric)
        } else {
            set.insert(metric)
        }
        return all.filter { set.contains($0) }
    }

    /// 网络在卡片上没有百分比，条形、竖条和液态按对数折成 0...1：
    /// 10 KB/s 以下是空，100 MB/s 是满。
    public static func networkFraction(_ bytesPerSecond: Double) -> Double {
        let low = log10(10_000.0), high = log10(100_000_000.0)
        guard bytesPerSecond > 10_000 else { return 0 }
        return min(max((log10(bytesPerSecond) - low) / (high - low), 0), 1)
    }
}
