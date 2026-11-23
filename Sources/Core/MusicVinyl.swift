import Foundation

/// 正在播放面板的样式：标准（原来的大封面）或黑胶模式。存在卡片配置里，
/// 默认标准，没选过的卡片外观不变。入口在面板底部「外观」里。
public enum MusicPanelStyle: String, CaseIterable, Sendable, Identifiable {
    case standard
    case vinyl

    public var id: String { rawValue }

    /// 卡片配置里的键。
    public static let key = "panelStyle"

    /// 这张卡片选的样式；没写过或写了认不得的值都按标准。
    public static func of(_ config: WidgetConfig) -> MusicPanelStyle {
        MusicPanelStyle(rawValue: config.string(key, default: MusicPanelStyle.standard.rawValue)) ?? .standard
    }

    /// 选一个样式。选回标准时把键去掉，配置和从没选过一样。
    public static func choosing(_ style: MusicPanelStyle, in config: WidgetConfig) -> WidgetConfig {
        var copy = config
        copy.set(key, style == .standard ? nil : .string(style.rawValue))
        return copy
    }

    public var title: String {
        switch self {
        case .standard: tr("标准")
        case .vinyl: tr("黑胶模式")
        }
    }
}

/// 黑胶模式的纯数学：唱台怎么摆、唱片转多快、唱臂按进度落在哪、水波纹怎么扩散。
/// 界面只拿这里算好的数画，测试可以拨到任意进度和时刻。
///
/// 坐标以唱台左上角为原点，y 向下；角度是唱臂相对竖直向下顺时针转过的度数
/// （和 SwiftUI `rotationEffect` 同向），0 度是唱臂收在支架上。
public enum MusicVinyl {
    // MARK: 唱台布局

    /// 设计稿宽度（320 面板的内容区）和唱台高度。窄于设计宽度时整体等比缩小。
    public static let designWidth: Double = 288
    public static let designHeight: Double = 200

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    /// 唱台各部分的位置，按给定宽度算好。
    public struct Stage: Equatable, Sendable {
        /// 缩放比例（宽度够时是 1）。
        public var scale: Double
        public var width: Double
        public var height: Double
        /// 左边的专辑封面玻璃卡。
        public var cover: Rect
        /// 唱片中心和半径。
        public var center: Point
        public var radius: Double
        /// 唱臂转轴和从转轴到唱针的长度。
        public var pivot: Point
        public var armLength: Double
        /// 转轴底座半径。
        public var pivotBase: Double

        /// 最外圈和最内圈纹路的半径：唱针从外圈走到内圈。
        public var outerGroove: Double { radius * MusicVinyl.outerGrooveRatio }
        public var innerGroove: Double { radius * MusicVinyl.innerGrooveRatio }
        /// 中心标签半径。
        public var label: Double { radius * MusicVinyl.labelRatio }
    }

    public static let outerGrooveRatio = 0.93
    public static let innerGrooveRatio = 0.44
    public static let labelRatio = 0.34

    /// 按可用宽度摆唱台。宽度不到设计宽时等比缩小，从不超出给的宽度。
    public static func stage(width: Double) -> Stage {
        let w = width.isFinite && width > 0 ? width : designWidth
        let s = min(1, w / designWidth)
        return Stage(
            scale: s,
            width: designWidth * s,
            height: designHeight * s,
            cover: Rect(x: 0, y: 36 * s, width: 124 * s, height: 124 * s),
            center: Point(x: 160 * s, y: 98 * s),
            radius: 90 * s,
            pivot: Point(x: 266 * s, y: 26 * s),
            armLength: 120 * s,
            pivotBase: 15 * s)
    }

    // MARK: 唱臂

    /// 唱臂在支架上（暂停、没在放）时的角度。
    public static let restAngle = 0.0
    /// 求落针角度时搜索的上限：再往里唱针就越过中心了。
    static let searchLimit = 50.0

    /// 唱臂转到 `angle` 度时唱针的位置。
    public static func stylus(_ stage: Stage, angle: Double) -> Point {
        let a = angle * .pi / 180
        return Point(x: stage.pivot.x - stage.armLength * sin(a),
                     y: stage.pivot.y + stage.armLength * cos(a))
    }

    /// 唱针离唱片中心多远。
    public static func stylusDistance(_ stage: Stage, angle: Double) -> Double {
        let p = stylus(stage, angle: angle)
        return hypot(p.x - stage.center.x, p.y - stage.center.y)
    }

    /// 唱针正好落在半径 `groove` 那圈时唱臂的角度。在 0 到 `searchLimit` 度之间
    /// 唱针离中心的距离一路变小，二分就能求出来。
    public static func angle(_ stage: Stage, groove: Double) -> Double {
        var low = restAngle
        var high = searchLimit
        for _ in 0..<48 {
            let mid = (low + high) / 2
            if stylusDistance(stage, angle: mid) > groove { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// 唱臂这一刻的角度：在放时按进度从外圈缓慢走向内圈，读不到进度（直播、浏览器
    /// 没时长）时停在外圈；暂停或没在放时抬回支架。
    public static func armAngle(_ stage: Stage, progress: Double?, playing: Bool) -> Double {
        guard playing else { return restAngle }
        let p = progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        let groove = stage.outerGroove + (stage.innerGroove - stage.outerGroove) * p
        return angle(stage, groove: groove)
    }

    // MARK: 唱片转动

    /// 匀速慢转：每秒 40 度（约 6.7 转每分钟），比真唱片慢，看得出在转又不晃眼。
    public static let degreesPerSecond = 40.0
    /// 转动和水波纹的帧率。
    public static let fps = 30.0

    /// 唱片角度：上次停下时的角度 `base`，从 `since` 起匀速转到 `now`；`since` 是
    /// nil（暂停）时停在 `base`。结果在 0..<360。
    public static func discAngle(base: Double, since: Date?, now: Date) -> Double {
        var angle = base
        if let since { angle += max(0, now.timeIntervalSince(since)) * degreesPerSecond }
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// 帧率：只在播放、面板看得见并且没开减弱动态效果时动，否则停在静帧（nil）。
    public static func framesPerSecond(playing: Bool, visible: Bool, reduceMotion: Bool) -> Double? {
        playing && visible && !reduceMotion ? fps : nil
    }

    // MARK: 水波纹

    /// 同时画几圈。
    public static let rippleCount = 3
    /// 一圈从唱片边扩散到最大要几秒。
    public static let ripplePeriod = 6.0
    /// 最大透明度，刚出现那圈也很淡。
    public static let rippleOpacity = 0.22
    /// 最大扩到唱片半径的几倍。
    public static let rippleReach = 0.4

    public struct Ripple: Equatable, Sendable {
        /// 相对唱片半径的大小，1 是唱片边。
        public var scale: Double
        public var opacity: Double
    }

    /// 时刻 `t`（秒）每一圈的大小和透明度；`t` 是 nil 时是静帧（暂停、减弱动态效果），
    /// 几圈均匀错开、不动。
    public static func ripples(t: Double?) -> [Ripple] {
        (0..<rippleCount).map { index in
            let offset = Double(index) / Double(rippleCount)
            // 静帧时几圈落在各自一段的中间，都看得见。
            var phase = (Double(index) + 0.5) / Double(rippleCount)
            if let t, t.isFinite {
                let raw = (t / ripplePeriod + offset).truncatingRemainder(dividingBy: 1)
                phase = raw < 0 ? raw + 1 : raw
            }
            // 刚出现和快消失时都淡：先淡入一小段，再随扩散淡出。
            let fadeIn = min(1, phase / 0.15)
            return Ripple(scale: 1 + rippleReach * phase,
                          opacity: rippleOpacity * fadeIn * (1 - phase))
        }
    }
}
