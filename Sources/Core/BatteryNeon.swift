import Foundation

// 「霓虹灯管」电池外观（Pro）的纯逻辑：电量到颜色、数字灌亮到哪里、插电动画
// 每一刻画什么、什么时候播、30 秒节流。界面在 Sources/Widgets/Kinds/BatteryNeonDigits.swift
// （扩展栏卡片、系统小组件、插电动画共用），插电动画的窗口在
// Sources/App/BatteryNeonPlugController.swift。
//
// 这个文件只用 Foundation，也编进系统小组件扩展（project.yml 的 DocklingWidgets），
// 所以不能引用 Core 里别的类型，也不调 `tr`。

public enum BatteryNeon {

    // MARK: 颜色

    /// 灯管的四档颜色：20% 及以下红，50% 及以下橙，90% 及以下黄，再往上绿。
    public enum Band: String, CaseIterable, Sendable {
        case red, orange, yellow, green
    }

    public static func band(percent: Int) -> Band {
        if percent <= 20 { return .red }
        if percent <= 50 { return .orange }
        if percent <= 90 { return .yellow }
        return .green
    }

    /// 0...1 的三个通道，界面自己转成 Color。
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        /// 直线混色：0 是自己，1 是 `other`。
        public func mixed(with other: RGB, _ amount: Double) -> RGB {
            let t = min(max(amount, 0), 1)
            return RGB(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
        }

        public static let white = RGB(1, 1, 1)
    }

    /// 灯管亮起来的颜色。深色底上亮一些；浅色底上压深一点，白玻璃上也看得清
    /// （效果图 design/battery-neon：黄色深色 #FFC424，浅色 #F6AC08）。
    public static func color(_ band: Band, dark: Bool) -> RGB {
        switch (band, dark) {
        case (.red, true): RGB(hex: 0xFF4C40)
        case (.red, false): RGB(hex: 0xE5352A)
        case (.orange, true): RGB(hex: 0xFF8A2A)
        case (.orange, false): RGB(hex: 0xEC700C)
        case (.yellow, true): RGB(hex: 0xFFC424)
        case (.yellow, false): RGB(hex: 0xF6AC08)
        case (.green, true): RGB(hex: 0x4BE070)
        case (.green, false): RGB(hex: 0x1FAF4B)
        }
    }

    public static func color(percent: Int, dark: Bool) -> RGB {
        color(band(percent: percent), dark: dark)
    }

    /// 灯管芯（最亮的那一道）：往白里提，深色底提得多。
    public static func core(_ color: RGB, dark: Bool) -> RGB {
        color.mixed(with: .white, dark ? 0.62 : 0.45)
    }

    // MARK: 灌亮

    /// 电量对应的灌亮比例 0...1。读不到电量（nil、负数、非数）是 0，绝不编一个出来。
    public static func fillFraction(percent: Int?) -> Double {
        guard let percent else { return 0 }
        return min(max(Double(percent) / 100, 0), 1)
    }

    /// 遮罩从字框底边往上量的高度（点）：数字的墨迹从基线到大写字母高度，字框底边
    /// 到基线还隔着下伸部（descent），所以 0% 时正好盖到基线、100% 时盖到数字顶，
    /// 中间按比例。`fraction` 超出 0...1 时夹住。
    public static func maskHeight(fraction: Double, descent: Double, capHeight: Double) -> Double {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let d = max(0, descent)
        let cap = max(0, capHeight)
        if f <= 0 { return 0 }
        if f >= 1 { return d + cap + max(1, cap * 0.08) }
        return d + cap * f
    }

    /// 灯管的线宽（点）：跟字号走，细而圆，字小时也不细到看不见。
    public static func tubeWidth(fontSize: Double) -> Double {
        max(1.2, fontSize * 0.045)
    }

    // MARK: 状态行

    /// 分钟拆成「几小时几分」。系统还在估算（nil 或 0 以下）是 nil。
    public static func hoursMinutes(_ minutes: Int?) -> (hours: Int, minutes: Int)? {
        guard let minutes, minutes > 0 else { return nil }
        return (minutes / 60, minutes % 60)
    }

    // MARK: 插电动画：什么时候播

    /// 设置里「插电时霓虹动画」的 UserDefaults 键，默认开（没存过就是开）。
    public static let plugAnimationKey = "battery.neonPlugAnimation"

    public static func plugAnimationEnabled(stored: Any?) -> Bool {
        (stored as? Bool) ?? (stored as? NSNumber)?.boolValue ?? true
    }

    /// 电源的来路：电池供电或接着电源。读不到（台式机、没有电池）是 nil。
    public enum PowerSource: String, Sendable {
        case battery, ac
    }

    /// 只有从电池切到接通电源才算「插上」。第一次读（`previous` 为 nil）不算，
    /// 免得码头一启动、或刚唤醒时就播一遍。
    public static func isPlugIn(from previous: PowerSource?, to current: PowerSource?) -> Bool {
        previous == .battery && current == .ac
    }

    /// 不播的原因，按判断顺序。`play` 是要播。
    public enum PlugDecision: Equatable, Sendable {
        case play
        case off
        case locked
        case throttled
        case fullscreen
        case sharing
        case presenting
        case notchBusy
    }

    /// 插电那一刻屏幕上的情况。
    public struct PlugContext: Equatable, Sendable {
        /// 设置里「插电时霓虹动画」开着。
        public var enabled: Bool
        /// 码头 Pro 已解锁（或试用中）。
        public var unlocked: Bool
        /// 有全屏 App 盖住了要播的那块屏幕。
        public var fullscreen: Bool
        /// 系统屏幕共享、远程管理正在看这台 Mac。
        public var sharing: Bool
        /// 码头的演示模式开着。
        public var presenting: Bool
        /// 刘海那里已经有码头的东西展开着：消息灵动岛的卡片、AI 刘海对话、提醒弹窗、
        /// 音量亮度的灵动提示。它们优先，这次动画跳过。
        public var notchBusy: Bool

        public init(enabled: Bool = true, unlocked: Bool = true, fullscreen: Bool = false, sharing: Bool = false,
                    presenting: Bool = false, notchBusy: Bool = false) {
            self.enabled = enabled
            self.unlocked = unlocked
            self.fullscreen = fullscreen
            self.sharing = sharing
            self.presenting = presenting
            self.notchBusy = notchBusy
        }
    }

    public static func plugDecision(_ context: PlugContext, gate: PlugGate, at now: Date) -> PlugDecision {
        guard context.enabled else { return .off }
        guard context.unlocked else { return .locked }
        guard gate.wouldAllow(at: now) else { return .throttled }
        if context.fullscreen { return .fullscreen }
        if context.sharing { return .sharing }
        if context.presenting { return .presenting }
        if context.notchBusy { return .notchBusy }
        return .play
    }

    /// 30 秒内重复插拔只播一次：从上一次真正播的那一刻算。被跳过的那次（全屏、
    /// 演示、刘海正忙）不占名额。
    public struct PlugGate: Equatable, Sendable {
        public static let defaultWindow: TimeInterval = 30

        public let window: TimeInterval
        public private(set) var lastPlayed: Date?

        public init(window: TimeInterval = PlugGate.defaultWindow) {
            self.window = window
        }

        public func wouldAllow(at now: Date) -> Bool {
            guard let lastPlayed else { return true }
            // 系统时间往回拨了：照常放行，免得一直不播。
            if now < lastPlayed { return true }
            return now.timeIntervalSince(lastPlayed) >= window
        }

        public mutating func recordPlay(at now: Date) {
            lastPlayed = now
        }
    }

    // MARK: 插电动画：每一刻画什么

    /// 动画本身 2.5 秒；之后刘海旁的小胶囊再留 3 秒、0.4 秒淡出。
    public enum Plug {
        public static let duration: TimeInterval = 2.5
        public static let chipHold: TimeInterval = 3
        public static let chipFade: TimeInterval = 0.4
        /// 窗口一共开这么久，到点收掉。
        public static var total: TimeInterval { duration + chipHold + chipFade }

        /// 各段起止（秒）。
        static let glowEnd = 0.45
        static let dropStart = 0.3
        static let dropEnd = 0.85
        static let digitsIn = (0.3, 0.6)
        static let fillSpan = (0.85, 1.85)
        static let digitsOut = (1.9, 2.5)
        static let chipIn = (1.9, 2.25)

        /// 一帧要画的东西，全是 0...1。
        public struct Frame: Equatable, Sendable {
            /// 刘海（或菜单栏中间）边缘亮多少。
            public var edgeGlow: Double
            /// 光滴从刘海落到数字顶的进度，不在下落时 nil。
            public var drop: Double?
            /// 霓虹数字（含底下状态行）的不透明度。
            public var digits: Double
            /// 灌亮了目标电量的多少（乘以电量才是灯管实际亮到的比例）。
            public var fill: Double
            /// 刘海旁小胶囊的不透明度。
            public var chip: Double
        }

        public static func frame(at t: TimeInterval) -> Frame {
            Frame(edgeGlow: edgeGlow(t), drop: drop(t), digits: digits(t), fill: fill(t), chip: chip(t))
        }

        /// 亮一下：前 0.12 秒升到顶，之后慢慢退。
        static func edgeGlow(_ t: TimeInterval) -> Double {
            guard t >= 0, t < glowEnd else { return 0 }
            let rise = 0.12
            if t < rise { return easeOut(t / rise) }
            return 1 - easeIn((t - rise) / (glowEnd - rise))
        }

        /// 光滴往下越落越快（重力那样的缓入）。
        static func drop(_ t: TimeInterval) -> Double? {
            guard t >= dropStart, t < dropEnd else { return nil }
            return easeIn((t - dropStart) / (dropEnd - dropStart))
        }

        static func digits(_ t: TimeInterval) -> Double {
            if t < digitsIn.0 || t >= digitsOut.1 { return 0 }
            if t < digitsIn.1 { return easeOut((t - digitsIn.0) / (digitsIn.1 - digitsIn.0)) }
            if t < digitsOut.0 { return 1 }
            return 1 - easeIn((t - digitsOut.0) / (digitsOut.1 - digitsOut.0))
        }

        /// 光滴落进来以后从下往上灌，先快后慢。
        static func fill(_ t: TimeInterval) -> Double {
            if t < fillSpan.0 { return 0 }
            if t >= fillSpan.1 { return 1 }
            return easeOut((t - fillSpan.0) / (fillSpan.1 - fillSpan.0))
        }

        static func chip(_ t: TimeInterval) -> Double {
            if t < chipIn.0 || t >= total { return 0 }
            if t < chipIn.1 { return easeOut((t - chipIn.0) / (chipIn.1 - chipIn.0)) }
            if t < duration + chipHold { return 1 }
            return 1 - (t - duration - chipHold) / chipFade
        }

        static func easeIn(_ x: Double) -> Double {
            let c = min(max(x, 0), 1)
            return c * c
        }

        static func easeOut(_ x: Double) -> Double {
            let c = min(max(x, 0), 1)
            return 1 - (1 - c) * (1 - c)
        }
    }
}
