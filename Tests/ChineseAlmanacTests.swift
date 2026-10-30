import XCTest
@testable import Docket

/// 每日一签页的真实黄历（Core 的 `ChineseAlmanac`，移植自 6tail lunar，MIT）。
///
/// 下面每一天的农历、干支、生肖、节气、建除、值日星宿、宜忌前几项，都是对着公开万年历网页抄的：
/// 万年历网 wnl365.com/rili/年/月-日.html、时间查询 timecha.com/rili/年/月-日.html，
/// 2025-02-02 那天这两家的宜忌和别家不同（立春前一日），按黄历网 huangli.com/huangli/2025/02_02.html。
/// 覆盖闰月（2020 闰四月、2023 闰二月、2025 闰六月）、春节前后（2025 除夕和初一、2026 初一）、
/// 节气交界（2025 立春前一天和当天、2026 小寒、冬至、寒露），以及今天。
final class ChineseAlmanacTests: XCTestCase {

    private struct Expected {
        var day: String
        var lunar: String
        var year: String
        var month: String
        var date: String
        var zodiac: String
        var term: String?
        var officer: String
        var mansion: String
        var good: [String]
        var bad: [String]
    }

    private let cases: [Expected] = [
        Expected(day: "2026-10-30", lunar: "九月廿一", year: "丙午", month: "戊戌", date: "丁丑", zodiac: "马",
                 term: nil, officer: "平", mansion: "娄", good: ["祭祀", "平治道涂", "馀事勿取"], bad: ["嫁娶", "开市"]),
        Expected(day: "2026-10-08", lunar: "八月廿八", year: "丙午", month: "戊戌", date: "乙卯", zodiac: "马",
                 term: "寒露", officer: "执", mansion: "井", good: ["祭祀", "入殓", "移柩"], bad: ["无"]),
        Expected(day: "2026-02-17", lunar: "正月初一", year: "丙午", month: "庚寅", date: "壬戌", zodiac: "马",
                 term: nil, officer: "成", mansion: "室", good: ["祭祀", "塞穴", "结网"], bad: ["嫁娶", "入宅"]),
        Expected(day: "2026-01-05", lunar: "冬月十七", year: "乙巳", month: "己丑", date: "己卯", zodiac: "蛇",
                 term: "小寒", officer: "满", mansion: "张", good: ["开市", "交易", "立券"], bad: ["修造", "上梁"]),
        Expected(day: "2025-07-25", lunar: "闰六月初一", year: "乙巳", month: "癸未", date: "乙未", zodiac: "蛇",
                 term: nil, officer: "建", mansion: "亢", good: ["嫁娶", "祭祀", "出行"], bad: ["移徙", "入宅"]),
        Expected(day: "2025-02-03", lunar: "正月初六", year: "乙巳", month: "戊寅", date: "癸卯", zodiac: "蛇",
                 term: "立春", officer: "除", mansion: "张", good: ["嫁娶", "安床", "开光"], bad: ["掘井", "词讼"]),
        Expected(day: "2025-02-02", lunar: "正月初五", year: "乙巳", month: "丁丑", date: "壬寅", zodiac: "蛇",
                 term: nil, officer: "除", mansion: "星", good: ["嫁娶", "开光", "解除"], bad: ["作灶", "安葬"]),
        Expected(day: "2025-01-29", lunar: "正月初一", year: "乙巳", month: "丁丑", date: "戊戌", zodiac: "蛇",
                 term: nil, officer: "收", mansion: "参", good: ["祭祀", "斋醮", "纳财"], bad: ["嫁娶", "开市"]),
        Expected(day: "2025-01-28", lunar: "腊月廿九", year: "甲辰", month: "丁丑", date: "丁酉", zodiac: "龙",
                 term: nil, officer: "成", mansion: "觜", good: ["祭祀", "斋醮", "入殓"], bad: ["嫁娶", "入宅"]),
        Expected(day: "2024-12-21", lunar: "冬月廿一", year: "甲辰", month: "丙子", date: "己未", zodiac: "龙",
                 term: "冬至", officer: "危", mansion: "女", good: ["安床", "祭祀", "祈福"], bad: ["安门", "栽种"]),
        Expected(day: "2023-03-22", lunar: "闰二月初一", year: "癸卯", month: "乙卯", date: "己卯", zodiac: "兔",
                 term: nil, officer: "建", mansion: "壁", good: ["祭祀", "出行", "嫁娶"], bad: ["掘井", "动土"]),
        Expected(day: "2020-05-23", lunar: "闰四月初一", year: "庚子", month: "辛巳", date: "丙寅", zodiac: "鼠",
                 term: nil, officer: "收", mansion: "胃", good: ["嫁娶", "纳采", "出行"], bad: ["动土", "破土"]),
    ]

    func testKnownDaysMatchPublicAlmanacs() throws {
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for item in cases {
            let date = try XCTUnwrap(ChineseCalendar.day(item.day), item.day)
            let day = ChineseAlmanac.day(date)
            XCTAssertEqual(day.lunarText, item.lunar, item.day)
            XCTAssertEqual(day.yearGanzhi, item.year, item.day)
            XCTAssertEqual(day.monthGanzhi, item.month, item.day)
            XCTAssertEqual(day.dayGanzhi, item.date, item.day)
            XCTAssertEqual(day.zodiac, item.zodiac, item.day)
            XCTAssertEqual(day.term, item.term, item.day)
            XCTAssertEqual(day.officer, item.officer + "日", item.day)
            XCTAssertEqual(day.mansion, item.mansion, item.day)
            XCTAssertEqual(Array(day.good.prefix(item.good.count)), item.good, item.day)
            XCTAssertEqual(Array(day.bad.prefix(item.bad.count)), item.bad, item.day)
            XCTAssertEqual(day.ganzhiText, "\(item.year)年 \(item.month)月 \(item.date)日")
        }
    }

    /// 立春前一天和当天：月份按节换（丑月 → 寅月），建除重一天（两天都是除），年干支按春节换（早就是乙巳）。
    func testSolarTermBoundary() throws {
        let before = ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2025-02-02")))
        let after = ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2025-02-03")))
        XCTAssertEqual(before.monthGanzhi, "丁丑")
        XCTAssertEqual(after.monthGanzhi, "戊寅")
        XCTAssertEqual(before.officer, after.officer, "节那天和前一天值日相同（重建）")
        XCTAssertEqual(before.yearGanzhi, after.yearGanzhi)
        // 除夕和初一之间换年、换生肖；月份还是丑月。
        let eve = ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2025-01-28")))
        let newYear = ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2025-01-29")))
        XCTAssertEqual(eve.zodiac, "龙")
        XCTAssertEqual(newYear.zodiac, "蛇")
        XCTAssertEqual(eve.monthGanzhi, newYear.monthGanzhi)
    }

    /// 低精度节气公式落错一天的那几年按校正表走：2014 年惊蛰在 3 月 6 日 00:02，2016 年小暑在 7 月 7 日 00:03。
    func testTermDayCorrections() throws {
        XCTAssertEqual(ChineseCalendar.term(on: try XCTUnwrap(ChineseCalendar.day("2014-03-06"))), "惊蛰")
        XCTAssertNil(ChineseCalendar.term(on: try XCTUnwrap(ChineseCalendar.day("2014-03-05"))))
        XCTAssertEqual(ChineseCalendar.term(on: try XCTUnwrap(ChineseCalendar.day("2016-07-07"))), "小暑")
        XCTAssertEqual(ChineseCalendar.termDayCorrections.count, 15)
        // 惊蛰当天起是卯月。
        XCTAssertEqual(ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2014-03-06"))).monthGanzhi, "丁卯")
        XCTAssertEqual(ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2014-03-05"))).monthGanzhi, "丙寅")
    }

    func testTablesAreComplete() throws {
        XCTAssertEqual(ChineseAlmanac.yiJiWords.count, 142)
        XCTAssertEqual(ChineseAlmanac.yiJiWordsEnglish.count, ChineseAlmanac.yiJiWords.count)
        for word in ChineseAlmanac.yiJiWordsEnglish {
            XCTAssertNil(word.range(of: #"\p{Han}"#, options: .regularExpression), word)
        }
        XCTAssertEqual(ChineseAlmanac.mansionRows.joined().count, 28)
        XCTAssertEqual(Set(ChineseAlmanac.mansionRows.joined()).count, 28)
        for mansion in ChineseAlmanac.mansionRows.joined() {
            XCTAssertNotNil(ChineseAlmanac.mansionInfo[String(mansion)], String(mansion))
        }
        XCTAssertEqual(ChineseAlmanac.termNamesEnglish.count, ChineseCalendar.termNames.count)
        XCTAssertEqual(ChineseAlmanac.ganzhi(0), "甲子")
        XCTAssertEqual(ChineseAlmanac.ganzhi(59), "癸亥")
        XCTAssertEqual(ChineseAlmanac.englishGanzhi(42), "Bing-Wu")
        XCTAssertFalse(ChineseAlmanac.dayYiJi.isEmpty)
        XCTAssertFalse(ChineseAlmanac.dayYiJi.contains("\u{2014}"))
    }

    /// 按日缓存：同一天不同钟点拿到同一份，和现算的一样；很多线程同时问也不乱（缓存加锁）。
    func testDayCache() throws {
        let date = try XCTUnwrap(ChineseCalendar.day("2026-10-30"))
        ChineseAlmanac.cache.removeAll()
        XCTAssertEqual(ChineseAlmanac.cache.count, 0)
        let morning = ChineseAlmanac.day(date.addingTimeInterval(8 * 3600))
        XCTAssertEqual(ChineseAlmanac.cache.count, 1)
        let night = ChineseAlmanac.day(date.addingTimeInterval(23 * 3600 + 59 * 60))
        XCTAssertEqual(ChineseAlmanac.cache.count, 1, "同一天只算一次")
        XCTAssertEqual(morning, night)
        XCTAssertEqual(morning, ChineseAlmanac.compute(date))
        let next = ChineseAlmanac.day(date.addingTimeInterval(24 * 3600))
        XCTAssertNotEqual(next.dayCycle, morning.dayCycle)
        XCTAssertEqual(ChineseAlmanac.cache.count, 2)

        let start = try XCTUnwrap(ChineseCalendar.day("2025-01-01"))
        DispatchQueue.concurrentPerform(iterations: 600) { index in
            let day = start.addingTimeInterval(Double(index % 300) * 86_400 + 3600)
            _ = ChineseAlmanac.day(day)
        }
        XCTAssertLessThanOrEqual(ChineseAlmanac.cache.count, ChineseAlmanac.DayCache.limit)
        for offset in stride(from: 0, to: 300, by: 37) {
            let day = start.addingTimeInterval(Double(offset) * 86_400)
            XCTAssertEqual(ChineseAlmanac.day(day), ChineseAlmanac.compute(day))
        }
    }

    /// 一整年每天都算得出来：宜忌不空、星宿 28 天一轮、建除十二天一轮（节那天重一天）。
    func testEveryDayOfAYear() throws {
        var date = try XCTUnwrap(ChineseCalendar.day("2026-01-01"))
        var previous: ChineseAlmanac.Day?
        for _ in 0..<365 {
            let day = ChineseAlmanac.day(date)
            XCTAssertFalse(day.good.isEmpty)
            XCTAssertFalse(day.bad.isEmpty)
            XCTAssertFalse(day.englishGood.isEmpty)
            XCTAssertTrue(ChineseAlmanac.officers.indices.contains(day.officerIndex))
            if let previous {
                XCTAssertEqual((previous.dayCycle + 1) % 60, day.dayCycle)
                if day.termIndex.map({ $0 % 2 == 0 }) != true {
                    XCTAssertEqual((previous.officerIndex + 1) % 12, day.officerIndex)
                }
            }
            previous = day
            date = ChineseCalendar.gregorian.date(byAdding: .day, value: 1, to: date)!
        }
        let today = ChineseAlmanac.day(try XCTUnwrap(ChineseCalendar.day("2026-10-30")))
        XCTAssertEqual(today.mansionText, "娄金狗")
        XCTAssertTrue(today.mansionLucky)
        XCTAssertEqual(today.englishLunar, "9/21")
        XCTAssertEqual(today.englishYear, "Bing-Wu")
        XCTAssertEqual(today.englishOfficer, "Balance")
        XCTAssertEqual(today.englishGood.first, "Sacrifice")
    }
}
