import Foundation

/// 正在播放面板的样式：标准（11-24 起是精简面板）或黑胶模式。存在卡片配置里，
/// 入口在面板底部「外观」里。没选过的卡片默认黑胶（见 `ProLicenseGate.musicPanelStyle`）。
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

    /// 选一个样式，明写进配置（没写过的默认黑胶，选精简得记住）。
    public static func choosing(_ style: MusicPanelStyle, in config: WidgetConfig) -> WidgetConfig {
        var copy = config
        copy.set(key, .string(style.rawValue))
        return copy
    }

    public var title: String {
        switch self {
        case .standard: tr("精简")
        case .vinyl: tr("黑胶模式")
        }
    }

    /// 11-24 起黑胶模式免费（之前是 Pro），两种样式都不要解锁。
    public var isPro: Bool { false }
}

/// 黑胶模式的纯数学：唱台怎么摆、唱片转多快、唱臂按进度落在哪、水波纹怎么扩散。
/// 界面只拿这里算好的数画，测试可以拨到任意进度和时刻。
///
/// 坐标以唱台左上角为原点，y 向下；角度是唱臂相对竖直向下顺时针转过的度数
/// （和 SwiftUI `rotationEffect` 同向），0 度是唱臂收在支架上。
public enum MusicVinyl {
    // MARK: 唱台布局

    /// 设计稿宽度（原 340 面板的内容区）和唱台高度；11-24 面板收到 320，唱台按 288 内容区等比缩到约 0.94。窄于设计宽度时整体等比缩小。
    /// V2 去掉左边的大封面卡，唱片放大居左，唱臂在右上，唱台约 250 高。
    public static let designWidth: Double = 308
    /// 黑胶模式的面板宽（精简面板 300）。11-24 改横排：唱台在左，控制在右；
    /// 同日按效果图放到 420，唱片是主角，和竖排的精简面板拉开差别。
    public static let panelWidth: Double = 420
    /// 横排面板里左边唱台的宽（唱台按设计宽等比缩小，约 0.64 倍，唱片直径约 140，唱台约 160 高）。
    public static let sideStageWidth: Double = 196
    public static let designHeight: Double = 250

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
        /// 唱片中心和半径。
        public var center: Point
        public var radius: Double
        /// 唱盘金属边比唱片多出来的宽度，和唱盘底下露出来的厚度。
        public var rim: Double
        public var thickness: Double
        /// 唱臂转轴和从转轴到唱针的长度。
        public var pivot: Point
        public var armLength: Double
        /// 转轴底座半径。
        public var pivotBase: Double
        /// 听歌小熊猫贴纸的位置（左下角，压在唱盘边上，不挡唱针走的音轨）。
        public var sticker: Rect

        /// 最外圈和最内圈纹路的半径：唱针从外圈走到内圈。
        public var outerGroove: Double { radius * MusicVinyl.outerGrooveRatio }
        public var innerGroove: Double { radius * MusicVinyl.innerGrooveRatio }
        /// 中心标签半径。
        public var label: Double { radius * MusicVinyl.labelRatio }
        /// 唱盘（含金属边）半径。
        public var platter: Double { radius + rim }
        /// 唱盘连厚度在内的最下沿。
        public var platterBottom: Double { center.y + platter + thickness }
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
            center: Point(x: 136 * s, y: 122 * s),
            radius: 110 * s,
            rim: 8 * s,
            thickness: 6 * s,
            pivot: Point(x: 280 * s, y: 38 * s),
            armLength: 140 * s,
            pivotBase: 17 * s,
            sticker: Rect(x: 0, y: 176 * s, width: 74 * s, height: 66 * s))
    }

    // MARK: 唱臂

    /// 唱臂在支架上（暂停、没在放）时的角度。
    public static let restAngle = 0.0
    /// 求落针角度时搜索的上限：再往里唱针就越过中心了。
    static let searchLimit = 50.0
    /// 暂停时唱针微微抬起的高度（0 落在唱片上，1 完全抬起）。
    public static let pausedLift = 0.4

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
    public static let rippleOpacity = 0.34
    /// 最大扩到唱片半径的几倍（V2 唱片放大后两边只剩这么多水面）。
    public static let rippleReach = 0.2
    /// 水面在唱片中心下面多远（按唱片半径），和水波纹椭圆的扁度（竖半径 / 横半径）。
    public static let waterDrop = 0.72
    public static let waterFlatness = 0.3

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

    /// 同上，按唱片转速（0 停、1 全速）调：转得越快波纹越明显，停下时只剩很淡的静水纹。
    /// 只按时间生成，不读音频。
    public static func ripples(t: Double?, energy: Double) -> [Ripple] {
        let e = energy.isFinite ? min(1, max(0, energy)) : 0
        return ripples(t: t).map { Ripple(scale: $0.scale, opacity: $0.opacity * (0.35 + 0.65 * e)) }
    }
}

// MARK: - 唱机的动作

/// 黑胶唱机的动作状态机：唱臂摆动、唱针抬落、唱片加减速。只放时间和角度的数学，
/// 界面每帧拿 `frame(at:groove:)` 画，测试可以拨到任意时刻。
///
/// - 开始播放：唱臂从支架缓缓移到外圈 → 轻轻落针 → 唱片起转。
/// - 暂停：唱片逐渐减速停下，唱针微微抬起，唱臂停在原处不归位。
/// - 继续：重新落针，唱片从暂停时的角度接着转。
/// - 放完或停止：抬针，唱臂缓缓回到支架，唱片减速停下。
/// - 播放中切歌：唱针抬一下、移回新歌的外圈再落下，唱片不停。
///
/// 唱臂角度和 `MusicVinyl.armAngle` 同一个坐标（0 度在支架上）；`lift` 0 是唱针落在
/// 唱片上，1 是完全抬起。
public struct VinylMotion: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// 唱臂在支架上，唱片不转。
        case rest
        case playing
        case paused
    }

    /// 唱臂移动多久、抬针和落针各多久、唱片加速和减速多久（秒）。
    public static let armMove = 1.2
    public static let armReturn = 1.4
    public static let trackMove = 0.8
    public static let raise = 0.25
    public static let drop = 0.35
    public static let spinUp = 0.8
    public static let spinDown = 1.2

    /// 画一帧要的数。
    public struct Frame: Equatable, Sendable {
        public var armAngle: Double
        public var lift: Double
        /// 唱片角度，0..<360。
        public var discAngle: Double
        /// 转速，相对全速 0...1（水波纹跟着它）。
        public var discSpeed: Double
    }

    /// 唱臂的一次动作：先抬到 `peak`，再从 `from` 摆到目标，最后落到 `end`。
    struct ArmMove: Equatable, Sendable {
        var start: Date
        var liftFrom: Double
        var peak: Double
        var end: Double
        var from: Double
        /// nil：跟着进度的音轨角度走；有值：摆到这个固定角度（支架、暂停的位置）。
        var to: Double?
        var duration: Double

        var raiseTime: Double { abs(peak - liftFrom) > 0.001 ? VinylMotion.raise : 0 }
        var finish: Date { start.addingTimeInterval(raiseTime + duration + (abs(end - peak) > 0.001 ? VinylMotion.drop : 0)) }

        func angle(at now: Date, groove: Double) -> Double {
            let target = to ?? groove
            let t = now.timeIntervalSince(start) - raiseTime
            guard duration > 0 else { return t < 0 ? from : target }
            return from + (target - from) * VinylMotion.ease(t / duration)
        }

        func lift(at now: Date) -> Double {
            let t = now.timeIntervalSince(start)
            if t < raiseTime { return liftFrom + (peak - liftFrom) * VinylMotion.ease(t / raiseTime) }
            let landing = t - raiseTime - duration
            if landing <= 0 { return peak }
            return peak + (end - peak) * VinylMotion.ease(landing / VinylMotion.drop)
        }

        /// 落针完成（唱片该起转）的时刻。
        var landed: Date { finish }
    }

    /// 唱片的一段转动：从 `start` 起，转速从 `speed` 线性变到 `target`，用 `ramp` 秒；
    /// `start` 之前停在 `angle`、保持 `speed`。
    struct Spin: Equatable, Sendable {
        var start: Date
        var angle: Double
        var speed: Double
        var target: Double
        var ramp: Double

        func speed(at now: Date) -> Double {
            let t = now.timeIntervalSince(start)
            guard t > 0 else { return speed }
            guard ramp > 0, t < ramp else { return target }
            return speed + (target - speed) * t / ramp
        }

        /// 转过的角度（度，没取余），转速单位是全速的倍数。
        func angle(at now: Date) -> Double {
            let t = now.timeIntervalSince(start)
            guard t > 0 else { return angle }
            let full = MusicVinyl.degreesPerSecond
            if ramp > 0, t < ramp {
                return angle + full * (speed * t + (target - speed) * t * t / (2 * ramp))
            }
            let during = ramp > 0 ? full * (speed * ramp + (target - speed) * ramp / 2) : 0
            return angle + during + full * target * (t - max(0, ramp))
        }
    }

    public private(set) var mode: Mode
    private(set) var arm: ArmMove
    private(set) var spin: Spin
    /// 正在放的歌（换歌时唱针回外圈）。
    public private(set) var track: String?

    /// 打开面板时的样子：已经在放就直接是落针、全速转的样子，不重放一遍落针。
    public static func settled(playing: Bool, track: String?, groove: Double, now: Date) -> VinylMotion {
        if playing {
            return VinylMotion(mode: .playing,
                               arm: ArmMove(start: now, liftFrom: 0, peak: 0, end: 0, from: groove, to: nil, duration: 0),
                               spin: Spin(start: now, angle: 0, speed: 1, target: 1, ramp: 0), track: track)
        }
        return VinylMotion(mode: .rest,
                           arm: ArmMove(start: now, liftFrom: 1, peak: 1, end: 1, from: MusicVinyl.restAngle,
                                        to: MusicVinyl.restAngle, duration: 0),
                           spin: Spin(start: now, angle: 0, speed: 0, target: 0, ramp: 0), track: track)
    }

    /// 这一刻的唱臂、唱针和唱片。`groove` 是按进度算的落针角度（`MusicVinyl.armAngle`）。
    public func frame(at now: Date, groove: Double) -> Frame {
        let angle = spin.angle(at: now).truncatingRemainder(dividingBy: 360)
        return Frame(armAngle: arm.angle(at: now, groove: groove), lift: arm.lift(at: now),
                     discAngle: angle < 0 ? angle + 360 : angle, discSpeed: min(1, max(0, spin.speed(at: now))))
    }

    /// 减弱动态效果时画的静帧：动作直接到终点，唱片停在现在的角度。
    public func stillFrame(at now: Date, groove: Double) -> Frame {
        let end = arm.finish.addingTimeInterval(1)
        var still = self.frame(at: max(now, end), groove: groove)
        still.discAngle = self.frame(at: now, groove: groove).discAngle
        still.discSpeed = 0
        return still
    }

    /// 这一刻还要不要逐帧刷新：唱片在转、在加减速，或唱臂还在动。都停了就是静帧。
    public func isAnimating(at now: Date) -> Bool {
        if now < arm.finish { return true }
        if spin.speed(at: now) > 0.0001 { return true }
        return now < spin.start.addingTimeInterval(spin.ramp) && spin.target != spin.speed
    }

    // MARK: 事件

    /// 在放时进度一下跳了这么多度（拖进度条、单曲循环回到开头）：唱针抬一下移过去，
    /// 不瞬移。
    public static let seekJump = 3.0

    /// 播放状态、歌或进度变了。`ended` 是这首放完了（停在最后）或播放器停止。
    /// `previousGroove` 是变之前的落针角度（这时的 `groove` 已经是新歌或新进度的），
    /// 唱臂从屏幕上原来的位置出发；不给时按 `groove`。
    public mutating func update(playing: Bool, ended: Bool, track: String?, groove: Double,
                                previousGroove: Double? = nil, now: Date) {
        let current = frame(at: now, groove: previousGroove ?? groove)
        let changedTrack = track != self.track
        self.track = track
        switch (mode, playing) {
        case (.rest, true), (.paused, true):
            let fromRest = mode == .rest
            mode = .playing
            arm = ArmMove(start: now, liftFrom: current.lift, peak: current.lift, end: 0, from: current.armAngle,
                          to: nil, duration: fromRest ? Self.armMove : (changedTrack ? Self.trackMove : 0.3))
            // 唱片停着时等落针后再起转；还在减速（刚暂停又继续）就从现在的转速直接加回去。
            let still = current.discSpeed < 0.01
            spin = Spin(start: still ? arm.landed : now, angle: Self.wrap(spin.angle(at: now)),
                        speed: still ? 0 : current.discSpeed, target: 1, ramp: Self.spinUp)
        case (.playing, true):
            if changedTrack {
                // 切歌：唱针抬一下回到新歌外圈再落，唱片接着转。
                arm = ArmMove(start: now, liftFrom: current.lift, peak: 0.6, end: 0, from: current.armAngle,
                              to: nil, duration: Self.trackMove)
            } else if abs(groove - current.armAngle) > Self.seekJump, now >= arm.finish {
                // 同一首里进度跳了：抬一下移到新位置再落。
                arm = ArmMove(start: now, liftFrom: current.lift, peak: 0.45, end: 0, from: current.armAngle,
                              to: nil, duration: 0.5)
            }
        case (.playing, false):
            if ended {
                stop(current: current, now: now)
            } else {
                mode = .paused
                arm = ArmMove(start: now, liftFrom: current.lift, peak: MusicVinyl.pausedLift,
                              end: MusicVinyl.pausedLift, from: current.armAngle, to: current.armAngle, duration: 0)
                spin = Spin(start: now, angle: Self.wrap(spin.angle(at: now)), speed: current.discSpeed,
                            target: 0, ramp: Self.spinDown)
            }
        case (.paused, false):
            if ended {
                stop(current: current, now: now)
            } else if changedTrack {
                // 暂停时切歌：唱针仍微抬着，唱臂移到新歌的外圈等着。
                arm = ArmMove(start: now, liftFrom: current.lift, peak: MusicVinyl.pausedLift,
                              end: MusicVinyl.pausedLift, from: current.armAngle, to: groove,
                              duration: Self.trackMove)
            }
        case (.rest, false):
            break
        }
    }

    private mutating func stop(current: Frame, now: Date) {
        mode = .rest
        arm = ArmMove(start: now, liftFrom: current.lift, peak: 1, end: 1, from: current.armAngle,
                      to: MusicVinyl.restAngle, duration: Self.armReturn)
        spin = Spin(start: now, angle: Self.wrap(spin.angle(at: now)), speed: current.discSpeed,
                    target: 0, ramp: Self.spinDown)
    }

    static func wrap(_ angle: Double) -> Double {
        let a = angle.truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// 两头慢、中间快，0...1。
    static func ease(_ x: Double) -> Double {
        guard x.isFinite else { return 1 }
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    /// 这首算不算放完：不在放，并且进度到了最后一秒以内。读不到时长时不算。
    public static func ended(playing: Bool, elapsed: Double, duration: Double) -> Bool {
        guard !playing, duration.isFinite, duration > 0, elapsed.isFinite else { return false }
        return elapsed >= duration - 1
    }
}
