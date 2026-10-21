import Foundation

/// 天气面板切换城市用到的纯逻辑：触控板两指左右滑、鼠标在顶部左右拖到多远多快
/// 才算换一个城市，到头不循环、只轻轻回弹，以及顶部只显示短地名（「石家庄」）。
///
/// 方向一律按手指算：手指往左（内容往左推）是下一个城市，往右是上一个，
/// 和翻页一样。触控板事件先按「自然滚动」换算成手指方向再交进来。
public enum WeatherCitySwipe {
    /// 拖过这么远（pt）就换城市。
    public static let distanceThreshold: Double = 56
    /// 快速一甩：速度到这个（pt/秒）且至少拖了 `flickMinimum` 也算。
    public static let velocityThreshold: Double = 420
    public static let flickMinimum: Double = 16
    /// 横向要比竖向多这么多倍才算左右滑，免得上下滚面板时误换城市。
    public static let dominance: Double = 1.5
    /// 先动这么多（pt）才定方向（横向还是竖向）。
    public static let axisLockDistance: Double = 8
    /// 小圆点的点击区域边长，至少 24pt。
    public static let dotHitSize: Double = 24
    /// 跟手位移上限（还能换的方向）。
    public static let followLimit: Double = 28
    /// 到头时的回弹上限：拉得再远也只动这么多。
    public static let edgeLimit: Double = 14

    /// 一次拖动（或一下两指滑动）结束时：横向位移 `dx`、竖向位移 `dy`、横向速度
    /// `velocity`（都按手指方向）。返回 +1 下一个、-1 上一个、nil 不换。
    public static func decision(dx: Double, dy: Double, velocity: Double = 0) -> Int? {
        guard dx.isFinite, dy.isFinite else { return nil }
        let distance = abs(dx)
        guard distance > 0, distance >= abs(dy) * dominance else { return nil }
        let fastEnough = velocity.isFinite && abs(velocity) >= velocityThreshold
            && distance >= flickMinimum && (velocity < 0) == (dx < 0)
        guard distance >= distanceThreshold || fastEnough else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// 从 `current` 往 `step` 走一步落到哪个城市；到头返回 nil（不循环）。
    public static func target(current: Int, step: Int, count: Int) -> Int? {
        guard count > 1, step != 0 else { return nil }
        let next = current + (step > 0 ? 1 : -1)
        guard next >= 0, next < count else { return nil }
        return next
    }

    /// 那个方向还能不能换：手指往左（dx < 0）看有没有下一个，往右看有没有上一个。
    public static func canMove(current: Int, count: Int, dx: Double) -> Bool {
        guard dx != 0 else { return false }
        return target(current: current, step: dx < 0 ? 1 : -1, count: count) != nil
    }

    /// 拖动中内容跟着手指偏多少：能换的方向跟一点（四分之一、不超过
    /// `followLimit`），到头了按橡皮筋算，越拉越紧，最多 `edgeLimit`。
    public static func offset(dx: Double, current: Int, count: Int) -> Double {
        guard dx.isFinite, dx != 0 else { return 0 }
        let sign: Double = dx < 0 ? -1 : 1
        if canMove(current: current, count: count, dx: dx) {
            return sign * min(abs(dx) * 0.25, followLimit)
        }
        return sign * rubberBand(abs(dx), limit: edgeLimit)
    }

    /// 经典橡皮筋：起步跟手约三分之一，越拉越慢，趋近 `limit` 但到不了。
    public static func rubberBand(_ distance: Double, limit: Double) -> Double {
        guard distance > 0, limit > 0 else { return 0 }
        let c = 0.33
        return (1 - 1 / (distance * c / limit + 1)) * limit
    }

    /// 触控板的一次两指滑动：一串滚动事件攒成一个判断。
    ///
    /// `feed` 每个事件调一次（惯性阶段的事件别喂），手指抬起时 `end` 给结论；
    /// 一次滑动最多换一个城市。先动 `axisLockDistance` 定方向，定成竖向的这次
    /// 就不管了，面板照常上下滚。
    public struct Tracker: Sendable, Equatable {
        public enum Axis: Sendable, Equatable { case undecided, horizontal, vertical }

        public private(set) var axis: Axis = .undecided
        public private(set) var dx: Double = 0
        public private(set) var dy: Double = 0
        /// 最近一小段的 (时间, 横向位移)，算抬手时的速度。
        private var samples: [Sample] = []

        private struct Sample: Sendable, Equatable {
            var time: Double
            var dx: Double
        }

        public init() {}

        public mutating func begin() { self = Tracker() }

        /// 横向位移，没定成横向时是 0。
        public var translation: Double { axis == .horizontal ? dx : 0 }

        /// 喂一个事件（手指方向的位移，pt）。返回这次滑动是不是横向的（是的话
        /// 调用方可以吞掉事件）。
        @discardableResult
        public mutating func feed(dx deltaX: Double, dy deltaY: Double, at time: Double) -> Bool {
            guard deltaX.isFinite, deltaY.isFinite else { return axis == .horizontal }
            dx += deltaX
            dy += deltaY
            samples.append(Sample(time: time, dx: deltaX))
            samples.removeAll { time - $0.time > 0.12 }
            if axis == .undecided, max(abs(dx), abs(dy)) >= WeatherCitySwipe.axisLockDistance {
                axis = abs(dx) >= abs(dy) * WeatherCitySwipe.dominance ? .horizontal : .vertical
            }
            return axis == .horizontal
        }

        /// 抬手时的横向速度（pt/秒），按最后约 0.12 秒算。
        public var velocity: Double {
            guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
            let moved = samples.dropFirst().reduce(0) { $0 + $1.dx }
            return moved / (last.time - first.time)
        }

        /// 手指抬起：+1、-1 或 nil；然后清零等下一次。
        public mutating func end() -> Int? {
            defer { self = Tracker() }
            guard axis == .horizontal else { return nil }
            return WeatherCitySwipe.decision(dx: dx, dy: dy, velocity: velocity)
        }
    }
}

/// 地名显示：顶部只放短名，完整地名放悬停提示。
///
/// 中文系统下定位反查回来的常是一整串「中国河北省石家庄市长安区」，没有逗号可切，
/// 顶部 19pt 一行放不下就被截成「中国河北省石…」。这里去掉国家和省、自治区，
/// 取地级市（没有就区县、州、盟）那一级，再去掉「市」「县」这类后缀；西文的
/// 「Mumbai, Maharashtra」取逗号前。认不出结构的原样返回。
public enum PlaceName {
    private static let countries = ["中华人民共和国", "中国", "中國"]
    /// 省一级的结尾。
    private static let provinceSuffixes = ["特别行政区", "特別行政區", "自治区", "自治區", "省"]
    /// 市、区县一级的结尾，长的在前。
    private static let levelSuffixes = ["自治州", "自治县", "自治縣", "自治旗", "地区", "地區",
                                        "林区", "市", "盟", "州", "县", "縣", "区", "區", "旗"]
    /// 直辖市：省一级就是城市本身。
    private static let municipalities = ["北京", "上海", "天津", "重庆", "重慶"]

    public static func short(_ full: String) -> String {
        var text = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        // 西文（或带逗号的）：第一段就是城市。
        if let comma = text.firstIndex(where: { $0 == "," || $0 == "，" }) {
            let head = text[..<comma].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { text = head }
        }
        guard text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return text }

        for country in countries where text.hasPrefix(country) && text.count > country.count {
            text = String(text.dropFirst(country.count))
            break
        }
        for city in municipalities where text.hasPrefix(city) {
            return city
        }
        // 香港特别行政区、澳门特别行政区：整串就是一个地方。
        for suffix in ["特别行政区", "特別行政區"] where text.hasSuffix(suffix) && text.count > suffix.count {
            let rest = String(text.dropLast(suffix.count))
            if !rest.contains("省"), !rest.contains("市") { return rest }
        }
        // 去掉省一级（「河北省」「新疆维吾尔自治区」）。
        if let province = firstLevel(in: text, suffixes: provinceSuffixes), province.end < text.endIndex {
            text = String(text[province.end...])
        }
        // 下一段就是要的：地级市，或直接是区县。
        if let level = firstLevel(in: text, suffixes: levelSuffixes) {
            return trimmed(String(text[..<level.end]), suffix: level.suffix)
        }
        return text
    }

    /// 完整地名和短名一样时不用提示。
    public static func tooltip(_ full: String) -> String? {
        let trimmedFull = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFull.isEmpty, short(trimmedFull) != trimmedFull else { return nil }
        return trimmedFull
    }

    /// 第一个以这些后缀之一结尾的片段（至少 2 个字，免得「市」开头之类误切）。
    private static func firstLevel(in text: String, suffixes: [String])
        -> (end: String.Index, suffix: String)? {
        var best: (end: String.Index, suffix: String)?
        for suffix in suffixes {
            var searchStart = text.startIndex
            while let range = text.range(of: suffix, range: searchStart..<text.endIndex) {
                if text.distance(from: text.startIndex, to: range.lowerBound) >= 1 {
                    if best == nil || range.upperBound < best!.end
                        || (range.upperBound == best!.end && suffix.count > best!.suffix.count) {
                        best = (range.upperBound, suffix)
                    }
                    break
                }
                searchStart = range.upperBound
            }
        }
        return best
    }

    /// 「石家庄市」→「石家庄」；去掉后只剩一个字的（「沙市」「通州」那样短的）保留后缀。
    private static func trimmed(_ name: String, suffix: String) -> String {
        guard ["市", "县", "縣", "区", "區", "地区", "地區"].contains(suffix) else { return name }
        let core = String(name.dropLast(suffix.count))
        return core.count >= 2 ? core : name
    }
}
