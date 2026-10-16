import Foundation

/// 剪贴板面板的“货架”排法：拷贝过的东西像小卡片一样立在一层层搁板上，
/// 每层放几张，卡片微微歪一点，像随手放上去的。
///
/// 纯函数：分层和每张卡片歪多少，测试可以直接算。
public enum ClipboardShelf {

    /// 面板 320 宽，一层放三张，卡片还能看清两行字。
    public static let perRow = 3

    /// 把 `count` 张卡片按每层 `perRow` 张分层，返回每层的下标范围。
    public static func rows(count: Int, perRow: Int = ClipboardShelf.perRow) -> [Range<Int>] {
        guard count > 0, perRow > 0 else { return [] }
        return stride(from: 0, to: count, by: perRow).map { $0..<min($0 + perRow, count) }
    }

    /// 第几张卡片歪多少度。按位置取一个固定的小角度，同一张卡片每次画都一样，
    /// 相邻两张往不同方向歪。
    public static func tilt(index: Int) -> Double {
        let angles: [Double] = [-2.5, 1.8, -1.2, 2.2, -1.8, 1.2]
        return angles[((index % angles.count) + angles.count) % angles.count]
    }

    /// 卡片上一行字最多留多少：换行压成空格，太长的截断加省略号。
    public static func excerpt(_ text: String, limit: Int = 40) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit, limit > 0 else { return flat }
        return String(flat.prefix(limit)) + "…"
    }
}
