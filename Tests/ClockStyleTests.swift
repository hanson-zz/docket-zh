import XCTest

/// 时钟样式注册表：添加面板只列 8 个，并掉的旧 layout 值读成新样式加选项、
/// 样子不变，子选项只在所属样式下列出，Pro 判定和原来一致。
final class ClockStyleTests: XCTestCase {

    private func config(_ values: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(values) }

    func testTheLibraryListsEightStylesInOrder() {
        XCTAssertEqual(ClockStyles.all.map(\.id), ["standard", "analog", "flip", "pixel", "lcd", "words", "neon", "nixie"])
        let clock = WidgetCatalog.entry(.clock)!
        XCTAssertEqual(clock.variants.count, 8)
        XCTAssertEqual(clock.variants.map(\.title), ClockStyles.all.map(\.title))
        for old in ["digital", "ring", "fold", "minimal"] {
            XCTAssertFalse(clock.variants.contains { $0.overrides["layout"] == .string(old) }, old)
        }
        // 原“简约”改名“液晶”，layout 值不变。
        XCTAssertEqual(ClockStyles.style("lcd")?.title, tr("液晶"))
    }

    func testStyleIDsAndOptionKeysAreUnique() {
        let ids = ClockStyles.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ClockStyles.legacyLayoutIDs.isDisjoint(with: Set(ids)))
        for option in ClockStyles.allOptions {
            XCTAssertTrue(option.key.hasPrefix("clock"), option.key)
            XCTAssertTrue(option.choices.contains { $0.value == option.defaultValue }, option.key)
        }
    }

    func testLegacyLayoutsDrawTheSameAsBefore() {
        // 目录会补上默认选项值，旧值隐含的选项要盖过它们。
        let defaults = WidgetCatalog.entry(.clock)!.defaults
        let cases: [(String, ClockFace, String)] = [
            ("digital", .bigDigits(heavy: true), "standard"),
            ("ring", .secondsRing, "analog"),
            ("fold", .foldFlip, "flip"),
            ("minimal", .bigFlipCards, "flip"),
        ]
        for (old, face, style) in cases {
            let merged = config(["layout": .string(old)]).merging(defaults: defaults)
            let look = ClockStyles.resolve(merged)
            XCTAssertEqual(look.face, face, old)
            XCTAssertEqual(look.styleID, style, old)
        }
    }

    func testMigrationRewritesLegacyLayouts() {
        let digital = ClockStyles.migrating(config(["layout": .string("digital"), "seconds": .bool(false)]))
        XCTAssertEqual(digital.string("layout"), "standard")
        XCTAssertEqual(digital.string(ClockStyles.Key.size), "large")
        XCTAssertEqual(digital.string(ClockStyles.Key.weight), "bold")
        XCTAssertFalse(digital.bool("seconds", default: true))
        XCTAssertEqual(ClockStyles.resolve(digital).face, .bigDigits(heavy: true))

        let ring = ClockStyles.migrating(config(["layout": .string("ring")]))
        XCTAssertEqual(ring.string("layout"), "analog")
        XCTAssertEqual(ring.string(ClockStyles.Key.dial), "ring")

        let fold = ClockStyles.migrating(config(["layout": .string("fold")]))
        XCTAssertEqual(fold.string("layout"), "flip")
        XCTAssertEqual(fold.string(ClockStyles.Key.flip), "fold")

        let minimal = ClockStyles.migrating(config(["layout": .string("minimal")]))
        XCTAssertEqual(minimal.string("layout"), "flip")
        XCTAssertEqual(minimal.string(ClockStyles.Key.card), "large")
        XCTAssertEqual(ClockStyles.resolve(minimal).face, .bigFlipCards)

        // 新值和别的配置原样不动。
        for id in ClockStyles.all.map(\.id) {
            let kept = config(["layout": .string(id)])
            XCTAssertEqual(ClockStyles.migrating(kept), kept, id)
        }
        XCTAssertEqual(ClockStyles.migrating(config([:])), config([:]))
    }

    func testDecodingAClockMigratesItsLayout() throws {
        let saved = WidgetInstance(kind: .clock, config: config(["layout": .string("minimal")]))
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(WidgetInstance.self, from: data)
        XCTAssertEqual(loaded.id, saved.id)
        XCTAssertEqual(loaded.config.string("layout"), "flip")
        XCTAssertEqual(loaded.config.string(ClockStyles.Key.card), "large")
        XCTAssertTrue(ProFeatures.isPro(loaded), "原极简并进翻页后仍是 Pro")
    }

    func testOptionsPickTheFace() {
        XCTAssertEqual(ClockStyles.resolve(config([:])).face, .standard(bold: false))
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("standard"),
                                                   ClockStyles.Key.weight: .string("bold")])).face, .standard(bold: true))
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("standard"),
                                                   ClockStyles.Key.size: .string("large")])).face, .bigDigits(heavy: false))
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("analog")])).face, .analog)
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("flip")])).face, .flip)
        // 大号卡片有自己的翻法，翻法选折叠也画大号卡片。
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("flip"),
                                                   ClockStyles.Key.card: .string("large"),
                                                   ClockStyles.Key.flip: .string("fold")])).face, .bigFlipCards)
        let plain: [(String, ClockFace)] = [("pixel", .pixel), ("words", .words), ("neon", .neon), ("nixie", .nixie), ("lcd", .lcd)]
        for (id, face) in plain {
            XCTAssertEqual(ClockStyles.resolve(config(["layout": .string(id)])).face, face, id)
        }
        // 认不出的值按默认读。
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("spiral")])).styleID, "standard")
        XCTAssertEqual(ClockStyles.resolve(config(["layout": .string("standard"),
                                                   ClockStyles.Key.size: .string("huge")])).face, .standard(bold: false))
    }

    func testOptionsOnlyShowUnderTheirStyle() {
        let standard = config(["layout": .string("standard")])
        XCTAssertTrue(WidgetCatalog.applies(ClockStyles.Key.size, to: standard, kind: .clock))
        XCTAssertTrue(WidgetCatalog.applies(ClockStyles.Key.weight, to: standard, kind: .clock))
        XCTAssertFalse(WidgetCatalog.applies(ClockStyles.Key.dial, to: standard, kind: .clock))
        XCTAssertFalse(WidgetCatalog.applies(ClockStyles.Key.flip, to: standard, kind: .clock))
        XCTAssertTrue(WidgetCatalog.applies("seconds", to: standard, kind: .clock))

        let analog = config(["layout": .string("analog")])
        XCTAssertTrue(WidgetCatalog.applies(ClockStyles.Key.dial, to: analog, kind: .clock))
        XCTAssertFalse(WidgetCatalog.applies(ClockStyles.Key.size, to: analog, kind: .clock))

        let flip = config(["layout": .string("flip")])
        XCTAssertTrue(WidgetCatalog.applies(ClockStyles.Key.card, to: flip, kind: .clock))
        XCTAssertTrue(WidgetCatalog.applies(ClockStyles.Key.flip, to: flip, kind: .clock))
        let bigCards = config(["layout": .string("flip"), ClockStyles.Key.card: .string("large")])
        XCTAssertFalse(WidgetCatalog.applies(ClockStyles.Key.flip, to: bigCards, kind: .clock))

        for id in ["pixel", "lcd", "words", "neon", "nixie"] {
            for key in ClockStyles.optionKeys {
                XCTAssertFalse(WidgetCatalog.applies(key, to: config(["layout": .string(id)]), kind: .clock), "\(id) \(key)")
            }
        }
        // 设置里时钟的选项按注册表顺序排在前面。
        let keys = WidgetCatalog.configurableKeys(.clock)
        XCTAssertEqual(Array(keys.prefix(ClockStyles.optionKeys.count)), ClockStyles.optionKeys)
        XCTAssertTrue(keys.contains("seconds"))
        XCTAssertFalse(keys.contains("layout"))
    }

    func testProStylesAndOptions() {
        XCTAssertEqual(ProFeatures.proClockLayouts, ["neon", "nixie", "lcd", "minimal"])
        XCTAssertEqual(Set(ClockStyles.all.filter(\.isPro).map(\.id)), ["neon", "nixie", "lcd"])
        XCTAssertTrue(ProFeatures.isProChoice(kind: .clock, key: ClockStyles.Key.card, value: "large"))
        XCTAssertFalse(ProFeatures.isProChoice(kind: .clock, key: ClockStyles.Key.card, value: "compact"))
        for key in [ClockStyles.Key.size, ClockStyles.Key.weight, ClockStyles.Key.dial, ClockStyles.Key.flip] {
            for choice in ClockStyles.option(key)!.choices {
                XCTAssertFalse(ProFeatures.isProChoice(kind: .clock, key: key, value: choice.value), "\(key) \(choice.value)")
            }
        }
        // 放好的卡片：翻页选大号卡片是 Pro，没解锁时画成普通翻页。
        let big = config(["layout": .string("flip"), ClockStyles.Key.card: .string("large")])
        XCTAssertTrue(ProFeatures.isPro(WidgetInstance(kind: .clock, config: big)))
        XCTAssertEqual(ClockStyles.face(big, unlocked: false), .flip)
        XCTAssertEqual(ClockStyles.face(big, unlocked: true), .bigFlipCards)
        XCTAssertEqual(ClockStyles.face(big, unlocked: false, preview: true), .bigFlipCards)
        XCTAssertEqual(ClockStyles.face(config(["layout": .string("neon")]), unlocked: false), .flip)
        XCTAssertFalse(ProFeatures.isPro(WidgetInstance(kind: .clock, config: config(["layout": .string("flip")]))))
        XCTAssertFalse(ProFeatures.isPro(WidgetInstance(kind: .clock, config: config(["layout": .string("ring")]))))
        XCTAssertFalse(ProFeatures.isPro(WidgetInstance(kind: .clock, config: config(["layout": .string("digital")]))))
        XCTAssertTrue(ProLicenseGate.canChoose(.clock, ["layout": .string("analog")], unlocked: false))
        XCTAssertFalse(ProLicenseGate.canChoose(.clock, [ClockStyles.Key.card: .string("large")], unlocked: false))
    }
}
