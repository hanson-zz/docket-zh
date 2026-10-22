import XCTest

/// 世界时钟改版：城市小知识表、日出日落、现在适合联系吗、卡片天空色和字色、
/// 汇率那一行、菜单栏第二时区。
final class WorldClockInfoTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    /// 效果图的示例时刻：2026-10-22 周四 15:56 北京时间（纽约 03:56、伦敦 08:56、东京 16:56）。
    private let sample = Date(timeIntervalSince1970: 1_792_655_760)

    private func city(_ id: String) -> WorldCity {
        guard let city = WorldCities.city(id: id) else {
            XCTFail("内置表里没有 \(id)")
            return WorldCity(name: id, zone: "UTC")
        }
        return city
    }

    private func date(_ text: String, zone: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts[0] * 60 + parts[1]
    }

    func testSampleMatchesTheMockup() {
        XCTAssertEqual(WorldClockInfo.hhmm(sample, zone: shanghai), "15:56")
        XCTAssertEqual(WorldClockInfo.hhmm(sample, zone: city("newyork").timeZone!), "03:56")
        XCTAssertEqual(WorldClockInfo.hhmm(sample, zone: city("london").timeZone!), "08:56")
        XCTAssertEqual(WorldClockInfo.hhmm(sample, zone: city("tokyo").timeZone!), "16:56")
    }

    // MARK: 城市小知识表

    func testEveryBuiltInCityHasFactsInTheSameOrder() {
        XCTAssertEqual(CityFacts.all.map(\.id), WorldCities.all.map(\.id))
        for city in WorldCities.all {
            XCTAssertNotNil(city.fact, city.id)
            XCTAssertNotNil(city.latitude, city.id)
            XCTAssertNotNil(city.longitude, city.id)
        }
    }

    func testCitiesOutsideTheTableHaveNoFacts() {
        let custom = WorldCity(name: "公司", zone: "Asia/Tokyo")
        XCTAssertNil(custom.fact)
        XCTAssertNil(custom.latitude)
        XCTAssertNil(WorldClockInfo.sun(custom, now: sample))
    }

    func testNotesAndIntrosAreShortCleanSentences() {
        for fact in CityFacts.all {
            XCTAssertFalse(fact.noteZh.isEmpty, fact.id)
            XCTAssertFalse(fact.noteEn.isEmpty, fact.id)
            XCTAssertLessThanOrEqual(fact.noteZh.count, 10, fact.id)
            XCTAssertLessThanOrEqual(fact.noteEn.count, 34, fact.id)
            XCTAssertTrue(fact.introZh.hasSuffix("。"), fact.id)
            XCTAssertTrue(fact.introEn.hasSuffix("."), fact.id)
            // 一两句。
            XCTAssertLessThanOrEqual(fact.introZh.filter { $0 == "。" }.count, 2, fact.id)
            for text in [fact.noteZh, fact.noteEn, fact.introZh, fact.introEn] {
                XCTAssertFalse(text.contains("\u{2014}"), fact.id)
                XCTAssertFalse(text.contains("  "), fact.id)
            }
            // 英文里不留中文和中文标点。
            for text in [fact.noteEn, fact.introEn] {
                XCTAssertNil(text.range(of: "[\\u4e00-\\u9fff，。、：；（）]", options: .regularExpression), fact.id)
            }
        }
    }

    func testNotesFromTheBrief() {
        XCTAssertEqual(city("beijing").fact?.noteZh, "中国首都")
        XCTAssertEqual(city("beijing").fact?.noteEn, "Capital of China")
        XCTAssertEqual(city("newyork").fact?.noteZh, "全球金融中心")
        XCTAssertEqual(city("london").fact?.noteZh, "英国首都")
        XCTAssertEqual(city("tokyo").fact?.noteZh, "日本首都")
        // 测试包里没有本地化表，取的是中文。
        XCTAssertEqual(city("beijing").fact?.note, "中国首都")
    }

    func testCurrenciesAndDialCodes() {
        for fact in CityFacts.all {
            XCTAssertNotNil(CityFacts.currencies[fact.currency], "\(fact.id) \(fact.currency)")
            XCTAssertNotNil(fact.currency.range(of: "^[A-Z]{3}$", options: .regularExpression), fact.id)
            XCTAssertNotNil(fact.dialCode.range(of: "^\\+[1-9][0-9]{0,3}$", options: .regularExpression), fact.id)
        }
        let expected: [String: (String, String)] = [
            "beijing": ("CNY", "+86"), "hongkong": ("HKD", "+852"), "macau": ("MOP", "+853"),
            "taipei": ("TWD", "+886"), "tokyo": ("JPY", "+81"), "seoul": ("KRW", "+82"),
            "singapore": ("SGD", "+65"), "london": ("GBP", "+44"), "paris": ("EUR", "+33"),
            "berlin": ("EUR", "+49"), "zurich": ("CHF", "+41"), "moscow": ("RUB", "+7"),
            "almaty": ("KZT", "+7"), "newyork": ("USD", "+1"), "toronto": ("CAD", "+1"),
            "sydney": ("AUD", "+61"), "auckland": ("NZD", "+64"), "dubai": ("AED", "+971"),
            "newdelhi": ("INR", "+91"), "saopaulo": ("BRL", "+55"), "quito": ("USD", "+593"),
            "sofia": ("EUR", "+359"), "mexicocity": ("MXN", "+52"), "cairo": ("EGP", "+20"),
        ]
        for (id, pair) in expected {
            XCTAssertEqual(city(id).fact?.currency, pair.0, id)
            XCTAssertEqual(city(id).fact?.dialCode, pair.1, id)
        }
        XCTAssertEqual(CityFacts.currencyName("USD"), "美元")
        XCTAssertEqual(CityFacts.currencyName("xyz"), "XYZ")
        XCTAssertEqual(WorldClockInfo.currencyTitle("usd"), "美元 USD")
    }

    // MARK: 经纬度和日出日落

    func testCoordinatesAgreeWithEachCitysClock() {
        // 经度写反、写错一位时，当地正午会偏出好几个小时；纬度写反时，六月和
        // 十二月谁的白天长会反过来。
        let days = ["2026-03-20", "2026-06-21", "2026-12-21"]
        for city in WorldCities.all {
            guard let lat = city.latitude, let lon = city.longitude, let zone = city.timeZone else { continue }
            XCTAssertTrue((-90...90).contains(lat), city.id)
            XCTAssertTrue((-180...180).contains(lon), city.id)
            var lengths: [TimeInterval] = []
            for day in days {
                let noon = date("\(day) 12:00", zone: city.zone)
                guard case .normal(let rise, let set)? = SunTimes.on(noon, latitude: lat, longitude: lon, zone: zone)
                else { XCTFail("\(city.id) \(day) 没有日出日落"); continue }
                let middle = rise.addingTimeInterval(set.timeIntervalSince(rise) / 2)
                let hour = WorldClockInfo.hour(middle, zone: zone)
                XCTAssertTrue((10.5...15.0).contains(hour), "\(city.id) \(day) 当地正午 \(hour)")
                lengths.append(set.timeIntervalSince(rise))
            }
            if lat > 10 { XCTAssertGreaterThan(lengths[1], lengths[2], city.id) }
            if lat < -10 { XCTAssertLessThan(lengths[1], lengths[2], city.id) }
        }
    }

    func testSunTimesMatchTheMockupForNewYork() {
        guard case .normal(let rise, let set)? = WorldClockInfo.sun(city("newyork"), now: sample) else {
            return XCTFail("纽约应该有日出日落")
        }
        // 2026-10-22 纽约：日出约 07:13，日落约 18:05（美国东部夏令时）。
        XCTAssertLessThanOrEqual(abs(minutes(rise) - minutes("07:13")), 4, rise)
        XCTAssertLessThanOrEqual(abs(minutes(set) - minutes("18:05")), 4, set)
    }

    func testSunTimesForBeijingAndSydney() {
        // 北京 2026-10-22：日出约 06:29，日落约 17:23。
        guard case .normal(let rise, let set)? = WorldClockInfo.sun(city("beijing"), now: sample) else {
            return XCTFail("北京应该有日出日落")
        }
        XCTAssertLessThanOrEqual(abs(minutes(rise) - minutes("06:29")), 5, rise)
        XCTAssertLessThanOrEqual(abs(minutes(set) - minutes("17:23")), 5, set)
        // 悉尼 10 月已是夏令时，日落在晚上 7 点前后。
        guard case .normal(_, let sydneySet)? = WorldClockInfo.sun(city("sydney"), now: sample) else {
            return XCTFail("悉尼应该有日出日落")
        }
        XCTAssertTrue((18 * 60 + 30...19 * 60 + 30).contains(minutes(sydneySet)), sydneySet)
    }

    // MARK: 现在适合联系吗

    func testContactRulesByClock() {
        typealias R = WorldClockContact.Reason
        let cases: [(String, String, R)] = [
            ("09:00", "10:00", .bothWorking),
            ("17:59", "09:00", .bothWorking),
            ("08:59", "10:00", .theyStartSoon),
            ("07:00", "10:00", .theyStartSoon),
            ("18:00", "10:00", .theyOffWork),
            ("21:59", "10:00", .theyOffWork),
            ("22:00", "10:00", .theyAsleep),
            ("03:56", "15:56", .theyAsleep),
            ("06:59", "10:00", .theyAsleep),
            ("00:00", "00:00", .theyAsleep),
            ("10:00", "08:59", .youBeforeWork),
            ("10:00", "07:00", .youBeforeWork),
            ("10:00", "18:00", .youOffWork),
            ("10:00", "21:59", .youOffWork),
            ("10:00", "22:00", .youLateNight),
            ("10:00", "06:59", .youLateNight),
        ]
        for (them, you, expected) in cases {
            XCTAssertEqual(WorldClockContact.reason(theirMinutes: minutes(them), yourMinutes: minutes(you)),
                           expected, "对方 \(them) 你 \(you)")
        }
        // 超出一天的分钟数按一天取余。
        XCTAssertEqual(WorldClockContact.reason(theirMinutes: 1440 + 600, yourMinutes: -1440 + 600), .bothWorking)
    }

    func testContactLevelsAndWords() {
        XCTAssertEqual(WorldClockContact.Reason.bothWorking.level, .good)
        XCTAssertEqual(WorldClockContact.Reason.theyAsleep.level, .asleep)
        for reason in [WorldClockContact.Reason.theyStartSoon, .theyOffWork, .youBeforeWork, .youOffWork, .youLateNight] {
            XCTAssertEqual(reason.level, .maybe, reason.rawValue)
        }
        XCTAssertEqual(WorldClockContact.Reason.bothWorking.text, "适合")
        XCTAssertEqual(WorldClockContact.Reason.theyAsleep.text, "对方在睡觉")
        XCTAssertEqual(WorldClockContact.Reason.theyStartSoon.text, "快上班")
        XCTAssertEqual(WorldClockContact.Reason.theyOffWork.text, "已下班")
        XCTAssertEqual(WorldClockContact.Reason.youOffWork.text, "你那边已下班")
        // 每种说法都不一样。
        XCTAssertEqual(Set(WorldClockContact.Reason.allCases.map(\.text)).count, WorldClockContact.Reason.allCases.count)
    }

    func testCapsuleWordsStayReadableInBothAppearances() {
        // 面板玻璃大致的底：浅色接近白，深色接近黑灰。
        let lightGlass = WorldClockSky.RGB(hex: 0xF2F2F5)
        let darkGlass = WorldClockSky.RGB(hex: 0x1E1E22)
        for level in WorldClockContact.Level.allCases {
            let opacity = WorldClockContact.Level.capsuleOpacity
            let onLight = WorldClockSky.over(level.dot, opacity: opacity, on: lightGlass)
            let onDark = WorldClockSky.over(level.dot, opacity: opacity, on: darkGlass)
            XCTAssertGreaterThanOrEqual(WorldClockSky.contrast(level.inkLight, onLight), 4.5, level.rawValue)
            XCTAssertGreaterThanOrEqual(WorldClockSky.contrast(level.inkDark, onDark), 4.5, level.rawValue)
        }
    }

    func testContactAtTheMockupMoment() {
        let zone = { (id: String) in self.city(id).timeZone! }
        XCTAssertEqual(WorldClockContact.reason(there: zone("newyork"), now: sample, here: shanghai), .theyAsleep)
        XCTAssertEqual(WorldClockContact.reason(there: zone("london"), now: sample, here: shanghai), .theyStartSoon)
        XCTAssertEqual(WorldClockContact.reason(there: zone("tokyo"), now: sample, here: shanghai), .bothWorking)
        XCTAssertEqual(WorldClockContact.theirTime(zone("newyork"), now: sample), "对方 03:56")
    }

    func testContactFollowsDaylightSaving() {
        // 2026-11-02 起纽约回到标准时间，同一个北京时间对方早一小时。
        let summer = date("2026-10-30 21:30", zone: "Asia/Shanghai")
        let winter = date("2026-11-06 21:30", zone: "Asia/Shanghai")
        let newYork = city("newyork").timeZone!
        XCTAssertEqual(WorldClockInfo.hhmm(summer, zone: newYork), "09:30")
        XCTAssertEqual(WorldClockInfo.hhmm(winter, zone: newYork), "08:30")
        XCTAssertEqual(WorldClockContact.reason(there: newYork, now: summer, here: shanghai), .youOffWork)
        XCTAssertEqual(WorldClockContact.reason(there: newYork, now: winter, here: shanghai), .theyStartSoon)
    }

    // MARK: 卡片天空色

    func testEveryPhaseKeepsTextAtLeast4_5To1() {
        for phase in WorldClockSky.Phase.allCases {
            XCTAssertGreaterThanOrEqual(WorldClockSky.worstContrast(phase), 4.5, phase.rawValue)
            XCTAssertEqual(WorldClockSky.colors(phase).count, 2)
        }
        XCTAssertFalse(WorldClockSky.usesLightInk(.day))
        XCTAssertTrue(WorldClockSky.usesLightInk(.night))
        XCTAssertTrue(WorldClockSky.usesLightInk(.dusk))
        XCTAssertTrue(WorldClockSky.usesLightInk(.dawn))
        XCTAssertTrue(WorldClockSky.Phase.night.hasStars)
        XCTAssertFalse(WorldClockSky.Phase.day.hasStars)
    }

    func testContrastMaths() {
        XCTAssertEqual(WorldClockSky.contrast(WorldClockSky.white, WorldClockSky.RGB(0, 0, 0)), 21, accuracy: 0.01)
        XCTAssertEqual(WorldClockSky.contrast(WorldClockSky.white, WorldClockSky.white), 1, accuracy: 0.001)
        XCTAssertEqual(WorldClockSky.RGB(hex: 0xFF8000), WorldClockSky.RGB(1, 128.0 / 255, 0))
    }

    func testPhaseByClockWithoutCoordinates() {
        XCTAssertEqual(WorldClockSky.phase(hour: 3), .night)
        XCTAssertEqual(WorldClockSky.phase(hour: 5.5), .dawn)
        XCTAssertEqual(WorldClockSky.phase(hour: 12), .day)
        XCTAssertEqual(WorldClockSky.phase(hour: 17.5), .dusk)
        XCTAssertEqual(WorldClockSky.phase(hour: 21), .night)
        let custom = WorldCity(name: "公司", zone: "America/New_York")
        XCTAssertEqual(WorldClockSky.phase(custom, now: sample), .night)
    }

    func testPhaseAtTheMockupMomentFollowsTheSun() {
        // 纽约深夜、伦敦早上（日出一个多小时后）、东京日落前后。
        XCTAssertEqual(WorldClockSky.phase(city("newyork"), now: sample), .night)
        XCTAssertEqual(WorldClockSky.phase(city("london"), now: sample), .day)
        XCTAssertEqual(WorldClockSky.phase(city("tokyo"), now: sample), .dusk)
        XCTAssertEqual(WorldClockSky.phase(city("beijing"), now: sample), .day)
    }

    // MARK: 汇率那一行

    private let rates = CurrencyRates(base: "CNY", rates: ["CNY": 1, "USD": 0.14, "JPY": 21.3, "KWD": 0.043, "GBP": 0.105],
                                      updated: Date(timeIntervalSince1970: 1_792_600_000))

    func testRateLine() {
        XCTAssertEqual(WorldClockInfo.rateLine(code: "USD", reference: "CNY", rates: rates), "1 美元 ≈ 7.14 元")
        XCTAssertEqual(WorldClockInfo.rateLine(code: "JPY", reference: "CNY", rates: rates), "100 日元 ≈ 4.69 元")
        XCTAssertEqual(WorldClockInfo.rateLine(code: "KWD", reference: "CNY", rates: rates), "1 科威特第纳尔 ≈ 23.3 元")
        XCTAssertEqual(WorldClockInfo.rateLine(code: "USD", reference: "GBP", rates: rates), "1 美元 ≈ 0.75 英镑")
    }

    func testNoRateLineWithoutARealRate() {
        XCTAssertNil(WorldClockInfo.rateLine(code: "CNY", reference: "CNY", rates: rates))
        XCTAssertNil(WorldClockInfo.rateLine(code: "USD", reference: "CNY", rates: nil))
        XCTAssertNil(WorldClockInfo.rateLine(code: "XPF", reference: "CNY", rates: rates))
    }

    func testReferenceCurrency() {
        XCTAssertEqual(WorldClockInfo.referenceCurrency(here: shanghai), "CNY")
        XCTAssertEqual(WorldClockInfo.referenceCurrency(here: TimeZone(identifier: "Europe/London")!), "GBP")
        XCTAssertEqual(WorldClockInfo.referenceCurrency(here: TimeZone(identifier: "Etc/GMT+3")!), "CNY")
    }

    // MARK: 菜单栏第二时区

    func testMenuBarPicksTheFirstCityThatIsNotHere() {
        let list = [city("beijing"), city("newyork"), city("london")]
        XCTAssertEqual(WorldClockMenuBar.pick(list, chosen: nil, now: sample, here: shanghai)?.id, "newyork")
        XCTAssertEqual(WorldClockMenuBar.pick(list, chosen: "london", now: sample, here: shanghai)?.id, "london")
        XCTAssertEqual(WorldClockMenuBar.pick(list, chosen: "Europe/London|伦敦", now: sample, here: shanghai)?.id, "london")
        // 选过的城市删掉了：回到默认。
        XCTAssertEqual(WorldClockMenuBar.pick(list, chosen: "paris", now: sample, here: shanghai)?.id, "newyork")
        // 都和此处同一时间：第二个。
        let sameTime = [city("beijing"), city("shanghai"), city("hongkong")]
        XCTAssertEqual(WorldClockMenuBar.pick(sameTime, chosen: nil, now: sample, here: shanghai)?.id, "shanghai")
        XCTAssertEqual(WorldClockMenuBar.pick([city("beijing")], chosen: nil, now: sample, here: shanghai)?.id, "beijing")
        XCTAssertNil(WorldClockMenuBar.pick([], chosen: nil, now: sample, here: shanghai))
        // 第一个就不在此处时用第一个。
        let abroad = [city("tokyo"), city("beijing")]
        XCTAssertEqual(WorldClockMenuBar.pick(abroad, chosen: nil, now: sample, here: shanghai)?.id, "tokyo")
    }

    func testMenuBarTitleAndRows() {
        XCTAssertEqual(WorldClockMenuBar.title(city("newyork"), now: sample), "纽约 03:56")
        let list = [city("beijing"), city("newyork"), city("london"), city("tokyo")]
        XCTAssertEqual(WorldClockMenuBar.rows(list, here: shanghai).map(\.id), ["newyork", "london", "tokyo"])
        XCTAssertEqual(WorldClockMenuBar.rows([city("beijing")], here: shanghai).map(\.id), ["beijing"])
        XCTAssertEqual(WorldClockMenuBar.toggleTitle(city("newyork")), "菜单栏显示纽约")
    }

    func testMenuBarSettingsDefaultOffAndDecodeOldFiles() throws {
        XCTAssertFalse(MenuBarSettings().showWorldClock)
        XCTAssertNil(MenuBarSettings().worldClockCity)
        let old = try JSONDecoder().decode(MenuBarSettings.self, from: Data(#"{"showIcon":true,"label":"none","labelReviewed":true}"#.utf8))
        XCTAssertFalse(old.showWorldClock)
        XCTAssertNil(old.worldClockCity)
        var on = MenuBarSettings()
        on.showWorldClock = true
        on.worldClockCity = "london"
        let back = try JSONDecoder().decode(MenuBarSettings.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.showWorldClock)
        XCTAssertEqual(back.worldClockCity, "london")
    }
}
