import Foundation

/// The five 电池 looks, stored as the widget's `look`.
///
/// 经典 and 液态 are free; 像素电池, 能量粒子 and 小熊猫抱电池 are Pro 专属
/// appearances, like the Wi-Fi rings. Every look reads the same battery, so
/// a locked one never hides information: it draws as 经典 instead.
///
/// A widget saved before looks existed has no `look` key and reads the
/// catalog default, which is 经典, so nobody's card changes under them. A
/// widget added from now on is created with 液态.
public enum BatteryLook: String, CaseIterable, Sendable {
    case classic
    case liquid
    case pixel
    case particles
    case panda

    public static let key = "look"
    /// What an existing widget without the key reads.
    public static let legacyDefault: BatteryLook = .classic
    /// What a freshly added widget is created with.
    public static let newWidgetDefault: BatteryLook = .liquid

    public var title: String {
        switch self {
        case .classic: tr("经典")
        case .liquid: tr("液态")
        case .pixel: tr("像素电池")
        case .particles: tr("能量粒子")
        case .panda: tr("小熊猫抱电池")
        }
    }

    public var isSupporterOnly: Bool {
        switch self {
        case .classic, .liquid: false
        case .pixel, .particles, .panda: true
        }
    }

    public static func from(_ raw: String) -> BatteryLook? { BatteryLook(rawValue: raw) }

    /// What is drawn: an unknown value reads as 经典, and a locked look
    /// falls back to 经典.
    public static func shown(_ raw: String, unlocked: Bool) -> BatteryLook {
        guard let look = BatteryLook(rawValue: raw) else { return .classic }
        return look.isSupporterOnly && !unlocked ? .classic : look
    }

    public static func shown(config: WidgetConfig, unlocked: Bool) -> BatteryLook {
        shown(config.string(key, default: legacyDefault.rawValue), unlocked: unlocked)
    }
}

// MARK: - Colour

/// A colour as three 0...1 channels, so the mapping can be tested without
/// SwiftUI.
public struct BatteryRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Straight-line mix: 0 is self, 1 is `other`.
    public func mixed(with other: BatteryRGB, _ amount: Double) -> BatteryRGB {
        let t = min(max(amount, 0), 1)
        return BatteryRGB(red + (other.red - red) * t,
                          green + (other.green - green) * t,
                          blue + (other.blue - blue) * t)
    }

    public static let white = BatteryRGB(1, 1, 1)
}

/// What colour a battery level is drawn in.
///
/// Above 50% green; 20% to 50% runs from orange at the bottom to yellow at
/// the top; below 20% red, slowly pulsing while it is not charging. Low
/// Power Mode overrides all of it with yellow, the colour macOS itself uses
/// for that mode.
public enum BatteryColorMap {
    public enum Band: String, Sendable { case green, amber, red, lowPower }

    public struct Tint: Equatable, Sendable {
        public var band: Band
        /// The main colour: water, cells, the arc.
        public var color: BatteryRGB
        /// The lighter end of the ring's gradient and its glow.
        public var highlight: BatteryRGB
        /// Red and not charging: the view breathes its opacity.
        public var pulses: Bool
    }

    public static let green = BatteryRGB(0.20, 0.84, 0.40)
    public static let orange = BatteryRGB(1.00, 0.55, 0.04)
    public static let yellow = BatteryRGB(1.00, 0.80, 0.04)
    public static let red = BatteryRGB(1.00, 0.27, 0.23)
    public static let lowPowerYellow = BatteryRGB(1.00, 0.84, 0.04)

    /// Whole percent, the way the card prints it, so the colour changes
    /// exactly when the number crosses a boundary.
    public static func percent(_ level: Double) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    public static func tint(level: Double, lowPower: Bool, charging: Bool) -> Tint {
        let value = percent(level)
        let band: Band
        let color: BatteryRGB
        if lowPower {
            band = .lowPower
            color = lowPowerYellow
        } else if value > 50 {
            band = .green
            color = green
        } else if value >= 20 {
            band = .amber
            color = orange.mixed(with: yellow, Double(value - 20) / 30)
        } else {
            band = .red
            color = red
        }
        return Tint(band: band, color: color, highlight: color.mixed(with: .white, 0.35),
                    pulses: band == .red && !charging)
    }

    /// The pulse's opacity factor at time `t` seconds: 0.55...1 over 2.4 s.
    public static func pulse(_ t: Double) -> Double {
        0.775 + 0.225 * cos(t * 2 * .pi / 2.4)
    }
}

// MARK: - Status line

/// The panel's one-line summary of the Mac battery.
public enum BatteryStatusText {
    /// "48 分钟", "2 小时", "1 小时 25 分钟". Hours round the minutes to
    /// five, since an estimate to the minute is false precision.
    public static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return tr("\(max(1, m)) 分钟") }
        var hours = m / 60
        var rest = Int((Double(m % 60) / 5).rounded()) * 5
        if rest == 60 { hours += 1; rest = 0 }
        return rest == 0 ? tr("\(hours) 小时") : tr("\(hours) 小时 \(rest) 分钟")
    }

    /// An estimate macOS gives: positive and under four days. It reports -1
    /// while it is still working one out, and 65535 for "unknown".
    public static func validMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0, minutes < 96 * 60 else { return nil }
        return minutes
    }

    public static func line(percent: Int, charging: Bool, onPower: Bool, charged: Bool,
                            watts: Int?, minutesToFull: Int?, minutesToEmpty: Int?) -> String {
        let wattText = watts.flatMap { $0 > 0 ? "\($0)W" : nil }
        if charging {
            var parts = [tr("充电中")]
            if let wattText { parts.append(wattText) }
            if let m = validMinutes(minutesToFull) { parts.append(tr("约 \(duration(minutes: m))充满")) }
            return parts.joined(separator: " · ")
        }
        if onPower {
            if charged || percent >= 100 { return tr("已充满") }
            // On the adapter but held back (optimised charging, a limit).
            var parts = [tr("已接电源")]
            if let wattText { parts.append(wattText) }
            parts.append(tr("暂未充电"))
            return parts.joined(separator: " · ")
        }
        if let m = validMinutes(minutesToEmpty) { return tr("使用电池 · 还能用约 \(duration(minutes: m))") }
        return tr("使用电池")
    }
}

// MARK: - Health

/// AppleSmartBattery's figures, read into what the panel shows. Anything that
/// does not make sense comes back nil, and the panel hides that item.
public enum BatteryHealth {
    /// 最大容量 as a percentage of the design capacity.
    ///
    /// Apple silicon publishes `AppleRawMaxCapacity` and `DesignCapacity`
    /// in mAh and a `MaxCapacity` that is already a percentage; Intel Macs
    /// publish `MaxCapacity` in mAh. A new battery can measure a little over
    /// its design, which reads as 100% the way System Settings shows it.
    public static func maximumCapacityPercent(rawMax: Int?, design: Int?, maxCapacity: Int?) -> Int? {
        if let rawMax, let design, rawMax > 0, design > 0 {
            return clamp(Double(rawMax) / Double(design) * 100)
        }
        if let maxCapacity, maxCapacity > 0 {
            if maxCapacity <= 100 { return maxCapacity }
            if let design, design > 0 { return clamp(Double(maxCapacity) / Double(design) * 100) }
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Int? {
        guard value.isFinite, value >= 1, value <= 150 else { return nil }
        return min(100, Int(value.rounded()))
    }

    public static func cycleCount(_ raw: Int?) -> Int? {
        guard let raw, raw >= 0, raw < 100_000 else { return nil }
        return raw
    }

    /// `Temperature` is in hundredths of a degree Celsius.
    public static func celsius(raw: Int?) -> Double? {
        guard let raw else { return nil }
        let value = Double(raw) / 100
        return (1...100).contains(value) ? value : nil
    }

    public static func celsiusText(_ celsius: Double) -> String {
        String(format: "%.1f°C", celsius)
    }
}

// MARK: - Motion

/// How often a battery look redraws, or nil for a still picture.
///
/// Animation costs power, which is a strange thing for a battery widget to
/// spend. So: a card animates only while it is actually on screen, and then
/// at full rate only while charging; on battery the water keeps a slow ripple
/// at about 10 fps and a red level keeps its slow pulse, and nothing else
/// moves. An open panel is looked at, so it animates either way. 减少动态效果
/// stops everything. 经典 never animates.
public enum BatteryMotion {
    public static let maxFPS = 30.0
    public static let idleFPS = 10.0

    public enum Host: Equatable, Sendable {
        case card(visible: Bool)
        case panel
    }

    public static func framesPerSecond(look: BatteryLook, charging: Bool, pulsing: Bool,
                                       flourish: Bool, host: Host, reduceMotion: Bool) -> Double? {
        guard !reduceMotion, look != .classic else { return nil }
        if case .card(let visible) = host, !visible { return nil }
        if flourish || charging { return maxFPS }
        if look == .liquid || pulsing { return idleFPS }
        return nil
    }

    /// Bubbles and particles move with the charger: a 30 W adapter is slow,
    /// 96 W and up is brisk. 1 at 60 W.
    public static func chargeSpeed(watts: Int?) -> Double {
        guard let watts, watts > 0 else { return 1 }
        return min(max(Double(watts) / 60, 0.4), 1.6)
    }

    /// How long the plug-in sweep and the full-charge glow last.
    public static let plugDuration: TimeInterval = 1.3
    public static let fullDuration: TimeInterval = 2.6

    public static func isFlourishing(pluggedAt: Date?, fullAt: Date?, now: Date) -> Bool {
        if let pluggedAt, now.timeIntervalSince(pluggedAt) >= 0,
           now.timeIntervalSince(pluggedAt) < plugDuration { return true }
        if let fullAt, now.timeIntervalSince(fullAt) >= 0,
           now.timeIntervalSince(fullAt) < fullDuration { return true }
        return false
    }

    /// The water surface's height above the level line at `x` (0...1 across)
    /// and time `t`, as a fraction of the gauge's height: two sine waves
    /// drifting opposite ways. Flattened toward empty and full so the wave
    /// never pokes outside the circle's bottom or top.
    public static func surface(x: Double, t: Double, level: Double, layer: Int, speed: Double) -> Double {
        let level = min(max(level, 0), 1)
        let room = min(level, 1 - level) * 4
        let amplitude = 0.035 * min(1, max(0.25, room))
        if layer == 0 {
            return amplitude * sin(2 * .pi * (x * 1.0 + t * 0.22 * speed))
        }
        return amplitude * 0.8 * sin(2 * .pi * (x * 1.35 - t * 0.16 * speed) + 1.3)
    }

    /// Cells lit in the 像素电池 at time `t`: the level's own cells, plus a
    /// run that climbs to five and starts again while charging.
    public static func pixelCells(level: Double, charging: Bool, t: Double, cells: Int = 5) -> Int {
        let percent = BatteryColorMap.percent(level)
        let base = percent == 0 ? 0 : min(cells, Int((Double(percent) / 100 * Double(cells)).rounded(.up)))
        guard charging, base < cells else { return base }
        let steps = cells - base + 1
        let step = Int(max(0, t) * 2.5) % steps
        return base + step
    }
}
