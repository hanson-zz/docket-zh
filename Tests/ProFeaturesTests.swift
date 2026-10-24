import XCTest

/// Pro 专属的清单：整种 Pro 的小组件、原来的赞助者样式、液态外观、只属于某种小组件的
/// Pro 样式（天气多城市、电池格、便签纸色）、颜色与背景、快速开关里的工具。
final class ProFeaturesTests: XCTestCase {

    func testWholeKindsMatchTheAgreedList() {
        XCTAssertEqual(ProFeatures.proKinds, [
            .slacker, .ambient, .podcast, .trash,
            .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
            .appVolume, .stock, .watchlist,
            .fileShelf, .translate, .cassette,
        ])
        XCTAssertEqual(ProFeatures.proKinds.count, 15)
        for kind in ProFeatures.proKinds {
            XCTAssertNotNil(WidgetCatalog.entry(kind), "\(kind) 不在小组件目录里")
            XCTAssertTrue(ProFeatures.isPro(kind, overrides: [:]))
        }
        for kind in [WidgetKind.clock, .water, .battery, .network, .toggles, .calendar,
                     .weather, .notes, .todo, .photos, .aiAssistant, .downloads, .volume,
                     .progress, .habit, .radio, .recorder, .wallpaper, .crypto] {
            XCTAssertFalse(ProFeatures.isProKind(kind), "\(kind) 不是整种 Pro")
            XCTAssertFalse(ProFeatures.isPro(kind, overrides: [:]))
        }
    }

    func testSupporterStylesAreUnchanged() {
        // 原来的赞助者判断搬到这里，WidgetCatalog.isSupporterOnly 调它，结果一样。
        for layout in ["neon", "nixie", "lcd", "minimal"] {
            XCTAssertTrue(ProFeatures.isSupporterStyle(["layout": .string(layout)]))
        }
        for layout in ["standard", "analog", "flip", "pixel", "digital", "ring", "words"] {
            XCTAssertFalse(ProFeatures.isSupporterStyle(["layout": .string(layout)]))
        }
        // 角色：只有企鹅、水獭、章鱼是 Pro；柴犬、橘猫改为喝水累计达标解锁。
        for character in WaterCharacter.allCases {
            XCTAssertEqual(ProFeatures.isSupporterStyle(["character": .string(character.rawValue)]),
                           [.penguin, .otter, .octopus].contains(character), "\(character)")
        }
        for style in WifiRingStyle.allCases {
            XCTAssertEqual(ProFeatures.isSupporterStyle(["layout": .string(style.rawValue)]), style.isSupporterOnly)
        }
        for look in BatteryLook.allCases {
            XCTAssertEqual(ProFeatures.isSupporterStyle([BatteryLook.key: .string(look.rawValue)]), look.isSupporterOnly)
        }
        XCTAssertEqual(WidgetCatalog.supporterClockLayouts, ProFeatures.proClockLayouts)
    }

    func testLiquidIsProButNotSupporterLocked() {
        let asLayout: [String: WidgetConfig.Value] = ["layout": .string(LiquidMotion.layout)]
        let asLook: [String: WidgetConfig.Value] = ["look": .string("liquid")]
        XCTAssertTrue(ProFeatures.isLiquid(asLayout))
        XCTAssertTrue(ProFeatures.isLiquid(asLook))
        XCTAssertTrue(ProFeatures.isProStyle(asLayout))
        XCTAssertTrue(ProFeatures.isProStyle(asLook))
        // 液态只标识，不归赞助者解锁管，免得已经在用的人被锁。
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(asLayout))
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(asLook))
        XCTAssertTrue(ProFeatures.isProChoice(key: "look", value: "liquid"))
        XCTAssertFalse(ProFeatures.isProChoice(key: "look", value: "ring"))
        XCTAssertFalse(ProFeatures.isProChoice(key: "layout", value: "bar"))
        XCTAssertFalse(ProFeatures.isLiquid(["mode": .string("liquid")]))
    }

    func testEveryCatalogLiquidVariantIsPro() {
        var found = 0
        for entry in WidgetCatalog.entries {
            for variant in entry.variants where ProFeatures.isLiquid(variant.overrides) {
                found += 1
                XCTAssertTrue(ProFeatures.isPro(entry.kind, overrides: variant.overrides))
            }
            for variant in entry.variants {
                XCTAssertEqual(WidgetCatalog.isSupporterOnly(variant.overrides),
                               ProFeatures.isSupporterStyle(variant.overrides))
                if WidgetCatalog.isSupporterOnly(variant.overrides) {
                    XCTAssertTrue(ProFeatures.isPro(entry.kind, overrides: variant.overrides))
                }
            }
        }
        XCTAssertGreaterThan(found, 0, "目录里至少有一个液态样式")
    }

    func testPlacedWidgetFollowsItsCurrentLook() {
        var clock = WidgetInstance(kind: .clock, config: WidgetConfig(["layout": .string("standard")]))
        XCTAssertFalse(ProFeatures.isPro(clock))
        clock.config.set("layout", .string("neon"))
        XCTAssertTrue(ProFeatures.isPro(clock))
        let slacker = WidgetInstance(kind: .slacker, config: WidgetConfig([:]))
        XCTAssertTrue(ProFeatures.isPro(slacker))
        let battery = WidgetInstance(kind: .battery, config: WidgetConfig([BatteryLook.key: .string("liquid")]))
        XCTAssertTrue(ProFeatures.isPro(battery))
    }

    func testWholeKindsAddedInThisRoundAreLocked() {
        for kind in [WidgetKind.appVolume, .stock, .watchlist,
                     .fileShelf, .translate] {
            XCTAssertTrue(ProFeatures.isProKind(kind), "\(kind)")
            XCTAssertFalse(ProLicenseGate.canAdd(kind, overrides: [:], unlocked: false), "\(kind)")
            XCTAssertTrue(ProLicenseGate.canAdd(kind, overrides: [:], unlocked: true), "\(kind)")
            let placed = WidgetInstance(kind: kind, config: WidgetConfig())
            XCTAssertTrue(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "\(kind)")
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: true), "\(kind)")
        }
    }

    func testFreeAndProCountsOfTheLibrary() {
        let kinds = Set(WidgetCatalog.entries.filter(\.selfContained).map(\.kind))
        let pro = kinds.filter(ProFeatures.isProKind)
        XCTAssertEqual(pro.count, 15, "复古卡带是第 15 个")
        XCTAssertEqual(kinds.count - pro.count, 44, "官网和 README 写的免费小组件数量")
    }

    func testWeatherCitiesIsPro() {
        let cities: [String: WidgetConfig.Value] = ["layout": .string("cities")]
        XCTAssertTrue(ProFeatures.isProStyle(.weather, cities))
        XCTAssertTrue(ProFeatures.isPro(.weather, overrides: cities))
        XCTAssertFalse(ProLicenseGate.canAdd(.weather, overrides: cities, unlocked: false))
        XCTAssertFalse(ProLicenseGate.canChoose(.weather, cities, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(.weather, cities, unlocked: true))
        // 只对天气算：同样的值放在别的小组件上不是 Pro。
        XCTAssertFalse(ProFeatures.isProStyle(cities))
        XCTAssertFalse(ProFeatures.isProStyle(.clock, cities))
        for layout in ["current", "forecast", "hourly", "conditions", "sky", "week", "tenDays"] {
            XCTAssertFalse(ProFeatures.isPro(.weather, overrides: ["layout": .string(layout)]), layout)
        }
        let placed = WidgetInstance(kind: .weather, config: WidgetConfig(cities))
        XCTAssertTrue(ProFeatures.isPro(placed))
        XCTAssertTrue(ProLicenseGate.needsLockOverlay(placed, unlocked: false))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: true))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false, isPreview: true))
        let current = WidgetInstance(kind: .weather, config: WidgetConfig(["layout": .string("current")]))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(current, unlocked: false))
        XCTAssertTrue(ProFeatures.isProChoice(kind: .weather, key: "layout", value: "cities"))
    }

    func testBatteryGaugeIsPro() {
        let gauge: [String: WidgetConfig.Value] = ["layout": .string("gauge")]
        XCTAssertTrue(ProFeatures.isProStyle(.battery, gauge))
        XCTAssertFalse(ProLicenseGate.canAdd(.battery, overrides: gauge, unlocked: false))
        XCTAssertFalse(ProFeatures.isProStyle(gauge))
        XCTAssertFalse(ProFeatures.isProStyle(.system, gauge))
        for layout in ["status", "icon"] {
            XCTAssertFalse(ProFeatures.isPro(.battery, overrides: ["layout": .string(layout)]), layout)
        }
        // 电池格（原百分比圆环）没有同样大小的免费样式可退，没解锁时盖小锁遮罩。
        let placed = WidgetInstance(kind: .battery, config: WidgetConfig(gauge))
        XCTAssertTrue(ProLicenseGate.needsLockOverlay(placed, unlocked: false))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: true))
        let status = WidgetInstance(kind: .battery, config: WidgetConfig(["layout": .string("status"),
                                                                          BatteryLook.key: .string("liquid")]))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(status, unlocked: false), "液态电池照旧退回经典，不盖")
    }

    func testCatalogStylesAreBadgedForTheirKind() {
        var proStyles: [String] = []
        for entry in WidgetCatalog.entries {
            for variant in entry.variants where ProFeatures.isKindProStyle(entry.kind, variant.overrides) {
                proStyles.append("\(entry.kind.rawValue):\(variant.title)")
            }
        }
        XCTAssertTrue(proStyles.contains("weather:多城市"))
        XCTAssertTrue(proStyles.contains("battery:电池格"))
        XCTAssertTrue(proStyles.contains("progress:四格"))
        XCTAssertTrue(proStyles.contains("water:角色"))
        XCTAssertFalse(proStyles.contains("water:圆环"))
        for title in ["木壳电子管", "晶体管便携", "数码卡座"] {
            XCTAssertTrue(proStyles.contains("radio:\(title)"), title)
        }
        XCTAssertFalse(proStyles.contains("radio:经典"))
        // 便签的纸色不再列成样式，改在面板和设置里选；十五种里免费五种，其余十种是 Pro 选项。
        XCTAssertTrue(proStyles.filter { $0.hasPrefix("notes:") }.isEmpty)
        XCTAssertEqual(PaperColor.picker.filter {
            ProFeatures.isProChoice(kind: .notes, key: "color", value: $0.rawValue)
        }.count, PaperColor.picker.count - 5)
    }

    /// 喝水：圆环免费，角色和液态是 Pro。没解锁时两者都画成圆环、不盖锁，
    /// 配置不改写；新放的写圆环，没存 layout 的老卡片按角色读。
    func testWaterCharacterAndLiquidAreProAndFallBackToTheRing() {
        let ring: [String: WidgetConfig.Value] = ["layout": .string("ring")]
        let character: [String: WidgetConfig.Value] = ["layout": .string("character")]
        let liquid: [String: WidgetConfig.Value] = ["layout": .string(LiquidMotion.layout)]
        XCTAssertFalse(ProFeatures.isProKind(.water))
        XCTAssertFalse(ProFeatures.isPro(.water, overrides: ring))
        XCTAssertTrue(ProFeatures.isPro(.water, overrides: character))
        XCTAssertTrue(ProFeatures.isPro(.water, overrides: liquid))
        XCTAssertTrue(ProFeatures.isKindProStyle(.water, character))
        XCTAssertFalse(ProFeatures.isKindProStyle(.water, liquid), "液态走通用的液态判断")
        XCTAssertTrue(ProFeatures.isProChoice(kind: .water, key: "layout", value: "character"))
        XCTAssertFalse(ProFeatures.isProChoice(kind: .water, key: "layout", value: "ring"))
        // 同样的 layout 值放在别的小组件上不是 Pro。
        XCTAssertFalse(ProFeatures.isProStyle(.pet, character))
        XCTAssertFalse(ProFeatures.isProStyle(character))
        XCTAssertTrue(ProLicenseGate.canAdd(.water, overrides: ring, unlocked: false))
        for overrides in [character, liquid] {
            XCTAssertFalse(ProLicenseGate.canAdd(.water, overrides: overrides, unlocked: false))
            XCTAssertFalse(ProLicenseGate.canChoose(.water, overrides, unlocked: false))
            XCTAssertTrue(ProLicenseGate.canChoose(.water, overrides, unlocked: true))
            // 已放好的不盖锁，退回圆环；解锁（或试用、老赞助者）后回来。
            let config = WidgetConfig(overrides)
            let placed = WidgetInstance(kind: .water, config: config)
            XCTAssertTrue(ProFeatures.isPro(placed))
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false))
            XCTAssertEqual(ProLicenseGate.waterLayout(config: config, unlocked: false), .ring)
            XCTAssertEqual(ProLicenseGate.waterLayout(config: config, unlocked: true).rawValue,
                           config.string("layout"))
            XCTAssertEqual(placed.config, config, "配置不改写")
        }
        XCTAssertEqual(ProLicenseGate.waterLayout(config: WidgetConfig(ring), unlocked: false), .ring)
        // 新放的是圆环，免费。
        let fresh = WidgetCatalog.make(.water)!
        XCTAssertEqual(fresh.config.string("layout"), "ring")
        XCTAssertFalse(ProFeatures.isPro(fresh))
        // 没存 layout 的老卡片按角色读：标 Pro，没解锁时画圆环。
        let legacy = WidgetInstance(kind: .water, config: WidgetConfig(["character": .string("panda")]))
        XCTAssertTrue(ProFeatures.isPro(legacy))
        XCTAssertEqual(WaterLayout.stored(legacy.config), .character)
        XCTAssertEqual(ProLicenseGate.waterLayout(config: legacy.config, unlocked: false), .ring)
        XCTAssertEqual(ProLicenseGate.waterLayout(config: legacy.config, unlocked: true), .character)
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(legacy, unlocked: false))
        // 三种样式一样大，退回圆环时卡片不跳。
        for layout in WaterLayout.allCases {
            let placed = WidgetCatalog.make(.water, overrides: ["layout": .string(layout.rawValue)])!
            XCTAssertEqual(WidgetCatalog.naturalSize(placed).width, 184, layout.rawValue)
            XCTAssertEqual(WidgetCatalog.verticalHeight(placed), 112, layout.rawValue)
        }
    }

    func testNoteColorsSplitIntoFreeAndPro() {
        XCTAssertEqual(ProFeatures.freeNoteColors, [.cream, .mint, .peach, .lavender, .yellow])
        XCTAssertTrue(ProFeatures.freeNoteColors.contains(.yellow), "默认的柠檬黄免费")
        for color in ProFeatures.freeNoteColors {
            XCTAssertTrue(PaperColor.picker.contains(color), "\(color) 在纸色列表里")
        }
        // 免费的五种是列表里最浅的五种。
        let byLightness = PaperColor.picker.sorted {
            WidgetTint.luminance(ColorCode(hex: $0.hex)!) > WidgetTint.luminance(ColorCode(hex: $1.hex)!)
        }
        XCTAssertEqual(Set(byLightness.prefix(5)), ProFeatures.freeNoteColors)
        for color in PaperColor.picker {
            let free = ProFeatures.freeNoteColors.contains(color)
            let overrides: [String: WidgetConfig.Value] = ["color": .string(color.rawValue)]
            XCTAssertEqual(ProFeatures.isPro(.notes, overrides: overrides), !free, "\(color)")
            XCTAssertEqual(ProLicenseGate.canChoose(.notes, overrides, unlocked: false), free, "\(color)")
            XCTAssertEqual(ProFeatures.isProChoice(kind: .notes, key: "color", value: color.rawValue), !free)
            // 已放好的便签不盖遮罩，Pro 纸色退回柠檬黄。
            let config = WidgetConfig(overrides)
            let placed = WidgetInstance(kind: .notes, config: config)
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false))
            XCTAssertEqual(ProLicenseGate.noteColor(config: config, unlocked: false), free ? color : .yellow)
            XCTAssertEqual(ProLicenseGate.noteColor(config: config, unlocked: true), color)
        }
        XCTAssertFalse(ProFeatures.isPro(WidgetCatalog.make(.notes)!), "新便签默认柠檬黄，免费")
        XCTAssertFalse(ProFeatures.isProNoteColor("nope"))
        XCTAssertEqual(ProLicenseGate.noteColor(config: WidgetConfig(), unlocked: false), .yellow)
        // 同样的颜色键放在别的小组件上不是 Pro。
        XCTAssertFalse(ProFeatures.isProStyle(.habit, ["color": .string("coral")]))
        XCTAssertFalse(ProFeatures.isProStyle(["color": .string("coral")]))
    }

    func testCustomTintAndGradientBackgroundArePro() {
        XCTAssertTrue(WidgetTint.isProChoice(.custom(ColorCode(hex: "#123456")!)))
        XCTAssertFalse(WidgetTint.isProChoice(.kindDefault))
        XCTAssertFalse(WidgetTint.isProChoice(.system))
        for preset in WidgetTint.Preset.allCases {
            XCTAssertFalse(WidgetTint.isProChoice(.preset(preset)), "预设色免费")
            XCTAssertTrue(ProLicenseGate.canChooseTint(.preset(preset), unlocked: false))
        }
        XCTAssertFalse(ProLicenseGate.canChooseTint(.custom(ColorCode(hex: "#123456")!), unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChooseTint(.custom(ColorCode(hex: "#123456")!), unlocked: true))
        for background in WidgetTint.Background.allCases {
            XCTAssertEqual(WidgetTint.isProBackground(background), background == .gradient)
            XCTAssertEqual(ProLicenseGate.canChooseBackground(background, unlocked: false), background != .gradient)
            XCTAssertTrue(ProLicenseGate.canChooseBackground(background, unlocked: true))
        }
        // 没解锁时已选的自定义颜色和渐变背景退回默认显示。
        let config = WidgetConfig([WidgetTint.key: .string("#123456"), WidgetTint.backgroundKey: .string("gradient")])
        XCTAssertEqual(WidgetTint.shownChoice(config, unlocked: false), .kindDefault)
        XCTAssertEqual(WidgetTint.shownChoice(config, unlocked: true), .custom(ColorCode(hex: "#123456")!))
        XCTAssertEqual(WidgetTint.shownBackground(config, unlocked: false), .plain)
        XCTAssertEqual(WidgetTint.shownBackground(config, unlocked: true), .gradient)
        let preset = WidgetConfig([WidgetTint.key: .string("blue"), WidgetTint.backgroundKey: .string("dark")])
        XCTAssertEqual(WidgetTint.shownChoice(preset, unlocked: false), .preset(.blue))
        XCTAssertEqual(WidgetTint.shownBackground(preset, unlocked: false), .dark)
    }

    func testRenamedCardsKeepTheirLayouts() {
        let ai = WidgetCatalog.entry(.aiAssistant)!.variants
        XCTAssertEqual(ai.map(\.title), ["横版", "竖版"])
        XCTAssertEqual(ai.map { $0.overrides["layout"] }, [.string(AIServices.wideLayout), .string(AIServices.squareLayout)])
        let photos = WidgetCatalog.entry(.photos)!.variants
        XCTAssertEqual(photos.map(\.title), ["标准", "宽幅"])
        XCTAssertEqual(photos.map { $0.overrides["layout"] }, [.string("standard"), .string("wide")])
    }

    // MARK: 时间进度和习惯打卡改为免费（2026-10-19）

    func testTimeProgressIsFreeExceptLiquidAndQuad() {
        XCTAssertFalse(ProFeatures.isProKind(.progress))
        XCTAssertTrue(ProLicenseGate.canAdd(.progress, overrides: [:], unlocked: false))
        for layout in ["ring", "percentage", "bars"] {
            let overrides: [String: WidgetConfig.Value] = ["layout": .string(layout)]
            XCTAssertFalse(ProFeatures.isPro(.progress, overrides: overrides), layout)
            XCTAssertTrue(ProLicenseGate.canAdd(.progress, overrides: overrides, unlocked: false), layout)
        }
        for layout in [LiquidMotion.layout, TimeProgress.quadLayout] {
            let overrides: [String: WidgetConfig.Value] = ["layout": .string(layout)]
            XCTAssertTrue(ProFeatures.isPro(.progress, overrides: overrides), layout)
            XCTAssertFalse(ProLicenseGate.canAdd(.progress, overrides: overrides, unlocked: false), layout)
            XCTAssertFalse(ProLicenseGate.canChoose(.progress, overrides, unlocked: false), layout)
            XCTAssertTrue(ProLicenseGate.canChoose(.progress, overrides, unlocked: true), layout)
            XCTAssertTrue(ProFeatures.isProChoice(kind: .progress, key: "layout", value: layout), layout)
            // 放好的液态、四格卡片没解锁时退回圆环，不盖遮罩。
            let config = WidgetConfig(overrides)
            let placed = WidgetInstance(kind: .progress, config: config)
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), layout)
            XCTAssertEqual(ProLicenseGate.timeProgressLayout(config: config, unlocked: false), "ring", layout)
            XCTAssertEqual(ProLicenseGate.timeProgressLayout(config: config, unlocked: true), layout)
        }
        // 免费外观照原样画；没存外观的旧卡片仍是进度条。
        XCTAssertEqual(ProLicenseGate.timeProgressLayout(config: WidgetConfig(["layout": .string("percentage")]),
                                                         unlocked: false), "percentage")
        XCTAssertEqual(ProLicenseGate.timeProgressLayout(config: WidgetConfig(), unlocked: false), "bars")
        // 新放上去的是圆环，免费。
        XCTAssertFalse(ProFeatures.isPro(WidgetCatalog.make(.progress)!))
        // 四格只对时间进度算 Pro。
        XCTAssertFalse(ProFeatures.isProStyle(.clock, ["layout": .string(TimeProgress.quadLayout)]))
    }

    func testHabitTrackerIsFreeForThreeHabits() {
        XCTAssertFalse(ProFeatures.isProKind(.habit))
        XCTAssertEqual(ProFeatures.freeHabitLimit, 3)
        XCTAssertTrue(ProLicenseGate.canAdd(.habit, overrides: [:], unlocked: false))
        let placed = WidgetInstance(kind: .habit, config: WidgetConfig())
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "习惯打卡整张卡片不再盖锁")
        XCTAssertEqual(ProLicenseGate.habitLimit(unlocked: false), 3)
        XCTAssertEqual(ProLicenseGate.habitLimit(unlocked: true), HabitTracker.maxHabits)
        XCTAssertTrue(ProLicenseGate.canAddHabit(count: 2, unlocked: false))
        XCTAssertFalse(ProLicenseGate.canAddHabit(count: 3, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canAddHabit(count: 3, unlocked: true))
        XCTAssertFalse(ProLicenseGate.canAddHabit(count: HabitTracker.maxHabits, unlocked: true))
        for index in 0..<HabitTracker.maxHabits {
            XCTAssertEqual(ProLicenseGate.isHabitLocked(at: index, unlocked: false), index >= 3, "\(index)")
            XCTAssertFalse(ProLicenseGate.isHabitLocked(at: index, unlocked: true), "\(index)")
        }
        XCTAssertFalse(ProLicenseGate.canSeeHabitReport(unlocked: false), "近七天报告是 Pro")
        XCTAssertTrue(ProLicenseGate.canSeeHabitReport(unlocked: true))
        // 竹篮仍是 Pro，它的三项（喝水、习惯、专注）现在都免费可用。
        XCTAssertTrue(ProFeatures.isProKind(.perfectDay))
        for kind in [WidgetKind.water, .habit, .timer] {
            XCTAssertFalse(ProFeatures.isProKind(kind), "\(kind)")
        }
    }

    private func habits(_ count: Int) -> [Habit] {
        (0..<count).map { Habit(id: "h\($0)", name: "习惯\($0)") }
    }

    func testFreeUsersCannotAddAFourthHabit() {
        let three = habits(3)
        let added = HabitTracker.adding("第四个", to: three, id: "new")
        XCTAssertEqual(added.count, 4)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: three, after: added, unlocked: false), three)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: three, after: added, unlocked: true), added)
        // 不满 3 个时照常加。
        let two = habits(2)
        let third = HabitTracker.adding("第三个", to: two, id: "new")
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: two, after: third, unlocked: false), third)
        // 已经有 5 个的再加也不行。
        let five = habits(5)
        let six = HabitTracker.adding("第六个", to: five, id: "new")
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: six, unlocked: false), five)
    }

    func testHabitsPastThreeAreReadOnlyButKept() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let five = habits(5)
        // 免费的前 3 个照常打卡。
        let first = HabitTracker.tapping("h0", day: today, in: five, today: today)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: first, unlocked: false), first)
        // 第 4 个起打卡、补卡、改名都退回原样，数据一条不删。
        let tapped = HabitTracker.tapping("h3", day: today, in: five, today: today)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: tapped, unlocked: false), five)
        let toggled = HabitTracker.toggling("h4", day: today, in: five, today: today)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: toggled, unlocked: false), five)
        let renamed = HabitTracker.renaming("h4", to: "新名字", in: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: renamed, unlocked: false), five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: tapped, unlocked: true), tapped)
        // 不能把锁着的挪进前 3 个，也不能把能用的挪到后面去换一个上来。
        let up = HabitTracker.moving("h3", by: -1, in: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: up, unlocked: false), five)
        let down = HabitTracker.moving("h2", by: 1, in: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: down, unlocked: false), five)
        // 前 3 个之间挪可以。
        let swap = HabitTracker.moving("h0", by: 1, in: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: swap, unlocked: false), swap)
        // 删除哪个都可以；删了前面的，第 4 个顶上来变成能用的。
        let deleted = HabitTracker.removing("h1", from: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: deleted, unlocked: false), deleted)
        XCTAssertFalse(ProLicenseGate.isHabitLocked("h3", in: deleted, unlocked: false))
        XCTAssertTrue(ProLicenseGate.isHabitLocked("h4", in: deleted, unlocked: false))
        let deletedLocked = HabitTracker.removing("h4", from: five)
        XCTAssertEqual(ProLicenseGate.allowedHabitEdit(before: five, after: deletedLocked, unlocked: false),
                       deletedLocked)
        XCTAssertFalse(ProLicenseGate.isHabitLocked("missing", in: five, unlocked: false))
    }

    func testProTools() {
        XCTAssertEqual(ProFeatures.proTools, [.textCapture, .qrCode, .presentation, .keyboardLock, .lowPower])
        for tool in QuickToggle.allCases {
            XCTAssertEqual(ProFeatures.isProListChoice(key: QuickToggle.key, value: tool.rawValue),
                           ProFeatures.proTools.contains(tool))
        }
        XCTAssertFalse(ProFeatures.isProListChoice(key: "metrics", value: QuickToggle.qrCode.rawValue))
        XCTAssertFalse(ProFeatures.isProTool("nope"))
    }

    func testWording() {
        XCTAssertEqual(ProFeatures.badgeTitle, "Pro")
        XCTAssertEqual(ProFeatures.label, "Pro 专属")
        XCTAssertTrue(ProFeatures.help.contains("激活码"))
        XCTAssertEqual(ProFeatures.menuTitle("霓虹", isPro: true), "霓虹（Pro 专属）")
        XCTAssertEqual(ProFeatures.menuTitle("标准", isPro: false), "标准")
        XCTAssertEqual(Set(ProFeatures.Setting.allCases), [.aiNotch, .chargeLimit, .windowPreview, .shelfGroups,
                                                              .shotTranslate, .shotPin, .notchMessage])
    }

    // MARK: 付费墙上的数量

    func testPaywallCountsComeFromTheLists() {
        XCTAssertEqual(ProFeatures.liquidKinds.count, 8)
        XCTAssertEqual(Set(ProFeatures.liquidKinds).count, ProFeatures.liquidKinds.count, "液态清单不重复")
        // 4 款表盘 + 3 个角色 + 1 种 Wi-Fi（数字）+ 3 种电池 + 6 种底板配色。
        XCTAssertEqual(ProFeatures.exclusiveStyleCount, 17)
        XCTAssertEqual(ProFeatures.proTools.count, 5)
    }
}
