import Foundation

/// The time said in Chinese words, for the clock's 文字 style:
/// "下午" over "四点四十三分".
public enum ChineseTimeText {
    /// The period of the day and the spoken time, from a 24-hour hour.
    public static func say(hour: Int, minute: Int) -> (period: String, time: String) {
        let h = ((hour % 24) + 24) % 24
        let m = min(max(minute, 0), 59)
        let period: String = switch h {
        case 0..<5: "凌晨"
        case 5..<8: "早上"
        case 8..<11: "上午"
        case 11..<13: "中午"
        case 13..<18: "下午"
        case 18..<23: "晚上"
        default: "深夜"
        }
        let twelve = h % 12 == 0 ? 12 : h % 12
        // 两点, never 二点, as it is said.
        let hourWord = twelve == 2 ? "两" : number(twelve)
        let time: String = switch m {
        case 0: "\(hourWord)点整"
        case 30: "\(hourWord)点半"
        case 1..<10: "\(hourWord)点零\(number(m))分"
        default: "\(hourWord)点\(number(m))分"
        }
        return (period, time)
    }

    /// 0...99 in Chinese numerals: 十, 十五, 二十, 四十三.
    public static func number(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard n >= 10 else { return digits[max(0, n)] }
        let tens = n / 10, ones = n % 10
        return (tens == 1 ? "" : digits[tens]) + "十" + (ones == 0 ? "" : digits[ones])
    }
}
