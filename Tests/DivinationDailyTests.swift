import XCTest
@testable import Docket

/// 卜卦每日一签的附加功能（Core 的 `DivinationDaily`）：星座 / 属相定签、幸运色和幸运数字、
/// 本周寄语、签历和收藏、皮肤、签卡分享图的尺寸和文件名，以及对应的 Pro 判断。
final class DivinationDailyTests: XCTestCase {

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    // MARK: 星座和属相

    func testSignLists() {
        XCTAssertEqual(DivinationSign.allCases.count, 24)
        XCTAssertEqual(DivinationSign.Kind.allCases, [.none, .star, .animal])
        XCTAssertEqual(DivinationSign.Kind.none.signs, [])
        XCTAssertEqual(DivinationSign.Kind.star.signs.count, 12)
        XCTAssertEqual(DivinationSign.Kind.animal.signs.count, 12)
        XCTAssertEqual(DivinationSign.Kind.star.signs.first, .aries)
        XCTAssertEqual(DivinationSign.Kind.animal.signs.first, .rat)
        XCTAssertTrue(DivinationSign.Kind.star.signs.allSatisfy { $0.kind == .star })
        XCTAssertTrue(DivinationSign.Kind.animal.signs.allSatisfy { $0.kind == .animal })
        XCTAssertEqual(DivinationSign.leo.name, "狮子座")
        XCTAssertEqual(DivinationSign.dragon.name, "属龙")
        XCTAssertEqual(DivinationSign.dragon.symbol, "龙")
        XCTAssertEqual(DivinationSign.leo.symbol.unicodeScalars.first?.value, 0x264C)
        XCTAssertEqual(Set(DivinationSign.allCases.map(\.name)).count, 24)
        XCTAssertEqual(Set(DivinationSign.allCases.map(\.symbol)).count, 24)
    }

    func testSameSignSameDaySameStickAcrossCards() {
        let now = date("2026-10-29T03:00:00Z")
        var a = WidgetConfig(), b = WidgetConfig()
        Divination.setSign(.leo, in: &a, now: now, cardSalt: "card-A", calendar: shanghai)
        Divination.setSign(.leo, in: &b, now: now, cardSalt: "card-B", calendar: shanghai)
        let drawA = Divination.drawStick(in: &a, now: now, salt: "card-A", calendar: shanghai)
        let drawB = Divination.drawStick(in: &b, now: now, salt: "card-B", calendar: shanghai)
        XCTAssertEqual(drawA.index, drawB.index, "同一天同星座同一支，和卡片无关")
        XCTAssertEqual(drawA.index, Divination.seededStick(day: "2026-10-29", salt: "sign:leo"))
        XCTAssertEqual(Divination.stickSalt(a, cardSalt: "card-A"), "sign:leo")
        // 不选：照旧按卡片 id。
        var plain = WidgetConfig()
        XCTAssertEqual(Divination.stickSalt(plain, cardSalt: "card-A"), "card-A")
        let drawPlain = Divination.drawStick(in: &plain, now: now, salt: "card-A", calendar: shanghai)
        XCTAssertEqual(drawPlain.index, Divination.seededStick(day: "2026-10-29", salt: "card-A"))
    }

    func testChangingSignAfterDrawingSwitchesTodaysStick() {
        let now = date("2026-10-29T03:00:00Z")
        var config = WidgetConfig()
        _ = Divination.drawStick(in: &config, now: now, salt: "card", calendar: shanghai)
        Divination.setSign(.dragon, in: &config, now: now, cardSalt: "card", calendar: shanghai)
        let expected = Divination.seededStick(day: "2026-10-29", salt: "sign:dragon")
        XCTAssertEqual(Divination.todayStick(config, now: now, calendar: shanghai), expected)
        XCTAssertEqual(Divination.stickLog(config)["2026-10-29"], expected, "签历里今天这条一起改")
        XCTAssertEqual(Divination.sign(config), .dragon)
        // 改回不选：回到卡片自己的那支。
        Divination.setSign(nil, in: &config, now: now, cardSalt: "card", calendar: shanghai)
        XCTAssertNil(Divination.sign(config))
        XCTAssertEqual(Divination.todayStick(config, now: now, calendar: shanghai),
                       Divination.seededStick(day: "2026-10-29", salt: "card"))
        // 没抽过时改星座只记下选择。
        var fresh = WidgetConfig()
        Divination.setSign(.pisces, in: &fresh, now: now, cardSalt: "card", calendar: shanghai)
        XCTAssertNil(Divination.todayStick(fresh, now: now, calendar: shanghai))
        XCTAssertTrue(Divination.stickLog(fresh).isEmpty)
    }

    func testLuckIsDeterministic() {
        let first = Divination.luck(day: "2026-10-29", sign: .leo)
        XCTAssertEqual(first, Divination.luck(day: "2026-10-29", sign: .leo))
        XCTAssertTrue(Divination.luckyNumbers.contains(first.number))
        XCTAssertTrue(Divination.luckyColors.contains(first.color))
        let month = (1...28).map { Divination.luck(day: String(format: "2026-02-%02d", $0), sign: .leo) }
        XCTAssertGreaterThan(Set(month.map(\.color.name)).count, 4, "换一天大多换颜色")
        XCTAssertGreaterThan(Set(month.map(\.number)).count, 3)
        XCTAssertGreaterThanOrEqual(Divination.luckyColors.count, 12)
        XCTAssertEqual(Set(Divination.luckyColors.map(\.name)).count, Divination.luckyColors.count)
        for color in Divination.luckyColors {
            XCTAssertTrue(color.hex.hasPrefix("#") && color.hex.count == 7, color.hex)
        }
    }

    // MARK: 本周寄语

    func testWeeklyLineChangesOnMonday() {
        // 2026-10-26 是周一，到 11-01 周日都是同一句；11-02 周一换。
        let monday = date("2026-10-25T16:30:00Z")
        let sunday = date("2026-11-01T15:00:00Z")
        let nextMonday = date("2026-11-01T16:30:00Z")
        XCTAssertEqual(DivinationWeekly.week(monday, calendar: shanghai).week, 44)
        XCTAssertEqual(DivinationWeekly.line(monday, calendar: shanghai),
                       DivinationWeekly.line(sunday, calendar: shanghai))
        XCTAssertNotEqual(DivinationWeekly.line(sunday, calendar: shanghai),
                          DivinationWeekly.line(nextMonday, calendar: shanghai))
        // 周日深夜在 UTC 已经是周一，按本地日历仍是上一周。
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(DivinationWeekly.week(sunday, calendar: shanghai).week, 44)
        XCTAssertEqual(DivinationWeekly.week(date("2026-11-01T23:30:00Z"), calendar: shanghai).week, 45)
        XCTAssertEqual(DivinationWeekly.week(date("2026-11-01T23:30:00Z"), calendar: utc).week, 44)
    }

    func testWeeklyLinesCoverAYearWithoutRepeats() {
        XCTAssertGreaterThanOrEqual(DivinationWeekly.lines.count, 52)
        XCTAssertEqual(Set(DivinationWeekly.lines).count, DivinationWeekly.lines.count, "不重复")
        // 2026 年（ISO 有 53 周）每周一句都不一样。
        var seen: Set<Int> = []
        var day = date("2025-12-28T16:30:00Z") // 2025-12-29 周一，ISO 2026 第 1 周
        for _ in 0..<53 {
            XCTAssertEqual(DivinationWeekly.week(day, calendar: shanghai).year, 2026)
            seen.insert(DivinationWeekly.index(day, calendar: shanghai))
            day = shanghai.date(byAdding: .day, value: 7, to: day)!
        }
        XCTAssertEqual(seen.count, 53)
        for line in DivinationWeekly.lines {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}"), line)
            for word in ["运势", "运气", "会发财", "必定", "注定", "预测"] {
                XCTAssertFalse(line.contains(word), "寄语不说运势：\(line)")
            }
        }
    }

    // MARK: 签历和收藏

    func testDrawsAreLoggedAndFavoritable() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 3)
        let day1 = date("2026-10-28T03:00:00Z")
        let day2 = date("2026-10-29T03:00:00Z")
        let first = Divination.drawStick(in: &config, now: day1, calendar: shanghai, using: &rng)
        let second = Divination.drawStick(in: &config, now: day2, calendar: shanghai, using: &rng)
        // 同一天再摇不改签历。
        _ = Divination.drawStick(in: &config, now: day2, calendar: shanghai, using: &rng)
        XCTAssertEqual(Divination.stickLog(config), ["2026-10-28": first.index, "2026-10-29": second.index])
        XCTAssertEqual(Divination.records(config).map(\.day), ["2026-10-29", "2026-10-28"], "新的在前")
        XCTAssertEqual(Divination.record(day: "2026-10-28", in: config)?.index, first.index)
        XCTAssertNil(Divination.record(day: "2026-10-27", in: config))

        XCTAssertTrue(Divination.toggleFavorite(day: "2026-10-28", in: &config))
        XCTAssertEqual(Divination.favorites(config).map(\.day), ["2026-10-28"])
        XCTAssertTrue(Divination.record(day: "2026-10-28", in: config)?.favorite ?? false)
        XCTAssertFalse(Divination.toggleFavorite(day: "2026-10-27", in: &config), "没抽过的日子不能收藏")
        XCTAssertFalse(Divination.toggleFavorite(day: "2026-10-28", in: &config))
        XCTAssertTrue(Divination.favorites(config).isEmpty)
        XCTAssertNil(config.values[Divination.stickFavoritesKey])
    }

    func testLogKeepsAYearAndFavorites() {
        var config = WidgetConfig()
        let now = date("2026-10-29T03:00:00Z")
        // 每条按当天记下（那时还在保留期里）。
        Divination.recordStick(1, day: "2025-01-01", in: &config, now: date("2025-01-01T03:00:00Z"), calendar: shanghai)
        Divination.recordStick(2, day: "2025-06-01", in: &config, now: date("2025-06-01T03:00:00Z"), calendar: shanghai)
        XCTAssertTrue(Divination.toggleFavorite(day: "2025-06-01", in: &config))
        Divination.recordStick(3, day: "2025-10-01", in: &config, now: date("2025-10-01T03:00:00Z"), calendar: shanghai)
        XCTAssertEqual(Divination.stickLog(config).count, 3)
        Divination.recordStick(4, day: "2026-10-29", in: &config, now: now, calendar: shanghai)
        let log = Divination.stickLog(config)
        XCTAssertNil(log["2025-01-01"], "400 天以前、没收藏的清掉")
        XCTAssertEqual(log["2025-06-01"], 2, "收藏的一直留着")
        XCTAssertEqual(log["2025-10-01"], 3, "一年以内的留着")
        XCTAssertEqual(log["2026-10-29"], 4)
        XCTAssertGreaterThanOrEqual(Divination.stickLogRetentionDays, 366)
        // 坏数据跳过。
        config.set(Divination.stickLogKey, .string("2026-10-01=5,bad,2026-10-02=999,2026-1-3=1,2026-10-04=7"))
        XCTAssertEqual(Divination.stickLog(config), ["2026-10-01": 5, "2026-10-04": 7])
        Divination.recordStick(999, day: "2026-10-05", in: &config, now: now, calendar: shanghai)
        XCTAssertNil(Divination.stickLog(config)["2026-10-05"])
    }

    func testMonthLevelsAndDayParsing() {
        var config = WidgetConfig()
        let now = date("2026-10-29T03:00:00Z")
        Divination.recordStick(0, day: "2026-10-01", in: &config, now: now, calendar: shanghai)
        Divination.recordStick(5, day: "2026-10-15", in: &config, now: now, calendar: shanghai)
        Divination.recordStick(6, day: "2026-09-30", in: &config, now: now, calendar: shanghai)
        let levels = Divination.monthLevels(config, month: now, calendar: shanghai)
        XCTAssertEqual(Set(levels.keys), ["2026-10-01", "2026-10-15"])
        XCTAssertEqual(levels["2026-10-15"], FortuneStick.all[5].level)
        XCTAssertTrue(Divination.isDayKey("2026-10-29"))
        XCTAssertFalse(Divination.isDayKey("2026-1-29"))
        XCTAssertFalse(Divination.isDayKey("abcd-ef-gh"))
        let parsed = Divination.date(fromDay: "2026-10-29", calendar: shanghai)!
        XCTAssertEqual(Divination.dayKey(parsed, calendar: shanghai), "2026-10-29")
        XCTAssertNil(Divination.date(fromDay: "nope", calendar: shanghai))
    }

    // MARK: 皮肤

    func testSkins() {
        XCTAssertEqual(TubeSkin.allCases, [.bamboo, .lacquer, .jade])
        XCTAssertEqual(CoinSkin.allCases, [.classic, .silver, .verdigris])
        XCTAssertFalse(TubeSkin.bamboo.isPro)
        XCTAssertTrue(TubeSkin.lacquer.isPro && TubeSkin.jade.isPro)
        XCTAssertFalse(CoinSkin.classic.isPro)
        XCTAssertTrue(CoinSkin.silver.isPro && CoinSkin.verdigris.isPro)
        // 默认款就是原来的配色。
        XCTAssertEqual(TubeSkin.bamboo.bodyHex, "#C98A3A")
        XCTAssertEqual(CoinSkin.classic.faceHex, Divination.goldHex)

        var config = WidgetConfig()
        XCTAssertEqual(Divination.tubeSkin(config, unlocked: true), .bamboo)
        XCTAssertEqual(Divination.coinSkin(config, unlocked: true), .classic)
        config.set(Divination.tubeSkinKey, .string("jade"))
        config.set(Divination.coinSkinKey, .string("verdigris"))
        XCTAssertEqual(Divination.tubeSkin(config, unlocked: true), .jade)
        XCTAssertEqual(Divination.coinSkin(config, unlocked: true), .verdigris)
        XCTAssertEqual(Divination.tubeSkin(config, unlocked: false), .bamboo, "没解锁画默认款")
        XCTAssertEqual(Divination.coinSkin(config, unlocked: false), .classic)
        XCTAssertEqual(Divination.storedTubeSkin(config), .jade, "选的照旧存着")
        XCTAssertEqual(Divination.storedCoinSkin(config), .verdigris)
        config.set(Divination.coinSkinKey, .string("gold-ish"))
        XCTAssertEqual(Divination.coinSkin(config, unlocked: true), .classic)
    }

    // MARK: 签卡和 Pro

    func testShareCard() {
        XCTAssertEqual(DivinationShareCard.pixelSize.width, 1080)
        XCTAssertEqual(DivinationShareCard.pixelSize.height, 1920)
        XCTAssertEqual(DivinationShareCard.fileName(day: "2026-10-29", dark: false), "码头每日一签-2026-10-29-浅色.png")
        XCTAssertEqual(DivinationShareCard.fileName(day: "2026-10-29", dark: true), "码头每日一签-2026-10-29-深色.png")
        let text = DivinationShareCard.dateText(day: "2026-10-29", calendar: shanghai,
                                                locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(text.contains("2026") && text.contains("29"), text)
        XCTAssertTrue(text.contains("星期四"), text)
    }

    func testProGates() {
        XCTAssertFalse(ProLicenseGate.canUseDivinationArchive(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseDivinationArchive(unlocked: true))
        XCTAssertFalse(ProLicenseGate.canShareDivinationCard(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canShareDivinationCard(unlocked: true))
        XCTAssertTrue(ProLicenseGate.canChooseDivinationSkin(isPro: TubeSkin.bamboo.isPro, unlocked: false))
        XCTAssertFalse(ProLicenseGate.canChooseDivinationSkin(isPro: TubeSkin.jade.isPro, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChooseDivinationSkin(isPro: CoinSkin.silver.isPro, unlocked: true))
        // 卜卦整种仍免费。
        XCTAssertFalse(ProFeatures.isProKind(.divination))
    }
}
