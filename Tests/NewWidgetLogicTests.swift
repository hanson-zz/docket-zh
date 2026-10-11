import Foundation
import XCTest

/// The pure halves of the v0.4.0 widgets. What touches AppKit, the network or
/// the microphone cannot run here, since the test target compiles the core
/// rather than hosting the app.
final class WallpaperCycleTests: XCTestCase {
    func testNextAndPreviousWrapAround() {
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .next, roll: 0), 1)
        XCTAssertEqual(WallpaperCycle.index(after: 2, count: 3, step: .next, roll: 0), 0)
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .previous, roll: 0), 2)
        XCTAssertEqual(WallpaperCycle.index(after: 1, count: 3, step: .previous, roll: 0), 0)
    }

    func testAPictureFromOutsideTheFolderStartsAtAnEnd() {
        XCTAssertEqual(WallpaperCycle.index(after: nil, count: 4, step: .next, roll: 0), 0)
        XCTAssertEqual(WallpaperCycle.index(after: nil, count: 4, step: .previous, roll: 0), 3)
        XCTAssertEqual(WallpaperCycle.index(after: 9, count: 4, step: .next, roll: 0), 0,
                       "an index past the end is treated as outside the folder")
    }

    func testAnEmptyFolderHasNothingToShow() {
        for step in WallpaperCycle.Step.allCases {
            XCTAssertNil(WallpaperCycle.index(after: nil, count: 0, step: step, roll: 0.5))
        }
    }

    func testRandomNeverRepeatsTheCurrentPicture() {
        for current in 0..<5 {
            for roll in stride(from: 0.0, through: 1.0, by: 0.05) {
                let pick = WallpaperCycle.index(after: current, count: 5, step: .random, roll: roll)!
                XCTAssertNotEqual(pick, current)
                XCTAssertTrue((0..<5).contains(pick))
            }
        }
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 1, step: .random, roll: 0.7), 0,
                       "one picture is the only choice")
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .random, roll: .nan), 1)
    }
}

final class AppStripTests: XCTestCase {
    func testEverythingShowsWhenItFits() {
        XCTAssertEqual(AppStrip.fit(total: 4, capacity: 6), .init(shown: 4, overflow: 0))
        XCTAssertEqual(AppStrip.fit(total: 6, capacity: 6), .init(shown: 6, overflow: 0))
        XCTAssertEqual(AppStrip.fit(total: 0, capacity: 6), .init(shown: 0, overflow: 0))
    }

    /// The marker takes a slot of its own, so it never covers an icon.
    func testTheLastSlotCountsTheRest() {
        XCTAssertEqual(AppStrip.fit(total: 7, capacity: 6), .init(shown: 5, overflow: 2))
        XCTAssertEqual(AppStrip.fit(total: 30, capacity: 6), .init(shown: 5, overflow: 25))
        let fit = AppStrip.fit(total: 9, capacity: 6)
        XCTAssertEqual(fit.shown + fit.overflow, 9)
    }

    func testTheFrontmostAppLeads() {
        let apps = [("a", false), ("b", true), ("c", false)]
        XCTAssertEqual(AppStrip.ordered(apps, isActive: { $0.1 }).map { $0.0 }, ["b", "a", "c"])
        XCTAssertEqual(AppStrip.ordered([("x", false)], isActive: { $0.1 }).map { $0.0 }, ["x"])
    }
}

final class BookmarkTests: XCTestCase {
    func testATitleAndAnAddress() {
        let link = Bookmark(parsing: "GitHub https://github.com/hanson-zz/docket-zh")
        XCTAssertEqual(link?.title, "GitHub")
        XCTAssertEqual(link?.url.absoluteString, "https://github.com/hanson-zz/docket-zh")
    }

    func testABareHostIsAWebAddressTitledByItsHost() {
        let link = Bookmark(parsing: "  www.bilibili.com ")
        XCTAssertEqual(link?.url.absoluteString, "https://www.bilibili.com")
        XCTAssertEqual(link?.title, "bilibili.com")
    }

    func testATitleOfSeveralWordsAndChinese() {
        XCTAssertEqual(Bookmark(parsing: "我的 项目 主页 example.org/x")?.title, "我的 项目 主页")
        XCTAssertEqual(Bookmark(parsing: "必应 https://cn.bing.com")?.initial, "必")
        XCTAssertEqual(Bookmark(parsing: "github.com")?.initial, "G")
    }

    func testNothingThatReadsAsAnAddressIsDropped() {
        XCTAssertNil(Bookmark(parsing: ""))
        XCTAssertNil(Bookmark(parsing: "just words"))
        XCTAssertNil(Bookmark(parsing: "https://"))
        XCTAssertNil(Bookmark(parsing: ".com"))
        XCTAssertEqual(Bookmark.list(["a b", "知乎 zhihu.com", "", "mailto:hi@example.com"]).count, 2)
    }

    func testTheColourIsStablePerHost() {
        let a = Bookmark(parsing: "A https://www.zhihu.com")!
        let b = Bookmark(parsing: "B zhihu.com/question/1")!
        XCTAssertEqual(a.paletteIndex(count: 8), b.paletteIndex(count: 8), "same host, same colour")
        XCTAssertTrue((0..<8).contains(a.paletteIndex(count: 8)))
        XCTAssertEqual(a.paletteIndex(count: 0), 0)
    }

    func testTheTileGrowsWithItsLinksUpToEight() {
        XCTAssertEqual(Bookmark.tileWidth(count: 0), 100)
        XCTAssertLessThan(Bookmark.tileWidth(count: 3), Bookmark.tileWidth(count: 4))
        XCTAssertEqual(Bookmark.tileWidth(count: 8), Bookmark.tileWidth(count: 20))
        XCTAssertEqual(Bookmark.columnHeight(count: 8), Bookmark.columnHeight(count: 9))
        XCTAssertGreaterThanOrEqual(Bookmark.columnHeight(count: 1), 62)
    }
}

final class RecordingNamingTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testTheNameSortsAndHasNoColon() {
        let date = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-14 17:46:40 UTC
        let name = RecordingNaming.fileName(for: date, calendar: utc)
        XCTAssertEqual(name, "录音 2026-10-14 17.46.40.m4a")
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(RecordingNaming.isRecording(name))
    }

    func testOnlyOurFilesAreListed() {
        XCTAssertTrue(RecordingNaming.isRecording("录音 2026-01-01 00.00.00 2.M4A"))
        XCTAssertFalse(RecordingNaming.isRecording("会议.m4a"))
        XCTAssertFalse(RecordingNaming.isRecording("录音 草稿.txt"))
    }

    func testASecondPressInTheSameSecondDoesNotOverwrite() {
        let name = "录音 2026-10-15 02.13.20.m4a"
        XCTAssertEqual(RecordingNaming.unique(name, taken: []), name)
        XCTAssertEqual(RecordingNaming.unique(name, taken: [name]), "录音 2026-10-15 02.13.20 2.m4a")
        XCTAssertEqual(RecordingNaming.unique(name, taken: [name, "录音 2026-10-15 02.13.20 2.m4a"]),
                       "录音 2026-10-15 02.13.20 3.m4a")
    }

    func testElapsedTime() {
        XCTAssertEqual(RecordingNaming.elapsed(0), "0:00")
        XCTAssertEqual(RecordingNaming.elapsed(7.9), "0:07")
        XCTAssertEqual(RecordingNaming.elapsed(754), "12:34")
        XCTAssertEqual(RecordingNaming.elapsed(3723), "1:02:03")
        XCTAssertEqual(RecordingNaming.elapsed(-5), "0:00")
        XCTAssertEqual(RecordingNaming.elapsed(.infinity), "0:00")
    }
}

final class MailBadgeTests: XCTestCase {
    func testParsesWhatMailAnswers() {
        XCTAssertEqual(MailBadge.parse("12"), 12)
        XCTAssertEqual(MailBadge.parse(" 0\n"), 0)
        XCTAssertNil(MailBadge.parse(nil))
        XCTAssertNil(MailBadge.parse("missing value"))
        XCTAssertNil(MailBadge.parse("-3"))
    }

    func testTheFigureCapsAtNinetyNine() {
        XCTAssertEqual(MailBadge.figure(0), "0")
        XCTAssertEqual(MailBadge.figure(99), "99")
        XCTAssertEqual(MailBadge.figure(100), "99+")
        XCTAssertEqual(MailBadge.caption(0), "没有未读邮件")
        XCTAssertEqual(MailBadge.caption(4), "封未读邮件")
    }
}

final class CalculatorTests: XCTestCase {
    private func value(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Double? {
        guard case .success(let v) = Calculator.evaluate(text) else { return nil }
        return v
    }

    private func failure(_ text: String) -> Calculator.Failure? {
        guard case .failure(let f) = Calculator.evaluate(text) else { return nil }
        return f
    }

    func testPrecedenceAndBrackets() {
        XCTAssertEqual(value("1+2*3"), 7)
        XCTAssertEqual(value("(1+2)*3"), 9)
        XCTAssertEqual(value("10-4-3"), 3, "left associative")
        XCTAssertEqual(value("100/10/5"), 2)
        XCTAssertEqual(value(" 2 * ( 3 + 4 ) "), 14)
    }

    func testPowersAndSigns() {
        XCTAssertEqual(value("2^3^2"), 512, "right associative")
        XCTAssertEqual(value("-2^2"), -4, "the power binds tighter than the sign")
        XCTAssertEqual(value("2^-1"), 0.5)
        XCTAssertEqual(value("2*-3"), -6)
        XCTAssertEqual(value("--3"), 3)
    }

    func testPercent() {
        XCTAssertEqual(value("50%"), 0.5)
        XCTAssertEqual(value("200*15%"), 30)
    }

    func testWhatChineseKeyboardsType() {
        XCTAssertEqual(value("１２＋３"), 15)
        XCTAssertEqual(value("7÷2"), 3.5)
        XCTAssertEqual(value("3×4"), 12)
        XCTAssertEqual(value("（1+1）×2"), 4)
        XCTAssertEqual(value("1,000+1"), 1001)
        XCTAssertEqual(value("5−8"), -3)
    }

    /// Every one of these would have raised an uncatchable exception in
    /// NSExpression. Here each is an error value.
    func testBadInputFailsInsteadOfCrashing() {
        XCTAssertEqual(failure(""), .empty)
        XCTAssertEqual(failure("   "), .empty)
        XCTAssertEqual(failure("2+"), .incomplete)
        XCTAssertEqual(failure("1/0"), .divisionByZero)
        XCTAssertEqual(failure("((1)"), .unbalanced)
        XCTAssertEqual(failure("1)"), .unbalanced)
        XCTAssertEqual(failure("1.2.3"), .unexpected("."))
        XCTAssertEqual(failure("2a"), .unexpected("a"))
        XCTAssertEqual(failure("sqrt(4)"), .unexpected("s"))
        XCTAssertEqual(failure("10^400"), .notFinite)
        XCTAssertNotNil(failure(String(repeating: "(", count: 200) + "1" + String(repeating: ")", count: 200)))
        XCTAssertEqual(failure(String(repeating: "1+", count: 300) + "1"), .tooLong)
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(10.0 / 3), "3.33333333333")
        XCTAssertEqual(Calculator.format(123_456_789_000), "123456789000")
        XCTAssertEqual(Calculator.format(-0.0), "0")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(1e20), "1e+20")
        XCTAssertEqual(Calculator.format(.nan), "-")
        for failure in [Calculator.Failure.empty, .incomplete, .unbalanced, .divisionByZero, .tooLong,
                        .notFinite, .unexpected("x")] {
            XCTAssertFalse(failure.message.isEmpty)
        }
    }
}

final class CurrencyRatesTests: XCTestCase {
    private let sample = Data("""
    {"result":"success","base_code":"CNY","time_last_update_unix":1792022400,
     "rates":{"CNY":1,"USD":0.1404,"EUR":0.1290,"JPY":21.05,"BAD":0}}
    """.utf8)

    func testParsesTheProvidersPayload() throws {
        let rates = try XCTUnwrap(CurrencyRates.parse(sample))
        XCTAssertEqual(rates.base, "CNY")
        XCTAssertEqual(rates.updated, Date(timeIntervalSince1970: 1_792_022_400))
        XCTAssertNil(rates.rates["BAD"], "a zero rate would divide by zero later")
        XCTAssertEqual(rates.codes, ["CNY", "EUR", "JPY", "USD"])
    }

    func testAnErrorResponseIsNotATable() {
        XCTAssertNil(CurrencyRates.parse(Data(#"{"result":"error","error-type":"unsupported-code"}"#.utf8)))
        XCTAssertNil(CurrencyRates.parse(Data("not json".utf8)))
        XCTAssertNil(CurrencyRates.parse(Data(#"{"result":"success","base_code":"CNY","rates":{}}"#.utf8)))
    }

    func testCrossRatesGoThroughTheBase() throws {
        let rates = try XCTUnwrap(CurrencyRates.parse(sample))
        XCTAssertEqual(try XCTUnwrap(rates.convert(100, from: "CNY", to: "USD")), 14.04, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(rates.convert(14.04, from: "USD", to: "CNY")), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(rates.rate(from: "USD", to: "EUR")), 0.1290 / 0.1404, accuracy: 1e-12)
        XCTAssertEqual(rates.convert(5, from: "usd", to: "usd"), 5, "codes are case-insensitive")
        XCTAssertNil(rates.convert(1, from: "USD", to: "XYZ"))
        XCTAssertNil(rates.convert(.infinity, from: "USD", to: "CNY"))
    }

    func testStalenessAndTheCacheRoundTrip() throws {
        let rates = try XCTUnwrap(CurrencyRates.parse(sample))
        XCTAssertFalse(rates.isStale(now: rates.updated.addingTimeInterval(3600)))
        XCTAssertTrue(rates.isStale(now: rates.updated.addingTimeInterval(13 * 3600)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(CurrencyRates.self, from: encoder.encode(rates)), rates)
    }

    func testNamesAndFormatting() {
        XCTAssertEqual(CurrencyNames.name("cny"), "人民币")
        XCTAssertEqual(CurrencyNames.name("ZZZ"), "ZZZ")
        XCTAssertEqual(CurrencyNames.common.first?.code, "CNY", "CNY leads the menus")
        XCTAssertEqual(Set(CurrencyNames.common.map { $0.code }).count, CurrencyNames.common.count)
        XCTAssertEqual(CurrencyNames.format(1234.5, code: "USD"), "1,234.50")
        XCTAssertEqual(CurrencyNames.format(2105.4, code: "JPY"), "2,105")
        XCTAssertEqual(CurrencyNames.format(.nan, code: "USD"), "-")
    }
}

final class SkyMathTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func local(_ y: Int, _ m: Int, _ d: Int, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func minutes(_ date: Date, zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    /// Beijing at the June solstice: sunrise about 04:46, sunset about 19:46
    /// (China Meteorological Administration tables).
    func testBeijingAtTheSolstice() {
        guard case .normal(let rise, let set)? = SunTimes.on(local(2026, 6, 21, zone: shanghai),
                                                             latitude: 39.9042, longitude: 116.4074,
                                                             zone: shanghai) else { return XCTFail() }
        XCTAssertEqual(minutes(rise, zone: shanghai), 4 * 60 + 46, accuracy: 4)
        XCTAssertEqual(minutes(set, zone: shanghai), 19 * 60 + 46, accuracy: 4)
    }

    /// Oslo in late December: about 09:18 and 15:12.
    func testOsloInWinter() {
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        guard case .normal(let rise, let set)? = SunTimes.on(local(2026, 12, 21, zone: oslo),
                                                             latitude: 59.9139, longitude: 10.7522,
                                                             zone: oslo) else { return XCTFail() }
        XCTAssertEqual(minutes(rise, zone: oslo), 9 * 60 + 18, accuracy: 5)
        XCTAssertEqual(minutes(set, zone: oslo), 15 * 60 + 12, accuracy: 5)
    }

    func testThePolesHaveNoSunriseSometimes() {
        let tromso = TimeZone(identifier: "Europe/Oslo")!
        XCTAssertEqual(SunTimes.on(local(2026, 6, 21, zone: tromso), latitude: 69.65, longitude: 18.96,
                                   zone: tromso), .polarDay)
        XCTAssertEqual(SunTimes.on(local(2026, 12, 21, zone: tromso), latitude: 69.65, longitude: 18.96,
                                   zone: tromso), .polarNight)
        XCTAssertNil(SunTimes.on(.now, latitude: .nan, longitude: 0))
        XCTAssertNil(SunTimes.on(.now, latitude: 95, longitude: 0))
    }

    func testWindIsNamedForWhereItComesFrom() {
        XCTAssertEqual(Wind.direction(0), "北风")
        XCTAssertEqual(Wind.direction(44), "东北风")
        XCTAssertEqual(Wind.direction(90), "东风")
        XCTAssertEqual(Wind.direction(200), "南风")
        XCTAssertEqual(Wind.direction(338), "北风")
        XCTAssertEqual(Wind.direction(-90), "西风")
        XCTAssertEqual(Wind.direction(720 + 135), "东南风")
    }

    func testBeaufortForce() {
        XCTAssertEqual(Wind.beaufort(0.1), 0)
        XCTAssertEqual(Wind.beaufort(1.0), 1)
        XCTAssertEqual(Wind.beaufort(4.2), 3)
        XCTAssertEqual(Wind.beaufort(10.8), 6)
        XCTAssertEqual(Wind.beaufort(40), 12)
        XCTAssertEqual(Wind.summary(speed: 4.2, from: 45), "东北风 3 级 · 4.2 m/s")
        XCTAssertEqual(Wind.summary(speed: 0.1, from: 45), "无风")
    }

    func testPixelDigitsAreFiveBySeven() {
        for character in "0123456789" {
            let glyph = PixelFont.glyph(character)
            XCTAssertEqual(glyph?.count, 7, "\(character)")
            XCTAssertTrue(glyph?.allSatisfy { $0.count == 5 } ?? false, "\(character)")
            XCTAssertTrue(glyph?.joined().contains(true) ?? false, "\(character) is blank")
        }
        let grid = PixelFont.render("12:34")
        XCTAssertEqual(grid.count, 7)
        XCTAssertEqual(grid[0].count, 5 * 4 + 1 + 4, "four digits, a colon, four gaps")
        XCTAssertTrue(grid.allSatisfy { $0.count == grid[0].count })
        XCTAssertNil(PixelFont.glyph("x"))
    }
}
