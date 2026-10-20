import XCTest

/// 表情符号面板：内置表、中英文搜索、肤色、收藏和最近用过的存取。
final class EmojiBookTests: XCTestCase {

    private func emoji(_ query: String, limit: Int = EmojiCatalog.searchLimit) -> [String] {
        EmojiCatalog.search(query, limit: limit).map(\.emoji)
    }

    // MARK: 内置表

    func testCatalogLoadsEveryRowOnce() {
        XCTAssertGreaterThan(EmojiCatalog.all.count, 1500)
        XCTAssertEqual(Set(EmojiCatalog.all.map(\.emoji)).count, EmojiCatalog.all.count)
        // 每个都有中文和英文关键词，搜得到。
        XCTAssertTrue(EmojiCatalog.all.allSatisfy { !$0.zh.isEmpty && !$0.en.isEmpty })
        // 表里只放不带肤色的写法。
        XCTAssertFalse(EmojiCatalog.all.contains { EmojiTone.hasTone($0.emoji) })
    }

    func testEntryAcceptsMissingVariationSelectorAndTone() {
        XCTAssertEqual(EmojiCatalog.entry("❤")?.emoji, "❤️")
        XCTAssertEqual(EmojiCatalog.entry("👍🏽")?.emoji, "👍")
        XCTAssertNil(EmojiCatalog.entry("猫"))
    }

    // MARK: 搜索

    func testChineseAndEnglishKeywordsFindTheSameThings() {
        XCTAssertTrue(emoji("笑").contains("😂"))
        XCTAssertTrue(emoji("心").contains("❤️"))
        XCTAssertTrue(emoji("猫").contains("🐱"))
        XCTAssertTrue(emoji("猫").contains("🐈"))
        XCTAssertTrue(emoji("cat").contains("😺"))
        XCTAssertTrue(emoji("thumbs").contains("👍"))
        XCTAssertEqual(emoji("赞").first, "👍")
    }

    func testExactEnglishNameRanksFirstAndCaseDoesNotMatter() {
        XCTAssertEqual(emoji("cat").first, "🐈")
        XCTAssertEqual(emoji("CAT"), emoji("cat"))
        XCTAssertEqual(emoji("  cat  "), emoji("cat"))
    }

    func testEnglishMatchesWordStartsNotTheMiddleOfWords() {
        // “cat” 不该找到 education 里的那三个字母。
        XCTAssertFalse(emoji("cat").contains("🎓"))
    }

    func testEmptyQueryAndLimit() {
        XCTAssertEqual(emoji(""), [])
        XCTAssertEqual(emoji("   "), [])
        XCTAssertEqual(emoji("笑", limit: 0), [])
        XCTAssertEqual(emoji("笑", limit: 3).count, 3)
        XCTAssertEqual(emoji("没有这种表情qzx"), [])
    }

    func testPastingAnEmojiFindsItself() {
        XCTAssertEqual(emoji("👍🏽"), ["👍"])
        XCTAssertEqual(emoji("🔥"), ["🔥"])
    }

    func testAlsoTryGivesTheEnglishWordForChineseQueries() {
        XCTAssertEqual(EmojiCatalog.alsoTry("猫"), "cat")
        XCTAssertEqual(EmojiCatalog.alsoTry("狗"), "dog")
        XCTAssertNil(EmojiCatalog.alsoTry("cat"))
        XCTAssertNil(EmojiCatalog.alsoTry(""))
        XCTAssertNil(EmojiCatalog.alsoTry("没有这种表情"))
    }

    // MARK: 肤色

    func testApplyingTones() {
        XCTAssertEqual(EmojiTone.apply(0, to: "👍"), "👍")
        XCTAssertEqual(EmojiTone.apply(3, to: "👍"), "👍🏽")
        XCTAssertEqual(EmojiTone.apply(5, to: "👍🏻"), "👍🏿")
        // 第一个字后面的 FE0F 让给肤色。
        XCTAssertEqual(EmojiTone.apply(2, to: "✌️"), "✌🏼")
        // 组合表情：肤色跟在人后面，性别符号保留。
        XCTAssertEqual(EmojiTone.apply(5, to: "🙋‍♀️"), "🙋🏿‍♀️")
        // 不能换肤色的原样返回，越界的夹住。
        XCTAssertEqual(EmojiTone.apply(3, to: "😂"), "😂")
        XCTAssertEqual(EmojiTone.apply(9, to: "👍"), "👍🏿")
        XCTAssertEqual(EmojiTone.apply(-1, to: "👍"), "👍")
    }

    func testBaseAndToneRoundTrip() {
        XCTAssertEqual(EmojiTone.base(of: "✌🏼"), "✌️")
        XCTAssertEqual(EmojiTone.base(of: "🙋🏿‍♀️"), "🙋‍♀️")
        XCTAssertEqual(EmojiTone.base(of: "😂"), "😂")
        XCTAssertEqual(EmojiTone.tone(of: "👍🏾"), 4)
        XCTAssertEqual(EmojiTone.tone(of: "👍"), 0)
        for entry in EmojiCatalog.all where entry.modifiable {
            for tone in 0..<EmojiTone.count {
                let toned = EmojiTone.apply(tone, to: entry.emoji)
                XCTAssertEqual(EmojiTone.base(of: toned), entry.emoji, entry.emoji)
                XCTAssertEqual(EmojiTone.tone(of: toned), tone, entry.emoji)
            }
        }
    }

    func testVariants() {
        let thumbs = EmojiTone.variants(of: "👍")
        XCTAssertEqual(thumbs.count, 6)
        XCTAssertEqual(Set(thumbs).count, 6)
        XCTAssertEqual(Set(EmojiTone.variants(of: "😂")), ["😂"])
    }

    // MARK: 存取

    func testANewWidgetGetsTheDefaultFavorites() {
        let prefs = EmojiPrefs(WidgetConfig())
        XCTAssertEqual(prefs.favorites, EmojiPrefs.defaultFavorites)
        XCTAssertEqual(prefs.recent, [])
        XCTAssertEqual(prefs.tone, 0)
        XCTAssertEqual(prefs.overrides, [:])
    }

    func testCatalogDefaultsMatchThePanelDefaults() {
        let config = WidgetCatalog.entry(.emoji)?.defaults ?? WidgetConfig()
        XCTAssertEqual(config.strings(EmojiPrefs.favoritesKey), EmojiPrefs.defaultFavorites)
    }

    func testRemovingTheLastFavoriteStaysEmptyAfterARestart() {
        var prefs = EmojiPrefs(favorites: ["😂"])
        prefs = prefs.removingFavorite(at: 0)
        XCTAssertEqual(prefs.favorites, [])
        var config = WidgetConfig()
        prefs.store(in: &config)
        XCTAssertEqual(EmojiPrefs(config).favorites, [])
        // 越界的移除什么都不做。
        XCTAssertEqual(prefs.removingFavorite(at: 3).favorites, [])
    }

    func testStoreAndReloadKeepsEverything() {
        let prefs = EmojiPrefs(favorites: ["👍", "🔥"], recent: ["😊", "🤔"], tone: 2, overrides: ["👍": 4])
        var config = WidgetConfig()
        prefs.store(in: &config)
        XCTAssertEqual(EmojiPrefs(config), prefs)
        XCTAssertEqual(EmojiPrefs(config).display("👍"), "👍🏾")
        XCTAssertEqual(EmojiPrefs(config).display("🙏"), "🙏🏼")
        XCTAssertEqual(EmojiPrefs(config).display("🔥"), "🔥")
    }

    func testHandWrittenTonedFavoritesBecomeOverrides() {
        var config = WidgetConfig()
        config.set(EmojiPrefs.favoritesKey, .list(["👍🏽", " 🔥 ", "", "👍"].map { .string($0) }))
        let prefs = EmojiPrefs(config)
        XCTAssertEqual(prefs.favorites, ["👍", "🔥"])
        XCTAssertEqual(prefs.overrides["👍"], 3)
        XCTAssertEqual(prefs.display("👍"), "👍🏽")
    }

    func testBadStoredValuesAreIgnoredOrClamped() {
        var config = WidgetConfig()
        config.set(EmojiPrefs.toneKey, .number(7))
        config.set(EmojiPrefs.overridesKey, .list(["👍=9", "nonsense", "🙏=1"].map { .string($0) }))
        let prefs = EmojiPrefs(config)
        XCTAssertEqual(prefs.tone, 5)
        XCTAssertEqual(prefs.overrides, ["🙏": 1])
    }

    func testRecentMovesToTheFrontAndIsCapped() {
        var prefs = EmojiPrefs(recent: ["😊", "🤔"])
        prefs = prefs.recording("🤔")
        XCTAssertEqual(prefs.recent, ["🤔", "😊"])
        prefs = prefs.recording("👍🏽")
        XCTAssertEqual(prefs.recent.first, "👍")
        for item in EmojiCatalog.all.prefix(40) { prefs = prefs.recording(item.emoji) }
        XCTAssertEqual(prefs.recent.count, EmojiPrefs.maxRecent)
        XCTAssertEqual(prefs.recent.first, EmojiCatalog.all[39].emoji)
        XCTAssertEqual(prefs.clearingRecent().recent, [])
    }

    func testFavoritesToggleAndStopAtTheLimit() {
        var prefs = EmojiPrefs(favorites: [])
        prefs = prefs.togglingFavorite("👍🏽") ?? prefs
        XCTAssertEqual(prefs.favorites, ["👍"])
        XCTAssertTrue(prefs.isFavorite("👍🏿"))
        prefs = prefs.togglingFavorite("👍") ?? prefs
        XCTAssertEqual(prefs.favorites, [])

        let full = EmojiPrefs(favorites: EmojiCatalog.all.prefix(EmojiPrefs.maxFavorites).map(\.emoji))
        XCTAssertTrue(full.favoritesFull)
        XCTAssertNil(full.togglingFavorite("🚀"))
        // 满了也能移除。
        XCTAssertEqual(full.togglingFavorite(full.favorites[0])?.favorites.count, EmojiPrefs.maxFavorites - 1)
    }

    func testMoreThanTheLimitIsCutWhenRead() {
        var config = WidgetConfig()
        config.set(EmojiPrefs.favoritesKey, .list(EmojiCatalog.all.prefix(30).map { .string($0.emoji) }))
        XCTAssertEqual(EmojiPrefs(config).favorites.count, EmojiPrefs.maxFavorites)
    }

    func testTonesPerEmojiAndDefault() {
        var prefs = EmojiPrefs(tone: 2)
        prefs = prefs.choosingTone(4, for: "👍🏼")
        XCTAssertEqual(prefs.overrides, ["👍": 4])
        // 选回和默认一样的，就不用单独记。
        prefs = prefs.choosingTone(2, for: "👍")
        XCTAssertEqual(prefs.overrides, [:])
        prefs = prefs.choosingTone(0, for: "👍").choosingTone(5, for: "🙏")
        XCTAssertEqual(prefs.display("👍"), "👍")
        // 改默认时，和新默认一样的单个另选去掉。
        prefs = prefs.settingDefaultTone(5)
        XCTAssertEqual(prefs.overrides, ["👍": 0])
        XCTAssertEqual(prefs.display("🙏"), "🙏🏿")
    }

    func testRestoringDefaultsKeepsRecent() {
        let prefs = EmojiPrefs(favorites: ["🫠"], recent: ["😊"], tone: 3, overrides: ["👍": 1])
            .restoringDefaults()
        XCTAssertEqual(prefs.favorites, EmojiPrefs.defaultFavorites)
        XCTAssertEqual(prefs.recent, ["😊"])
        XCTAssertEqual(prefs.tone, 0)
        XCTAssertEqual(prefs.overrides, [:])
    }

    // MARK: 拖动排序

    func testMovingFavorites() {
        let prefs = EmojiPrefs(favorites: ["a", "b", "c", "d"])
        XCTAssertEqual(prefs.movingFavorite(from: 0, to: 2).favorites, ["b", "c", "a", "d"])
        XCTAssertEqual(prefs.movingFavorite(from: 3, to: 0).favorites, ["d", "a", "b", "c"])
        XCTAssertEqual(prefs.movingFavorite(from: 1, to: 99).favorites, ["a", "c", "d", "b"])
        XCTAssertEqual(prefs.movingFavorite(from: 9, to: 0).favorites, ["a", "b", "c", "d"])
    }

    func testGridDropIndex() {
        // 6 列 48，行距 54，共 9 个。
        func drop(_ from: Int, _ dx: Double, _ dy: Double) -> Int {
            EmojiPrefs.dropIndex(from: from, dx: dx, dy: dy, cell: 48, rowStep: 54, columns: 6, count: 9)
        }
        XCTAssertEqual(drop(0, 0, 0), 0)
        XCTAssertEqual(drop(0, 20, 0), 0)
        XCTAssertEqual(drop(0, 30, 0), 1)
        XCTAssertEqual(drop(0, 48 * 2, 54), 8)
        // 拖出右边夹在最后一列，拖到最后一格之外夹在最后一个。
        XCTAssertEqual(drop(2, 500, 0), 5)
        XCTAssertEqual(drop(0, 48 * 5, 54), 8)
        XCTAssertEqual(drop(8, -500, -500), 0)
        XCTAssertEqual(EmojiPrefs.dropIndex(from: 0, dx: 0, dy: 0, cell: 48, rowStep: 54, columns: 6, count: 0), 0)
    }

    func testRows() {
        XCTAssertEqual(EmojiPrefs.rows(count: 0, columns: 8), 0)
        XCTAssertEqual(EmojiPrefs.rows(count: 8, columns: 8), 1)
        XCTAssertEqual(EmojiPrefs.rows(count: 9, columns: 8), 2)
        XCTAssertEqual(EmojiPrefs.rows(count: 3, columns: 0), 0)
    }
}
