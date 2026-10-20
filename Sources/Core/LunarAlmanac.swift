import Foundation

/// 农历面板顶上那块「宜 / 忌」：按建除十二值日给每天四件宜、四件忌，全在本机算。
///
/// 日干支从儒略日数推（2026-10-20 是丁卯日）；月建按节气换月，立春起寅月、惊蛰
/// 卯月……小寒丑月，节当天就算新的月（所以节那天和前一天值日相同，就是通书说的
/// 「重建」）。值日 = 日支减月支：建、除、满、平、定、执、破、危、成、收、开、闭。
///
/// 每个值日对应的宜忌取通书里最常见的说法，各留四件，是简化版：不叠加神煞，
/// 所以和完整黄历偶有出入，面板上写明「按建除十二值日，仅供参考」。
public enum LunarAlmanac {
    static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)

    /// 建除十二值日，按顺序。
    public static let officers = ["建", "除", "满", "平", "定", "执", "破", "危", "成", "收", "开", "闭"]

    /// 每个值日的宜、忌，各四件，顺序同 `officers`。
    static let table: [(good: [String], bad: [String])] = [
        (["出行", "上任", "会友", "求财"], ["动土", "开仓", "嫁娶", "安葬"]),   // 建
        (["祭祀", "祈福", "扫舍", "求医"], ["嫁娶", "出行", "开市", "上任"]),   // 除
        (["祈福", "开市", "交易", "纳财"], ["栽种", "安葬", "上任", "求医"]),   // 满
        (["修造", "平治道涂", "涂泥", "会友"], ["开渠", "栽种", "嫁娶", "出行"]), // 平
        (["嫁娶", "交易", "纳畜", "入学"], ["诉讼", "出行", "求医", "栽种"]),   // 定
        (["祭祀", "捕捉", "纳采", "立券"], ["搬家", "开市", "出行", "开仓"]),   // 执
        (["求医", "破屋", "坏垣", "治病"], ["嫁娶", "开市", "出行", "动土"]),   // 破
        (["祭祀", "祈福", "安床", "纳财"], ["登高", "行船", "出行", "嫁娶"]),   // 危
        (["嫁娶", "开市", "入学", "搬家"], ["诉讼", "登高", "争执", "安葬"]),   // 成
        (["纳财", "收割", "捕捉", "入宅"], ["出行", "安葬", "开市", "求医"]),   // 收
        (["开市", "嫁娶", "入学", "出行"], ["安葬", "动土", "伐木", "诉讼"]),   // 开
        (["筑堤", "补垣", "塞穴", "收藏"], ["开市", "出行", "求医", "上任"]),   // 闭
    ]

    /// 1970-01-01 在中国的那天（儒略日 2440588）是辛巳日，六十甲子第 17 位（甲子为 0）。
    static let epochCycleIndex = 17

    /// 当天在六十甲子里的位置，甲子为 0。
    public static func dayCycleIndex(_ date: Date) -> Int {
        let calendar = ChineseCalendar.gregorian
        guard let epoch = calendar.date(from: DateComponents(year: 1970, month: 1, day: 1)) else { return 0 }
        let days = ChineseCalendar.days(from: epoch, to: date)
        return ((days + epochCycleIndex) % 60 + 60) % 60
    }

    /// 丁卯
    public static func dayGanzhi(_ date: Date) -> String {
        let index = dayCycleIndex(date)
        return stems[index % 10] + branches[index % 12]
    }

    /// 月建的地支，子为 0。节当天就算新的月。
    public static func monthBranch(_ date: Date) -> Int {
        let calendar = ChineseCalendar.gregorian
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        // 节是 termNames 里的偶数位：小寒、立春、惊蛰……大雪。
        let jie = ChineseCalendar.solarTerms(year: year).enumerated().filter { $0.offset % 2 == 0 }
        guard let last = jie.last(where: { $0.element.day <= day }) else {
            // 小寒之前还在上一年大雪起的子月。
            return 0
        }
        return (last.offset / 2 + 1) % 12
    }

    /// 建除十二值日的序号，建为 0。
    public static func officerIndex(_ date: Date) -> Int {
        let dayBranch = dayCycleIndex(date) % 12
        return ((dayBranch - monthBranch(date)) % 12 + 12) % 12
    }

    /// 执日
    public static func officerName(_ date: Date) -> String { officers[officerIndex(date)] + "日" }

    public static func good(_ date: Date) -> [String] { table[officerIndex(date)].good }
    public static func bad(_ date: Date) -> [String] { table[officerIndex(date)].bad }

    /// 表里出现过的所有词，英文表要逐个有译文。
    public static var allWords: [String] {
        Array(Set(table.flatMap { $0.good + $0.bad })).sorted()
    }
}
