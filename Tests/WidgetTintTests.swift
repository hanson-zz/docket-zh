import XCTest

/// 小组件颜色主题：预设、读写、默认色表、对比色、背景和对比度。
final class WidgetTintTests: XCTestCase {

    // MARK: 预设

    func testPresetsMatchTheReferencePanel() {
        XCTAssertEqual(WidgetTint.Preset.allCases.count, 15)
        XCTAssertEqual(WidgetTint.Preset.allCases.map(\.title),
                       ["粉", "浅粉", "玫红", "红", "黄", "橙", "琥珀", "黄绿",
                        "薄荷绿", "绿", "青", "天蓝", "蓝", "淡紫", "紫"])
    }

    func testEveryPresetParsesAndHasADifferentContrast() {
        for preset in WidgetTint.Preset.allCases {
            XCTAssertNotNil(ColorCode(hex: preset.hex), preset.rawValue)
            XCTAssertNotNil(ColorCode(hex: preset.contrastHex), preset.rawValue)
            XCTAssertNotEqual(preset.palette.main, preset.palette.contrast, preset.rawValue)
        }
        XCTAssertEqual(Set(WidgetTint.Preset.allCases.map(\.hex)).count, 15, "预设颜色不重复")
    }

    // MARK: 读写

    func testMissingKeyIsTheKindDefault() {
        XCTAssertEqual(WidgetTint.choice(WidgetConfig()), .kindDefault)
        XCTAssertEqual(WidgetTint.background(WidgetConfig()), .plain)
        XCTAssertFalse(WidgetTint.choice(WidgetConfig()).isChosen)
    }

    func testChoiceRoundTrips() {
        let choices: [WidgetTint.Choice] = [
            .kindDefault, .system, .preset(.mint), .preset(.purple),
            .custom(ColorCode(hex: "#12AB34")!),
        ]
        for choice in choices {
            XCTAssertEqual(WidgetTint.Choice(raw: choice.raw), choice, choice.raw)
        }
        XCTAssertEqual(WidgetTint.Choice.kindDefault.raw, "")
    }

    func testParsingIsForgiving() {
        XCTAssertEqual(WidgetTint.Choice(raw: "default"), .kindDefault)
        XCTAssertEqual(WidgetTint.Choice(raw: "  blue "), .preset(.blue))
        XCTAssertEqual(WidgetTint.Choice(raw: "#ff0000"), .custom(ColorCode(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(WidgetTint.Choice(raw: "chartreuse"), .kindDefault)
        XCTAssertEqual(WidgetTint.Choice(raw: "#12"), .kindDefault)
        XCTAssertEqual(WidgetTint.Choice(raw: "FF0000"), .kindDefault, "自定义要带 #，不和预设名混")
        var config = WidgetConfig()
        config.set(WidgetTint.backgroundKey, .string("gradient"))
        XCTAssertEqual(WidgetTint.background(config), .gradient)
        config.set(WidgetTint.backgroundKey, .string("plaid"))
        XCTAssertEqual(WidgetTint.background(config), .plain)
    }

    func testPaletteForEachChoice() {
        XCTAssertEqual(WidgetTint.palette(.kindDefault, kind: .calendar), WidgetTint.defaultPalette(.calendar))
        XCTAssertNil(WidgetTint.palette(.system, kind: .calendar))
        XCTAssertEqual(WidgetTint.palette(.preset(.green), kind: .calendar), WidgetTint.Preset.green.palette)
        let custom = ColorCode(hex: "#3366CC")!
        let palette = WidgetTint.palette(.custom(custom), kind: .water)
        XCTAssertEqual(palette?.main, custom)
        XCTAssertNotEqual(palette?.contrast, custom)
    }

    // MARK: 默认色表

    func testEveryKindHasItsOwnPaletteWithADifferentContrast() {
        for kind in WidgetKind.allCases {
            let palette = WidgetTint.defaultPalette(kind)
            XCTAssertNotEqual(palette.main, palette.contrast, kind.rawValue)
            // 对比色是另一种色相，不是同色的深浅。
            let a = palette.main.hslComponents.h, b = palette.contrast.hslComponents.h
            let distance = min(abs(a - b), 360 - abs(a - b))
            XCTAssertGreaterThan(distance, 30, kind.rawValue)
        }
    }

    func testDefaultsAreNotAllOneColour() {
        let mains = Set(WidgetKind.allCases.map { WidgetTint.defaultPalette($0).main })
        XCTAssertGreaterThan(mains.count, 30)
    }

    /// 常一起放在扩展栏上的卡片，默认主色两两不同。
    func testCommonNeighboursDoNotClash() {
        let commonNeighbours: [WidgetKind] = [
            .clock, .world, .timer, .progress, .calendar, .todo, .water, .weather,
            .system, .aiUsage, .slacker, .battery, .downloads, .clipboard, .pet, .stock, .music,
        ]
        let mains = commonNeighbours.map { WidgetTint.defaultPalette($0).main }
        XCTAssertEqual(Set(mains).count, mains.count)
        // 时间进度和 Codex 用量都是紫，但不是同一种紫。
        XCTAssertNotEqual(WidgetTint.defaultPalette(.progress).main, WidgetTint.defaultPalette(.aiUsage).main)
    }

    func testCharacterOfTheDefaults() {
        func hue(_ kind: WidgetKind) -> Double { WidgetTint.defaultPalette(kind).main.hslComponents.h }
        XCTAssertTrue(hue(.calendar) < 15 || hue(.calendar) > 345, "日历红")
        XCTAssertTrue((15...45).contains(hue(.todo)), "待办橙")
        XCTAssertTrue((90...150).contains(hue(.timer)), "专注计时绿")
        XCTAssertTrue((250...290).contains(hue(.progress)), "时间进度紫")
        XCTAssertTrue((180...215).contains(hue(.water)), "喝水青蓝")
        // 行情：红涨绿跌。
        let stock = WidgetTint.defaultPalette(.stock)
        XCTAssertGreaterThan(stock.main.red, stock.main.green)
        XCTAssertGreaterThan(stock.contrast.green, stock.contrast.red)
    }

    func testTimerKeepsACustomSessionColour() {
        XCTAssertEqual(WidgetTint.timerPalette(.kindDefault, session: .indigo), WidgetTint.defaultPalette(.timer))
        XCTAssertEqual(WidgetTint.timerPalette(.kindDefault, session: .orange)?.main, ColorCode(hex: PaletteColor.orange.hex))
        XCTAssertEqual(WidgetTint.timerPalette(.preset(.sky), session: .orange), WidgetTint.Preset.sky.palette)
        XCTAssertNil(WidgetTint.timerPalette(.system, session: .orange))
    }

    func testPickerOffers() {
        XCTAssertTrue(WidgetTint.offersColor(.progress))
        XCTAssertTrue(WidgetTint.offersColor(.timer))
        XCTAssertTrue(WidgetTint.offersColor(.world))
        XCTAssertFalse(WidgetTint.offersColor(.photos))
        XCTAssertFalse(WidgetTint.offersBackground(.slacker), "摸鱼时钟有自己的背景")
        XCTAssertTrue(WidgetTint.offersBackground(.progress))
        XCTAssertTrue(WidgetTint.Background.dark.forcesDarkInk)
        XCTAssertFalse(WidgetTint.Background.dots.forcesDarkInk)
    }

    // MARK: 对比度

    func testContrastRatioBounds() {
        let black = ColorCode(red: 0, green: 0, blue: 0), white = ColorCode(red: 1, green: 1, blue: 1)
        XCTAssertEqual(WidgetTint.contrastRatio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(WidgetTint.contrastRatio(white, white), 1, accuracy: 0.001)
    }

    func testInkOnFill() {
        XCTAssertTrue(WidgetTint.inkIsDark(on: ColorCode(hex: WidgetTint.Preset.yellow.hex)!))
        XCTAssertTrue(WidgetTint.inkIsDark(on: ColorCode(hex: WidgetTint.Preset.blush.hex)!))
        XCTAssertFalse(WidgetTint.inkIsDark(on: ColorCode(hex: "#1C1C1E")!))
        XCTAssertFalse(WidgetTint.inkIsDark(on: ColorCode(hex: "#5E6AD2")!))
    }

    func testReadableInBothAppearances() {
        let colours = WidgetTint.Preset.allCases.map(\.palette.main)
            + WidgetKind.allCases.map { WidgetTint.defaultPalette($0).main }
            + [ColorCode(red: 0, green: 0, blue: 0), ColorCode(red: 1, green: 1, blue: 1)]
        for colour in colours {
            let dark = WidgetTint.readable(colour, dark: true)
            let light = WidgetTint.readable(colour, dark: false)
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(dark, WidgetTint.darkCard),
                                        WidgetTint.minimumContrast - 0.01, colour.hex)
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(light, WidgetTint.lightCard),
                                        WidgetTint.minimumContrast - 0.01, colour.hex)
        }
        // 本来就够的不动。
        let blue = ColorCode(hex: "#2F7BFF")!
        XCTAssertEqual(WidgetTint.readable(blue, dark: false), blue)
    }

    func testHSLRoundTrip() {
        let code = ColorCode(hex: "#8E5CF0")!
        let hsl = code.hslComponents
        let back = ColorCode(hue: hsl.h, saturation: hsl.s, lightness: hsl.l)
        XCTAssertEqual(back.hex, code.hex)
        XCTAssertEqual(ColorCode(hue: 0, saturation: 0, lightness: 0.5).hex, "#808080")
    }

    func testMixing() {
        let black = ColorCode(red: 0, green: 0, blue: 0), white = ColorCode(red: 1, green: 1, blue: 1)
        XCTAssertEqual(black.mixed(with: white, by: 0.5).hex, "#808080")
        XCTAssertEqual(black.mixed(with: white, by: 3), white)
        XCTAssertEqual(black.mixed(with: white, by: .nan), black)
    }
}

/// 世界时钟的城市表。
final class WorldCitiesTests: XCTestCase {
    func testEveryZoneResolves() {
        XCTAssertGreaterThanOrEqual(WorldCities.all.count, 40)
        for city in WorldCities.all {
            XCTAssertNotNil(TimeZone(identifier: city.zone), "\(city.name) \(city.zone)")
            XCTAssertFalse(city.name.isEmpty)
        }
        XCTAssertEqual(Set(WorldCities.all.map(\.name)).count, WorldCities.all.count, "城市名不重复")
    }

    func testRequiredCitiesArePresent() {
        let required = ["北京", "上海", "香港", "台北", "东京", "首尔", "新加坡", "曼谷", "迪拜", "莫斯科",
                        "伦敦", "巴黎", "柏林", "纽约", "洛杉矶", "旧金山", "芝加哥", "多伦多", "温哥华",
                        "悉尼", "墨尔本", "奥克兰"]
        let names = Set(WorldCities.all.map(\.name))
        for name in required { XCTAssertTrue(names.contains(name), name) }
    }

    func testCatalogDefaultIsInTheTable() {
        XCTAssertNotNil(WorldCities.city(zone: "Europe/London", name: "伦敦"))
    }

    func testSearchByChineseEnglishPinyinAndZone() {
        XCTAssertEqual(WorldCities.search("东京").first?.zone, "Asia/Tokyo")
        XCTAssertEqual(WorldCities.search("tokyo").first?.zone, "Asia/Tokyo")
        XCTAssertEqual(WorldCities.search("niuyue").first?.name, "纽约")
        XCTAssertEqual(WorldCities.search("New York").first?.name, "纽约")
        XCTAssertEqual(WorldCities.search("newyork").first?.name, "纽约")
        XCTAssertTrue(WorldCities.search("美国").contains { $0.name == "芝加哥" })
        XCTAssertTrue(WorldCities.search("Los_Angeles").contains { $0.name == "旧金山" })
    }

    func testEmptyQueryListsTheTable() {
        XCTAssertEqual(WorldCities.search("  "), WorldCities.all)
    }

    func testSystemZonesAreSearchable() {
        let zones = ["Asia/Kathmandu", "Asia/Tokyo", "America/Argentina/Buenos_Aires"]
        let found = WorldCities.search("kathmandu", systemZones: zones)
        XCTAssertEqual(found.map(\.zone), ["Asia/Kathmandu"])
        XCTAssertEqual(found.first?.name, "Kathmandu")
        // 内置表已有的时区不重复列一遍。
        XCTAssertEqual(WorldCities.search("tokyo", systemZones: zones).filter { $0.zone == "Asia/Tokyo" }.count, 1)
        XCTAssertEqual(WorldCities.displayName(zone: "America/Argentina/Buenos_Aires"), "Buenos Aires")
        // 真的系统时区也能搜到。
        XCTAssertTrue(WorldCities.search("Kathmandu").contains { $0.zone == "Asia/Kathmandu" })
        XCTAssertTrue(WorldCities.search("").allSatisfy { TimeZone(identifier: $0.zone) != nil })
    }
}
