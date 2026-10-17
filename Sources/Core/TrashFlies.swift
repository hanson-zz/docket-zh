import Foundation

/// 废纸篓的苍蝇：垃圾越多、放得越久，苍蝇越多。
///
/// The idea is BananaBin's (bananabin.app): once the Trash passes a size
/// you choose, flies start circling it, more arrive every hour it is left,
/// and moving the pointer over it scares them off for a moment. Nothing here
/// is their code; this is the arithmetic, kept pure so it can be tested.
public enum TrashFlies {
    /// The size choices offered in settings, smallest first.
    public static let thresholds: [(label: String, value: String, bytes: Int64)] = [
        (tr("有东西就有"), "any", 1),
        ("10 MB", "10MB", 10_000_000),
        ("100 MB", "100MB", 100_000_000),
        ("500 MB", "500MB", 500_000_000),
        ("1 GB", "1GB", 1_000_000_000),
        ("5 GB", "5GB", 5_000_000_000),
    ]

    public static let defaultThreshold = "100MB"
    /// Enough to be unpleasant, few enough to stay a joke.
    public static let maxFlies = 12

    public static func thresholdBytes(_ value: String) -> Int64 {
        thresholds.first { $0.value == value }?.bytes
            ?? thresholds.first { $0.value == defaultThreshold }!.bytes
    }

    /// One fly at the threshold, one more each time the Trash doubles past
    /// it, and one more for every hour it has stayed over.
    public static func count(bytes: Int64, threshold: Int64, overSince: Date?, now: Date) -> Int {
        guard bytes > 0, bytes >= threshold else { return 0 }
        let ratio = Double(bytes) / Double(max(threshold, 1))
        let bySize = 1 + Int(log2(max(ratio, 1)).rounded(.down))
        let hours = overSince.map { max(0, Int(now.timeIntervalSince($0) / 3_600)) } ?? 0
        return min(maxFlies, bySize + hours)
    }

    /// When the Trash first went over the threshold, carried across checks:
    /// kept while it stays over, started now when it crosses, cleared when
    /// it drops back under.
    public static func overSince(previous: Date?, bytes: Int64, threshold: Int64, now: Date) -> Date? {
        guard bytes > 0, bytes >= threshold else { return nil }
        return previous ?? now
    }

    /// The same, for every threshold anything is showing flies for: the
    /// 废纸篓 widget and the shelf's own Trash icon can each pick a size, so
    /// each size keeps its own clock. A threshold in `watching` starts its
    /// clock when the Trash crosses it; one nobody watches any more keeps
    /// its date while the Trash stays over and is dropped once it falls
    /// under, so coming back to it later never resumes a stale clock.
    public static func overSince(previous: [Int64: Date], watching: Set<Int64>,
                                 bytes: Int64, now: Date) -> [Int64: Date] {
        var next: [Int64: Date] = [:]
        for threshold in watching.union(previous.keys) {
            let start = overSince(previous: previous[threshold], bytes: bytes, threshold: threshold, now: now)
            guard let start, previous[threshold] != nil || watching.contains(threshold) else { continue }
            next[threshold] = start
        }
        return next
    }

    /// How big a fly is drawn on a bin `side` points across: the widget's
    /// badge (34 to 40 points) is the reference, a smaller shelf icon gets
    /// smaller flies and a large one larger, within reason.
    public static func flyScale(side: Double) -> Double {
        guard side > 0 else { return 0 }
        return min(1.6, max(0.6, side / 40))
    }

    /// Where fly `index` is at time `t`, as an offset from the centre of the
    /// bin in units of its half-width, plus the direction it faces. Each fly
    /// has its own orbit, speed and wobble so the swarm never moves as one.
    public static func position(index: Int, t: Double) -> (x: Double, y: Double, heading: Double) {
        let seed = Double(index) * 1.618_033_988
        let speed = 1.1 + (seed.truncatingRemainder(dividingBy: 1)) * 1.4
        let direction: Double = index.isMultiple(of: 2) ? 1 : -1
        let phase = seed * 2.399_963
        let angle = direction * speed * t + phase
        let radius = 0.95 + 0.25 * sin(t * (0.7 + 0.13 * Double(index % 5)) + phase)
        // A quick zigzag on top of the orbit is what makes it read as a fly.
        let jitterX = 0.08 * sin(t * 13 + phase * 3)
        let jitterY = 0.08 * cos(t * 11 + phase * 2)
        let x = cos(angle) * radius * 1.15 + jitterX
        let y = sin(angle) * radius * 0.75 + jitterY - 0.1
        let heading = angle + direction * .pi / 2
        return (x, y, heading)
    }

    /// How far the flies have fled, 0 to 1, `elapsed` seconds after a scare:
    /// out fast, back slowly.
    public static func scare(elapsed: Double) -> Double {
        guard elapsed >= 0 else { return 0 }
        if elapsed < 0.6 { return elapsed / 0.6 }
        if elapsed < 3 { return 1 }
        return max(0, 1 - (elapsed - 3) / 2)
    }

    /// 1.2 GB, 340 MB, 12 KB, 空.
    public static func format(bytes: Int64) -> String {
        guard bytes > 0 else { return tr("空") }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        let text = value >= 100 || value.rounded() == value
            ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return "\(text) \(units[unit])"
    }
}
