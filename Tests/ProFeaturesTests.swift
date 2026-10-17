import XCTest

/// Pro 专属的清单：整种 Pro 的小组件、原来的赞助者样式、液态外观、快速开关里的工具。
final class ProFeaturesTests: XCTestCase {

    func testWholeKindsMatchTheAgreedList() {
        XCTAssertEqual(ProFeatures.proKinds, [
            .slacker, .progress, .ambient, .podcast, .trash,
            .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
        ])
        for kind in ProFeatures.proKinds {
            XCTAssertNotNil(WidgetCatalog.entry(kind), "\(kind) 不在小组件目录里")
            XCTAssertTrue(ProFeatures.isPro(kind, overrides: [:]))
        }
        for kind in [WidgetKind.clock, .water, .battery, .network, .toggles, .calendar] {
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
