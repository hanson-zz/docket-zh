import XCTest
@testable import Docket

/// 卜卦（Core 的 `Divination`、`Hexagram`、`Casting`、`WorryBook`）：六十四卦的卦序和卦画、
/// 铜钱起卦规则、变卦、起卦记录、每日一签按日期定签、解忧书换页、存法、尺寸和音效合成。
final class DivinationTests: XCTestCase {

    // MARK: 六十四卦

    /// 文王卦序每一卦的「下卦上卦」，取自《周易》各卦卦题下的「某下某上」（和数据表分开写，
    /// 用来交叉校对卦画）。
    private static let compositions = """
    乾乾 坤坤 震坎 坎艮 乾坎 坎乾 坎坤 坤坎 乾巽 兑乾 乾坤 坤乾 离乾 乾离 艮坤 坤震 \
    震兑 巽艮 兑坤 坤巽 震离 离艮 坤艮 震坤 震乾 乾艮 震艮 巽兑 坎坎 离离 艮兑 巽震 \
    艮乾 乾震 坤离 离坤 离巽 兑离 艮坎 坎震 兑艮 震巽 乾兑 巽乾 坤兑 巽坤 坎兑 巽坎 \
    离兑 巽离 震震 艮艮 艮巽 兑震 离震 艮离 巽巽 兑兑 坎巽 兑坎 兑巽 艮震 离坎 坎离
    """.split(separator: " ").map(String.init)

    /// 文王卦序的卦名。
    private static let names = """
    乾 坤 屯 蒙 需 讼 师 比 小畜 履 泰 否 同人 大有 谦 豫 随 蛊 临 观 噬嗑 贲 剥 复 \
    无妄 大畜 颐 大过 坎 离 咸 恒 遯 大壮 晋 明夷 家人 睽 蹇 解 损 益 夬 姤 萃 升 \
    困 井 革 鼎 震 艮 渐 归妹 丰 旅 巽 兑 涣 节 中孚 小过 既济 未济
    """.split(separator: " ").map(String.init)

    func testSixtyFourInKingWenOrder() {
        XCTAssertEqual(Hexagram.all.count, 64)
        XCTAssertEqual(Self.names.count, 64)
        XCTAssertEqual(Self.compositions.count, 64)
        for (i, hexagram) in Hexagram.all.enumerated() {
            XCTAssertEqual(hexagram.number, i + 1)
            XCTAssertEqual(hexagram.name, Self.names[i], "第 \(i + 1) 卦")
            XCTAssertEqual(Hexagram.number(i + 1), hexagram)
        }
        XCTAssertNil(Hexagram.number(0))
        XCTAssertNil(Hexagram.number(65))
    }

    func testLinesMatchTrigramComposition() {
        let byName = Dictionary(uniqueKeysWithValues: Trigram.allCases.map { ($0.name, $0) })
        for (i, hexagram) in Hexagram.all.enumerated() {
            let pair = Array(Self.compositions[i])
            XCTAssertEqual(hexagram.lower, byName[String(pair[0])], "\(hexagram.name) 下卦")
            XCTAssertEqual(hexagram.upper, byName[String(pair[1])], "\(hexagram.name) 上卦")
            XCTAssertEqual(hexagram.lines.count, 6)
            XCTAssertTrue(hexagram.lines.allSatisfy { $0 == "0" || $0 == "1" })
            XCTAssertEqual(Array(hexagram.yang[0..<3]), hexagram.lower.lines)
            XCTAssertEqual(Array(hexagram.yang[3..<6]), hexagram.upper.lines)
        }
    }

    func testBinaryValuesAreDistinctAndRoundTrip() {
        let values = Hexagram.all.map(\.value)
        XCTAssertEqual(Set(values).count, 64)
        XCTAssertEqual(Set(values), Set(0..<64))
        for hexagram in Hexagram.all {
            XCTAssertEqual(Hexagram.with(value: hexagram.value), hexagram)
            XCTAssertEqual(Hexagram.with(yang: hexagram.yang), hexagram)
        }
        XCTAssertNil(Hexagram.with(yang: [true]))
    }

    func testKnownHexagrams() {
        // 自下而上：初爻在最左。
        XCTAssertEqual(Hexagram.number(1)?.lines, "111111")
        XCTAssertEqual(Hexagram.number(1)?.value, 63)
        XCTAssertEqual(Hexagram.number(2)?.lines, "000000")
        XCTAssertEqual(Hexagram.number(2)?.value, 0)
        XCTAssertEqual(Hexagram.number(3)?.lines, "100010", "屯：震下坎上")
        XCTAssertEqual(Hexagram.number(11)?.lines, "111000", "泰：乾下坤上")
        XCTAssertEqual(Hexagram.number(12)?.lines, "000111", "否：坤下乾上")
        XCTAssertEqual(Hexagram.number(29)?.lines, "010010")
        XCTAssertEqual(Hexagram.number(30)?.lines, "101101")
        XCTAssertEqual(Hexagram.number(63)?.lines, "101010", "既济：离下坎上")
        XCTAssertEqual(Hexagram.number(64)?.lines, "010101", "未济：坎下离上")
    }

    func testKingWenPairs() {
        // 文王卦序两两一对：后一卦是前一卦倒过来；倒过来还是自己的，就阴阳全反。
        for n in stride(from: 1, to: 64, by: 2) {
            guard let a = Hexagram.number(n), let b = Hexagram.number(n + 1) else { return XCTFail() }
            let reversed = String(a.lines.reversed())
            if reversed == a.lines {
                let inverted = String(a.lines.map { $0 == "1" ? "0" : "1" })
                XCTAssertEqual(b.lines, inverted, "\(a.name)、\(b.name) 应当阴阳相反")
            } else {
                XCTAssertEqual(b.lines, reversed, "\(a.name)、\(b.name) 应当上下颠倒")
            }
        }
    }

    func testFullNamesAndSymbols() {
        XCTAssertEqual(Hexagram.number(1)?.fullName, "乾为天")
        XCTAssertEqual(Hexagram.number(2)?.fullName, "坤为地")
        XCTAssertEqual(Hexagram.number(3)?.fullName, "水雷屯")
        XCTAssertEqual(Hexagram.number(11)?.fullName, "地天泰")
        XCTAssertEqual(Hexagram.number(19)?.fullName, "地泽临")
        XCTAssertEqual(Hexagram.number(29)?.fullName, "坎为水")
        XCTAssertEqual(Hexagram.number(61)?.fullName, "风泽中孚")
        XCTAssertEqual(Hexagram.number(1)?.symbol, "䷀")
        XCTAssertEqual(Hexagram.number(64)?.symbol, "䷿")
        XCTAssertEqual(Trigram.qian.lines, [true, true, true])
        XCTAssertEqual(Trigram.zhen.lines, [true, false, false], "震：一阳在下")
        XCTAssertEqual(Trigram.gen.lines, [false, false, true], "艮：一阳在上")
    }

    func testTextsMatchTheLines() {
        let positions = ["初", "二", "三", "四", "五", "上"]
        for hexagram in Hexagram.all {
            XCTAssertFalse(hexagram.judgment.isEmpty, hexagram.name)
            XCTAssertEqual(hexagram.lineTexts.count, 6, hexagram.name)
            for (i, text) in hexagram.lineTexts.enumerated() {
                let title = String(text.prefix(2))
                XCTAssertTrue(title.contains(positions[i]), "\(hexagram.name) \(text)")
                // 爻题的九、六要和卦画的阴阳一致。
                XCTAssertTrue(title.contains(hexagram.yang[i] ? "九" : "六"), "\(hexagram.name) \(text)")
                XCTAssertTrue(text.dropFirst(2).hasPrefix("："), "\(hexagram.name) \(text)")
            }
            XCTAssertFalse(hexagram.plain.isEmpty, hexagram.name)
            XCTAssertLessThanOrEqual(hexagram.plain.count, 40, "白话一两句")
        }
        XCTAssertEqual(Hexagram.number(1)?.extraText, "用九：见群龙无首，吉。")
        XCTAssertEqual(Hexagram.number(2)?.extraText, "用六：利永贞。")
        XCTAssertEqual(Hexagram.all.filter { $0.extraText != nil }.count, 2, "只有乾坤有用九、用六")
        XCTAssertEqual(Hexagram.number(11)?.judgment, "小往大来，吉，亨。")
        XCTAssertEqual(Hexagram.number(11)?.lineTexts[2], "九三：无平不陂，无往不复，艰贞无咎。勿恤其孚，于食有福。")
    }

    func testNoForbiddenCharactersInData() {
        var all: [String] = []
        for hexagram in Hexagram.all {
            all += [hexagram.name, hexagram.judgment, hexagram.plain] + hexagram.lineTexts
            if let extra = hexagram.extraText { all.append(extra) }
        }
        for stick in FortuneStick.all { all += stick.poem + [stick.good, stick.avoid, stick.plain] }
        all += WorryBook.answers
        for text in all {
            XCTAssertFalse(text.contains("\u{2014}"), text)
            XCTAssertFalse(text.isEmpty)
        }
    }

    // MARK: 铜钱规则

    func testCoinRule() {
        // 三背老阳（变）、三字老阴（变）、两背一字少阳、两字一背少阴。true 是背。
        XCTAssertEqual(LineKind(coins: [true, true, true]), .oldYang)
        XCTAssertEqual(LineKind(coins: [false, false, false]), .oldYin)
        XCTAssertEqual(LineKind(coins: [true, true, false]), .youngYang)
        XCTAssertEqual(LineKind(coins: [false, true, true]), .youngYang)
        XCTAssertEqual(LineKind(coins: [true, false, false]), .youngYin)
        XCTAssertEqual(LineKind(coins: [false, false, true]), .youngYin)
        XCTAssertEqual(LineKind.oldYin.rawValue, 6)
        XCTAssertEqual(LineKind.youngYang.rawValue, 7)
        XCTAssertEqual(LineKind.youngYin.rawValue, 8)
        XCTAssertEqual(LineKind.oldYang.rawValue, 9)
        XCTAssertTrue(LineKind.oldYang.isYang && LineKind.oldYang.isChanging)
        XCTAssertFalse(LineKind.oldYang.changedYang, "老阳变阴")
        XCTAssertTrue(LineKind.oldYin.changedYang, "老阴变阳")
        XCTAssertTrue(LineKind.youngYang.changedYang && !LineKind.youngYang.isChanging)
        XCTAssertFalse(LineKind.youngYin.changedYang || LineKind.youngYin.isChanging)
    }

    func testTossesAreSeededAndRoughlyFair() {
        func cast(_ seed: UInt64) -> [LineKind] {
            var casting = Casting()
            var rng = MineRandom(seed: seed)
            casting.tossAll(using: &rng)
            return casting.lines
        }
        XCTAssertEqual(cast(42), cast(42), "同一个种子同一卦")
        var counts: [LineKind: Int] = [:]
        for seed in UInt64(0)..<400 { for line in cast(seed) { counts[line, default: 0] += 1 } }
        // 2400 爻：老阳、老阴各约 1/8，少阳、少阴各约 3/8。
        XCTAssertEqual(counts.values.reduce(0, +), 2400)
        XCTAssertGreaterThan(counts[.oldYang] ?? 0, 200)
        XCTAssertLessThan(counts[.oldYang] ?? 0, 400)
        XCTAssertGreaterThan(counts[.youngYin] ?? 0, 750)
        XCTAssertLessThan(counts[.youngYin] ?? 0, 1050)
    }

    func testCastingGoesBottomUpAndStopsAtSix() {
        var casting = Casting(question: "问", time: 5)
        var rng = MineRandom(seed: 9)
        for n in 1...6 {
            XCTAssertNotNil(casting.toss(using: &rng))
            XCTAssertEqual(casting.count, n)
            XCTAssertEqual(casting.isComplete, n == 6)
            if n < 6 { XCTAssertNil(casting.primary) }
        }
        XCTAssertNil(casting.toss(using: &rng), "摇满六爻不再摇")
        XCTAssertNotNil(casting.primary)
    }

    func testChangedHexagram() {
        // 泰（乾下坤上），九三老阳变：成临（兑下坤上）。初爻在前。
        let yang = [true, true, true], young = [true, true, false], yin = [true, false, false]
        let casting = Casting(tosses: [young, young, yang, yin, yin, yin])
        XCTAssertEqual(casting.primary?.name, "泰")
        XCTAssertEqual(casting.changingIndices, [2])
        XCTAssertEqual(casting.changed?.name, "临")
        XCTAssertEqual(casting.changingTexts, ["九三：无平不陂，无往不复，艰贞无咎。勿恤其孚，于食有福。"])
        XCTAssertEqual(Divination.castingSummary(casting), "六次摇钱 · 第三爻为变")

        // 没有变爻：没有之卦。
        let still = Casting(tosses: Array(repeating: young, count: 6))
        XCTAssertEqual(still.primary?.name, "乾")
        XCTAssertNil(still.changed)
        XCTAssertTrue(still.changingTexts.isEmpty)
        XCTAssertEqual(Divination.castingSummary(still), "六次摇钱 · 没有变爻")

        // 乾六爻全变：之卦是坤，加上用九。
        let all = Casting(tosses: Array(repeating: yang, count: 6))
        XCTAssertEqual(all.changed?.name, "坤")
        XCTAssertEqual(all.changingTexts.count, 7)
        XCTAssertEqual(all.changingTexts.last, "用九：见群龙无首，吉。")

        // 初爻、上爻变。
        let ends = Casting(tosses: [[false, false, false], yin, yin, yin, yin, yang])
        XCTAssertEqual(ends.changingIndices, [0, 5])
        XCTAssertEqual(Divination.castingSummary(ends), "六次摇钱 · 初爻、上爻为变")
    }

    func testEveryChangedHexagramFlipsOnlyChangingLines() {
        for seed in UInt64(0)..<200 {
            var casting = Casting()
            var rng = MineRandom(seed: seed)
            casting.tossAll(using: &rng)
            guard let primary = casting.primary else { return XCTFail() }
            guard let changed = casting.changed else {
                XCTAssertTrue(casting.changingIndices.isEmpty)
                continue
            }
            for i in 0..<6 {
                let flips = casting.changingIndices.contains(i)
                XCTAssertEqual(primary.yang[i] != changed.yang[i], flips)
            }
        }
    }

    func testCastingCodableRoundTrip() throws {
        var casting = Casting(question: "这个月换工作合适吗", time: 1_700_000_000)
        var rng = MineRandom(seed: 3)
        casting.toss(using: &rng)
        casting.toss(using: &rng)
        let data = try JSONEncoder().encode(casting)
        XCTAssertEqual(try JSONDecoder().decode(Casting.self, from: data), casting)
        let bad = Data(#"{"t":1,"f":"11,000"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Casting.self, from: bad))
        XCTAssertEqual(Casting(question: String(repeating: "问", count: 99)).question.count, Divination.questionLimit)
    }

    // MARK: 起卦记录

    func testTossInConfigStartsNewCastingAndRecordsHistory() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 1)
        let first = Divination.toss(in: &config, question: "  问一  ", all: false, now: 10, using: &rng)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.question, "问一")
        XCTAssertTrue(Divination.history(config).isEmpty, "没摇满不记")
        let done = Divination.toss(in: &config, question: "改了也不换", all: true, now: 11, using: &rng)
        XCTAssertTrue(done.isComplete)
        XCTAssertEqual(done.question, "问一", "摇到一半问题不换")
        XCTAssertEqual(Divination.history(config).first, done)
        // 摇满后再摇：开新的一卦。
        let next = Divination.toss(in: &config, question: "问二", all: false, now: 20, using: &rng)
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next.question, "问二")
        XCTAssertEqual(Divination.casting(config), next)
        Divination.resetCasting(in: &config)
        XCTAssertEqual(Divination.casting(config).count, 0)
    }

    func testHistoryKeepsNewestFive() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 2)
        for n in 0..<8 {
            Divination.toss(in: &config, question: "第\(n)次", all: true, now: Double(n), using: &rng)
        }
        let history = Divination.history(config)
        XCTAssertEqual(history.count, Divination.historyLimit)
        XCTAssertEqual(history.map(\.question), ["第7次", "第6次", "第5次", "第4次", "第3次"])
        Divination.record(Casting(question: "半截"), in: &config)
        XCTAssertEqual(Divination.history(config).first?.question, "第7次", "没摇满的不记")
        Divination.clearHistory(in: &config)
        XCTAssertTrue(Divination.history(config).isEmpty)
        config.set(Divination.historyKey, .string("坏了"))
        XCTAssertTrue(Divination.history(config).isEmpty)
    }

    // MARK: 每日一签

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    func testDayKeyUsesLocalDate() {
        // UTC 16:30 已经是上海的第二天 00:30。
        let moment = date("2026-10-29T16:30:00Z")
        XCTAssertEqual(Divination.dayKey(moment, calendar: shanghai), "2026-10-30")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Divination.dayKey(moment, calendar: utc), "2026-10-29")
    }

    func testOneStickPerDay() {
        var config = WidgetConfig()
        let morning = date("2026-10-29T01:00:00Z")
        let evening = date("2026-10-29T15:00:00Z")
        let tomorrow = date("2026-10-29T16:30:00Z")
        XCTAssertNil(Divination.todayStick(config, now: morning, calendar: shanghai))
        var rng = MineRandom(seed: 5)
        let first = Divination.drawStick(in: &config, now: morning, calendar: shanghai, using: &rng)
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(Divination.todayStick(config, now: evening, calendar: shanghai), first.index)
        // 今天再点：还是那支，不重抽。
        var other = MineRandom(seed: 999)
        let again = Divination.drawStick(in: &config, now: evening, calendar: shanghai, using: &other)
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(again.index, first.index)
        // 第二天重置。
        XCTAssertNil(Divination.todayStick(config, now: tomorrow, calendar: shanghai))
        let next = Divination.drawStick(in: &config, now: tomorrow, calendar: shanghai, using: &other)
        XCTAssertTrue(next.isNew)
        XCTAssertEqual(config.string(Divination.stickDayKey), "2026-10-30")
    }

    func testSeededStickIsStablePerDayAndCard() {
        XCTAssertEqual(Divination.seededStick(day: "2026-10-29", salt: "A"),
                       Divination.seededStick(day: "2026-10-29", salt: "A"))
        let days = (1...28).map { Divination.seededStick(day: String(format: "2026-02-%02d", $0), salt: "A") }
        XCTAssertGreaterThan(Set(days).count, 10, "换一天大多换签")
        XCTAssertTrue(days.allSatisfy { FortuneStick.all.indices.contains($0) })
        XCTAssertEqual(Divination.stableHash("abc"), Divination.stableHash("abc"))
        XCTAssertNotEqual(Divination.stableHash("abc"), Divination.stableHash("abd"))
        XCTAssertEqual(Divination.stableHash(""), 0xCBF2_9CE4_8422_2325)

        let now = date("2026-10-29T03:00:00Z")
        var a = WidgetConfig(), b = WidgetConfig()
        let drawA = Divination.drawStick(in: &a, now: now, salt: "card", calendar: shanghai)
        let drawB = Divination.drawStick(in: &b, now: now, salt: "card", calendar: shanghai)
        XCTAssertEqual(drawA, drawB, "同一天同一张卡片同一支")
        XCTAssertEqual(drawA.index, Divination.seededStick(day: "2026-10-29", salt: "card"))
    }

    func testBadStoredStickIsIgnored() {
        var config = WidgetConfig()
        let now = date("2026-10-29T03:00:00Z")
        config.set(Divination.stickDayKey, .string("2026-10-29"))
        config.set(Divination.stickKey, .number(999))
        XCTAssertNil(Divination.todayStick(config, now: now, calendar: shanghai))
    }

    func testStickLibrary() {
        XCTAssertGreaterThanOrEqual(FortuneStick.all.count, 60)
        XCTAssertEqual(Set(FortuneStick.all.map(\.level)), Set(StickLevel.allCases), "每一级都有")
        for stick in FortuneStick.all {
            XCTAssertEqual(stick.poem.count, 4)
            XCTAssertTrue(stick.poem.allSatisfy { $0.count == 7 }, "七言四句：\(stick.poem)")
            XCTAssertEqual(stick.poemLines.first?.last, "，")
            XCTAssertEqual(stick.poemLines.last?.last, "。")
            XCTAssertFalse(stick.good.isEmpty)
            XCTAssertFalse(stick.avoid.isEmpty)
            XCTAssertFalse(stick.plain.isEmpty)
        }
        XCTAssertEqual(Set(FortuneStick.all.map { $0.poem.joined() }).count, FortuneStick.all.count, "签诗不重复")
        XCTAssertEqual(StickLevel.best.title, "上上签")
        XCTAssertEqual(StickLevel.low.title, "下签")
        XCTAssertTrue(StickLevel.best.isFestive && StickLevel.great.isFestive)
        XCTAssertFalse(StickLevel.fair.isFestive)
        XCTAssertLessThan(StickLevel.best.rank, StickLevel.low.rank)
    }

    func testChineseNumbers() {
        XCTAssertEqual(Divination.chineseNumber(1), "一")
        XCTAssertEqual(Divination.chineseNumber(10), "十")
        XCTAssertEqual(Divination.chineseNumber(11), "十一")
        XCTAssertEqual(Divination.chineseNumber(20), "二十")
        XCTAssertEqual(Divination.chineseNumber(37), "三十七")
        XCTAssertEqual(Divination.chineseNumber(60), "六十")
        XCTAssertEqual(Divination.stickNumber(36), "第三十七签")
        XCTAssertEqual(Divination.lineName(0), "初爻")
        XCTAssertEqual(Divination.lineName(2), "第三爻")
        XCTAssertEqual(Divination.lineName(5), "上爻")
    }

    // MARK: 解忧书

    func testAnswerLibrary() {
        XCTAssertGreaterThanOrEqual(WorryBook.answers.count, 300)
        XCTAssertEqual(Set(WorryBook.answers).count, WorryBook.answers.count, "不重复")
        for answer in WorryBook.answers {
            XCTAssertLessThanOrEqual(answer.count, 18, "简短：\(answer)")
            XCTAssertFalse(answer.contains("答案之书"))
        }
    }

    func testTurningAvoidsRecentPages() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 11)
        var pages: [Int] = []
        for _ in 0..<WorryBook.recentWindow {
            pages.append(Divination.turnPage(in: &config, using: &rng))
        }
        XCTAssertEqual(Set(pages).count, pages.count, "最近 \(WorryBook.recentWindow) 页不重复")
        XCTAssertEqual(Divination.lastPage(config), pages.last)
        XCTAssertEqual(Divination.bookRecent(config), pages)
        // 记录只留最近的窗口。
        for _ in 0..<10 { Divination.turnPage(in: &config, using: &rng) }
        XCTAssertEqual(Divination.bookRecent(config).count, WorryBook.recentWindow)
    }

    func testSameSeedSamePage() {
        var a = WidgetConfig(), b = WidgetConfig()
        var r1 = MineRandom(seed: 77), r2 = MineRandom(seed: 77)
        XCTAssertEqual(Divination.turnPage(in: &a, using: &r1), Divination.turnPage(in: &b, using: &r2))
    }

    func testSplitAnswer() {
        let parts = WorryBook.split("先迈出一小步，答案会自己出现")
        XCTAssertEqual(parts.first, "先迈出一小步，")
        XCTAssertEqual(parts.second, "答案会自己出现")
        XCTAssertNil(WorryBook.split("好的开始").second)
        XCTAssertNil(WorryBook.split("就这样，").second)
    }

    // MARK: 页、音效开关

    func testPageAndSoundDefaults() {
        var config = WidgetConfig()
        XCTAssertEqual(Divination.page(config), .stick)
        XCTAssertTrue(Divination.soundOn(config), "默认开声音")
        Divination.setPage(.book, in: &config)
        Divination.setSound(false, in: &config)
        XCTAssertEqual(Divination.page(config), .book)
        XCTAssertFalse(Divination.soundOn(config))
        XCTAssertEqual(DivinationPage.allCases.map(\.title), ["每日一签", "起卦", "解忧书"])
    }

    // MARK: 尺寸

    func testSizes() {
        XCTAssertEqual(Divination.panelWidth, 340)
        XCTAssertEqual(Divination.panelContentWidth, 266, accuracy: 0.001)
        XCTAssertEqual(Divination.tileWidth, 188)
        XCTAssertEqual(Divination.columnHeight, 120)
        XCTAssertGreaterThanOrEqual(Divination.minimumFont, 13)
        XCTAssertEqual(Divination.disclaimerFont, 12)
        XCTAssertTrue(DesktopCardsDivinationPlan.handles(.divination))
        XCTAssertFalse(DesktopCardsDivinationPlan.handles(.pullTooth))
        XCTAssertFalse(DesktopCardsDivinationPlan.canCast(.small))
        XCTAssertTrue(DesktopCardsDivinationPlan.canCast(.medium))
        XCTAssertTrue(DesktopCardsDivinationPlan.canCast(.large))
        XCTAssertEqual(DesktopPinSupport.mode(.divination, hasDetail: true, panelWidth: 340), .dedicated)
        XCTAssertLessThan(DesktopCardsDivinationPlan.mediumStickWidth + DesktopCardsDivinationPlan.mediumSpacing
                          + DesktopCardsDivinationPlan.inset(.medium) * 2, DesktopPinSize.medium.width - 120)
    }

    // MARK: 音效

    func testSoundsAreShortAndClean() {
        for sound in DivinationSound.allCases {
            let samples = DivinationSoundSynth.render(sound)
            XCTAssertFalse(samples.isEmpty, sound.rawValue)
            XCTAssertLessThan(Double(samples.count) / DivinationSoundSynth.sampleRate, 1.2, sound.rawValue)
            XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.95 }, sound.rawValue)
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.02, "听得见：\(sound.rawValue)")
            XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.0001, "尾巴渐弱到 0")
            XCTAssertEqual(DivinationSoundSynth.render(sound), samples, "每次合成一样")
            XCTAssertGreaterThan(DivinationSoundSynth.wav(sound).count, 44)
        }
        // 三枚铜钱错开落下。
        XCTAssertEqual(DivinationSoundSynth.clinkOffsets.count, 3)
        XCTAssertEqual(DivinationSoundSynth.clinkOffsets, DivinationSoundSynth.clinkOffsets.sorted())
        XCTAssertEqual(Set(DivinationSoundSynth.clinkOffsets).count, 3)
    }

    // MARK: 目录

    func testCatalogEntry() {
        let entry = WidgetCatalog.entry(.divination)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "卜卦")
        XCTAssertEqual(entry?.category, .tools)
        XCTAssertEqual(entry?.selfContained, true)
        XCTAssertTrue(WidgetLibraryGroups.isNew(.divination))
        XCTAssertFalse(ProFeatures.isProKind(.divination), "免费")
        XCTAssertEqual(WidgetKind(rawValue: "divination"), .divination)
        let keywords = WidgetSearch.keywords["divination"] ?? []
        for word in ["卜卦", "抽签", "求签", "易经", "周易", "算卦", "六十四卦", "fortune", "iching"] {
            XCTAssertTrue(keywords.contains(word), word)
        }
    }
}
