import Foundation

// 播客面板 2.0（沉浸式播放器）的纯逻辑：封面主色和背景渐变、单集状态与筛选、
// 列表折叠、两种日期的标注、节目短名、小熊猫什么时候出现。不碰 SwiftUI 和 AppKit，
// 测试在 PodcastPlayerLookTests。

// MARK: - 封面主色

/// 从封面缩略图的像素里取颜色。像素由界面层读出来（几十个点就够），这里只算。
public enum PodcastCoverColor {
    /// 太黑、太白的点不算（黑底、白边会把颜色冲掉）。
    public static let darkCutoff = 0.08
    public static let lightCutoff = 0.94
    /// 饱和度低于这个的点没有可说的色相，不参与主色投票。
    public static let chromaCutoff = 0.15
    /// 主色那一桶的平均饱和度低于这个，整张封面按灰处理（返回 nil）。
    public static let greyThreshold = 0.1
    /// 色相分几桶：够分清蓝和青，又不会把一面墙的渐变劈成两半。
    public static let buckets = 12

    /// 平均色：去掉太黑、太白的点后取平均。一个点都不剩时 nil。
    public static func average(_ samples: [ColorCode]) -> ColorCode? {
        let kept = samples.filter { usable($0) }
        guard !kept.isEmpty else { return nil }
        let n = Double(kept.count)
        return ColorCode(red: kept.map(\.red).reduce(0, +) / n,
                         green: kept.map(\.green).reduce(0, +) / n,
                         blue: kept.map(\.blue).reduce(0, +) / n)
    }

    /// 主色：按色相分桶，每个点按「饱和度 x 亮度」加权投票，票最多那一桶的平均色。
    /// 平均色在多彩封面上会变成灰褐（对立色相互相抵消），主色不会。
    /// 黑白、灰色封面没有主色，返回 nil（界面就不染色）。
    public static func dominant(_ samples: [ColorCode]) -> ColorCode? {
        var mass = [Double](repeating: 0, count: buckets)
        var hueSum = [Double](repeating: 0, count: buckets)
        var saturationSum = [Double](repeating: 0, count: buckets)
        var valueSum = [Double](repeating: 0, count: buckets)
        for sample in samples where usable(sample) {
            let (h, s, v) = PodcastArtTint.hsv(sample)
            guard s > chromaCutoff else { continue }
            let weight = s * v
            let bucket = min(buckets - 1, Int(h * Double(buckets)))
            mass[bucket] += weight
            hueSum[bucket] += h * weight
            saturationSum[bucket] += s * weight
            valueSum[bucket] += v * weight
        }
        guard let winner = mass.indices.max(by: { mass[$0] < mass[$1] }), mass[winner] > 0 else { return nil }
        let saturation = saturationSum[winner] / mass[winner]
        guard saturation >= greyThreshold else { return nil }
        return PodcastArtTint.rgb(hueSum[winner] / mass[winner], saturation, valueSum[winner] / mass[winner])
    }

    private static func usable(_ c: ColorCode) -> Bool {
        let peak = max(c.red, c.green, c.blue), floor = min(c.red, c.green, c.blue)
        return peak >= darkCutoff && floor <= lightCutoff
    }

    // MARK: 背景渐变

    /// 播放器背后那层渐变：同一个色相，亮度由设计定死（浅色外观很亮、深色外观很暗），
    /// 饱和度压低，透明度也有上限，所以不管封面是什么颜色，字都看得清，也不会一大片发光。
    public struct Backdrop: Equatable, Sendable {
        public var top: ColorCode
        public var bottom: ColorCode
        /// 顶上的不透明度；往下渐渐变成透明（见 `fadeEnd`）。
        public var opacity: Double
    }

    /// 浅色外观：接近白的淡彩，保持浅底。
    public static let lightTopBrightness = 0.97
    public static let lightBottomBrightness = 0.93
    public static let lightSaturationCap = 0.22
    public static let lightOpacity = 0.55
    /// 深色外观：很暗的同色，和深色玻璃融在一起。
    public static let darkTopBrightness = 0.30
    public static let darkBottomBrightness = 0.18
    public static let darkSaturationCap = 0.45
    public static let darkOpacity = 0.6
    /// 蓝色系（青到蓝紫）再收一点饱和度：大面积蓝最容易显得像发光。
    public static let blueHues = 0.45...0.72
    public static let blueDamping = 0.7
    /// 渐变在面板高度的这个比例处完全消失，下半截保持原来的玻璃。
    public static let fadeEnd = 0.7

    /// 没有主色（没封面、灰白封面）时 nil：不染色，只留玻璃。
    public static func backdrop(_ color: ColorCode?, dark: Bool) -> Backdrop? {
        guard let color else { return nil }
        let (h, s, _) = PodcastArtTint.hsv(color)
        guard s >= greyThreshold else { return nil }
        var cap = dark ? darkSaturationCap : lightSaturationCap
        if blueHues.contains(h) { cap *= blueDamping }
        let saturation = min(s, cap)
        let top = PodcastArtTint.rgb(h, saturation, dark ? darkTopBrightness : lightTopBrightness)
        let bottom = PodcastArtTint.rgb(h, saturation, dark ? darkBottomBrightness : lightBottomBrightness)
        return Backdrop(top: top, bottom: bottom, opacity: dark ? darkOpacity : lightOpacity)
    }

    /// 相对亮度（WCAG），测试用来证明浅色下够浅、深色下够暗。
    public static func luminance(_ c: ColorCode) -> Double {
        func channel(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }
}

// MARK: - 强调色

/// 播客面板的整套强调色：选中胶囊描边、「继续收听」标签、进度条、播放大按钮、「查看全部」、
/// 单集播放图标和背景氛围，全部从当前封面的主色来，换节目就换颜色，代码里没有固定的色相。
///
/// 可读性校正：浅色外观把颜色压暗、深色外观提亮，直到和面板底色的对比度够 4.5:1
/// （WCAG AA 正文）；播放键的图标和底色之间同样够 4.5:1。灰白、低饱和封面和没封面时
/// 回退中性灰（`neutral` 为 true）。
public struct PodcastPalette: Equatable, Sendable {
    /// 文字、细线、进度条用的强调色，和面板底色对比度至少 `minimumContrast`。
    public var accent: ColorCode
    /// 播放大按钮的底色和上面的图标色。
    public var playFill: ColorCode
    public var playIcon: ColorCode
    /// 背后的氛围渐变，没主色时 nil。
    public var backdrop: PodcastCoverColor.Backdrop?
    /// 没有可用的封面色，用的是中性灰。
    public var neutral: Bool

    public static let minimumContrast = 4.5
    /// 拿来校正的面板底色：浅色玻璃接近白，深色玻璃接近 #1C1C1E。
    public static let lightSurface = ColorCode(red: 0.95, green: 0.95, blue: 0.96)
    public static let darkSurface = ColorCode(red: 0.12, green: 0.12, blue: 0.13)
    /// 强调色的饱和度范围：太淡看不出颜色，太艳刺眼。
    public static let saturationRange = 0.4...0.8

    public static func make(_ cover: ColorCode?, dark: Bool) -> PodcastPalette {
        let surface = dark ? darkSurface : lightSurface
        guard let cover else { return neutralPalette(dark: dark) }
        let (h, s0, _) = PodcastArtTint.hsv(cover)
        guard s0 >= PodcastCoverColor.greyThreshold else { return neutralPalette(dark: dark) }
        var s = min(max(s0, saturationRange.lowerBound), saturationRange.upperBound)
        var accent: ColorCode
        if dark {
            // 提亮：先把亮度推到顶，还不够就减饱和度（越接近白越亮）。
            var v = 0.85
            accent = PodcastArtTint.rgb(h, s, v)
            while contrast(accent, surface) < minimumContrast {
                if v < 1 { v = min(1, v + 0.05) } else if s > 0 { s = max(0, s - 0.05) } else { break }
                accent = PodcastArtTint.rgb(h, s, v)
            }
        } else {
            // 压暗：亮度一步步往下降。
            var v = 0.75
            accent = PodcastArtTint.rgb(h, s, v)
            while contrast(accent, surface) < minimumContrast, v > 0.05 {
                v -= 0.04
                accent = PodcastArtTint.rgb(h, s, v)
            }
        }
        let playFill: ColorCode
        let playIcon: ColorCode
        if dark {
            // 深色：接近白、带一点封面色的圆，图标是同色相的深色。
            playFill = PodcastArtTint.rgb(h, min(s0, 0.16), 0.97)
            playIcon = PodcastArtTint.rgb(h, min(max(s0, 0.5), 0.8), 0.24)
        } else {
            // 浅色：压暗过的强调色做底，白色图标。
            playFill = accent
            playIcon = ColorCode(red: 1, green: 1, blue: 1)
        }
        return PodcastPalette(accent: accent, playFill: playFill, playIcon: playIcon,
                              backdrop: PodcastCoverColor.backdrop(cover, dark: dark), neutral: false)
    }

    public static func neutralPalette(dark: Bool) -> PodcastPalette {
        dark
            ? PodcastPalette(accent: ColorCode(red: 0.86, green: 0.86, blue: 0.88),
                             playFill: ColorCode(red: 0.95, green: 0.95, blue: 0.96),
                             playIcon: ColorCode(red: 0.11, green: 0.11, blue: 0.12),
                             backdrop: nil, neutral: true)
            : PodcastPalette(accent: ColorCode(red: 0.28, green: 0.28, blue: 0.30),
                             playFill: ColorCode(red: 0.17, green: 0.17, blue: 0.19),
                             playIcon: ColorCode(red: 1, green: 1, blue: 1),
                             backdrop: nil, neutral: true)
    }

    /// WCAG 对比度，1...21。
    public static func contrast(_ a: ColorCode, _ b: ColorCode) -> Double {
        let la = PodcastCoverColor.luminance(a), lb = PodcastCoverColor.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: - 单集状态

/// 列表里一集显示的状态：正在播放、未听、收听中（带百分比）、已听完。
public enum PodcastEpisodeStatus: Equatable, Sendable {
    case playing
    case unheard
    case listening(percent: Int)
    case finished

    /// `state` 是存档里的收听状态，`isCurrent` 表示播放器手里正是这一集（播放或暂停）。
    /// 正在播放（不是暂停）的一集显示「正在播放」；暂停在播放器里的一集按它的进度算。
    public static func of(_ state: PodcastEpisodeState, isPlaying: Bool,
                          livePosition: Double? = nil, liveDuration: Double? = nil) -> PodcastEpisodeStatus {
        if isPlaying { return .playing }
        if let position = livePosition, let duration = liveDuration, duration > 0, position > 0 {
            if position >= duration - PodcastPlayback.finishMargin { return .finished }
            return .listening(percent: percent(position / duration))
        }
        switch state {
        case .new, .unplayed: return .unheard
        case .inProgress(let fraction): return .listening(percent: percent(fraction))
        case .finished: return .finished
        }
    }

    /// 1 到 99：开了头就至少 1%，没听完就最多 99%，免得「收听中 0%」「收听中 100%」。
    public static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 1 }
        return min(99, max(1, Int((fraction * 100).rounded(.down))))
    }

    public var label: String {
        switch self {
        case .playing: tr("正在播放")
        case .unheard: tr("未听")
        case .listening(let percent): tr("收听中 \(percent)%")
        case .finished: tr("已听完")
        }
    }
}

// MARK: - 单集筛选

public enum PodcastEpisodeFilter: String, CaseIterable, Sendable {
    case all
    case unheard
    case listening

    public var title: String {
        switch self {
        case .all: tr("全部")
        case .unheard: tr("未听")
        case .listening: tr("收听中")
        }
    }

    /// 筛完没有单集时的那句话。
    public var emptyText: String {
        switch self {
        case .all: tr("这个节目还没有单集。")
        case .unheard: tr("没有未听的单集")
        case .listening: tr("没有收听中的单集")
        }
    }

    /// 正在播放的一集算「收听中」，不算「未听」。
    public func includes(_ status: PodcastEpisodeStatus) -> Bool {
        switch self {
        case .all: true
        case .unheard: status == .unheard
        case .listening:
            switch status {
            case .playing, .listening: true
            case .unheard, .finished: false
            }
        }
    }

    /// 按筛选留下的单集，顺序不变。
    public func apply<T>(_ items: [T], status: (T) -> PodcastEpisodeStatus) -> [T] {
        self == .all ? items : items.filter { includes(status($0)) }
    }
}

// MARK: - 列表折叠

/// 最近单集默认只露两条，其余点「查看全部」展开，在列表里滚动。
public enum PodcastEpisodeListing {
    public static let collapsedCount = 2
    /// 展开后列表最高这么多点，再多在里面滚。
    public static let expandedMaxHeight: Double = 280

    public static func visibleCount(total: Int, expanded: Bool) -> Int {
        expanded ? max(0, total) : min(max(0, total), collapsedCount)
    }

    /// 折叠时藏了几条（「查看全部」按钮上不显示数字时为 0）。
    public static func hiddenCount(total: Int, expanded: Bool) -> Int {
        max(0, total) - visibleCount(total: total, expanded: expanded)
    }

    /// 需不需要「查看全部 / 收起」这个按钮。
    public static func needsToggle(total: Int) -> Bool { total > collapsedCount }
}

// MARK: - 日期标注

/// 节目「最近更新」和单集「发布于」是两件事，分开写清楚，不再都只写一个日期。
public enum PodcastDateLabel {
    public static func updated(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        let text = PodcastPlayback.dateText(date, now: now, calendar: calendar)
        return text.isEmpty ? "" : tr("节目更新于 \(text)")
    }

    public static func published(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        let text = PodcastPlayback.dateText(date, now: now, calendar: calendar)
        return text.isEmpty ? "" : tr("发布于 \(text)")
    }
}

// MARK: - 节目短名

/// 封面选择器下面那行短名：小宇宙节目名常带副标题（「节目｜副标题」「节目：介绍」），
/// 取第一段；还太长就截断加省略号。汉字按 2 个宽度、其他字符按 1 个算。
public enum PodcastShowName {
    public static let separators: [String] = ["｜", "|", "丨", "：", ":", "·", "・", " - ", "（", "(", "【", "[", "，", ","]
    /// 大约 5 个汉字宽。
    public static let maxWidth = 10

    public static func short(_ title: String, maxWidth: Int = maxWidth) -> String {
        var head = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in separators {
            if let range = head.range(of: separator) {
                let first = head[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !first.isEmpty { head = first }
            }
        }
        guard width(head) > maxWidth else { return head }
        var out = ""
        for character in head {
            if width(out + String(character)) > maxWidth - 1 { break }
            out.append(character)
        }
        return out.trimmingCharacters(in: .whitespaces) + "…"
    }

    public static func width(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (wide($1) ? 2 : 1) }
    }

    private static func wide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD: true
        default: false
        }
    }
}

// MARK: - 小熊猫

/// 播客面板的小熊猫：播放时不出现。只在没订阅（待机）或没有可播的单集（休息）时
/// 当空状态，听完一整集时短暂表态一次（完成，`PandaMotion.doneHold`）。
public enum PodcastPandaCue {
    /// 空状态画哪个样子；有可播内容时 nil（不画）。
    public static func empty(showCount: Int, playableCount: Int, loading: Bool) -> PandaState? {
        if showCount == 0 { return .idle }
        if playableCount == 0, !loading { return .rest }
        return nil
    }

    /// 听完一整集那一下。
    public static func finishPulse(at now: Date) -> PandaPulse {
        PandaPulse(state: .done, started: now, until: now.addingTimeInterval(PandaMotion.doneHold))
    }
}
