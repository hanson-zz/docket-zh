import Foundation

/// 待办和废纸篓的三段小动画用到的纯数学：全部完成时小熊猫跳出来庆祝、
/// 横滑删除一行、清空废纸篓时纸团被吞进去。
///
/// Kept out of the views so the curves can be tested without drawing, and so
/// the tile and the panel share one timing. Every function takes the seconds
/// since the moment started and returns plain numbers in unit space; the
/// views scale them to their own size.

/// 全部完成：小熊猫弹出、跳两下，周围撒一圈小星点，然后淡出。
public enum CheerMotion {
    /// The whole moment, start to fade-out.
    public static let duration: Double = 2.2
    /// How many sparks are thrown out around the panda.
    public static let sparks = 14

    private static let pop: Double = 0.45

    /// Grows from nothing past full size and settles back (an ease-out-back).
    public static func pandaScale(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let p = min(1, t / pop) - 1
        let overshoot = 1.70158
        return 1 + (overshoot + 1) * p * p * p + overshoot * p * p
    }

    /// Two small hops after the pop, each lower than the last. 0 is resting,
    /// 1 is the top of the first hop.
    public static func hop(_ t: Double) -> Double {
        let u = t - pop
        guard u > 0 else { return 0 }
        let decay = max(0, 1 - u / 1.0)
        return abs(sin(u * .pi / 0.35)) * decay
    }

    /// Fades in quickly, holds, and fades out over the last 0.4 seconds.
    public static func opacity(_ t: Double) -> Double {
        guard t > 0, t < duration else { return 0 }
        let fadeIn = min(1, t / 0.12)
        let fadeOut = min(1, (duration - t) / 0.4)
        return min(fadeIn, fadeOut)
    }

    /// One spark: where it is in the unit circle around the panda, how
    /// visible and how big (1 is full size). Sparks fly out fast, slow down
    /// and drift a little downward as they fade.
    public static func spark(index: Int, t: Double) -> (x: Double, y: Double, opacity: Double, size: Double) {
        let start = 0.12
        let life = 1.1
        let p = (t - start) / life
        guard p > 0, p < 1 else { return (0, 0, 0, 0) }
        let count = Double(sparks)
        let angle = Double(index) / count * 2 * .pi + (index.isMultiple(of: 2) ? 0 : 0.22)
        let reach = 0.62 + 0.38 * Double((index * 7) % 5) / 4
        let travel = 1 - (1 - p) * (1 - p)
        let x = cos(angle) * reach * travel
        let y = sin(angle) * reach * travel + 0.3 * p * p
        return (x, y, 1 - p, 1 - 0.5 * p)
    }
}

/// 横滑删除：往左拖一行，拖过一半左右或甩得够快就删，否则弹回去。
public enum SwipeDelete {
    /// How far left, as a share of the row's width, counts as "delete".
    public static let threshold = 0.45

    /// Left follows the pointer; right is a short rubber band, so the row
    /// says "not this way" without going anywhere.
    public static func offset(for translation: Double) -> Double {
        guard translation > 0 else { return translation }
        return 18 * translation / (translation + 30)
    }

    /// Past the threshold, or flicked hard to the left after a real start.
    public static func shouldDelete(offset: Double, predicted: Double, width: Double) -> Bool {
        guard width > 0, offset < 0 else { return false }
        if offset <= -width * threshold { return true }
        return predicted <= -width * 0.9 && offset <= -width * 0.15
    }

    /// 0 at rest, 1 once letting go would delete. Drives the red behind the row.
    public static func progress(offset: Double, width: Double) -> Double {
        guard width > 0, offset < 0 else { return 0 }
        return min(1, -offset / (width * threshold))
    }
}

/// 清空废纸篓：几张纸从上面依次落下，转着、缩小着掉进桶口，桶每吞一张就鼓一下。
public enum SwallowMotion {
    public static let sheets = 4
    private static let stagger = 0.14
    private static let fall = 0.6
    private static let gulp = 0.3

    /// The whole moment, last sheet's gulp included.
    public static var duration: Double { stagger * Double(sheets - 1) + fall + gulp + 0.1 }

    /// One sheet: x and y relative to the bin's mouth (y = -1 is the top of
    /// the drop, 0 is the mouth), its turn in radians, scale and opacity.
    public static func sheet(index: Int, t: Double) -> (x: Double, y: Double, rotation: Double, scale: Double, opacity: Double) {
        let p = (t - stagger * Double(index)) / fall
        guard p > 0, p < 1 else { return (0, 0, 0, 0, 0) }
        let lanes: [Double] = [-0.55, 0.45, -0.2, 0.65]
        let lane = lanes[index % lanes.count]
        let eased = p * p
        let spin = (index.isMultiple(of: 2) ? 1.0 : -1.0) * (0.35 + 2.2 * eased)
        let scale = 1 - 0.75 * eased
        let opacity = min(1, p / 0.12) * (p > 0.85 ? (1 - p) / 0.15 : 1)
        return (lane * (1 - eased), -1 + eased, spin, scale, opacity)
    }

    /// How much the bin bulges, 0 at rest. Each sheet that lands adds a short
    /// bump; the bumps can overlap but never stack past a small cap.
    public static func gulpAmount(_ t: Double) -> Double {
        var total = 0.0
        for index in 0..<sheets {
            let u = t - (stagger * Double(index) + fall)
            guard u > 0, u < gulp else { continue }
            total += sin(u / gulp * .pi) * 0.09
        }
        return min(0.12, total)
    }

    /// Wider and shorter while it swallows, anchored at the bottom.
    public static func binScale(_ t: Double) -> (x: Double, y: Double) {
        let g = gulpAmount(t)
        return (1 + 0.7 * g, 1 - g)
    }
}

extension QuickTodo {
    /// True when checking `id` closes the last open task in a list that has
    /// any. The celebration is decided from the list before the change, so it
    /// does not depend on when the write lands.
    public static func finishesAll(toggling id: String, in items: [TodoItem]) -> Bool {
        let open = items.filter { !$0.done }
        return open.count == 1 && open[0].id == id
    }

    /// Puts back a task that was just deleted, at the place it had, unless it
    /// is already there (an undo pressed twice).
    public static func restoring(_ item: TodoItem, at index: Int, in items: [TodoItem]) -> [TodoItem] {
        guard !items.contains(where: { $0.id == item.id }) else { return ordered(items) }
        var list = ordered(items)
        list.insert(item, at: max(0, min(index, list.count)))
        return ordered(list)
    }
}
