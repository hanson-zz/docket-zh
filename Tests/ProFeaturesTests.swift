import XCTest

/// Pro 专属的清单：整种 Pro 的小组件、原来的赞助者样式、液态外观、只属于某种小组件的
/// Pro 样式（天气多城市、电池格、便签纸色）、颜色与背景、快速开关里的工具。
final class ProFeaturesTests: XCTestCase {

    func testWholeKindsMatchTheAgreedList() {
        XCTAssertEqual(ProFeatures.proKinds, [
            .slacker, .progress, .ambient, .podcast, .trash,
            .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
            .appVolume, .recorder, .stock, .watchlist, .crypto,
            .wallpaper, .radio, .fileShelf, .translate, .habit,
        ])
        XCTAssertEqual(ProFeatures.proKinds.count, 20)
        for kind in ProFeatures.proKinds {
            XCTAssertNotNil(WidgetCatalog.entry(kind), "\(kind) 不在小组件目录里")
            XCTAssertTrue(ProFeatures.isPro(kind, overrides: [:]))
        }
        for kind in [WidgetKind.clock, .water, .battery, .network, .toggles, .calendar,
                     .weather, .notes, .todo, .photos, .aiAssistant, .downloads, .volume] {
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
        XCTAssertFalse(ProFeatures.isSupporterStyle(["character": .string(WaterCharacter.redPanda.rawValue)]))
        for character in WaterCharacter.allCases where character != .redPanda {
            XCTAssertTrue(ProFeatures.isSupporterStyle(["character": .string(character.rawValue)]))
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
        for kind in [WidgetKind.appVolume, .recorder, .stock, .watchlist, .crypto,
                     .wallpaper, .radio, .fileShelf, .translate, .habit] {
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
        XCTAssertEqual(pro.count, 20)
        XCTAssertEqual(kinds.count - pro.count, 40, "官网和 README 写的免费小组件数量")
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
        for layout in ["current", "conditions", "hourly", "sky", "week", "tenDays"] {
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
        // 便签的纸色不再列成样式，改在面板和设置里选；十五种里免费五种，其余十种是 Pro 选项。
        XCTAssertTrue(proStyles.filter { $0.hasPrefix("notes:") }.isEmpty)
        XCTAssertEqual(PaperColor.picker.filter {
            ProFeatures.isProChoice(kind: .notes, key: "color", value: $0.rawValue)
        }.count, PaperColor.picker.count - 5)
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
        let preset = WidgetConfig([WidgetTint.key: .string("blue"), WidgetTint.backgroundKey: .string("dots")])
        XCTAssertEqual(WidgetTint.shownChoice(preset, unlocked: false), .preset(.blue))
        XCTAssertEqual(WidgetTint.shownBackground(preset, unlocked: false), .dots)
    }

    func testRenamedCardsKeepTheirLayouts() {
        let ai = WidgetCatalog.entry(.aiAssistant)!.variants
        XCTAssertEqual(ai.map(\.title), ["AI 任意门（横版）", "AI 任意门（竖版）"])
        XCTAssertEqual(ai.map { $0.overrides["layout"] }, [.string(AIServices.wideLayout), .string(AIServices.squareLayout)])
        let photos = WidgetCatalog.entry(.photos)!.variants
        XCTAssertEqual(photos.map(\.title), ["相册标准", "相册宽幅"])
        XCTAssertEqual(photos.map { $0.overrides["layout"] }, [.string("standard"), .string("wide")])
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
        XCTAssertEqual(Set(ProFeatures.Setting.allCases), [.aiNotch, .chargeLimit])
    }
}
