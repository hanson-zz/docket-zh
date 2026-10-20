import Foundation

/// 天气面板里“拖动逐小时预报”的计算部分。
///
/// 手指在一排小时上拖，横向位置换成第几个小时（可以落在两个小时之间），
/// 温度在相邻两小时之间线性过渡，天空的明暗和暖色按那个时刻离日出日落多远来算。
/// 纯函数，测试不需要界面。
public enum HourScrub {
    /// 横向位置换成小数下标：每一列的中心正好是整数，两头夹住。
    /// `count` 列平均分 `width`，第 i 列的中心在 (i + 0.5) * width / count。
    public static func position(x: Double, width: Double, count: Int) -> Double {
        guard count > 1, width > 0 else { return 0 }
        let column = width / Double(count)
        let raw = x / column - 0.5
        return min(max(raw, 0), Double(count - 1))
    }

    /// 最近的那一列。
    public static func index(position: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int(position.rounded()), 0), count - 1)
    }

    /// 在相邻两列之间线性插值。空数组返回 nil。
    public static func interpolate(_ values: [Double], at position: Double) -> Double? {
        guard let first = values.first else { return nil }
        guard values.count > 1 else { return first }
        let clamped = min(max(position, 0), Double(values.count - 1))
        let low = Int(clamped.rounded(.down))
        let high = min(low + 1, values.count - 1)
        let fraction = clamped - Double(low)
        return values[low] + (values[high] - values[low]) * fraction
    }

    /// 逐小时那一排打开时停在哪一列：第一个还没过完的小时（开始时刻加一小时
    /// 晚于现在）。预报是上次刷新时取的，过了一阵前几列可能已经过去，
    /// 就跳过它们；全都过去了停在最后一列，没有数据时是 0。`starts` 是每列的
    /// 开始时刻（秒），按时间先后排。
    public static func nowIndex(starts: [Double], now: Double, hour: Double = 3600) -> Int {
        guard !starts.isEmpty else { return 0 }
        return starts.firstIndex { $0 + hour > now } ?? starts.count - 1
    }

    /// 暮光的宽度：日落后到全黑、全黑到日出前各这么久。
    public static let twilight: TimeInterval = 50 * 60

    /// 夜色深浅，0 是白天，1 是夜里，日出日落前后的暮光里平滑过渡。
    public static func night(at date: Date, rise: Date, set: Date) -> Double {
        if date >= rise.addingTimeInterval(twilight / 2), date <= set.addingTimeInterval(-twilight / 2) {
            return 0
        }
        // 离最近的日出或日落有多远（带符号：在白天一侧为负）。
        let fromRise = rise.timeIntervalSince(date)   // 日出前为正
        let fromSet = date.timeIntervalSince(set)     // 日落后为正
        let outside = abs(fromRise) < abs(fromSet) ? fromRise : fromSet
        // outside = -twilight/2 时是白天，+twilight/2 时是夜里。
        let linear = (outside + twilight / 2) / twilight
        let clamped = min(max(linear, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// 暖色（朝霞晚霞）的强度，0...1，正好在日出日落那一刻最亮，前后一小时内退掉。
    public static func glow(at date: Date, rise: Date, set: Date) -> Double {
        let nearest = min(abs(date.timeIntervalSince(rise)), abs(date.timeIntervalSince(set)))
        let window: TimeInterval = 60 * 60
        guard nearest < window else { return 0 }
        let k = 1 - nearest / window
        return k * k
    }
}
