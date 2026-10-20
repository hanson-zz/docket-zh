import Foundation

/// 圆环仪表每个圆环的警戒线：过了线圆环和读数变红。
///
/// 存在卡片里，一个圆环一个键，值是百分数的字符串，"0" 是不变红：
/// - 存储 `storageAlert`：可用空间剩多少以下变红，默认 10%。
/// - 电池 `batteryAlert`：用电池时电量多少以下变红，默认 10%（和以前写死的一样；
///   20% 以下仍画橙色提醒）。充电或接着电源时不变红。
/// - CPU `cpuAlert`、内存 `memoryAlert`：占用多少以上变红，默认不变红（和以前一样）。
///
/// 面板编辑里用加减按钮在 `choices` 里挪，设置页是下拉菜单，只列卡片上有的圆环。
public enum GaugeAlert {
    public static func key(_ ring: String) -> String { "\(ring)Alert" }

    public static let keys = GaugeReading.allRings.map(key)

    public static func defaultValue(_ ring: String) -> Int {
        switch ring {
        case "storage", "battery": 10
        default: 0
        }
    }

    /// 能选的线（百分数），0 是不变红，排在最前。
    public static func choices(_ ring: String) -> [Int] {
        switch ring {
        case "storage": [0, 5, 10, 15, 20, 25, 30]
        case "battery": [0, 5, 10, 15, 20, 30]
        default: [0, 50, 60, 70, 80, 90, 95]
        }
    }

    /// 存着的线；不认得的值退回默认。
    public static func value(_ ring: String, _ config: WidgetConfig) -> Int {
        let fallback = defaultValue(ring)
        let stored = Int(config.string(key(ring), default: String(fallback))) ?? fallback
        return choices(ring).contains(stored) ? stored : fallback
    }

    /// 加减按钮：在 `choices` 里往前或往后一格，到头了不动。
    public static func stepped(_ ring: String, from value: Int, by offset: Int) -> Int {
        let list = choices(ring)
        guard let index = list.firstIndex(of: value) else { return defaultValue(ring) }
        return list[min(max(index + offset, 0), list.count - 1)]
    }

    /// 过线没有。`fraction` 是圆环上画的那个比例：存储是已用（剩下的 = 1 - 已用），
    /// 电池是电量，CPU 和内存是占用。电池充电或接着电源时不算。
    public static func isOver(_ ring: String, fraction: Double, line: Int, charging: Bool = false) -> Bool {
        guard line > 0 else { return false }
        let percent = min(max(fraction, 0), 1) * 100
        switch ring {
        case "storage": return 100 - percent < Double(line)
        case "battery": return !charging && percent <= Double(line)
        default: return percent >= Double(line)
        }
    }

    /// 按钮中间和设置菜单里写的：“剩 10%”“低于 20%”“超过 90%”“不变红”。
    public static func short(_ ring: String, _ line: Int) -> String {
        guard line > 0 else { return tr("不变红") }
        switch ring {
        case "storage": return tr("剩 \(line)%")
        case "battery": return tr("低于 \(line)%")
        default: return tr("超过 \(line)%")
        }
    }

    /// 面板每个圆环下面那行说明。
    public static func caption(_ ring: String, _ line: Int) -> String {
        guard line > 0 else { return tr("不设警戒线") }
        switch ring {
        case "storage": return tr("剩 \(line)% 以下变红")
        case "battery": return tr("用电池时低于 \(line)% 变红")
        default: return tr("超过 \(line)% 变红")
        }
    }

    /// 圆环的名字：存储、电池、CPU、内存。
    public static func title(_ ring: String) -> String {
        switch ring {
        case "storage": tr("存储")
        case "battery": tr("电池")
        case "cpu": "CPU"
        default: tr("内存")
        }
    }
}

/// 存储里几大块各占多少，面板那条分段条用。应用、下载、废纸篓是量出来的，
/// 其他 = 已用减去这三块（不会小于 0）。读不到的那块是 nil，不画也不减。
public struct StorageBreakdown: Equatable, Sendable {
    public var apps: Int64?
    public var downloads: Int64?
    public var trash: Int64?

    public init(apps: Int64? = nil, downloads: Int64? = nil, trash: Int64? = nil) {
        self.apps = apps
        self.downloads = downloads
        self.trash = trash
    }

    public struct Part: Equatable, Sendable {
        public var name: String
        public var bytes: Int64
        /// 占整块盘的比例。
        public var fraction: Double
    }

    /// 分段条的几段，按应用、下载、废纸篓、其他；总量不知道时为空。
    public func parts(used: Int64, total: Int64) -> [Part] {
        guard total > 0 else { return [] }
        let named: [(String, Int64?)] = [(tr("应用"), apps), (tr("下载"), downloads), (tr("废纸篓"), trash)]
        var list: [Part] = []
        var known: Int64 = 0
        for (name, bytes) in named {
            guard let bytes, bytes > 0 else { continue }
            known += bytes
            list.append(Part(name: name, bytes: bytes, fraction: Double(bytes) / Double(total)))
        }
        let other = max(0, used - known)
        if other > 0 {
            list.append(Part(name: tr("其他"), bytes: other, fraction: Double(other) / Double(total)))
        }
        return list
    }
}
