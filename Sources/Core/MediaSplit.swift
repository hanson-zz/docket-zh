import Foundation

// 音量 / 应用音量 / 正在播放 分工，以及相册宽幅、AI 任意门竖版的纯逻辑。
//
// 音量管“这台 Mac 从哪儿出声、总共多大声”：一排输出设备，点一下切过去，
// 下面一根总音量。应用音量管“谁吵关谁”：每个应用一格，在卡片上左右拖。
// 正在播放只管这首歌，不放音量。这里只有算术和文字，Core Audio 在 Services。

// MARK: - 输出设备

/// 输出设备的连接方式，从 Core Audio 的 transport type（四个字符）来。
public enum OutputTransport: String, Sendable, CaseIterable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, virtual, aggregate, other

    /// `kAudioDeviceTransportType…` 的四字符码。
    public init(fourCC: UInt32) {
        switch Self.text(fourCC) {
        case "bltn": self = .builtIn
        case "blue", "blea": self = .bluetooth
        case "usb ": self = .usb
        case "hdmi": self = .hdmi
        case "dprt": self = .displayPort
        case "airp": self = .airPlay
        case "thun": self = .thunderbolt
        case "virt": self = .virtual
        case "grup", "agrp": self = .aggregate
        default: self = .other
        }
    }

    public static func fourCC(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func text(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 排在一排里的先后：本机、耳机、显示器、隔空播放，其余在后。
    var rank: Int {
        switch self {
        case .builtIn: 0
        case .bluetooth: 1
        case .usb, .thunderbolt: 2
        case .hdmi, .displayPort: 3
        case .airPlay: 4
        case .virtual, .aggregate, .other: 5
        }
    }
}

/// 一台输出设备，从 Core Audio 读出来摊平。
public struct OutputDevice: Hashable, Sendable, Identifiable {
    public var id: UInt32
    public var uid: String
    public var name: String
    public var transport: OutputTransport

    public init(id: UInt32, uid: String, name: String, transport: OutputTransport) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

public enum OutputDevices {
    /// 卡片上一排最多放几个设备按钮，多出来的收进“…”菜单。
    public static let shelfLimit = 3

    /// SF Symbol：按连接方式，蓝牙耳机再按名字认 AirPods。
    public static func symbol(for device: OutputDevice) -> String {
        let name = device.name.lowercased()
        switch device.transport {
        case .builtIn:
            if name.contains("imac") || name.contains("mac mini") || name.contains("studio") {
                return "desktopcomputer"
            }
            return "laptopcomputer"
        case .bluetooth:
            if name.contains("airpods max") { return "airpodsmax" }
            if name.contains("airpods pro") { return "airpodspro" }
            if name.contains("airpods") { return "airpods" }
            if name.contains("beats") { return "beats.headphones" }
            if name.contains("homepod") { return "homepod.fill" }
            if name.contains("speaker") || name.contains("音箱") || name.contains("音响") { return "hifispeaker.fill" }
            return "headphones"
        case .usb, .thunderbolt:
            if name.contains("headset") || name.contains("耳机") || name.contains("headphone") { return "headphones" }
            return "hifispeaker.fill"
        case .hdmi, .displayPort: return "display"
        case .airPlay: return "airplayaudio"
        case .virtual, .aggregate, .other: return "waveform"
        }
    }

    /// 排好序的一排：按连接方式，同类按名字。
    public static func sorted(_ devices: [OutputDevice]) -> [OutputDevice] {
        devices.sorted {
            if $0.transport.rank != $1.transport.rank { return $0.transport.rank < $1.transport.rank }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 卡片上画哪几个，以及还剩几个收进菜单。当前设备一定在里面：
    /// 排在前 `limit` 之外时，换掉最后一个。
    public static func visible(_ devices: [OutputDevice], current: UInt32?,
                               limit: Int = shelfLimit) -> (shown: [OutputDevice], overflow: Int) {
        let all = sorted(devices)
        guard limit > 0 else { return ([], all.count) }
        guard all.count > limit else { return (all, 0) }
        var shown = Array(all.prefix(limit))
        if let current, !shown.contains(where: { $0.id == current }),
           let active = all.first(where: { $0.id == current }) {
            shown[limit - 1] = active
        }
        return (shown, all.count - shown.count)
    }

    /// 音量百分比，四舍五入。
    public static func percentText(_ level: Double) -> String {
        "\(Int((min(1, max(0, level.isFinite ? level : 0)) * 100).rounded()))%"
    }
}

// MARK: - 应用音量：卡片上的每一格

public enum AppVolumeStrip {
    /// 卡片上最多几格。
    public static let maxCells = 4
    /// 不超过这么多格时，图标旁边写应用名；四格只写百分比。
    public static let namedCells = 3

    /// 音量条填多少：0...150% 铺满一整条，100% 落在三分之二处。
    public static func fraction(percent: Double, muted: Bool) -> Double {
        muted ? 0 : AppVolume.clamp(percent) / AppVolume.range.upperBound
    }

    /// 100%（不处理）在条上的位置，画一道小刻度。
    public static var unityFraction: Double { AppVolume.unity / AppVolume.range.upperBound }

    /// 左右拖：从按下时的音量出发，拖过一整条宽度就是 0 到 150%。
    /// 靠近 100% 时吸过去，和面板里的滑杆一样。
    public static func percent(start: Double, dragged dx: Double, width: Double) -> Double {
        guard width > 0, dx.isFinite else { return AppVolume.clamp(start) }
        let moved = dx / width * AppVolume.range.upperBound
        return AppVolume.snapped(start + moved)
    }

    /// 卡片上画哪些应用，以及要不要写名字。改过音量或静音的排前面，
    /// 免得被挤出卡片；同类保持原来的顺序（按名字）。
    public static func cells<T>(_ rows: [T], changed: (T) -> Bool) -> (shown: [T], named: Bool, more: Int) {
        let ordered = rows.filter(changed) + rows.filter { !changed($0) }
        let shown = Array(ordered.prefix(maxCells))
        return (shown, shown.count <= namedCells, max(0, rows.count - shown.count))
    }

    /// 一格下面的小字。
    public static func label(percent: Double, muted: Bool) -> String {
        muted ? tr("静音") : AppVolume.percentText(percent)
    }
}

// MARK: - 相册宽幅：那年今天

/// 一张照片的拍摄日期和地点，宽幅卡片写在照片下沿。
public enum PhotoMemory {
    /// 往回找多少年的“那年今天”。
    public static let yearsBack = 30

    /// 是不是往年的今天（同月同日、更早的年份）。
    public static func isOnThisDay(_ date: Date, today: Date, calendar: Calendar = .current) -> Bool {
        let a = calendar.dateComponents([.year, .month, .day], from: date)
        let b = calendar.dateComponents([.year, .month, .day], from: today)
        guard let ay = a.year, let by = b.year, ay < by else { return false }
        return a.month == b.month && a.day == b.day
    }

    /// 往年今天的起止（当天 0 点到次日 0 点），从去年往回排。2 月 29 日只在闰年有。
    public static func dayRanges(today: Date, years: Int = yearsBack,
                                 calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day, years > 0 else { return [] }
        var ranges: [(Date, Date)] = []
        for back in 1...years {
            var c = DateComponents()
            c.year = year - back
            c.month = month
            c.day = day
            guard c.isValidDate(in: calendar), let start = calendar.date(from: c),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            ranges.append((start, end))
        }
        return ranges
    }

    /// “2024.10.18”。
    public static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return String(format: "%04ld.%02ld.%02ld", y, m, d)
    }

    /// 照片下沿那一行：有地点写“2024.10.18 · 杭州”，没有就只写日期。
    public static func caption(date: Date, place: String?, calendar: Calendar = .current) -> String {
        let day = dateText(date, calendar: calendar)
        guard let place = place?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty else { return day }
        return "\(day) · \(place)"
    }

    /// 上面一行小字：往年今天写“那年今天”，别的日子不写。
    public static func headline(date: Date, today: Date, calendar: Calendar = .current) -> String? {
        isOnThisDay(date, today: today, calendar: calendar) ? tr("那年今天") : nil
    }

    /// 反查地点得到的“城市, 省份”只留城市；中文逗号也认。
    public static func placeName(cityWithContext text: String?) -> String? {
        guard let text else { return nil }
        let first = text.split(whereSeparator: { $0 == "," || $0 == "，" }).first.map(String.init) ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// EXIF 的 DateTimeOriginal（“2024:10:18 15:42:07”），按本机时区读。
    public static func exifDate(_ text: String?, timeZone: TimeZone = .current) -> Date? {
        guard let text else { return nil }
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        c.hour = parts.count > 3 ? parts[3] : 0
        c.minute = parts.count > 4 ? parts[4] : 0
        c.second = parts.count > 5 ? parts[5] : 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard c.isValidDate(in: calendar), (c.year ?? 0) > 1900 else { return nil }
        return calendar.date(from: c)
    }

    /// GPS 的度数加南北东西，变成有正负的坐标；超出范围的算没有。
    public static func coordinate(_ value: Double?, ref: String?, isLatitude: Bool) -> Double? {
        guard let value, value.isFinite else { return nil }
        let negative = ["S", "W"].contains(ref?.uppercased() ?? "")
        let signed = negative ? -abs(value) : value
        let limit = isLatitude ? 90.0 : 180.0
        return abs(signed) <= limit ? signed : nil
    }

    /// 轮播底下最多画几个圆点。
    public static let maxDots = 5

    /// 第几个点亮：照片多于点数时按比例落在点上。
    public static func dot(index: Int, count: Int, dots: Int = maxDots) -> Int {
        guard count > 1, dots > 0 else { return 0 }
        let shown = min(count, dots)
        guard count > shown else { return min(max(0, index), shown - 1) }
        return min(shown - 1, max(0, index) * shown / count)
    }
}
